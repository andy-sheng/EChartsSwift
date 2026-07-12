// Ported from echarts/src/chart/sankey/sankeyLayout.ts — keep in sync with upstream
/*
* Licensed to the Apache Software Foundation (ASF) under one
* or more contributor license agreements.  See the NOTICE file
* distributed with this work for additional information
* regarding copyright ownership.  The ASF licenses this file
* to you under the Apache License, Version 2.0 (the
* "License"); you may not use this file except in compliance
* with the License.  You may obtain a copy of the License at
*
*   http://www.apache.org/licenses/LICENSE-2.0
*
* Unless required by applicable law or agreed to in writing,
* software distributed under the License is distributed on an
* "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
* KIND, either express or implied.  See the License for the
* specific language governing permissions and limitations
* under the License.
*/

import Foundation
import ZRenderKit

// upstream imports:
//   import * as zrUtil from 'zrender/src/core/util';                 -> `util.*` (ZRenderKit).
//   import {createSimpleOverallStageHandler, groupData} from '../../util/model';
//       -> `model.createSimpleOverallStageHandler` / `model.groupData` (util/modelUtil.swift).
//   import ExtensionAPI from '../../core/ExtensionAPI';              -> ExtensionAPI (core/ExtensionAPI.swift).
//   import SankeySeriesModel, { SankeySeriesOption, SankeyNodeItemOption, SERIES_TYPE_SANKEY }
//       from './SankeySeries';   -> SankeySeriesModel / `SERIES_TYPE_SANKEY` (sibling SankeySeries.swift).
//   import { GraphNode, GraphEdge } from '../../data/Graph';         -> GraphNode / GraphEdge (data/Graph.swift).
//   import { LayoutOrient } from '../../util/types';                 -> `String` ('horizontal' | 'vertical').
//   import GlobalModel from '../../model/Global';                    -> GlobalModel (model/Global.swift).
//   import { createBoxLayoutReference, getLayoutRect } from '../../util/layout';
//       -> `layout.createBoxLayoutReference` / `layout.getLayoutRect` (util/layout.swift).
//   import { asc } from '../../util/number';                         -> `number.asc` (util/number.swift).

// upstream:
//   export const sankeyLayoutStageHandler = createSimpleOverallStageHandler(SERIES_TYPE_SANKEY, sankeyLayout);
// `createSimpleOverallStageHandler` expects a `StageHandlerOverallReset = (GlobalModel, ExtensionAPI,
// Payload?) -> Void`; the upstream `sankeyLayout` is `(ecModel, api)` (2-arg). Adapt with a thin wrapper
// that drops the (unused) payload, keeping `sankeyLayout` byte-faithful (2-arg) below (see funnelLayout.swift).
public let sankeyLayoutStageHandler = model.createSimpleOverallStageHandler(
    SERIES_TYPE_SANKEY,
    { ecModel, api, _ in sankeyLayout(ecModel, api) }
)

// Exposed for the driver to call directly (mirrors funnelLayout), matching upstream's module-private
// `function sankeyLayout(ecModel, api)`.
public func sankeyLayout(
    _ ecModel: GlobalModel,
    _ api: ExtensionAPI
) {
    ecModel.eachSeriesByType(SERIES_TYPE_SANKEY) { seriesModelBase, _ in
        // upstream typed callback param `seriesModel: SankeySeriesModel`.
        let seriesModel = seriesModelBase as! SankeySeriesModel

        // nodeWidth / nodeGap are Int-boxed defaults (20 / 8) — read via sankeyNum, never bare `as? Double`.
        let nodeWidth = sankeyNum(seriesModel.get("nodeWidth")) ?? Double.nan
        let nodeGap = sankeyNum(seriesModel.get("nodeGap")) ?? Double.nan

        let refContainer = layout.createBoxLayoutReference(seriesModel, api).refContainer
        let layoutInfo = layout.getLayoutRect(seriesModel.getBoxLayoutParams(), refContainer)

        seriesModel.layoutInfo = layoutInfo

        let width = layoutInfo.width
        let height = layoutInfo.height

        let graph = seriesModel.getGraph()

        let nodes = graph.nodes
        let edges = graph.edges

        computeNodeValues(nodes)

        let filteredNodes = util.filter(nodes) { node, _ in
            return lget(node.getLayout(), "value") == 0
        }

        // filteredNodes.length !== 0 ? 0 : seriesModel.get('layoutIterations')
        // `layoutIterations` is an Int-boxed default (32) — read via sankeyNum.
        let iterations: Double = filteredNodes.count != 0
            ? 0
            : (sankeyNum(seriesModel.get("layoutIterations")) ?? Double.nan)

        let orient = (seriesModel.get("orient") as? String) ?? ""

        let nodeAlign = seriesModel.get("nodeAlign")
        let sort = seriesModel.get("sort")

        layoutSankey(nodes, edges, nodeWidth, nodeGap, width, height, iterations, orient, nodeAlign, sort)
    }
}

private func layoutSankey(
    _ nodes: [GraphNode],
    _ edges: [GraphEdge],
    _ nodeWidth: Double,
    _ nodeGap: Double,
    _ width: Double,
    _ height: Double,
    _ iterations: Double,
    _ orient: String,
    _ nodeAlign: Any?,
    _ sort: Any?
) {
    computeNodeBreadths(nodes, edges, nodeWidth, width, height, orient, nodeAlign)
    computeNodeDepths(nodes, edges, height, width, nodeGap, iterations, orient, sort)
    computeEdgeDepths(nodes, orient)
}

/**
 * Compute the value of each node by summing the associated edge's value
 */
private func computeNodeValues(_ nodes: [GraphNode]) {
    util.each(nodes) { node, _ in
        let value1 = sum(node.outEdges, getEdgeValue)
        let value2 = sum(node.inEdges, getEdgeValue)
        // node.getValue() as number || 0
        let nodeRawValue = jsNumOr0(node.getValue())
        let value = Swift.max(value1, value2, nodeRawValue)
        node.setLayout(["value": value], true)
    }
}

/**
 * Compute the x-position for each node.
 *
 * Here we use Kahn algorithm to detect cycle when we traverse
 * the node to computer the initial x position.
 */
private func computeNodeBreadths(
    _ nodes: [GraphNode],
    _ edges: [GraphEdge],
    _ nodeWidth: Double,
    _ width: Double,
    _ height: Double,
    _ orient: String,
    _ nodeAlign: Any?
) {
    // Used to mark whether the edge is deleted. if it is deleted,
    // the value is 0, otherwise it is 1.
    var remainEdges: [Int] = []
    // Storage each node's indegree.
    var indegreeArr: [Int] = []
    // Used to storage the node with indegree is equal to 0.
    var zeroIndegrees: [GraphNode] = []
    var nextTargetNode: [GraphNode] = []
    var x = 0
    // let kx = 0;

    for i in 0..<edges.count {
        _ = i
        remainEdges.append(1)
    }
    for i in 0..<nodes.count {
        indegreeArr.append(nodes[i].inEdges.count)
        if indegreeArr[i] == 0 {
            zeroIndegrees.append(nodes[i])
        }
    }
    var maxNodeDepth = -1
    // Traversing nodes using topological sorting to calculate the
    // horizontal(if orient === 'horizontal') or vertical(if orient === 'vertical')
    // position of the nodes.
    while zeroIndegrees.count != 0 {
        for idx in 0..<zeroIndegrees.count {
            let node = zeroIndegrees[idx]
            let item = node.hostGraph.data.getRawDataItem(node.dataIndex)
            let itemDepth = rawDepth(item)
            let isItemDepth = itemDepth != nil && itemDepth! >= 0
            if isItemDepth && Int(itemDepth!) > maxNodeDepth {
                maxNodeDepth = Int(itemDepth!)
            }
            node.setLayout(["depth": isItemDepth ? itemDepth! : Double(x)], true)
            orient == "vertical"
                ? node.setLayout(["dy": nodeWidth], true)
                : node.setLayout(["dx": nodeWidth], true)

            for edgeIdx in 0..<node.outEdges.count {
                let edge = node.outEdges[edgeIdx]
                let indexEdge = indexOfRef(edges, edge)
                remainEdges[indexEdge] = 0
                let targetNode = edge.node2
                let nodeIndex = indexOfRef(nodes, targetNode)
                indegreeArr[nodeIndex] -= 1
                if indegreeArr[nodeIndex] == 0 && indexOfRef(nextTargetNode, targetNode) < 0 {
                    nextTargetNode.append(targetNode)
                }
            }
        }
        x += 1
        zeroIndegrees = nextTargetNode
        nextTargetNode = []
    }

    for i in 0..<remainEdges.count {
        if remainEdges[i] == 1 {
            // upstream: `throw new Error('Sankey is a DAG, the original data has cycle!');`
            // PORT-NOTE: the layout stage handler closure is non-throwing, so the unrecoverable upstream
            //   throw is mirrored with a fatalError (cyclic input is invalid data) — semantically equivalent.
            fatalError("Sankey is a DAG, the original data has cycle!")
        }
    }

    let maxDepth = maxNodeDepth > x - 1 ? maxNodeDepth : x - 1
    if jsTruthy(nodeAlign) && (nodeAlign as? String) != "left" {
        adjustNodeWithNodeAlign(nodes, nodeAlign, orient, Double(maxDepth))
    }
    let kx = orient == "vertical"
        ? (height - nodeWidth) / Double(maxDepth)
        : (width - nodeWidth) / Double(maxDepth)

    scaleNodeBreadths(nodes, kx, orient)
}

private func isNodeDepth(_ node: GraphNode) -> Bool {
    let item = node.hostGraph.data.getRawDataItem(node.dataIndex)
    let depth = rawDepth(item)
    return depth != nil && depth! >= 0
}

private func adjustNodeWithNodeAlign(
    _ nodes: [GraphNode],
    _ nodeAlign: Any?,
    _ orient: String,
    _ maxDepth: Double
) {
    if (nodeAlign as? String) == "right" {
        var nextSourceNode: [GraphNode] = []
        var remainNodes = nodes
        var nodeHeight = 0
        while remainNodes.count != 0 {
            for i in 0..<remainNodes.count {
                let node = remainNodes[i]
                node.setLayout(["skNodeHeight": Double(nodeHeight)], true)
                for j in 0..<node.inEdges.count {
                    let edge = node.inEdges[j]
                    if indexOfRef(nextSourceNode, edge.node1) < 0 {
                        nextSourceNode.append(edge.node1)
                    }
                }
            }
            remainNodes = nextSourceNode
            nextSourceNode = []
            nodeHeight += 1
        }

        util.each(nodes) { node, _ in
            if !isNodeDepth(node) {
                node.setLayout(
                    ["depth": Swift.max(0, maxDepth - lget(node.getLayout(), "skNodeHeight"))],
                    true
                )
            }
        }
    }
    else if (nodeAlign as? String) == "justify" {
        moveSinksRight(nodes, maxDepth)
    }
}

/**
 * All the node without outEgdes are assigned maximum x-position and
 *     be aligned in the last column.
 *
 * @param nodes.  node of sankey view.
 * @param maxDepth.  use to assign to node without outEdges as x-position.
 */
private func moveSinksRight(_ nodes: [GraphNode], _ maxDepth: Double) {
    util.each(nodes) { node, _ in
        if !isNodeDepth(node) && node.outEdges.count == 0 {
            node.setLayout(["depth": maxDepth], true)
        }
    }
}

/**
 * Scale node x-position to the width
 *
 * @param nodes  node of sankey view
 * @param kx   multiple used to scale nodes
 */
private func scaleNodeBreadths(_ nodes: [GraphNode], _ kx: Double, _ orient: String) {
    util.each(nodes) { node, _ in
        let nodeDepth = lget(node.getLayout(), "depth") * kx
        orient == "vertical"
            ? node.setLayout(["y": nodeDepth], true)
            : node.setLayout(["x": nodeDepth], true)
    }
}

/**
 * Using Gauss-Seidel iterations method to compute the node depth(y-position)
 *
 * @param nodes  node of sankey view
 * @param edges  edge of sankey view
 * @param height  the whole height of the area to draw the view
 * @param nodeGap  the vertical distance between two nodes
 *     in the same column.
 * @param iterations  the number of iterations for the algorithm
 * @param sort  sorting method used when resolving collisions within each column
 */
private func computeNodeDepths(
    _ nodes: [GraphNode],
    _ edges: [GraphEdge],
    _ height: Double,
    _ width: Double,
    _ nodeGap: Double,
    _ iterations: Double,
    _ orient: String,
    _ sort: Any?
) {
    var nodesByBreadth = prepareNodesByBreadth(nodes, orient)

    initializeNodeDepth(nodesByBreadth, edges, height, width, nodeGap, orient)
    resolveCollisions(&nodesByBreadth, nodeGap, height, width, orient, sort)

    var alpha = 1.0
    var iterations = iterations
    while iterations > 0 {
        // 0.99 is a experience parameter, ensure that each iterations of
        // changes as small as possible.
        alpha *= 0.99
        relaxRightToLeft(nodesByBreadth, alpha, orient)
        resolveCollisions(&nodesByBreadth, nodeGap, height, width, orient, sort)
        relaxLeftToRight(nodesByBreadth, alpha, orient)
        resolveCollisions(&nodesByBreadth, nodeGap, height, width, orient, sort)
        iterations -= 1
    }
}

private func prepareNodesByBreadth(_ nodes: [GraphNode], _ orient: String) -> [[GraphNode]] {
    var nodesByBreadth: [[GraphNode]] = []
    let keyAttr = orient == "vertical" ? "y" : "x"

    let groupResult = model.groupData(nodes) { node -> Double in
        return lget(node.getLayout(), keyAttr)
    }
    let keys = number.asc(groupResult.keys)
    util.each(keys) { key, _ in
        nodesByBreadth.append(groupResult.buckets.get(key) ?? [])
    }

    return nodesByBreadth
}

/**
 * Compute the original y-position for each node
 */
private func initializeNodeDepth(
    _ nodesByBreadth: [[GraphNode]],
    _ edges: [GraphEdge],
    _ height: Double,
    _ width: Double,
    _ nodeGap: Double,
    _ orient: String
) {
    var minKy = Double.infinity
    util.each(nodesByBreadth) { nodes, _ in
        let n = nodes.count
        var sum = 0.0
        util.each(nodes) { node, _ in
            sum += lget(node.getLayout(), "value")
        }
        let ky = orient == "vertical"
                    ? (width - Double(n - 1) * nodeGap) / sum
                    : (height - Double(n - 1) * nodeGap) / sum

        if ky < minKy {
            minKy = ky
        }
    }

    util.each(nodesByBreadth) { nodes, _ in
        util.each(nodes) { node, i in
            let nodeDy = lget(node.getLayout(), "value") * minKy
            if orient == "vertical" {
                node.setLayout(["x": Double(i)], true)
                node.setLayout(["dx": nodeDy], true)
            }
            else {
                node.setLayout(["y": Double(i)], true)
                node.setLayout(["dy": nodeDy], true)
            }
        }
    }

    util.each(edges) { edge, _ in
        // +edge.getValue() * minKy
        let edgeDy = jsNum(edge.getValue()) * minKy
        edge.setLayout(["dy": edgeDy], true)
    }
}

/**
 * Resolve the collision of initialized depth (y-position)
 */
private func resolveCollisions(
    _ nodesByBreadth: inout [[GraphNode]],
    _ nodeGap: Double,
    _ height: Double,
    _ width: Double,
    _ orient: String,
    _ sort: Any?
) {
    let keyAttr = orient == "vertical" ? "x" : "y"
    for bi in 0..<nodesByBreadth.count {
        var nodes = nodesByBreadth[bi]
        // sort !== null
        if !(sort == nil || sort is NSNull) {
            nodes.sort { a, b in
                return lget(a.getLayout(), keyAttr) - lget(b.getLayout(), keyAttr) < 0
            }
        }
        // Persist the (possibly) re-sorted bucket back, mirroring JS in-place `nodes.sort`.
        nodesByBreadth[bi] = nodes

        var nodeX: Double
        // `node` mirrors upstream's outer-scope loop variable retained after the for-loop.
        var node: GraphNode? = nil
        var dy: Double
        var y0 = 0.0
        let n = nodes.count
        let nodeDyAttr = orient == "vertical" ? "dx" : "dy"
        for i in 0..<n {
            node = nodes[i]
            dy = y0 - lget(node!.getLayout(), keyAttr)
            if dy > 0 {
                nodeX = lget(node!.getLayout(), keyAttr) + dy
                orient == "vertical"
                    ? node!.setLayout(["x": nodeX], true)
                    : node!.setLayout(["y": nodeX], true)
            }
            y0 = lget(node!.getLayout(), keyAttr) + lget(node!.getLayout(), nodeDyAttr) + nodeGap
        }
        let viewWidth = orient == "vertical" ? width : height
        // If the bottommost node goes outside the bounds, push it back up
        dy = y0 - nodeGap - viewWidth
        if dy > 0, let lastNode = node {
            node = lastNode
            nodeX = lget(node!.getLayout(), keyAttr) - dy
            orient == "vertical"
                ? node!.setLayout(["x": nodeX], true)
                : node!.setLayout(["y": nodeX], true)

            y0 = nodeX
            var i = n - 2
            while i >= 0 {
                node = nodes[i]
                dy = lget(node!.getLayout(), keyAttr) + lget(node!.getLayout(), nodeDyAttr) + nodeGap - y0
                if dy > 0 {
                    nodeX = lget(node!.getLayout(), keyAttr) - dy
                    orient == "vertical"
                        ? node!.setLayout(["x": nodeX], true)
                        : node!.setLayout(["y": nodeX], true)
                }
                y0 = lget(node!.getLayout(), keyAttr)
                i -= 1
            }
        }
    }
}

/**
 * Change the y-position of the nodes, except most the right side nodes
 * @param nodesByBreadth
 * @param alpha  parameter used to adjust the nodes y-position
 */
private func relaxRightToLeft(
    _ nodesByBreadth: [[GraphNode]],
    _ alpha: Double,
    _ orient: String
) {
    util.each(Array(nodesByBreadth.reversed())) { nodes, _ in
        util.each(nodes) { node, _ in
            if node.outEdges.count != 0 {
                var y = sum(node.outEdges, weightedTarget, orient)
                    / sum(node.outEdges, getEdgeValue)

                if y.isNaN {
                    let len = node.outEdges.count
                    y = len != 0 ? sum(node.outEdges, centerTarget, orient) / Double(len) : 0
                }

                if orient == "vertical" {
                    let nodeX = lget(node.getLayout(), "x") + (y - center(node, orient)) * alpha
                    node.setLayout(["x": nodeX], true)
                }
                else {
                    let nodeY = lget(node.getLayout(), "y") + (y - center(node, orient)) * alpha
                    node.setLayout(["y": nodeY], true)
                }
            }
        }
    }
}

private func weightedTarget(_ edge: GraphEdge, _ orient: String?) -> Double {
    return center(edge.node2, orient ?? "") * jsNum(edge.getValue())
}
private func centerTarget(_ edge: GraphEdge, _ orient: String?) -> Double {
    return center(edge.node2, orient ?? "")
}

private func weightedSource(_ edge: GraphEdge, _ orient: String?) -> Double {
    return center(edge.node1, orient ?? "") * jsNum(edge.getValue())
}
private func centerSource(_ edge: GraphEdge, _ orient: String?) -> Double {
    return center(edge.node1, orient ?? "")
}

private func center(_ node: GraphNode, _ orient: String) -> Double {
    return orient == "vertical"
            ? lget(node.getLayout(), "x") + lget(node.getLayout(), "dx") / 2
            : lget(node.getLayout(), "y") + lget(node.getLayout(), "dy") / 2
}

private func getEdgeValue(_ edge: GraphEdge, _ orient: String?) -> Double {
    return jsNum(edge.getValue())
}

// upstream `sum<T>(array, cb, orient?)`: sums `+cb(item, orient)` skipping NaN results.
private func sum<T>(
    _ array: [T],
    _ cb: (T, String?) -> Double,
    _ orient: String? = nil
) -> Double {
    var sum = 0.0
    let len = array.count
    var i = -1
    while true {
        i += 1
        if i >= len { break }
        let value = cb(array[i], orient)
        if !value.isNaN {
            sum += value
        }
    }
    return sum
}

/**
 * Change the y-position of the nodes, except most the left side nodes
 */
private func relaxLeftToRight(_ nodesByBreadth: [[GraphNode]], _ alpha: Double, _ orient: String) {
    util.each(nodesByBreadth) { nodes, _ in
        util.each(nodes) { node, _ in
            if node.inEdges.count != 0 {
                var y = sum(node.inEdges, weightedSource, orient)
                        / sum(node.inEdges, getEdgeValue)

                if y.isNaN {
                    let len = node.inEdges.count
                    y = len != 0 ? sum(node.inEdges, centerSource, orient) / Double(len) : 0
                }

                if orient == "vertical" {
                    let nodeX = lget(node.getLayout(), "x") + (y - center(node, orient)) * alpha
                    node.setLayout(["x": nodeX], true)
                }
                else {
                    let nodeY = lget(node.getLayout(), "y") + (y - center(node, orient)) * alpha
                    node.setLayout(["y": nodeY], true)
                }
            }
        }
    }
}

/**
 * Compute the depth(y-position) of each edge
 */
private func computeEdgeDepths(_ nodes: [GraphNode], _ orient: String) {
    let keyAttr = orient == "vertical" ? "x" : "y"
    util.each(nodes) { node, _ in
        node.outEdges.sort { a, b in
            return lget(a.node2.getLayout(), keyAttr) - lget(b.node2.getLayout(), keyAttr) < 0
        }
        node.inEdges.sort { a, b in
            return lget(a.node1.getLayout(), keyAttr) - lget(b.node1.getLayout(), keyAttr) < 0
        }
    }
    util.each(nodes) { node, _ in
        var sy = 0.0
        var ty = 0.0
        util.each(node.outEdges) { edge, _ in
            edge.setLayout(["sy": sy], true)
            sy += lget(edge.getLayout(), "dy")
        }
        util.each(node.inEdges) { edge, _ in
            edge.setLayout(["ty": ty], true)
            ty += lget(edge.getLayout(), "dy")
        }
    }
}

// ─── JS coercion / option-read shims (not upstream symbols) ───────────────────────────────────────

// TRAP (1): `[String: Any]` defaultOptions store numbers as bare Int literals (nodeWidth: 20, nodeGap: 8,
//   layoutIterations: 32, ...). `as? Double` returns nil on an Int and SILENTLY DROPS the value.
//   Read EVERY numeric option through this helper (Int | Double | NSNumber -> Double).
private func sankeyNum(_ v: Any?) -> Double? {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let n = v as? NSNumber { return n.doubleValue }
    return nil
}

// Reads a numeric field out of a node/edge layout dict (`node.getLayout().<key>`). JS `undefined`
//   participating in arithmetic yields NaN, so a missing key returns NaN to match.
private func lget(_ layout: Any?, _ key: String) -> Double {
    guard let dict = layout as? [String: Any] else { return Double.nan }
    return sankeyNum(dict[key]) ?? Double.nan
}

// Reads `item.depth` off a raw data item (`getRawDataItem(...) as SankeyNodeItemOption`); nil when the
//   item is a scalar / the slot is absent (models `item.depth != null`).
private func rawDepth(_ item: Any?) -> Double? {
    guard let dict = item as? [String: Any] else { return nil }
    let d = dict["depth"]
    if d == nil || d is NSNull { return nil }
    return sankeyNum(d)
}

// JS unary `+x` numeric coercion for edge values (returns NaN when not a number).
private func jsNum(_ v: Any?) -> Double {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let n = v as? NSNumber { return n.doubleValue }
    if let s = v as? String { return Double(s) ?? Double.nan }
    return Double.nan
}

// Models `node.getValue() as number || 0`: JS falsy (0 / NaN / null / undefined) -> 0.
private func jsNumOr0(_ v: Any?) -> Double {
    let d = jsNum(v)
    return (d != 0 && !d.isNaN) ? d : 0
}

// Mirrors JS `x || y` truthiness for `nodeAlign && nodeAlign !== 'left'` (nil / NSNull / "" -> falsy).
private func jsTruthy(_ v: Any?) -> Bool {
    guard let v = v else { return false }
    if v is NSNull { return false }
    if let b = v as? Bool { return b }
    if let n = v as? Double { return n != 0 && !n.isNaN }
    if let i = v as? Int { return i != 0 }
    if let s = v as? String { return !s.isEmpty }
    return true
}

// Identity-based `zrUtil.indexOf` for reference-type node/edge arrays (upstream compares by reference).
private func indexOfRef<T: AnyObject>(_ arr: [T], _ v: T) -> Int {
    for (i, e) in arr.enumerated() {
        if e === v { return i }
    }
    return -1
}
