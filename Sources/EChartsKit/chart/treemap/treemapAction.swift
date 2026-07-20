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
        //   `query: payload` is resolved by the faithful mechanism — `makeQueryConditionKindA` builds the
        //   `{seriesId, seriesIndex, seriesName}` query (handling the numeric and array id/name forms of
        //   `OptionId`, which a hand-rolled `as? String` compare drops) and `eachComponent` applies it.
        //   Same idiom as `ECharts.updateDirectly`.
        var payload = payload
        let condition = model.makeQueryConditionKindA(payload, "series", "treemap")

        ecModel.eachComponent(condition) { cmpt, _ in
            guard let model = cmpt as? TreemapSeriesModel else { return }

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
                //   PORT-TODO: this is a DEAD WRITE. `Payload` is a value type, so `payload.other["direction"]`
                //     mutates only this local copy and never reaches the dispatch batch or the ensuing
                //     layout/render pass. Upstream stamps the flag on the shared payload object and reads it
                //     back in TreemapView.render as `reRoot.direction` — not only for the drill-down/roll-up
                //     ANIMATION (TreemapView.ts:199/378) but also at TreemapView.ts:1090
                //     (`parentNode && (!reRoot || reRoot.direction === 'drillDown')`), which selects the
                //     element's starting rect and is therefore a rendering concern too. Thread the direction
                //     another way when TreemapView._doAnimation is ported — e.g. return it in this handler's
                //     ECEventData, or store it on TreemapSeriesModel so render() can reconstruct `reRoot`.
                //     The assignment is kept so the upstream line stays traceable.
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

// (The local `seriesIndex` Int coercion helper is gone: the `query: payload` filter is now resolved by
//   `model.makeQueryConditionKindA` + `ecModel.eachComponent`, which handle the numeric/array id and
//   index forms of `OptionId` upstream-faithfully.)
