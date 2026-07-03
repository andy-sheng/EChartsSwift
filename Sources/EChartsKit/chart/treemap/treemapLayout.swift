// Ported from echarts/src/chart/treemap/treemapLayout.ts — keep in sync with upstream
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

/*
* A third-party license is embedded for some of the code in this file:
* The treemap layout implementation was originally copied from
* "d3.js" with some modifications made for this project.
* (See more details in the comment of the method "squarify" below.)
* The use of the source code of this file is also subject to the terms
* and consitions of the license of "d3.js" (BSD-3Clause, see
* </licenses/LICENSE-d3>).
*/

import Foundation
import ZRenderKit

// upstream imports (mapped to the already-ported siblings / ZRenderKit where available):
//   import * as zrUtil from 'zrender/src/core/util';                    -> `util.*` (ZRenderKit).
//   import BoundingRect, { RectLike } from 'zrender/src/core/BoundingRect'; -> BoundingRect / RectLike (ZRenderKit).
//   import {MAX_SAFE_INTEGER} from '../../util/number';                 -> `number.MAX_SAFE_INTEGER` (util/number.swift).
//   import * as layout from '../../util/layout';                        -> `layout.*` (util/layout.swift).
//   import * as helper from '../helper/treeHelper';                     -> PORT-TODO: treeHelper.ts not ported yet
//       (retrieveTargetInfo / getPathToRoot reimplemented at the bottom of this file).
//   import TreemapSeriesModel, { TreemapSeriesNodeItemOption } from './TreemapSeries'; -> sibling TreemapSeries.swift.
//   import GlobalModel from '../../model/Global';                       -> GlobalModel (model/Global.swift).
//   import ExtensionAPI from '../../core/ExtensionAPI';                 -> ExtensionAPI (core/ExtensionAPI.swift).
//   import { TreeNode } from '../../data/Tree';                         -> TreeNode (data/Tree.swift).
//   import Model from '../../model/Model';                              -> Model (model/Model.swift).
//   import { TreemapRenderPayload, TreemapMovePayload, TreemapZoomToNodePayload } from './treemapAction';
//       -> PORT-TODO: treemapAction.ts not ported; payload read dynamically off `Payload` (util/types.swift).
//   import { initExtentForUnion } from '../../util/model';              -> `model.initExtentForUnion`.
//   import { RoamOptionMixin } from '../../util/types';                 -> type-only (dropped, CONVENTIONS §2).
//   import { clampByZoomLimit } from '../../coord/View';                -> PORT-TODO: coord/View.ts not ported;
//       reimplemented faithfully at the bottom of this file.

// const mathMax = Math.max;  -> `Swift.max`
// const mathMin = Math.min;  -> `Swift.min`
// const each = zrUtil.each;  -> `util.each`

private let PATH_BORDER_WIDTH = ["itemStyle", "borderWidth"]
private let PATH_GAP_WIDTH = ["itemStyle", "gapWidth"]
private let PATH_UPPER_LABEL_SHOW = ["upperLabel", "show"]
private let PATH_UPPER_LABEL_HEIGHT = ["upperLabel", "height"]

// interface TreemapLayoutNode extends TreeNode { parentNode; children; viewChildren }
// TreeNode is a `final class` (can't be subclassed); upstream only narrows the field types, so
// alias TreemapLayoutNode -> TreeNode and use TreeNode's `parentNode`/`children`/`viewChildren`.
public typealias TreemapLayoutNode = TreeNode

// interface TreemapItemLayout extends RectLike { ... }
// The layout is stored/merged at runtime as a dynamic `[String: Any]` dict (upstream builds it with
// partial object literals + `setLayout(..., true)` merge — CONVENTIONS §2). This struct documents the
// full shape produced by the layout; it is not the runtime storage type.
public struct TreemapItemLayout {
    // RectLike
    public var x: Double = 0
    public var y: Double = 0
    public var width: Double = 0
    public var height: Double = 0

    public var area: Double = 0
    public var isLeafRoot: Bool = false
    public var dataExtent: [Double] = [Double.nan, Double.nan]

    public var borderWidth: Double = 0
    public var upperHeight: Double = 0
    public var upperLabelHeight: Double = 0

    public var isInView: Bool = false
    public var invisible: Bool = false

    public var isAboveViewRoot: Bool = false

    public init() {}
}

// type NodeModel = Model<TreemapSeriesNodeItemOption>;  -> Model.

// type OrderBy = 'asc' | 'desc' | boolean;  -> modeled as `Any?` (String / Bool / nil).

// type LayoutRow = TreemapLayoutNode[] & { area: number };
// A JS array carrying an extra `area` property; modeled as a value struct with `nodes` + `area`.
private struct LayoutRow {
    var nodes: [TreemapLayoutNode] = []
    var area: Double = 0
}

// upstream options bag passed to `squarify` / `initChildren`: { sort?, squareRatio?, leafDepth? }.
private struct SquarifyOptions {
    var squareRatio: Double
    var sort: Any?
    var leafDepth: Double?
}

/**
 * @public
 */
// upstream: `export default { seriesType: 'treemap', reset: function (seriesModel, ecModel, api, payload?) {...} }`
// modeled as a `StageHandler` value carrying `seriesType` + `reset` (matches candlestick/boxplot idiom).
public let treemapLayout: StageHandler = {
    var handler = StageHandler()

    handler.seriesType = "treemap"

    handler.reset = { (seriesModelBase: SeriesModel, _ ecModel: GlobalModel, _ api: ExtensionAPI, _ payload: Payload?) -> Any? in
        // upstream typed `seriesModel: TreemapSeriesModel`.
        treemapLayoutReset(seriesModelBase as! TreemapSeriesModel, ecModel, api, payload)
        return nil
    }

    return handler
}()

// Exposed for direct invocation (mirrors sibling layout handlers); byte-faithful to the upstream
// `reset` function body.
public func treemapLayoutReset(
    _ seriesModel: TreemapSeriesModel,
    _ ecModel: GlobalModel,
    _ api: ExtensionAPI,
    _ payload: Payload?
) {
    // Layout result in each node:
    // {x, y, width, height, area, borderWidth}
    // const seriesOption = seriesModel.option;
    let seriesOptionDict = (seriesModel.option as? [String: Any])

    let refContainer = layout.createBoxLayoutReference(seriesModel, api).refContainer
    let layoutInfo = layout.getLayoutRect(seriesModel.getBoxLayoutParams(), refContainer)

    // Fetch payload info.
    let payloadType = payload?.type
    let types = ["treemapZoomToNode", "treemapRootToNode"]
    let targetInfo = retrieveTargetInfo(payload, types, seriesModel)
    // const rootRect = (payloadType === 'treemapRender' || payloadType === 'treemapMove') ? payload.rootRect : null;
    // PORT-TODO: upstream `payload.rootRect: RectLike`; read dynamically off `Payload.other`.
    let rootRect: [String: Double]? = (payloadType == "treemapRender" || payloadType == "treemapMove")
        ? (payload?.other["rootRect"] as? [String: Double])
        : nil
    // const viewRoot = seriesModel.getViewRoot();
    //   `getViewRoot()` is `TreeNode?` in the sibling port (upstream is non-null); bail if absent
    //   (an unrooted series has nothing to lay out).
    guard let viewRoot = seriesModel.getViewRoot() else { return }
    let viewAbovePath = getPathToRoot(viewRoot)

    if payloadType != "treemapMove" {
        var needClampZoom = false
        // const rootSize: Pick<RectLike, 'width' | 'height'> = ...
        var rootSize: (width: Double, height: Double)
        if payloadType == "treemapZoomToNode" {
            needClampZoom = true
            rootSize = estimateRootSize(seriesModel, targetInfo, viewRoot, (width: layoutInfo.width, height: layoutInfo.height))
        }
        else if let rootRect = rootRect {
            needClampZoom = true
            // zrUtil.extend({}, rootRect)
            rootSize = (width: rootRect["width"] ?? 0, height: rootRect["height"] ?? 0)
        }
        else {
            // zrUtil.extend({}, layoutInfo)
            rootSize = (width: layoutInfo.width, height: layoutInfo.height)
        }

        if needClampZoom {
            var zoom = calculateCurrentZoom((width: layoutInfo.width, height: layoutInfo.height), rootSize)
            zoom = treemapClampZoom(zoom, seriesModel)
            rootSize.width = layoutInfo.width * zoom
            rootSize.height = layoutInfo.height * zoom
        }

        // let sort = seriesOption.sort;
        var sort: Any? = seriesOptionDict?["sort"]
        // if (sort && sort !== 'asc' && sort !== 'desc') { sort = 'desc'; }
        if jsTruthy(sort) && (sort as? String) != "asc" && (sort as? String) != "desc" {
            // Default to be desc order.
            sort = "desc"
        }
        // const options = { squareRatio, sort, leafDepth };
        let leafDepthRaw = seriesOptionDict?["leafDepth"]
        let options = SquarifyOptions(
            squareRatio: treemapAsNumber(seriesOptionDict?["squareRatio"]),
            sort: sort,
            leafDepth: (leafDepthRaw == nil || leafDepthRaw is NSNull) ? nil : treemapAsNumber(leafDepthRaw)
        )

        // layout should be cleared because using updateView but not update.
        viewRoot.hostTree.clearLayouts()

        // TODO
        // optimize: if out of view clip, do not layout.
        // But take care that if do not render node out of view clip,
        // how to calculate start po

        // let viewRootLayout = { x, y, width, height, area };
        var viewRootLayout: [String: Any] = [
            "x": 0.0,
            "y": 0.0,
            "width": rootSize.width,
            "height": rootSize.height,
            "area": rootSize.width * rootSize.height
        ]
        viewRoot.setLayout(viewRootLayout)

        squarify(viewRoot, options, false, 0)
        // Supplement layout.
        viewRootLayout = (viewRoot.getLayout() as? [String: Any]) ?? [:]
        util.each(viewAbovePath) { (node: TreemapLayoutNode, index: Int) in
            // const childValue = (viewAbovePath[index + 1] || viewRoot).getValue();
            let childNode = (index + 1 < viewAbovePath.count) ? viewAbovePath[index + 1] : viewRoot
            let childValue = treemapAsNumber(childNode.getValue())
            // node.setLayout(zrUtil.extend({dataExtent, borderWidth, upperHeight}, viewRootLayout));
            var merged: [String: Any] = [
                "dataExtent": [childValue, childValue],
                "borderWidth": 0.0,
                "upperHeight": 0.0
            ]
            for (k, v) in viewRootLayout { merged[k] = v }
            node.setLayout(merged)
        }
    }

    let treeRoot: TreemapLayoutNode = seriesModel.getData().tree!.root

    treeRoot.setLayout(
        calculateRootPosition(layoutInfo, rootRect, targetInfo),
        true
    )

    seriesModel.setLayoutInfo(layoutInfo)

    // FIXME: narrow down pruning boungding rect.
    // Currently ec width/height is used becuases clip is not supported.
    prunning(
        treeRoot,
        // Transform to base element coordinate system.
        BoundingRect(-layoutInfo.x, -layoutInfo.y, api.getWidth(), api.getHeight()),
        viewAbovePath,
        viewRoot,
        0
    )
}

/**
 * Layout treemap with squarify algorithm.
 * The original presentation of this algorithm
 * was made by Mark Bruls, Kees Huizing, and Jarke J. van Wijk
 * <https://graphics.ethz.ch/teaching/scivis_common/Literature/squarifiedTreeMaps.pdf>.
 * The implementation of this algorithm was originally copied from "d3.js"
 * <https://github.com/d3/d3/blob/9cc9a875e636a1dcf36cc1e07bdf77e1ad6e2c74/src/layout/treemap.js>
 * with some modifications made for this program.
 * See the license statement at the head of this file.
 */
private func squarify(
    _ node: TreemapLayoutNode,
    _ options: SquarifyOptions,
    _ hideChildren: Bool,
    _ depth: Double
) {
    var hideChildren = hideChildren
    var width: Double
    var height: Double

    if node.isRemoved() {
        return
    }

    let thisLayout = node.getLayout()
    width = layoutNum(thisLayout, "width")
    height = layoutNum(thisLayout, "height")

    // Considering border and gap
    // const nodeModel = node.getModel<TreemapSeriesNodeItemOption>();
    let nodeModel = node.getModel()!
    let borderWidth = treemapAsNumber(nodeModel.get(PATH_BORDER_WIDTH))
    let halfGapWidth = treemapAsNumber(nodeModel.get(PATH_GAP_WIDTH)) / 2
    let upperLabelHeight = getUpperLabelHeight(nodeModel)
    let upperHeight = Swift.max(borderWidth, upperLabelHeight)
    let layoutOffset = borderWidth - halfGapWidth
    let layoutOffsetUpper = upperHeight - halfGapWidth

    node.setLayout([
        "borderWidth": borderWidth,
        "upperHeight": upperHeight,
        "upperLabelHeight": upperLabelHeight
    ] as [String: Any], true)

    width = Swift.max(width - 2 * layoutOffset, 0)
    height = Swift.max(height - layoutOffset - layoutOffsetUpper, 0)

    let totalArea = width * height
    let viewChildren = initChildren(
        node, nodeModel, totalArea, options, hideChildren, depth
    )

    if viewChildren.isEmpty {
        return
    }

    var rect: [String: Double] = ["x": layoutOffset, "y": layoutOffsetUpper, "width": width, "height": height]
    var rowFixedLength = Swift.min(width, height)
    var best = Double.infinity // the best row score so far
    var row = LayoutRow()
    row.area = 0

    var i = 0
    let len = viewChildren.count
    while i < len {
        let child = viewChildren[i]

        row.nodes.append(child)
        row.area += layoutNum(child.getLayout(), "area")
        let score = worst(row, rowFixedLength, options.squareRatio)

        // continue with this orientation
        if score <= best {
            i += 1
            best = score
        }
        // abort, and try a different orientation
        else {
            let popped = row.nodes.removeLast()
            row.area -= layoutNum(popped.getLayout(), "area")
            position(row, rowFixedLength, &rect, halfGapWidth, false)
            rowFixedLength = Swift.min(rect["width"]!, rect["height"]!)
            row.nodes = []
            row.area = 0
            best = Double.infinity
        }
    }

    if !row.nodes.isEmpty {
        position(row, rowFixedLength, &rect, halfGapWidth, true)
    }

    if !hideChildren {
        let childrenVisibleMin = nodeModel.get("childrenVisibleMin")
        if childrenVisibleMin != nil && !(childrenVisibleMin is NSNull) && totalArea < treemapAsNumber(childrenVisibleMin) {
            hideChildren = true
        }
    }

    for i in 0..<viewChildren.count {
        squarify(viewChildren[i], options, hideChildren, depth + 1)
    }
}

/**
 * Set area to each child, and calculate data extent for visual coding.
 */
private func initChildren(
    _ node: TreemapLayoutNode,
    _ nodeModel: Model,
    _ totalArea: Double,
    _ options: SquarifyOptions,
    _ hideChildren: Bool,
    _ depth: Double
) -> [TreemapLayoutNode] {
    // let viewChildren = node.children || [];
    var viewChildren = node.children
    var orderBy: Any? = options.sort
    // orderBy !== 'asc' && orderBy !== 'desc' && (orderBy = null);
    if (orderBy as? String) != "asc" && (orderBy as? String) != "desc" {
        orderBy = nil
    }

    let overLeafDepth = options.leafDepth != nil && options.leafDepth! <= depth

    // leafDepth has higher priority.
    if hideChildren && !overLeafDepth {
        node.viewChildren = []
        return node.viewChildren
    }

    // Sort children, order by desc.
    viewChildren = util.filter(viewChildren) { child, _ in
        return !child.isRemoved()
    }

    viewChildren = treemapSort(viewChildren, orderBy)

    var info = statistic(nodeModel, viewChildren, orderBy)

    if info.sum == 0 {
        node.viewChildren = []
        return node.viewChildren
    }

    info.sum = filterByThreshold(nodeModel, totalArea, info.sum, orderBy, &viewChildren)

    if info.sum == 0 {
        node.viewChildren = []
        return node.viewChildren
    }

    // Set area to each child.
    for i in 0..<viewChildren.count {
        let area = treemapAsNumber(viewChildren[i].getValue()) / info.sum * totalArea
        // Do not use setLayout({...}, true), because it is needed to clear last layout.
        viewChildren[i].setLayout([
            "area": area
        ] as [String: Any])
    }

    if overLeafDepth {
        if !viewChildren.isEmpty {
            node.setLayout([
                "isLeafRoot": true
            ] as [String: Any], true)
        }
        viewChildren = []
    }

    node.viewChildren = viewChildren
    node.setLayout([
        "dataExtent": info.dataExtent
    ] as [String: Any], true)

    return viewChildren
}

/**
 * Consider 'visibleMin'. Modify viewChildren and get new sum.
 */
private func filterByThreshold(
    _ nodeModel: Model,
    _ totalArea: Double,
    _ sum: Double,
    _ orderBy: Any?,
    _ orderedChildren: inout [TreemapLayoutNode]
) -> Double {
    var sum = sum

    // visibleMin is not supported yet when no option.sort.
    if !jsTruthy(orderBy) {
        return sum
    }

    let visibleMin = treemapAsNumber(nodeModel.get("visibleMin"))
    let len = orderedChildren.count
    var deletePoint = len

    // Always travel from little value to big value.
    var i = len - 1
    while i >= 0 {
        let value = treemapAsNumber(orderedChildren[
            (orderBy as? String) == "asc" ? len - i - 1 : i
        ].getValue())

        if value / sum * totalArea < visibleMin {
            deletePoint = i
            sum -= value
        }
        i -= 1
    }

    if (orderBy as? String) == "asc" {
        // orderedChildren.splice(0, len - deletePoint)
        orderedChildren.removeSubrange(0..<(len - deletePoint))
    }
    else {
        // orderedChildren.splice(deletePoint, len - deletePoint)
        orderedChildren.removeSubrange(deletePoint..<len)
    }

    return sum
}

/**
 * Sort
 */
// upstream `function sort(...)` — renamed `treemapSort` to avoid clashing with `Array.sort` (mirrors
// sunburstLayout.swift's `sunburstSort`). Value-returning: upstream sorts in place and relies on the
// caller reusing the same array; the caller here reassigns the result.
private func treemapSort(
    _ viewChildren: [TreemapLayoutNode],
    _ orderBy: Any?
) -> [TreemapLayoutNode] {
    if jsTruthy(orderBy) {
        let isAsc = (orderBy as? String) == "asc"
        var mutableChildren = viewChildren
        // viewChildren.sort(function (a, b) { ... });
        //   JS `Array.prototype.sort` is stable; the comparator already tiebreaks equal values by
        //   dataIndex, so it never returns 0 for distinct nodes — `<` is a valid strict ordering.
        mutableChildren.sort { a, b in
            let diff = isAsc
                ? treemapAsNumber(a.getValue()) - treemapAsNumber(b.getValue())
                : treemapAsNumber(b.getValue()) - treemapAsNumber(a.getValue())
            let cmp = diff == 0
                ? (isAsc
                    ? Double(a.dataIndex) - Double(b.dataIndex) : Double(b.dataIndex) - Double(a.dataIndex)
                )
                : diff
            return cmp < 0
        }
        return mutableChildren
    }
    return viewChildren
}

/**
 * Statistic
 */
private func statistic(
    _ nodeModel: Model,
    _ children: [TreemapLayoutNode],
    _ orderBy: Any?
) -> (sum: Double, dataExtent: [Double]) {
    // Calculate sum.
    var sum: Double = 0
    for i in 0..<children.count {
        sum += treemapAsNumber(children[i].getValue())
    }

    // Statistic data extent for latter visual coding.
    // Notice: data extent should be calculate based on raw children
    // but not filtered view children, otherwise visual mapping will not
    // be stable when zoom (where children is filtered by visibleMin).

    let dimension = nodeModel.get("visualDimension")
    var dataExtent: [Double]

    // The same as area dimension.
    if children.isEmpty {
        dataExtent = [Double.nan, Double.nan]
    }
    else if (dimension as? String) == "value" && jsTruthy(orderBy) {
        dataExtent = [
            treemapAsNumber(children[children.count - 1].getValue()),
            treemapAsNumber(children[0].getValue())
        ]
        if (orderBy as? String) == "asc" { dataExtent.reverse() }
    }
    // Other dimension.
    else {
        dataExtent = model.initExtentForUnion()
        util.each(children) { child, _ in
            let value = treemapAsNumber(child.getValue(dimension))
            if value < dataExtent[0] { dataExtent[0] = value }
            if value > dataExtent[1] { dataExtent[1] = value }
        }
    }

    return (sum: sum, dataExtent: dataExtent)
}

/**
 * Computes the score for the specified row,
 * as the worst aspect ratio.
 */
private func worst(_ row: LayoutRow, _ rowFixedLength: Double, _ ratio: Double) -> Double {
    var areaMax: Double = 0
    var areaMin = Double.infinity

    for i in 0..<row.nodes.count {
        let area = layoutNum(row.nodes[i].getLayout(), "area")
        // if (area) { ... }  — JS truthy: 0 and NaN are falsy.
        if area != 0 && !area.isNaN {
            if area < areaMin { areaMin = area }
            if area > areaMax { areaMax = area }
        }
    }

    let squareArea = row.area * row.area
    let f = rowFixedLength * rowFixedLength * ratio

    // return squareArea ? mathMax(...) : Infinity;  — JS truthy on squareArea.
    return (squareArea != 0 && !squareArea.isNaN)
        ? Swift.max(
            (f * areaMax) / squareArea,
            squareArea / (f * areaMin)
        )
        : Double.infinity
}

/**
 * Positions the specified row of nodes. Modifies `rect`.
 */
private func position(
    _ row: LayoutRow,
    _ rowFixedLength: Double,
    _ rect: inout [String: Double],
    _ halfGapWidth: Double,
    _ flush: Bool = false
) {
    // When rowFixedLength === rect.width,
    // it is horizontal subdivision,
    // rowFixedLength is the width of the subdivision,
    // rowOtherLength is the height of the subdivision,
    // and nodes will be positioned from left to right.

    // wh[idx0WhenH] means: when horizontal,
    //      wh[idx0WhenH] => wh[0] => 'width'.
    //      xy[idx1WhenH] => xy[1] => 'y'.
    let idx0WhenH = rowFixedLength == rect["width"]! ? 0 : 1
    let idx1WhenH = 1 - idx0WhenH
    let xy = ["x", "y"]
    let wh = ["width", "height"]

    var last = rect[xy[idx0WhenH]]!
    var rowOtherLength = rowFixedLength != 0
        ? row.area / rowFixedLength : 0

    if flush || rowOtherLength > rect[wh[idx1WhenH]]! {
        rowOtherLength = rect[wh[idx1WhenH]]! // over+underflow
    }
    for i in 0..<row.nodes.count {
        let node = row.nodes[i]
        var nodeLayout: [String: Any] = [:]
        let step = rowOtherLength != 0
            ? layoutNum(node.getLayout(), "area") / rowOtherLength : 0

        let wh1 = Swift.max(rowOtherLength - 2 * halfGapWidth, 0)
        nodeLayout[wh[idx1WhenH]] = wh1

        // We use Math.max/min to avoid negative width/height when considering gap width.
        let remain = rect[xy[idx0WhenH]]! + rect[wh[idx0WhenH]]! - last
        let modWH = (i == row.nodes.count - 1 || remain < step) ? remain : step
        let wh0 = Swift.max(modWH - 2 * halfGapWidth, 0)
        nodeLayout[wh[idx0WhenH]] = wh0

        nodeLayout[xy[idx1WhenH]] = rect[xy[idx1WhenH]]! + Swift.min(halfGapWidth, wh1 / 2)
        nodeLayout[xy[idx0WhenH]] = last + Swift.min(halfGapWidth, wh0 / 2)

        last += modWH
        node.setLayout(nodeLayout, true)
    }

    rect[xy[idx1WhenH]]! += rowOtherLength
    rect[wh[idx1WhenH]]! -= rowOtherLength
}

// Return containerSize as default.
private func estimateRootSize(
    _ seriesModel: TreemapSeriesModel,
    _ targetInfo: TargetInfo?,
    _ viewRoot: TreemapLayoutNode,
    _ containerSize: (width: Double, height: Double)
) -> (width: Double, height: Double) {
    // If targetInfo.node exists, we zoom to the node,
    // so estimate whole width and height by target node.
    // let currNode = (targetInfo || {}).node;
    var currNode: TreemapLayoutNode? = targetInfo?.node
    let containerWidth = containerSize.width
    let containerHeight = containerSize.height
    let defaultSize = (width: containerWidth, height: containerHeight)

    if currNode == nil || currNode === viewRoot {
        return defaultSize
    }

    var parent: TreemapLayoutNode?
    let viewArea = containerWidth * containerHeight
    // let area = viewArea * seriesModel.option.zoomToNodeRatio;
    var area = viewArea * treemapAsNumber((seriesModel.option as? [String: Any])?["zoomToNodeRatio"])

    // while (parent = currNode.parentNode) { ... }
    parent = currNode?.parentNode
    while let p = parent {
        var sum: Double = 0
        let siblings = p.children

        for i in 0..<siblings.count {
            sum += treemapAsNumber(siblings[i].getValue())
        }
        let currNodeValue = treemapAsNumber(currNode!.getValue())
        if currNodeValue == 0 {
            return defaultSize
        }
        area *= sum / currNodeValue

        // Considering border, suppose aspect ratio is 1.
        // const parentModel = parent.getModel<TreemapSeriesNodeItemOption>();
        let parentModel = p.getModel()!
        let borderWidth = treemapAsNumber(parentModel.get(PATH_BORDER_WIDTH))
        let upperHeight = Swift.max(borderWidth, getUpperLabelHeight(parentModel))
        area += 4 * borderWidth * borderWidth
            + (3 * borderWidth + upperHeight) * pow(area, 0.5)

        if area > number.MAX_SAFE_INTEGER { area = number.MAX_SAFE_INTEGER }

        currNode = p
        parent = p.parentNode
    }

    if area < viewArea { area = viewArea }
    let scale = pow(area / viewArea, 0.5)

    return (width: containerWidth * scale, height: containerHeight * scale)
}

// Root position based on coord of containerGroup
private func calculateRootPosition(
    _ layoutInfo: LayoutRect,
    _ rootRect: [String: Double]?,
    _ targetInfo: TargetInfo?
) -> [String: Any] {
    if let rootRect = rootRect {
        return ["x": rootRect["x"] ?? 0, "y": rootRect["y"] ?? 0]
    }

    let defaultPosition: [String: Any] = ["x": 0.0, "y": 0.0]
    guard let targetInfo = targetInfo else {
        return defaultPosition
    }

    // If targetInfo is fetched by 'retrieveTargetInfo',
    // old tree and new tree are the same tree,
    // so the node still exists and we can visit it.

    let targetNode = targetInfo.node
    let layoutAny = targetNode.getLayout()

    guard let layoutDict = layoutAny as? [String: Any] else {
        return defaultPosition
    }

    // Transform coord from local to container.
    var targetCenter = [layoutNum(layoutDict, "width") / 2, layoutNum(layoutDict, "height") / 2]
    var node: TreemapLayoutNode? = targetNode
    while let n = node {
        let nodeLayout = n.getLayout()
        targetCenter[0] += layoutNum(nodeLayout, "x")
        targetCenter[1] += layoutNum(nodeLayout, "y")
        node = n.parentNode
    }

    return [
        "x": layoutInfo.width / 2 - targetCenter[0],
        "y": layoutInfo.height / 2 - targetCenter[1]
    ]
}

// Mark nodes visible for prunning when visual coding and rendering.
// Prunning depends on layout and root position, so we have to do it after layout.
private func prunning(
    _ node: TreemapLayoutNode,
    _ clipRect: BoundingRect,
    _ viewAbovePath: [TreemapLayoutNode],
    _ viewRoot: TreemapLayoutNode,
    _ depth: Double
) {
    let nodeLayoutAny = node.getLayout()
    let depthIdx = Int(depth)
    let nodeInViewAbovePath: TreemapLayoutNode? = (depthIdx >= 0 && depthIdx < viewAbovePath.count)
        ? viewAbovePath[depthIdx] : nil
    let isAboveViewRoot = nodeInViewAbovePath != nil && nodeInViewAbovePath === node

    if
        (nodeInViewAbovePath != nil && !isAboveViewRoot)
        || (Int(depth) == viewAbovePath.count && node !== viewRoot) {
        return
    }

    // clipRect.intersect(nodeLayout) — nodeLayout is a RectLike; wrap the dict as a BoundingRect.
    let nodeRect = BoundingRect(
        layoutNum(nodeLayoutAny, "x"),
        layoutNum(nodeLayoutAny, "y"),
        layoutNum(nodeLayoutAny, "width"),
        layoutNum(nodeLayoutAny, "height")
    )

    node.setLayout([
        // isInView means: viewRoot sub tree + viewAbovePath
        "isInView": true,
        // invisible only means: outside view clip so that the node can not
        // see but still layout for animation preparation but not render.
        "invisible": !isAboveViewRoot && !clipRect.intersect(nodeRect),
        "isAboveViewRoot": isAboveViewRoot
    ] as [String: Any], true)

    // Transform to child coordinate.
    let childClipRect = BoundingRect(
        clipRect.x - layoutNum(nodeLayoutAny, "x"),
        clipRect.y - layoutNum(nodeLayoutAny, "y"),
        clipRect.width,
        clipRect.height
    )

    util.each(node.viewChildren) { child, _ in
        prunning(child, childClipRect, viewAbovePath, viewRoot, depth + 1)
    }
}

private func getUpperLabelHeight(_ model: Model) -> Double {
    // return model.get(PATH_UPPER_LABEL_SHOW) ? model.get(PATH_UPPER_LABEL_HEIGHT) : 0;
    return jsTruthy(model.get(PATH_UPPER_LABEL_SHOW)) ? treemapAsNumber(model.get(PATH_UPPER_LABEL_HEIGHT)) : 0
}

public func calculateCurrentZoom(
    _ baseSize: (width: Double, height: Double),
    _ currSize: (width: Double, height: Double)
) -> Double {
    // width ratio and height ratio are suppposed to be the same.
    // return (currSize.width / baseSize.width) || (currSize.height / baseSize.height) || 1;
    // JS `||` truthy: a `0` or `NaN` ratio falls through; `Infinity` (x/0) is truthy and returned.
    let a = currSize.width / baseSize.width
    if a != 0 && !a.isNaN { return a }
    let b = currSize.height / baseSize.height
    if b != 0 && !b.isNaN { return b }
    return 1
}

public func treemapClampZoom(_ zoom: Double, _ seriesModel: TreemapSeriesModel) -> Double {
    return clampByZoomLimit(zoom, seriesModel.get("scaleLimit", true))
}

// ---- helpers not present verbatim upstream (port scaffolding) ----

// upstream `interface { node: TreemapLayoutNode }` returned by helper.retrieveTargetInfo.
private struct TargetInfo {
    var node: TreemapLayoutNode
}

// PORT-TODO: upstream `helper.retrieveTargetInfo(payload, types, seriesModel)` from
//   '../helper/treeHelper' resolves the payload's target node for the `treemapZoomToNode` /
//   `treemapRootToNode` actions. treeHelper.ts is not ported yet, so this returns nil (no target),
//   which drives the container-size / default-root-position branches (the non-action render path).
private func retrieveTargetInfo(
    _ payload: Payload?,
    _ types: [String],
    _ seriesModel: TreemapSeriesModel
) -> TargetInfo? {
    return nil
}

// PORT-TODO: upstream `helper.getPathToRoot(node)` from '../helper/treeHelper'. Reimplemented
//   verbatim here until treeHelper.ts is ported. Note upstream advances to `parentNode` BEFORE
//   pushing, so the returned path EXCLUDES `node` itself: [root, ..., node.parentNode].
private func getPathToRoot(_ node: TreemapLayoutNode) -> [TreemapLayoutNode] {
    var path: [TreemapLayoutNode] = []
    var node: TreemapLayoutNode? = node
    while node != nil {
        node = node?.parentNode
        if let n = node { path.append(n) }
    }
    path.reverse()
    return path
}

// PORT-TODO: upstream `import { clampByZoomLimit } from '../../coord/View'`. coord/View.ts is not
//   ported yet; reimplemented faithfully (View.clampByZoomLimit).
private func clampByZoomLimit(_ zoom: Double, _ zoomLimit: Any?) -> Double {
    if let zoomLimit = zoomLimit as? [String: Any], jsTruthy(zoomLimit) {
        // const zoomMin = zoomLimit.min || 0;
        let zoomMin = jsOr(zoomLimit["min"], 0)
        // const zoomMax = zoomLimit.max || Infinity;
        let zoomMax = jsOr(zoomLimit["max"], Double.infinity)
        return Swift.max(
            Swift.min(zoomMax, zoom),
            zoomMin
        )
    }
    return zoom
}

// JS `x as number` coercion shim for the dynamic option/value bag (mirrors sunburstAsNumber):
// a number stays; a leading array element is unwrapped; everything else -> NaN.
private func treemapAsNumber(_ v: Any?) -> Double {
    guard let v = v else { return Double.nan }
    if v is NSNull { return Double.nan }
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let arr = v as? [Any] { return treemapAsNumber(arr.first ?? nil) }
    return Double.nan
}

// Read a numeric field out of a node's dynamic `[String: Any]` layout dict (NaN when absent).
private func layoutNum(_ layout: Any?, _ key: String) -> Double {
    guard let dict = layout as? [String: Any], let v = dict[key] else { return Double.nan }
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    return Double.nan
}

// Mirrors JS `||`/`&&` truthiness for a dynamic `Any?` (nil / NSNull / false / 0 / NaN / "" are falsy).
private func jsTruthy(_ v: Any?) -> Bool {
    guard let v = v else { return false }
    if v is NSNull { return false }
    if let b = v as? Bool { return b }
    if let n = v as? Double { return n != 0 && !n.isNaN }
    if let i = v as? Int { return i != 0 }
    if let s = v as? String { return !s.isEmpty }
    return true
}

// JS `a || fallback` numeric coercion: return Number(a) unless `a` is falsy, then `fallback`.
private func jsOr(_ v: Any?, _ fallback: Double) -> Double {
    return jsTruthy(v) ? treemapAsNumber(v) : fallback
}
