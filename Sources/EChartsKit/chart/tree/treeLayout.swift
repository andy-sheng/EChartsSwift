// Ported from echarts/src/chart/tree/treeLayout.ts — keep in sync with upstream
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
//   import { eachAfter, eachBefore } from './traversalHelper';        -> `traversalHelper.*` (sibling).
//   import { init, firstWalk, secondWalk, separation as sep, radialCoordinate, TreeLayoutNode }
//       from './layoutHelper';                                        -> `layoutHelper.*` (sibling).
//   import GlobalModel from '../../model/Global';                     -> GlobalModel (model/Global.swift).
//   import ExtensionAPI from '../../core/ExtensionAPI';               -> ExtensionAPI (core/ExtensionAPI.swift).
//   import TreeSeriesModel from './TreeSeries';                       -> TreeSeriesModel (sibling TreeSeries.swift).
//   import { createBoxLayoutReference, getLayoutRect } from '../../util/layout';
//       -> `layout.createBoxLayoutReference` / `layout.getLayoutRect` (util/layout.swift).

// NOTE: preserve it as a function rather than StageHandler as a test case of
// `Scheduler['wrapStageHandler']` and `detectSeriseType`.
// upstream `export default function treeLayout(ecModel, api)`.
public func treeLayout(_ ecModel: GlobalModel, _ api: ExtensionAPI) {
    ecModel.eachSeriesByType("tree") { seriesModelBase, _ in
        // upstream typed callback param `seriesModel: TreeSeriesModel`.
        let seriesModel = seriesModelBase as! TreeSeriesModel
        commonLayout(seriesModel, api)
    }
}

private func commonLayout(_ seriesModel: TreeSeriesModel, _ api: ExtensionAPI) {
    let refContainer = layout.createBoxLayoutReference(seriesModel, api).refContainer
    let layoutInfo = layout.getLayoutRect(seriesModel.getBoxLayoutParams(), refContainer)
    seriesModel.layoutInfo = layoutInfo
    // `layout` is the util namespace; the option key is read into `layoutOpt` to avoid shadowing it.
    let layoutOpt = seriesModel.get("layout")
    var width: Double = 0
    var height: Double = 0
    let separation: SeparationFunc

    if (layoutOpt as? String) == "radial" {
        width = 2 * Double.pi
        height = Swift.min(layoutInfo.height, layoutInfo.width) / 2
        separation = layoutHelper.separation({ node1, node2 in
            return (node1.parentNode === node2.parentNode ? 1 : 2) / node1.depth
        })
    }
    else {
        width = layoutInfo.width
        height = layoutInfo.height
        separation = layoutHelper.separation()
    }

    // const virtualRoot = seriesModel.getData().tree.root as TreeLayoutNode;
    let virtualRoot: TreeNode = seriesModel.getData().tree!.root
    // const realRoot = virtualRoot.children[0]; — undefined (nil) when there are no children.
    let realRootOpt: TreeNode? = virtualRoot.children.first

    if let realRoot = realRootOpt {
        layoutHelper.`init`(virtualRoot)
        defer { layoutHelper.clear(virtualRoot) }
        traversalHelper.eachAfter(realRoot, layoutHelper.firstWalk, separation)
        virtualRoot.hierNode.modifier = -realRoot.hierNode.prelim
        traversalHelper.eachBefore(realRoot, layoutHelper.secondWalk)

        var left = realRoot
        var right = realRoot
        var bottom = realRoot
        traversalHelper.eachBefore(realRoot) { node in
            let x = getLayoutX(node)
            if x < getLayoutX(left) {
                left = node
            }
            if x > getLayoutX(right) {
                right = node
            }
            if node.depth > bottom.depth {
                bottom = node
            }
        }

        let delta: Double = (left === right) ? 1 : separation(left, right) / 2
        let tx = delta - getLayoutX(left)
        var kx: Double = 0
        var ky: Double = 0
        var coorX: Double = 0
        var coorY: Double = 0
        if (layoutOpt as? String) == "radial" {
            kx = width / (getLayoutX(right) + delta + tx)
            // here we use (node.depth - 1), bucause the real root's depth is 1
            // ky = height / ((bottom.depth - 1) || 1); — JS `||`: 0 falls through to 1.
            ky = height / ((bottom.depth - 1) != 0 ? (bottom.depth - 1) : 1)
            traversalHelper.eachBefore(realRoot) { node in
                coorX = (getLayoutX(node) + tx) * kx
                coorY = (node.depth - 1) * ky
                let finalCoor = layoutHelper.radialCoordinate(coorX, coorY)
                node.setLayout([
                    "x": finalCoor.x,
                    "y": finalCoor.y,
                    "rawX": coorX,
                    "rawY": coorY
                ] as [String: Any], true)
            }
        }
        else {
            let orient = seriesModel.getOrient()
            if orient == "RL" || orient == "LR" {
                ky = height / (getLayoutX(right) + delta + tx)
                kx = width / ((bottom.depth - 1) != 0 ? (bottom.depth - 1) : 1)
                traversalHelper.eachBefore(realRoot) { node in
                    coorY = (getLayoutX(node) + tx) * ky
                    coorX = orient == "LR"
                        ? (node.depth - 1) * kx
                        : width - (node.depth - 1) * kx
                    node.setLayout(["x": coorX, "y": coorY] as [String: Any], true)
                }
            }
            else if orient == "TB" || orient == "BT" {
                kx = width / (getLayoutX(right) + delta + tx)
                ky = height / ((bottom.depth - 1) != 0 ? (bottom.depth - 1) : 1)
                traversalHelper.eachBefore(realRoot) { node in
                    coorX = (getLayoutX(node) + tx) * kx
                    coorY = orient == "TB"
                        ? (node.depth - 1) * ky
                        : height - (node.depth - 1) * ky
                    node.setLayout(["x": coorX, "y": coorY] as [String: Any], true)
                }
            }
        }
    }
}

// upstream reads `node.getLayout().x`; `getLayout()` returns the dynamic layout bag (`[String: Any]`),
// so the `x` field is coerced back to a Double. Not an upstream symbol.
private func getLayoutX(_ node: TreeNode) -> Double {
    let layout = node.getLayout() as? [String: Any]
    if let d = layout?["x"] as? Double { return d }
    if let i = layout?["x"] as? Int { return Double(i) }
    return 0
}
