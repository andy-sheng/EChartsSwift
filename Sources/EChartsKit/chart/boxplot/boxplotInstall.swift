// Ported from echarts/src/chart/boxplot/install.ts — keep in sync with upstream
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
//   import { EChartsExtensionInstallRegisters } from '../../extension';       -> EChartsExtensionInstallRegisters
//       (stub registrar; the registerSeriesModel/registerChartView/registerLayout/registerTransform
//        surface is owned by the Orchestrate/Integrate driver — `ECharts.installOnce()` in
//        core/ECharts.swift — not this file).
//   import BoxplotSeriesModel from './BoxplotSeries';                         -> sibling BoxplotSeries.swift (ported).
//   import BoxplotView from './BoxplotView';
//       -> sibling BoxplotView.swift (ported); hosts the BoxPath custom shape.
//   import {boxplotLayoutStageHandler, registerBoxplotAxisHandlers} from './boxplotLayout';
//       -> sibling boxplotLayout.swift (ported): `boxplotLayoutStageHandler` / `registerBoxplotAxisHandlers`.
//   import { boxplotTransform } from './boxplotTransform';
//       -> sibling boxplotTransform.swift (ported): the `echarts:boxplot` dataset transform.

// export function install(registers: EChartsExtensionInstallRegisters) { ... }
// PORT-NOTE: registration boilerplate belongs to the Orchestrate/Integrate driver, not this
//   render-layer file (same convention as chart/themeRiver/themeRiverInstall.swift and
//   component/grid/installSimple.swift). Upstream's registrars are not bridged to GlobalModel
//   instantiation in this port (the base `EChartsExtensionInstallRegisters` only exposes
//   registerProcessor/PRIORITY), so `ECharts.installOnce()` (core/ECharts.swift) performs the
//   equivalent registration explicitly. ALL FIVE install() registrations below are LIVE in the driver,
//   but in four different places: `registerSeriesModel` + `registerBoxplotAxisHandlers` directly in
//   `ECharts.installOnce()`; `registerChartView` as a `_chartViewFactories` map entry; `registerTransform`
//   in `transformInstall` (which `installOnce()` calls); and `registerLayout` as the bare
//   `boxplotLayout(ecModel)` call in `ECharts.render()`'s layout stage — see
//   the INTEGRATION SURFACE block for the exact call sites (this note claims registration liveness
//   only; per-file gaps stay tracked by the `PORT-TODO:` markers in the sibling files). Preserved as
//   commented source for the diffable surface:
//
//     export function install(registers) {
//         registers.registerSeriesModel(BoxplotSeriesModel);
//         registers.registerChartView(BoxplotView);
//         registers.registerLayout(boxplotLayoutStageHandler);
//         registers.registerTransform(boxplotTransform);
//
//         registerBoxplotAxisHandlers(registers);
//     }
//
// INTEGRATION SURFACE (performed by `ECharts.installOnce()` / the driver's stages):
//   - registerSeriesModel: `ComponentModel.registerClass(BoxplotSeriesModel.self)` — in `installOnce()`
//                            (core/ECharts.swift, the `-- chart/boxplot/install.ts --` block)
//   - registerChartView:   the `"boxplot": { BoxplotView() }` entry in the `_chartViewFactories`
//                            dictionary literal (core/ECharts.swift), NOT a call inside `installOnce()`.
//   - registerLayout:      the bare `boxplotLayout(ecModel)` call in `ECharts.render()`'s layout stage
//                            (core/ECharts.swift) — the OVERALL layout stage, again NOT in `installOnce()`;
//                            `boxplotLayoutStageHandler` is the registrar
//                            wrapper around that same bare 1-arg handler (chart/boxplot/boxplotLayout.swift).
//   - registerTransform:   `try! registerExternalTransform(boxplotTransform)` — this port centralizes
//                            external-transform registration in `transformInstall` (component/transform/
//                            transformInstall.swift), which `ECharts.installOnce()` calls; it enables
//                            `transform: { type: "boxplot" }` (registerExternalTransform strips the
//                            official `echarts:` namespace).
//   - registerBoxplotAxisHandlers(registers): `registerBoxplotAxisHandlers(_registers)` (core/ECharts.swift)
//                            — populates the axisStatistics `clientsForLookup` (bandWidth → box width);
//                            the axis-statistics processor registered by the bar handlers picks it up.
