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
//   not this render-layer file (same convention as boxplotInstall.swift). All four registrations are
//   performed there — see the `-- chart/bar/installPictorialBar.ts --` block in `installOnce()` and the
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
// INTEGRATION SURFACE (all PORTED and WIRED in `ECharts.installOnce()` — core/ECharts.swift):
//   - registerSeriesModel: `ComponentModel.registerClass(PictorialBarSeriesModel.self)`
//                          (chart/bar/PictorialBarSeries.swift; ECharts.swift `-- chart/bar/installPictorialBar.ts --`)
//   - registerChartView:   `_chartViewFactories["pictorialBar"] = { PictorialBarView() }`
//                          (chart/bar/PictorialBarView.swift)
//   - registerLayout(PRIORITY.VISUAL.LAYOUT):
//                          `createCrossSeriesLayoutHandler(SERIES_TYPE_PICTORIAL_BAR)` held as
//                          `ECharts._pictorialBarLayoutHandler` (layout/barGrid.swift); its `overallReset`
//                          runs in the layout stage.
//   - registerLayout(PRIORITY.VISUAL.PROGRESSIVE_LAYOUT):
//                          `createProgressiveLayout(SERIES_TYPE_PICTORIAL_BAR)` held as
//                          `ECharts._pictorialBarProgressiveLayoutHandler` (layout/barGrid.swift); driven
//                          through `runSeriesStageHandler` right after the cross-series handler.
//                          PORT-NOTE: the driver additionally gates BOTH pictorialBar layout stages on
//                          `!ecModel.getSeriesByType(SERIES_TYPE_PICTORIAL_BAR).isEmpty`. This is
//                          behaviourally equivalent to upstream, NOT a deviation: the cross-series
//                          `overallReset` only walks `eachAxisOnKey(ecModel, makeAxisStatKey2("pictorialBar",
//                          cartesian2d))` and `setLayout` is applied only inside `eachSeriesOnAxisOnKey` for
//                          that same key (axis-stat clients are keyed by `seriesModel.subType`), so with no
//                          pictorialBar series the key holds zero axes and the stage is already a no-op;
//                          `runSeriesStageHandler` likewise skips every series whose `subType` differs from
//                          `handler.seriesType`. Plain bar series' bandWidth/offset/size are never touched
//                          either way — the guard is only a cheap early-out.
//   - registerBarGridAxisHandlers(registers):
//                          `registerBarGridAxisHandlers(_registers)` (layout/barGrid.swift) is called once
//                          from the bar wiring and registers BOTH "bar" and "pictorialBar" axis handlers
//                          (barGrid.swift `register("bar")` / `register("pictorialBar")`, guarded by
//                          `callOnlyOnce`), so pictorialBar needs no second call — matching upstream, where
//                          the same `callOnlyOnce` makes the duplicate install-time call a no-op.
