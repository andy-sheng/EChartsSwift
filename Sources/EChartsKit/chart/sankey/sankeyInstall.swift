// Ported from echarts/src/chart/sankey/install.ts — keep in sync with upstream
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
//   import { EChartsExtensionInstallRegisters } from '../../extension';       -> registrar surface owned by
//       the Orchestrate/Integrate driver (same convention as chart/sunburst/sunburstInstall.swift).
//   import SankeyView from './SankeyView';
//       -> note: chart/sankey/SankeyView.swift is a sibling port (the render layer:
//          node Rects + ribbon Path + labels). Registered via ECharts.installOnce.
//   import SankeySeriesModel, { SERIES_TYPE_SANKEY } from './SankeySeries';   -> sibling SankeySeries.swift (ported).
//   import { COMPONENT_MAIN_TYPE_SERIES, Payload } from '../../util/types';   -> util/types.swift.
//   import GlobalModel from '../../model/Global';                             -> GlobalModel (model/Global.swift).
//   import { registerRoamActionSimply } from '../../component/helper/roamHelper';
//       -> note: ported as registerSankeyRoamAction() (component/helper/roamHelperViewGroup.swift).
//   import { sankeyLayoutStageHandler } from './sankeyLayout';
//       -> note: chart/sankey/sankeyLayout.swift is a sibling port (box layout stage).
//   import { sankeyVisualStageHandler } from './sankeyVisual';                -> sibling sankeyVisual.swift (ported).

// interface SankeyDragNodePayload extends Payload { localX: number; localY: number }
//   type-only payload shape for the `dragNode` action (implemented in sankeyAction.swift installSankeyAction).

// export function install(registers: EChartsExtensionInstallRegisters) { ... }
// registration boilerplate belongs to the Orchestrate/Integrate driver, not this
//   render-layer file (same convention as chart/sunburst/sunburstInstall.swift). The `dragNode` action +
//   `registerRoamActionSimply` (drag/roam) are wired in ECharts.installOnce (installSankeyAction). `SankeyView`
//   and `sankeyLayoutStageHandler` are likewise registered there. Preserved as commented source for the diffable surface:
//
//     export function install(registers) {
//         registers.registerChartView(SankeyView);                // -> SankeyView (SankeyView.swift)
//         registers.registerSeriesModel(SankeySeriesModel);       // -> SankeySeriesModel (SankeySeries.swift)
//
//         registers.registerLayout(sankeyLayoutStageHandler);     // -> sankeyLayoutStageHandler (sankeyLayout.swift)
//         registers.registerVisual(sankeyVisualStageHandler);     // -> sankeyVisualStageHandler (sankeyVisual.swift)
//
//         registers.registerAction({
//             type: 'dragNode',
//             event: 'dragnode',
//             // here can only use 'update' now, other value is not support in echarts.
//             update: 'update'
//         }, function (payload: SankeyDragNodePayload, ecModel: GlobalModel) {
//             ecModel.eachComponent({
//                 mainType: COMPONENT_MAIN_TYPE_SERIES,
//                 subType: SERIES_TYPE_SANKEY,
//                 query: payload
//             }, function (seriesModel: SankeySeriesModel) {
//                 seriesModel.setNodePosition(payload.dataIndex, [payload.localX, payload.localY]);
//             });
//         });
//
//         registerRoamActionSimply(registers, COMPONENT_MAIN_TYPE_SERIES, SERIES_TYPE_SANKEY);  // roam DEFERRED
//     }
//
// INTEGRATION SURFACE (for the driver, once SankeyView + sankeyLayout land):
//   - registerSeriesModel: `SankeySeriesModel`     (chart/sankey/SankeySeries.swift)
//   - registerChartView:   `SankeyView`            (chart/sankey/SankeyView.swift — later phase)
//   - registerLayout:      `sankeyLayoutStageHandler` (chart/sankey/sankeyLayout.swift — later phase)
//   - registerVisual:      `sankeyVisualStageHandler` (chart/sankey/sankeyVisual.swift — ported here)
