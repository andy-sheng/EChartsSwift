// Ported from echarts/src/chart/sunburst/sunburstAction.ts — keep in sync with upstream
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

/**
 * @file Sunburst action
 */

import Foundation
import ZRenderKit

// upstream imports:
//   import SunburstSeriesModel from './SunburstSeries';                 -> sibling `SunburstSeriesModel`.
//   import { Payload } from '../../util/types';                         -> `Payload` (util/types.swift).
//   import GlobalModel from '../../model/Global';                       -> `GlobalModel`.
//   import ExtensionAPI from '../../core/ExtensionAPI';                 -> `ExtensionAPI`.
//   import { extend } from 'zrender/src/core/util';                     -> `util.extend`.
//   import { deprecateReplaceLog } from '../../util/log';               -> PORT-NOTE: dev-only deprecation log (skipped).
//   import { EChartsExtensionInstallRegisters } from '../../extension'; -> `EChartsExtensionInstallRegisters`.
//   import { retrieveTargetInfo, aboveViewRoot } from '../helper/treeHelper';  -> `treeHelper.*` (sibling helper).

// export const ROOT_TO_NODE_ACTION = 'sunburstRootToNode';
public let ROOT_TO_NODE_ACTION = "sunburstRootToNode"

// const HIGHLIGHT_ACTION = 'sunburstHighlight';
private let HIGHLIGHT_ACTION = "sunburstHighlight"
// const UNHIGHLIGHT_ACTION = 'sunburstUnhighlight';
private let UNHIGHLIGHT_ACTION = "sunburstUnhighlight"

// export function installSunburstAction(registers: EChartsExtensionInstallRegisters)
public func installSunburstAction(_ registers: EChartsExtensionInstallRegisters) {
    _ = registers   // registration flows through the module-global `registerAction` (see legendAction.swift).

    // registers.registerAction({type: ROOT_TO_NODE_ACTION, update: 'updateView'}, handler)
    //   `updateView` collapses to a full `update()` in the driver (partial-update fast paths
    //   unported), which re-runs the layout stage around the new view root and re-renders — the exact
    //   re-root the drill-down needs.
    var rootToNodeInfo = ActionInfo(type: ROOT_TO_NODE_ACTION)
    rootToNodeInfo.update = "updateView"
    registerAction(rootToNodeInfo) { payload, ecModel, _ in

        // ecModel.eachComponent({mainType:'series', subType:'sunburst', query: payload}, handleRootToNode)
        //   Component-query fields (seriesId/seriesIndex/…) live in `payload.other`.
        ecModel.eachComponent(
            QueryConditionKindA(mainType: "series", query: payload.other, subType: "sunburst")
        ) { modelBase, _ in
            // function handleRootToNode(model, index) { ... }
            guard let model = modelBase as? SunburstSeriesModel else { return }

            // const targetInfo = retrieveTargetInfo(payload, [ROOT_TO_NODE_ACTION], model);
            let targetInfo = treeHelper.retrieveTargetInfo(payload, [ROOT_TO_NODE_ACTION], model)

            if let targetInfo = targetInfo {
                // const originViewRoot = model.getViewRoot();
                // if (originViewRoot) { payload.direction = aboveViewRoot(...) ? 'rollUp' : 'drillDown'; }
                //   `getViewRoot()` is non-optional in the port (always resolves), so the `if` is implicit.
                // PORT-TODO: `payload.direction` is consumed only by the DEFERRED entrance-animation routing
                //   (rollUp/drillDown) in SunburstView; `Payload` is a value type here, so the write is a
                //   no-op for the caller anyway. The `aboveViewRoot` classification is preserved for parity:
                _ = treeHelper.aboveViewRoot(model.getViewRoot(), targetInfo.node)
                // model.resetViewRoot(targetInfo.node);
                model.resetViewRoot(targetInfo.node)
            }
        }

        return nil
    }

    // registers.registerAction({type: HIGHLIGHT_ACTION, update: 'none'}, handler)  — a DEPRECATED alias
    //   that resolves the target node's dataIndex and fast-forwards to the ported `highlight` action.
    //   The sunburst emphasis/blur state wiring it forwards into is now ported (SunburstPiece routes
    //   `states.toggleHoverEmphasis`; `highlight`/`downplay` are registered in actionRegister.swift and
    //   dispatch through `updateDirectly` → `view.highlight`/`downplay`).
    var highlightInfo = ActionInfo(type: HIGHLIGHT_ACTION)
    highlightInfo.update = "none"
    registerAction(highlightInfo) { payload, ecModel, api in
        // payload = extend({}, payload);  — `Payload` is a value type, so a `var` copy IS the clone.
        var payload = payload

        // ecModel.eachComponent({mainType:'series', subType:'sunburst', query: payload}, handleHighlight)
        //   Component-query fields (seriesId/seriesIndex/…) live in `payload.other` (see rootToNode above).
        ecModel.eachComponent(
            QueryConditionKindA(mainType: "series", query: payload.other, subType: "sunburst")
        ) { modelBase, _ in
            // function handleHighlight(model) { ... }
            guard let model = modelBase as? SunburstSeriesModel else { return }
            // const targetInfo = retrieveTargetInfo(payload, [HIGHLIGHT_ACTION], model);
            let targetInfo = treeHelper.retrieveTargetInfo(payload, [HIGHLIGHT_ACTION], model)
            if let targetInfo = targetInfo {
                // payload.dataIndex = targetInfo.node.dataIndex;  — `dataIndex` lives in `payload.other`
                //   in the port (mirrors EChartsView `_handleClick`); the captured `var` mutation persists.
                payload.other["dataIndex"] = targetInfo.node.dataIndex
            }
        }

        // if (__DEV__) { deprecateReplaceLog('sunburstHighlight', 'highlight'); }
        //   dev-only deprecation log skipped (no __DEV__ / logging path wired; see the import note above).

        // api.dispatchAction(extend(payload, {type: 'highlight'}));
        payload.type = "highlight"
        api.dispatchAction(payload)

        return nil
    }

    // registers.registerAction({type: UNHIGHLIGHT_ACTION, update: 'updateView'}, handler)  — a DEPRECATED
    //   alias that fast-forwards to the ported `downplay` action (no target-node resolution upstream).
    var unhighlightInfo = ActionInfo(type: UNHIGHLIGHT_ACTION)
    unhighlightInfo.update = "updateView"
    registerAction(unhighlightInfo) { payload, _, api in
        // payload = extend({}, payload);  — value-type clone.
        var payload = payload

        // if (__DEV__) { deprecateReplaceLog('sunburstUnhighlight', 'downplay'); }
        //   dev-only deprecation log skipped (see the import note above).

        // api.dispatchAction(extend(payload, {type: 'downplay'}));
        payload.type = "downplay"
        api.dispatchAction(payload)

        return nil
    }
}
