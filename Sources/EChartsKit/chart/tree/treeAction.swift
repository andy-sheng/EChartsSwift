// Ported from echarts/src/chart/tree/treeAction.ts — keep in sync with upstream.
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
//   import {registerRoamActionSimply} from '../../component/helper/roamHelper';
//       -> `registerTreeRoamAction()` (component/helper/roamHelperViewGroup.swift), the port's
//          view-group `registerRoamActionSimply(registers, 'series', 'tree')` (= action type 'treeRoam').
//   import { COMPONENT_MAIN_TYPE_SERIES, Payload } from '../../util/types';   -> Payload (util/types.swift).
//   import TreeSeriesModel, { SERIES_TYPE_TREE } from './TreeSeries';         -> siblings.
//   import { EChartsExtensionInstallRegisters } from '../../extension';       -> EChartsExtensionInstallRegisters.

// upstream: export interface TreeExpandAndCollapsePayload extends Payload { dataIndex: number }
//   The port carries `dataIndex` (and the `seriesId` query) on the dynamic `Payload.other` bag.

// upstream: export function installTreeAction(registers: EChartsExtensionInstallRegisters)
public func installTreeAction(_ registers: EChartsExtensionInstallRegisters) {
    _ = registers

    // registers.registerAction({ type: 'treeExpandAndCollapse', event: 'treeExpandAndCollapse',
    //     update: 'update' }, function (payload, ecModel) { ... })
    //   The `registerAction` is module-level (Phase-29), so — like installToolboxActions — this only
    //   registers the action; `update:'update'` collapses to the full `update()` the driver runs after the
    //   handler (which re-runs treeLayout, so a now-collapsed subtree's nodes lose their layout and stop
    //   rendering — the symbolNeedsDraw gate in TreeView drops them).
    var info = ActionInfo(type: "treeExpandAndCollapse")
    info.event = "treeExpandAndCollapse"
    info.update = "update"
    registerAction(info) { payload, ecModel, _ in
        // upstream: ecModel.eachComponent({ mainType: COMPONENT_MAIN_TYPE_SERIES, subType: SERIES_TYPE_TREE,
        //     query: payload }, function (seriesModel: TreeSeriesModel) { ... })
        //   The port resolves the `query: payload` (a `seriesId` filter here) by iterating the tree series
        //   and matching `payload.seriesId` — the same idiom the ported `<sub>Roam` actions use
        //   (roamHelperViewGroup.registerViewGroupRoamAction).
        let targetSeriesId = payload.other["seriesId"] as? String
        guard let dataIndex = treeActionPayloadInt(payload.other["dataIndex"]) else { return nil }

        ecModel.eachSeriesByType(SERIES_TYPE_TREE) { s, _ in
            guard let seriesModel = s as? TreeSeriesModel else { return }
            if let sid = targetSeriesId, !sid.isEmpty, seriesModel.id != sid { return }

            // const tree = seriesModel.getData().tree;
            // const node = tree.getNodeByDataIndex(dataIndex);
            // node.isExpand = !node.isExpand;
            guard let node = seriesModel.getData().tree?.getNodeByDataIndex(dataIndex) else { return }
            node.isExpand = !node.isExpand
        }
        return nil
    }

    // registerRoamActionSimply(registers, COMPONENT_MAIN_TYPE_SERIES, SERIES_TYPE_TREE);
    //   -> the view-group 'treeRoam' action (see roamHelperViewGroup.swift).
    registerTreeRoamAction()
}

// `payload.dataIndex` coercion (Int/Double/NSNumber). Payload numbers may arrive boxed either way through
//   the dynamic `other` bag; mirror the Int-vs-Double option-read guard.
private func treeActionPayloadInt(_ v: Any?) -> Int? {
    if let i = v as? Int { return i }
    if let d = v as? Double { return Int(d) }
    if let n = v as? NSNumber { return n.intValue }
    return nil
}
