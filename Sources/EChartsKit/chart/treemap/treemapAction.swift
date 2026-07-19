// Ported from echarts/src/chart/treemap/treemapAction.ts — keep in sync with upstream.
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
//   import * as helper from '../helper/treeHelper';                          -> `treeHelper` (chart/helper/treeHelper.swift).
//   import { Payload } from '../../util/types';                              -> Payload (util/types.swift).
//   import TreemapSeriesModel from './TreemapSeries';                        -> sibling TreemapSeries.swift.
//   import { TreeNode } from '../../data/Tree';                              -> TreeNode (data/Tree.swift).
//   import { RectLike } from 'zrender/src/core/BoundingRect';                -> RectLike (ZRenderKit); only used by the
//       deferred payload interfaces below (rootRect never read by the ported handlers).
//   import { EChartsExtensionInstallRegisters } from '../../extension';      -> EChartsExtensionInstallRegisters.
//   import { noop } from 'zrender/src/core/util';                           -> a local no-op ActionHandler (see below).

// const actionTypes = ['treemapZoomToNode', 'treemapRender', 'treemapMove'];
private let treemapActionTypes = [
    "treemapZoomToNode",
    "treemapRender",
    "treemapMove"
]

// upstream payload interfaces (TreemapZoomToNodePayload / TreemapRenderPayload / TreemapMovePayload /
//   TreemapRootToNodePayload) — the port carries their fields (targetNode / targetNodeId / direction, and the
//   `seriesId` / `seriesIndex` query) on the dynamic `Payload.other` bag; no distinct Swift structs are needed.

// Local `noop` ActionHandler (upstream `noop` from zrender/core/util, typed as an action handler here).
private let treemapNoopAction: ActionHandler = { _, _, _ in nil }

// upstream: export function installTreemapAction(registers: EChartsExtensionInstallRegisters)
public func installTreemapAction(_ registers: EChartsExtensionInstallRegisters) {
    _ = registers

    // for (let i = 0; i < actionTypes.length; i++) {
    //     registers.registerAction({ type: actionTypes[i], update: 'updateView' }, noop);
    // }
    //   `treemapMove` / `treemapRender` roam is handled by the view-group RoamController (the port's
    //   'treemapRoam' action); these noop registrations just make the three types dispatchable, with
    //   `update:'updateView'` collapsing to the driver's updateView re-render after the (empty) handler.
    for actionType in treemapActionTypes {
        var info = ActionInfo(type: actionType)
        info.update = "updateView"
        registerAction(info, treemapNoopAction)
    }

    // registers.registerAction({ type: 'treemapRootToNode', update: 'updateView' }, function (payload, ecModel) {...})
    var rootToNode = ActionInfo(type: "treemapRootToNode")
    rootToNode.update = "updateView"
    registerAction(rootToNode) { payload, ecModel, _ in
        // ecModel.eachComponent({ mainType: 'series', subType: 'treemap', query: payload }, handleRootToNode);
        //   The `query: payload` (a `seriesId` / `seriesIndex` filter) is resolved by iterating the treemap
        //   series and matching the payload — the same idiom installTreeAction / installSankeyAction use.
        var payload = payload
        let targetSeriesId = payload.other["seriesId"] as? String
        let targetSeriesIndex = treemapActionInt(payload.other["seriesIndex"])

        ecModel.eachSeriesByType("treemap") { s, index in
            guard let model = s as? TreemapSeriesModel else { return }
            if let sid = targetSeriesId, !sid.isEmpty, model.id != sid { return }
            if let sIndex = targetSeriesIndex, Double(sIndex) != index { return }

            // function handleRootToNode(model, index) {
            //   const types = ['treemapZoomToNode', 'treemapRootToNode'];
            //   const targetInfo = helper.retrieveTargetInfo(payload, types, model);
            let types = ["treemapZoomToNode", "treemapRootToNode"]
            let targetInfo = treeHelper.retrieveTargetInfo(payload, types, model)

            //   if (targetInfo) {
            if let targetInfo = targetInfo {
                //     const originViewRoot = model.getViewRoot();
                //     if (originViewRoot) {
                //         payload.direction = helper.aboveViewRoot(originViewRoot, targetInfo.node)
                //             ? 'rollUp' : 'drillDown';
                //     }
                //   PORT-NOTE: `Payload` is a value type, so writing `payload.other["direction"]` mutates only
                //     this local copy — it does not propagate back to the dispatch batch. That matches the
                //     current port: no consumer reads `payload.direction` (the drill-down/roll-up animation
                //     direction in TreemapView is DEFERRED). Kept faithful for when that path is wired.
                if let originViewRoot = model.getViewRoot() {
                    payload.other["direction"] = treeHelper.aboveViewRoot(originViewRoot, targetInfo.node)
                        ? "rollUp" : "drillDown"
                }
                //     model.resetViewRoot(targetInfo.node);
                model.resetViewRoot(targetInfo.node)
            }
        }
        return nil
    }
}

// `payload.seriesIndex` coercion (Int/Double/NSNumber). Payload numbers may arrive boxed either way through
//   the dynamic `other` bag; mirror the Int-vs-Double option-read guard.
private func treemapActionInt(_ v: Any?) -> Int? {
    if let i = v as? Int { return i }
    if let d = v as? Double { return Int(d) }
    if let n = v as? NSNumber { return n.intValue }
    return nil
}
