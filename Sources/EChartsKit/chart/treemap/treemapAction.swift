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
//   import { RectLike } from 'zrender/src/core/BoundingRect';                -> RectLike (ZRenderKit); the dynamic
//       rootRect payload is consumed by treemapLayout.
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
    // These noop registrations make the upstream actions dispatchable. TreemapView emits
    // `treemapMove` / `treemapRender` with rootRect, and updateView re-runs treemapLayout for that rect.
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
                if let originViewRoot = model.getViewRoot() {
                    // Upstream mutates the shared action payload. The port's Payload is a value type, so
                    // carry that same one-render field on the selected model and consume it in TreemapView.
                    model.setTreemapRootDirectionForUpdate(
                        treeHelper.aboveViewRoot(originViewRoot, targetInfo.node)
                            ? "rollUp" : "drillDown"
                    )
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
