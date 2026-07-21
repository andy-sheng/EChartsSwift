// Ported from echarts/src/chart/bar/installPictorialBar.ts — keep in sync with upstream
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
//   import { EChartsExtensionInstallRegisters } from '../../extension';
//   import PictorialBarView from './PictorialBarView';                 -> sibling PictorialBarView.swift (ported).
//   import PictorialBarSeriesModel from './PictorialBarSeries';        -> sibling PictorialBarSeries.swift (ported).
//   import { createProgressiveLayout, createCrossSeriesLayoutHandler, registerBarGridAxisHandlers }
//       from '../../layout/barGrid';                                   -> layout/barGrid.swift (ported).
//   import { SERIES_TYPE_PICTORIAL_BAR } from '../../layout/barCommon';  -> layout/barCommon.swift.

// export function install(registers) { ... }
// PORT-NOTE: registration boilerplate lives in the Orchestrate/Integrate driver (core/ECharts.swift),
//   not this render-layer file (same convention as boxplotInstall.swift). All five registration calls are
//   accounted for there — see the `-- chart/bar/installPictorialBar.ts --` block in `installOnce()` and the
//   layout stage; the mapping is tabulated under INTEGRATION SURFACE below.
//   Preserved as commented source for the diffable surface:
//
//     export function install(registers) {
//         registers.registerChartView(PictorialBarView);
//         registers.registerSeriesModel(PictorialBarSeriesModel);
//
//         registers.registerLayout(
//             registers.PRIORITY.VISUAL.LAYOUT, createCrossSeriesLayoutHandler(SERIES_TYPE_PICTORIAL_BAR)
//         );
//         // Do layout after other overall layout, which can prepare some information.
//         registers.registerLayout(
//             registers.PRIORITY.VISUAL.PROGRESSIVE_LAYOUT, createProgressiveLayout(SERIES_TYPE_PICTORIAL_BAR)
//         );
//
//         registerBarGridAxisHandlers(registers);
//     }
//
// INTEGRATION SURFACE (WIRED in `ECharts.installOnce()` — core/ECharts.swift; bullets in upstream
//   `install()` order. Ported except where a PORT-NOTE below records a deferral/deviation):
//   - registerChartView:   `_chartViewFactories["pictorialBar"] = { PictorialBarView() }`
//                          (chart/bar/PictorialBarView.swift)
//   - registerSeriesModel: `ComponentModel.registerClass(PictorialBarSeriesModel.self)`
//                          (chart/bar/PictorialBarSeries.swift; ECharts.swift `-- chart/bar/installPictorialBar.ts --`)
//   - registerLayout(PRIORITY.VISUAL.LAYOUT):
//                          `createCrossSeriesLayoutHandler(SERIES_TYPE_PICTORIAL_BAR)` held as
//                          `ECharts._pictorialBarLayoutHandler` (layout/barGrid.swift); its `overallReset`
//                          runs in the layout stage.
//   - registerLayout(PRIORITY.VISUAL.PROGRESSIVE_LAYOUT):
//                          `createProgressiveLayout(SERIES_TYPE_PICTORIAL_BAR)` held as
//                          `ECharts._pictorialBarProgressiveLayoutHandler` (layout/barGrid.swift); driven
//                          through `runSeriesStageHandler` right after the cross-series handler.
//                          The driver additionally gates BOTH pictorialBar layout stages on
//                          `!ecModel.getSeriesByType(SERIES_TYPE_PICTORIAL_BAR).isEmpty`; that guard is a
//                          cheap early-out, not a behaviour change — see the canonical GUARD note on the
//                          `if` itself in core/ECharts.swift (layout stage,
//                          `-- chart/bar/installPictorialBar.ts --`).
//                          PORT-NOTE (deferred): `createProgressiveLayout` does not port upstream's
//                          `plan: createRenderPlanner()` — layout/barGrid.swift sets `handler.plan = nil`
//                          (the ported `StageHandlerPlan` typealias cannot express "no reset"), so the
//                          `reset` stage re-runs every pass instead of being plan-gated.
//                          PORT-NOTE (ordering deviation): upstream's `PRIORITY.VISUAL.PROGRESSIVE_LAYOUT`
//                          places this after EVERY overall layout stage; the driver has no priority buckets
//                          and calls the two pictorialBar stages inline back-to-back, so later overall
//                          stages (pieLayout, funnelLayout, candlestickLayout, boxplotLayout,
//                          sunburstLayoutStageHandler, treemapLayout) now run AFTER it. Benign today —
//                          pictorialBar only consumes bandWidth/offset/size from the cross-series handler
//                          above — revisit if any later overall stage must prepare information for it.
//   - registerBarGridAxisHandlers(registers):
//                          `registerBarGridAxisHandlers(_registers)` (layout/barGrid.swift) is called once
//                          from the bar wiring and registers BOTH "bar" and "pictorialBar" axis handlers
//                          (barGrid.swift `register("bar")` / `register("pictorialBar")`, guarded by
//                          `callOnlyOnce`), so pictorialBar needs no second call — matching upstream, where
//                          the same `callOnlyOnce` makes the duplicate install-time call a no-op.
