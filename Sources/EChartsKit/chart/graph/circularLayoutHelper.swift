// Ported from echarts/src/chart/graph/circularLayoutHelper.ts — keep in sync with upstream
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
//   import * as vec2 from 'zrender/src/core/vector';                 -> `vector.*` (ZRenderKit).
//   import {getSymbolSize, getNodeGlobalScale} from './graphHelper';
//       -> `graphHelper.getSymbolSize` / `graphHelper.getNodeGlobalScale`
//          (chart/graph/graphHelper.swift).
//   import GraphSeriesModel, { GraphEdgeItemOption, GraphNodeItemOption } from './GraphSeries';
//       -> GraphSeriesModel (chart/graph/GraphSeries.swift).
//   import Graph, { GraphNode } from '../../data/Graph';             -> Graph / GraphNode (data/Graph.swift).
//   import Symbol from '../helper/Symbol';                           -> Symbol (chart/helper/SymbolElement.swift, class Symbol).
//   import SeriesData from '../../data/SeriesData';                  -> SeriesData (data/SeriesData.swift).
//   import * as zrUtil from 'zrender/src/core/util';                 -> `util.*` (ZRenderKit).
//   import {getCurvenessForEdge} from '../helper/multipleGraphEdgeHelper';
//       -> `multipleGraphEdgeHelper.getCurvenessForEdge` (chart/helper/multipleGraphEdgeHelper.swift).

// const PI = Math.PI;
private let PI = Double.pi

// const _symbolRadiansHalf: number[] = [];
private var _symbolRadiansHalf: [Double] = []

/**
 * `basedOn` can be:
 * 'value':
 *     This layout is not accurate and have same bad case. For example,
 *     if the min value is very smaller than the max value, the nodes
 *     with the min value probably overlap even though there is enough
 *     space to layout them. So we only use this approach in the as the
 *     init layout of the force layout.
 *     FIXME
 *     Probably we do not need this method any more but use
 *     `basedOn: 'symbolSize'` in force layout if
 *     delay its init operations to GraphView.
 * 'symbolSize':
 *     This approach work only if all of the symbol size calculated.
 *     That is, the progressive rendering is not applied to graph.
 *     FIXME
 *     If progressive rendering is applied to graph some day,
 *     probably we have to use `basedOn: 'value'`.
 */
public func circularLayout(
    _ seriesModel: GraphSeriesModel,
    _ basedOn: String,                     // upstream: 'value' | 'symbolSize'
    _ draggingNode: GraphNode? = nil,
    _ pointer: [Double]? = nil
) {
    let coordSys = seriesModel.coordinateSystem as? CoordinateSystem
    // if (coordSys && coordSys.type !== 'view') { return; }
    if coordSys != nil && coordSys!.type != "view" {
        return
    }

    // const rect = coordSys.getBoundingRect();
    // Upstream dereferences `coordSys` unconditionally here; a graph series always carries a view
    // coord sys once created, so we force-unwrap to mirror that assumption.
    let rect = coordSys!.getBoundingRect()!

    let nodeData = seriesModel.getData()
    let graph = nodeData.graph!

    let cx = rect.width / 2 + rect.x
    let cy = rect.height / 2 + rect.y
    let r = Swift.min(rect.width, rect.height) / 2
    let count = nodeData.count()

    nodeData.setLayout([
        "cx": cx,
        "cy": cy
    ] as [String: Any])

    // if (!count) { return; }
    if count == 0 {
        return
    }

    if let draggingNode = draggingNode {
        // const [tempX, tempY] = coordSys.pointToData(pointer) as [number, number];
        let td = (coordSys!.pointToData(pointer!, nil) as? [Double]) ?? [0, 0]
        let tempX = td[0]
        let tempY = td[1]
        // const v = [tempX - cx, tempY - cy];
        var v: [Double] = [tempX - cx, tempY - cy]
        // vec2.normalize(v, v); vec2.scale(v, v, r);  (value-returning per CONVENTIONS §3)
        v = toArr(vector.normalize(toV(v)))
        v = toArr(vector.scale(toV(v), r))
        draggingNode.setLayout([cx + v[0], cy + v[1]], true)

        let circularRotateLabel = (seriesModel.get(["circular", "rotateLabel"]) as? Bool) ?? false
        rotateNodeLabel(draggingNode, circularRotateLabel, cx, cy)
    }

    _layoutNodesBasedOn[basedOn]!(seriesModel, graph, nodeData, r, cx, cy, Double(count))

    graph.eachEdge { edge, index in
        // let curveness = zrUtil.retrieve3(
        //     edge.getModel<GraphEdgeItemOption>().get(['lineStyle', 'curveness']),
        //     getCurvenessForEdge(edge, seriesModel, index),
        //     0
        // );
        var curveness: Double = util.retrieve3(
            asNumberOpt(edge.getModel()?.get(["lineStyle", "curveness"])),
            multipleGraphEdgeHelper.getCurvenessForEdge(edge, seriesModel, Double(index), false),
            0
        ) ?? 0
        // const p1 = vec2.clone(edge.node1.getLayout()); (value copy — [Double] is a value type)
        let p1 = asPoint(edge.node1.getLayout())
        let p2 = asPoint(edge.node2.getLayout())
        var cp1: [Double]? = nil
        let x12 = (p1[0] + p2[0]) / 2
        let y12 = (p1[1] + p2[1]) / 2
        if curveness != 0 {                 // +curveness
            curveness *= 3
            cp1 = [
                cx * curveness + x12 * (1 - curveness),
                cy * curveness + y12 * (1 - curveness)
            ]
        }
        // edge.setLayout([p1, p2, cp1]);
        // Upstream keeps a trailing `undefined` when cp1 is unset; we omit it — adjustEdge treats a
        // missing 3rd point identically to `linePoints[2] == null`.
        var pointsLayout: [[Double]] = [p1, p2]
        if let cp1 = cp1 {
            pointsLayout.append(cp1)
        }
        edge.setLayout(pointsLayout)
    }
}

// interface LayoutNode { (seriesModel, graph, nodeData, r, cx, cy, count): void }
private typealias LayoutNode = (
    _ seriesModel: GraphSeriesModel,
    _ graph: Graph,
    _ nodeData: SeriesData,
    _ r: Double,
    _ cx: Double,
    _ cy: Double,
    _ count: Double
) -> Void

// const _layoutNodesBasedOn: Record<'value' | 'symbolSize', LayoutNode> = { ... }
private let _layoutNodesBasedOn: [String: LayoutNode] = [

    "value": { seriesModel, graph, nodeData, r, cx, cy, count in
        var angle: Double = 0
        let sum = nodeData.getSum("value")
        // const unitAngle = Math.PI * 2 / (sum || count);  — JS `||`: falsy (0/NaN) falls through to count.
        let sumTruthy = (sum != 0 && !sum.isNaN)
        let unitAngle = Double.pi * 2 / (sumTruthy ? sum : count)

        graph.eachNode { node, _ in
            let value = asNumber(node.getValue("value"))
            // const radianHalf = unitAngle * (sum ? value : 1) / 2;  — JS truthiness of `sum`.
            let radianHalf = unitAngle * (sumTruthy ? value : 1) / 2

            angle += radianHalf
            node.setLayout([
                r * cos(angle) + cx,
                r * sin(angle) + cy
            ])
            angle += radianHalf
        }
    },

    "symbolSize": { seriesModel, graph, nodeData, r, cx, cy, count in
        var sumRadian: Double = 0
        // _symbolRadiansHalf.length = count;
        _symbolRadiansHalf = [Double](repeating: 0, count: Int(count))

        let nodeScale = graphHelper.getNodeGlobalScale(seriesModel)

        graph.eachNode { node, _ in
            var symbolSize = graphHelper.getSymbolSize(node)

            // Normally this case will not happen, but we still add
            // some the defensive code (2px is an arbitrary value).
            if symbolSize.isNaN { symbolSize = 2 }
            if symbolSize < 0 { symbolSize = 0 }

            symbolSize *= nodeScale

            var symbolRadianHalf = asin(symbolSize / 2 / r)
            // when `symbolSize / 2` is bigger than `r`.
            if symbolRadianHalf.isNaN { symbolRadianHalf = PI / 2 }
            _symbolRadiansHalf[node.dataIndex] = symbolRadianHalf
            sumRadian += symbolRadianHalf * 2
        }

        let halfRemainRadian = (2 * PI - sumRadian) / count / 2

        var angle: Double = 0
        graph.eachNode { node, _ in
            let radianHalf = halfRemainRadian + _symbolRadiansHalf[node.dataIndex]

            angle += radianHalf
            // init circular layout for
            // 1. layout undefined node
            // 2. not fixed node
            // (!node.getLayout() || !node.getLayout().fixed) && node.setLayout([...]);
            let nl = node.getLayout()
            let notPresent = (nl == nil) || (nl is NSNull)
            if notPresent || !layoutFixed(nl) {
                node.setLayout([
                    r * cos(angle) + cx,
                    r * sin(angle) + cy
                ])
            }
            angle += radianHalf
        }
    }
]

public func rotateNodeLabel(
    _ node: GraphNode,
    _ circularRotateLabel: Bool,
    _ cx: Double,
    _ cy: Double
) {
    // const el = node.getGraphicEl() as Symbol;
    // need to check if el exists. '-' value may not create node element.
    // upstream casts the graphic el to `Symbol` (chart/helper/SymbolElement.swift, now ported)
    // and drives `el.getSymbolPath().setTextConfig(...)` / its emphasis state. Both are wired below.
    guard let el = node.getGraphicEl() as? Symbol else {
        return
    }
    let nodeModel = node.getModel()
    // let labelRotate = nodeModel.get(['label', 'rotate']) || 0;  — JS `||`: falsy -> 0.
    var labelRotate = truthyNumberOr0(nodeModel?.get(["label", "rotate"]))
    // const symbolPath = el.getSymbolPath();
    let symbolPath = el.getSymbolPath()
    if circularRotateLabel {
        let pos = asPoint(node.getLayout())
        var rad = atan2(pos[1] - cy, pos[0] - cx)
        if rad < 0 {
            rad = Double.pi * 2 + rad
        }
        let isLeft = pos[0] < cx
        if isLeft {
            rad = rad - Double.pi
        }
        let textPosition: String = isLeft ? "left" : "right"

        var tc = symbolPath?.textConfig ?? ElementTextConfig()
        tc.rotation = -rad
        tc.position = textPosition
        tc.origin = "center"
        symbolPath?.setTextConfig(tc)
        // const emphasisState = symbolPath.ensureState('emphasis');
        // zrUtil.extend(emphasisState.textConfig ||= {}, { position: textPosition });
        if let symbolPath = symbolPath {
            let emphasisState = symbolPath.ensureState("emphasis")
            if emphasisState.textConfig == nil {
                emphasisState.textConfig = ElementTextConfig()
            }
            emphasisState.textConfig?.position = textPosition
        }
    }
    else {
        // symbolPath.setTextConfig({ rotation: labelRotate *= Math.PI / 180 });
        labelRotate *= Double.pi / 180
        // `setTextConfig` assigns the value bag wholesale in this port. Preserve the position,
        // distance and color config created by setLabelStyle while updating only rotation.
        var tc = symbolPath?.textConfig ?? ElementTextConfig()
        tc.rotation = labelRotate
        symbolPath?.setTextConfig(tc)
    }
}

// MARK: - Port helpers (not upstream symbols)

// Bridge a JS `number[]` 2-vector (<->) to `VectorArray` (SIMD2<Double>) for the vec2 math helpers.
private func toV(_ p: [Double]) -> VectorArray { VectorArray(p[0], p[1]) }
private func toArr(_ v: VectorArray) -> [Double] { [v[0], v[1]] }

private func asNumber(_ v: Any?) -> Double {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    return Double.nan
}

private func asNumberOpt(_ v: Any?) -> Double? {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    return nil
}

private func asPoint(_ layout: Any?) -> [Double] {
    if let a = layout as? [Double] { return a }
    if let a = layout as? [Any] {
        return a.map { (($0 as? Double) ?? Double(($0 as? Int) ?? 0)) }
    }
    return [Double.nan, Double.nan]
}

// `node.getLayout().fixed` — a `fixed` flag carried on the node's layout object (set by force layout).
// A plain `[x, y]` point layout has no `fixed`, so this reads false. note: force layout stores
// the flag as an attached property on the point array (JS); modeled as a dict key here (semantically
// equivalent — a non-dict layout has no flag either way).
private func layoutFixed(_ layout: Any?) -> Bool {
    if let d = layout as? [String: Any] {
        return (d["fixed"] as? Bool) ?? false
    }
    return false
}

// JS `x || 0` for a numeric option: falsy (undefined/null/0/NaN/'') -> 0, else the number.
private func truthyNumberOr0(_ v: Any?) -> Double {
    guard let v = v else { return 0 }
    if let d = v as? Double { return (d != 0 && !d.isNaN) ? d : 0 }
    if let i = v as? Int { return Double(i) }
    return 0
}
