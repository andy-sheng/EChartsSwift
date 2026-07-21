// Ported from echarts/src/chart/sunburst/install.ts — keep in sync with upstream
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
//       the Orchestrate/Integrate driver (same convention as chart/boxplot/install.swift).
//   import SunburstView from './SunburstView';                               -> sibling SunburstView.swift (ported).
//   import SunburstSeriesModel from './SunburstSeries';                      -> sibling SunburstSeries.swift (ported).
//   import { sunburstVisualStageHandler } from './sunburstVisual';           -> sibling sunburstVisual.swift (ported).
//   import { installSunburstAction } from './sunburstAction';
//       -> sibling sunburstAction.swift (`sunburstRootToNode` drill-down/roll-up PLUS the deprecated
//          `sunburstHighlight`/`sunburstUnhighlight` aliases, which fast-forward to the ported
//          `highlight`/`downplay` actions — all registered from ECharts.installOnce via
//          `installSunburstAction(ECharts._registers)`). One gap remains INSIDE sunburstAction:
//          `payload.direction` (rollUp/drillDown), consumed solely by the deferred SunburstView
//          entrance-animation routing — see the `PORT-NOTE (deferred)` in sunburstAction.swift.
//   import { sunburstLayoutStageHandler } from './sunburstLayout';           -> sibling sunburstLayout.swift (ported).

// export function install(registers: EChartsExtensionInstallRegisters) { ... }
// PORT-NOTE: registration boilerplate belongs to the Orchestrate/Integrate driver, not this
//   render-layer file (same convention as chart/boxplot/boxplotInstall.swift). Upstream's registrars are
//   not bridged to GlobalModel instantiation in this port, so `ECharts.installOnce()`
//   (core/ECharts.swift) performs the equivalent registration explicitly. All five install()
//   registrations below are live there (the only remaining sunburst gap is `payload.direction` inside
//   sunburstAction.swift, noted above). Preserved as commented source for the diffable surface:
//
//     export function install(registers) {
//         registers.registerChartView(SunburstView);
//         registers.registerSeriesModel(SunburstSeriesModel);
//         registers.registerLayout(sunburstLayoutStageHandler);
//         registers.registerVisual(sunburstVisualStageHandler);
//         installSunburstAction(registers);
//     }
//
// INTEGRATION SURFACE (performed by `ECharts.installOnce()` / the driver's stages):
//   - registerSeriesModel: `ComponentModel.registerClass(SunburstSeriesModel.self)`
//                            (core/ECharts.swift, the `-- chart/sunburst/install.ts --` block)
//   - registerChartView:   `_chartViewFactories["sunburst"] = { SunburstView() }`
//   - registerLayout:      `sunburstLayoutStageHandler.overallReset?(ecModel, api, nil)` — an OVERALL stage
//                            run from the driver's layout stage in `render()` (it needs the canvas
//                            center/radius geometry), like the pie layout stage.
//   - registerVisual:      `sunburstVisualStageHandler.overallReset?(ecModel, api, nil)` — run from
//                            `performCoordlessSeriesVisualStage`, i.e. BEFORE `performVisualMapStage`, so a
//                            visualMap-mapped color is not clobbered by this stage's palette fill
//                            (upstream priority: VISUAL.CHART 3000 < COMPONENT 4000).
//   - installSunburstAction(registers): `installSunburstAction(ECharts._registers)` — registers
//                            `sunburstRootToNode` (update:'updateView') plus the deprecated
//                            `sunburstHighlight`/`sunburstUnhighlight` aliases (chart/sunburst/sunburstAction.swift).
//                            DEFERRED inside that file: `payload.direction` (rollUp vs drillDown), which only
//                            the not-yet-ported SunburstView entrance-animation routing would consume.
