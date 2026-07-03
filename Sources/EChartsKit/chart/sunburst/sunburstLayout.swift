// Ported from echarts/src/chart/sunburst/sunburstLayout.ts — keep in sync with upstream
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
//   import { parsePercent } from '../../util/number';               -> `number.parsePercent` (util/number.swift).
//   import * as zrUtil from 'zrender/src/core/util';                -> `util.*` (ZRenderKit).
//   import GlobalModel from '../../model/Global';                   -> GlobalModel (model/Global.swift).
//   import ExtensionAPI from '../../core/ExtensionAPI';             -> ExtensionAPI (core/ExtensionAPI.swift).
//   import SunburstSeriesModel, { SERIES_TYPE_SUNBURST, SunburstSeriesOption } from './SunburstSeries';
//       -> sibling SunburstSeries.swift.
//   import { TreeNode } from '../../data/Tree';                     -> TreeNode (data/Tree.swift, sibling track).
//   import { createSimpleOverallStageHandler } from '../../util/model'; -> `model.createSimpleOverallStageHandler`.

// let PI2 = Math.PI * 2;
// const RADIAN = Math.PI / 180;
private let RADIAN = Double.pi / 180

// upstream:
//   export const sunburstLayoutStageHandler = createSimpleOverallStageHandler(SERIES_TYPE_SUNBURST, sunburstLayout);
// `createSimpleOverallStageHandler` expects a `StageHandlerOverallReset = (GlobalModel, ExtensionAPI,
// Payload?) -> Void`; upstream `sunburstLayout` is `(ecModel, api)` (2-arg). Adapt with a thin wrapper
// that drops the (unused) payload, keeping `sunburstLayout` byte-faithful (2-arg) below.
public let sunburstLayoutStageHandler = model.createSimpleOverallStageHandler(
    SERIES_TYPE_SUNBURST,
    { ecModel, api, _ in sunburstLayout(ecModel, api) }
)

// Exposed for the slim driver to call directly (mirrors pie/funnel layout handlers), matching
// upstream's module-private `function sunburstLayout(ecModel, api)`.
public func sunburstLayout(
    _ ecModel: GlobalModel,
    _ api: ExtensionAPI
) {
    ecModel.eachSeriesByType(SERIES_TYPE_SUNBURST) { seriesModelBase, _ in
        // upstream typed callback param `seriesModel: SunburstSeriesModel`.
        let seriesModel = seriesModelBase as! SunburstSeriesModel

        var center = seriesModel.get("center")
        var radius = seriesModel.get("radius")

        // if (!zrUtil.isArray(radius)) { radius = [0, radius]; }
        if !util.isArray(radius) {
            radius = [0, radius as Any] as [Any]
        }
        // if (!zrUtil.isArray(center)) { center = [center, center]; }
        if !util.isArray(center) {
            center = [center as Any, center as Any] as [Any]
        }
        let radiusArr = (radius as? [Any]) ?? [0, "75%"]
        let centerArr = (center as? [Any]) ?? ["50%", "50%"]

        let width = api.getWidth()
        let height = api.getHeight()
        let size = Swift.min(width, height)
        let cx = number.parsePercent(centerArr[0], width)
        let cy = number.parsePercent(centerArr[1], height)
        let r0 = number.parsePercent(radiusArr[0], size / 2)
        let r = number.parsePercent(radiusArr[1], size / 2)

        let startAngle = -(sunburstAsNumber(seriesModel.get("startAngle"))) * RADIAN
        let minAngle = sunburstAsNumber(seriesModel.get("minAngle")) * RADIAN

        let virtualRoot: TreeNode = seriesModel.getData().tree!.root   // tree present once initTree has run; annotate to unwrap IUO `root`
        let treeRoot = seriesModel.getViewRoot()
        let rootDepth = Double(treeRoot.depth)

        let sort = seriesModel.get("sort")
        // if (sort != null) { initChildren(treeRoot, sort); }
        if sort != nil && !(sort is NSNull) {
            initChildren(treeRoot, sort)
        }

        var validDataCount: Double = 0
        // zrUtil.each(treeRoot.children, function (child) { !isNaN(child.getValue()) && validDataCount++; });
        util.each(treeRoot.children) { child, _ in
            let v = sunburstAsNumber(child.getValue())
            if !v.isNaN { validDataCount += 1 }
        }

        let sum = sunburstAsNumber(treeRoot.getValue())
        // Sum may be 0
        // const unitRadian = Math.PI / (sum || validDataCount) * 2;
        // JS `sum || validDataCount`: 0 AND NaN fall through to validDataCount.
        let unitRadian = Double.pi / ((sum == 0 || sum.isNaN) ? validDataCount : sum) * 2

        // const renderRollupNode = treeRoot.depth > 0;
        let renderRollupNode = Double(treeRoot.depth) > 0
        // const levels = treeRoot.height - (renderRollupNode ? -1 : 1);
        let levels = Double(treeRoot.height) - (renderRollupNode ? -1 : 1)
        // const rPerLevel = (r - r0) / (levels || 1);
        let rPerLevel = (r - r0) / ((levels == 0 || levels.isNaN) ? 1 : levels)

        let clockwise = (seriesModel.get("clockwise") as? Bool) ?? true

        let stillShowZeroSum = (seriesModel.get("stillShowZeroSum") as? Bool) ?? false

        // const dir = clockwise ? 1 : -1;
        let dir: Double = clockwise ? 1 : -1

        /**
         * Render a tree
         * @return increased angle
         */
        // upstream declares `const renderNode = function (node, startAngle) { ... }` (recursive).
        var renderNode: ((TreeNode?, Double) -> Double)!
        renderNode = { node, startAngle in
            // if (!node) { return; }
            //   (unreachable for real children — kept faithful; upstream returns undefined here.)
            guard let node = node else { return 0 }

            var endAngle = startAngle

            // Render self
            if node !== virtualRoot {
                // Tree node is virtual, so it doesn't need to be drawn
                let value = sunburstAsNumber(node.getValue())

                var angle = (sum == 0 && stillShowZeroSum)
                    ? unitRadian : (value * unitRadian)
                if angle < minAngle {
                    angle = minAngle
                    // restAngle -= minAngle;
                }
                // else { valueSumLargerThanMinAngle += value; }

                endAngle = startAngle + dir * angle

                // const depth = node.depth - rootDepth - (renderRollupNode ? -1 : 1);
                let depth = Double(node.depth) - rootDepth
                    - (renderRollupNode ? -1 : 1)
                var rStart = r0 + rPerLevel * depth
                var rEnd = r0 + rPerLevel * (depth + 1)

                let levelModel = seriesModel.getLevelModel(node)
                if let levelModel = levelModel {
                    // upstream deliberately shadows the outer r0/r/radius here.
                    var r0 = levelModel.get("r0", true)
                    var r = levelModel.get("r", true)
                    let radius = levelModel.get("radius", true)

                    if radius != nil {
                        r0 = (radius as? [Any])?[0]
                        r = (radius as? [Any])?[1]
                    }

                    // (r0 != null) && (rStart = parsePercent(r0, size / 2));
                    if r0 != nil { rStart = number.parsePercent(r0, size / 2) }
                    // (r != null) && (rEnd = parsePercent(r, size / 2));
                    if r != nil { rEnd = number.parsePercent(r, size / 2) }
                }

                node.setLayout([
                    "angle": angle,
                    "startAngle": startAngle,
                    "endAngle": endAngle,
                    "clockwise": clockwise,
                    "cx": cx,
                    "cy": cy,
                    "r0": rStart,
                    "r": rEnd
                ] as [String: Any])
            }

            // Render children
            // if (node.children && node.children.length) { ... }
            if !node.children.isEmpty {
                // currentAngle = startAngle;
                var siblingAngle: Double = 0
                util.each(node.children) { child, _ in
                    siblingAngle += renderNode(child, startAngle + siblingAngle)
                }
            }

            return endAngle - startAngle
        }

        // Virtual root node for roll up
        if renderRollupNode {
            let rStart = r0
            let rEnd = r0 + rPerLevel

            let angle = Double.pi * 2
            virtualRoot.setLayout([
                "angle": angle,
                "startAngle": startAngle,
                "endAngle": startAngle + angle,
                "clockwise": clockwise,
                "cx": cx,
                "cy": cy,
                "r0": rStart,
                "r": rEnd
            ] as [String: Any])
        }

        _ = renderNode(treeRoot, startAngle)
    }
}

/**
 * Init node children by order and update visual
 */
// function initChildren(node: TreeNode, sortOrder?: SunburstSeriesOption['sort']) { ... }
func initChildren(_ node: TreeNode, _ sortOrder: Any?) {
    // const children = node.children || [];
    let children = node.children

    // node.children = sort(children, sortOrder);
    node.children = sunburstSort(children, sortOrder)

    // Init children recursively
    if !children.isEmpty {
        util.each(node.children) { child, _ in
            initChildren(child, sortOrder)
        }
    }
}

/**
 * Sort children nodes
 *
 * @param children children of node to be sorted
 * @param sort sort method. See SunburstSeries.js for details.
 */
// upstream `function sort(...)` — renamed `sunburstSort` to avoid clashing with `Array.sort`.
func sunburstSort(_ children: [TreeNode], _ sortOrder: Any?) -> [TreeNode] {
    // if (zrUtil.isFunction(sortOrder)) { ... }
    if let sortFn = sortOrder as? (SortParam, SortParam) -> Double {
        // const sortTargets = zrUtil.map(children, (child, idx) => ({ params: {...}, index: idx }));
        var sortTargets: [(params: SortParam, index: Int)] = util.map(children) { child, idx in
            let value = sunburstAsNumber(child.getValue())
            return (
                params: SortParam(
                    depth: Double(child.depth),
                    height: Double(child.height),
                    dataIndex: Double(child.dataIndex),
                    getValue: { value }
                ),
                index: idx
            )
        }
        // sortTargets.sort((a, b) => sortOrder(a.params, b.params));
        //   JS `Array.prototype.sort` is stable (ES2019); Swift `sort(by:)` is NOT. When the
        //   user comparator returns 0 (equal ranking), fall back to the original index so equal
        //   nodes keep their input order — faithful to the stable JS sort.
        sortTargets.sort { a, b in
            let cmp = sortFn(a.params, b.params)
            return cmp != 0 ? cmp < 0 : a.index < b.index
        }

        // return zrUtil.map(sortTargets, (target) => children[target.index]);
        return util.map(sortTargets) { target, _ in
            return children[target.index]
        }
    }
    else {
        // const isAsc = sortOrder === 'asc';
        let isAsc = (sortOrder as? String) == "asc"
        // return children.sort(function (a, b) { ... });
        var mutableChildren = children
        mutableChildren.sort { a, b in
            let diff = (sunburstAsNumber(a.getValue()) - sunburstAsNumber(b.getValue())) * (isAsc ? 1 : -1)
            let cmp = diff == 0
                ? (Double(a.dataIndex) - Double(b.dataIndex)) * (isAsc ? -1 : 1)
                : diff
            return cmp < 0
        }
        return mutableChildren
    }
}

// upstream `interface SortParam { dataIndex; depth; height; getValue(): number }` — materialized here
// because the (rare) callback form of `sort` consumes it by value.
public struct SortParam {
    public var depth: Double
    public var height: Double
    public var dataIndex: Double
    public var getValue: () -> Double
    public init(depth: Double, height: Double, dataIndex: Double, getValue: @escaping () -> Double) {
        self.depth = depth
        self.height = height
        self.dataIndex = dataIndex
        self.getValue = getValue
    }
}
