// Ported from echarts/src/chart/sankey/install.ts (the inline `dragNode` action) — keep in sync with upstream.
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

// upstream imports (chart/sankey/install.ts):
//   import {registerRoamActionSimply} from '../../component/helper/roamHelper';
//       -> `registerSankeyRoamAction()` (component/helper/roamHelperViewGroup.swift), the port's
//          view-group `registerRoamActionSimply(registers, 'series', 'sankey')` (= action type 'sankeyRoam').
//   import { COMPONENT_MAIN_TYPE_SERIES, Payload } from '../../util/types';   -> Payload (util/types.swift).
//   import SankeySeriesModel, { SERIES_TYPE_SANKEY } from './SankeySeries';   -> sibling SankeySeries.swift.
//   import { EChartsExtensionInstallRegisters } from '../../extension';       -> EChartsExtensionInstallRegisters.

// upstream: interface SankeyDragNodePayload extends Payload { localX: number; localY: number }
//   The port carries `dataIndex` / `localX` / `localY` (+ the `seriesId` query) on the dynamic `Payload.other` bag.

// upstream: the `dragNode` action + roam action are registered inline inside `install(registers)`. Mirrored
//   as an `installSankeyAction` helper (same shape as `installTreeAction`), invoked from ECharts.installOnce.
public func installSankeyAction(_ registers: EChartsExtensionInstallRegisters) {
    _ = registers

    // registers.registerAction({ type: 'dragNode', event: 'dragnode', update: 'update' },
    //     function (payload, ecModel) { ... })
    //   The slim `registerAction` is module-level (Phase-29), so — like installTreeAction — this only
    //   registers the action; `update:'update'` collapses to the full `update()` the driver runs after the
    //   handler. That re-render re-reads each node's `localX`/`localY` (persisted by setNodePosition below),
    //   so the dragged node moves and its incident edge ribbons re-route to the new endpoints.
    var info = ActionInfo(type: "dragNode")
    info.event = "dragnode"
    info.update = "update"
    registerAction(info) { payload, ecModel, _ in
        // upstream: ecModel.eachComponent({ mainType: COMPONENT_MAIN_TYPE_SERIES, subType: SERIES_TYPE_SANKEY,
        //     query: payload }, function (seriesModel: SankeySeriesModel) {
        //         seriesModel.setNodePosition(payload.dataIndex, [payload.localX, payload.localY]); });
        //   The `query: payload` (a `seriesId` filter here) is resolved by iterating the sankey series and
        //   matching `payload.seriesId` — the same idiom installTreeAction / the `<sub>Roam` actions use.
        let targetSeriesId = payload.other["seriesId"] as? String
        guard let dataIndex = sankeyActionInt(payload.other["dataIndex"]) else { return nil }
        let localX = sankeyActionDouble(payload.other["localX"]) ?? 0
        let localY = sankeyActionDouble(payload.other["localY"]) ?? 0

        ecModel.eachSeriesByType(SERIES_TYPE_SANKEY) { s, _ in
            guard let seriesModel = s as? SankeySeriesModel else { return }
            if let sid = targetSeriesId, !sid.isEmpty, seriesModel.id != sid { return }
            // seriesModel.setNodePosition(payload.dataIndex, [payload.localX, payload.localY]);
            seriesModel.setNodePosition(dataIndex, [localX, localY])
        }
        return nil
    }

    // registerRoamActionSimply(registers, COMPONENT_MAIN_TYPE_SERIES, SERIES_TYPE_SANKEY);
    //   -> the view-group 'sankeyRoam' action (see roamHelperViewGroup.swift).
    registerSankeyRoamAction()
}

// `payload.dataIndex` coercion (Int/Double/NSNumber). Payload numbers may arrive boxed either way through
//   the dynamic `other` bag; mirror the Int-vs-Double option-read guard.
private func sankeyActionInt(_ v: Any?) -> Int? {
    if let i = v as? Int { return i }
    if let d = v as? Double { return Int(d) }
    if let n = v as? NSNumber { return n.intValue }
    return nil
}

// `payload.localX` / `payload.localY` coercion (a fractional 0..1 view coordinate; boxed Int/Double/NSNumber).
private func sankeyActionDouble(_ v: Any?) -> Double? {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let n = v as? NSNumber { return n.doubleValue }
    return nil
}
