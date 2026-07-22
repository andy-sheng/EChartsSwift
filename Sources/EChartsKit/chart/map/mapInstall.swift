// Ported from echarts/src/chart/map/install.ts — keep in sync with upstream
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

// upstream imports (mapped to this port; `->` marks the Swift symbol used):
//   import { EChartsExtensionInstallRegisters, use } from '../../extension';
//       -> registrar surface owned by the Orchestrate/Integrate driver (same convention as
//          chart/sankey/sankeyInstall.swift / chart/sunburst/sunburstInstall.swift).
//   import MapView from './MapView';
//       -> MapView (chart/map/MapView.swift, ported) — the render layer that draws each GeoJSON region
//          as a Polygon/Path COLORED by the series datum value (mirrors GeoView, but per `getItemVisual`
//          fill instead of the region itemStyle backdrop).
//   import MapSeries from './MapSeries';                         -> MapSeriesModel (sibling MapSeries.swift, ported).
//   import {createLegacyDataSelectAction} from '../../legacy/dataSelectAction';
//       -> `dataSelectAction.createLegacyDataSelectAction` (legacy/dataSelectAction.swift) — PORTED and
//          CALLED from `ECharts.installOnce()` (core/ECharts.swift:989).
//   import {install as installGeo} from '../../component/geo/install';
//       -> the geo component install (geoCreator + GeoModel + GeoView). Wired by the driver via `use`.
//   import { mapSymbolLayoutStageHandler } from './mapSymbolLayout';
//       -> mapSymbolLayoutStageHandler (chart/map/mapSymbolLayout.swift:40, ported) — the map symbol layout
//          stage that places the per-region series symbols. NOTE: that StageHandler value is currently
//          UNREFERENCED; the driver calls the faithful 1-arg `mapSymbolLayout(ecModel)` directly from the
//          render-stage layout block (core/ECharts.swift:2119), mirroring sankeyLayout / radarLayout.
//   import { mapDataStatisticStageHandler } from './mapDataStatistic';
//       -> `mapDataStatisticStageHandler` (sibling mapDataStatistic.swift, ported).

// export function install(registers: EChartsExtensionInstallRegisters) { ... }
// PORT-NOTE: registration boilerplate belongs to the Orchestrate/Integrate driver, not this
//   render-layer file (same convention as chart/sankey/sankeyInstall.swift). `MapView`,
//   `mapSymbolLayout`, `mapDataStatisticStageHandler` and `createLegacyDataSelectAction` are ALL ported
//   AND wired by the driver (see INTEGRATION SURFACE below for the exact call sites); nothing is
//   outstanding. Preserved as commented source for the diffable surface:
//
//     export function install(registers) {
//         use(installGeo);                                        // -> geo component (geoCreator/GeoModel/GeoView)
//
//         registers.registerChartView(MapView);                  // PORT-NOTE: MapView (ported)
//         registers.registerSeriesModel(MapSeries);              // -> MapSeriesModel (MapSeries.swift)
//
//         registers.registerLayout(mapSymbolLayoutStageHandler); // PORT-NOTE: mapSymbolLayout (ported; the
//                                                                //   driver calls mapSymbolLayout(ecModel)
//                                                                //   directly — see below)
//         registers.registerProcessor(
//             registers.PRIORITY.PROCESSOR.STATISTIC,
//             mapDataStatisticStageHandler                        // -> mapDataStatisticStageHandler (mapDataStatistic.swift)
//         );
//
//         createLegacyDataSelectAction('map', registers.registerAction);
//             // PORTED + WIRED: provider is dataSelectAction.createLegacyDataSelectAction
//             // (legacy/dataSelectAction.swift); the registration call itself lives in
//             // `ECharts.installOnce()` beside `ComponentModel.registerClass(MapSeriesModel.self)`,
//             // per this repo's convention that install() bodies are inlined there. The pie-side call
//             // (upstream chart/pie/install.ts:33) is wired in the same place, next to PieSeriesModel.
//     }
//
// INTEGRATION SURFACE (all of it is wired by the driver — but across FOUR different surfaces, not just
//   `installOnce()`; the exact call site is recorded per entry, line numbers as of core/ECharts.swift):
//   - use:                 the geo component install — `CoordinateSystemManager.register("geo", geoCreator)`
//                          in `installOnce()` (ECharts.swift:973) + `"geo": { GeoView() }` in the
//                          `_componentViewFactories` literal (:1287).
//   - registerSeriesModel: `MapSeriesModel` (chart/map/MapSeries.swift — ported) —
//                          `ComponentModel.registerClass(MapSeriesModel.self)` in `installOnce()` (:986).
//   - registerChartView:   `MapView` (chart/map/MapView.swift — ported; `render` still runs the inlined
//                          STATIC path rather than a persistent MapDraw, see the PORT-NOTE at
//                          MapView.swift:34) — entry `"map": { MapView() }` in the `_chartViewFactories`
//                          stored dictionary (:1364), NOT in `installOnce()`.
//   - registerLayout:      the driver calls the faithful 1-arg `mapSymbolLayout(ecModel)` DIRECTLY from the
//                          render-stage layout block (:2119). `mapSymbolLayoutStageHandler`
//                          (chart/map/mapSymbolLayout.swift:40) is ported but currently UNREFERENCED —
//                          the layout does NOT run through the Scheduler stage-handler pipeline here.
//                          Mirrors sankeyLayout / radarLayout / themeRiverLayout.
//   - registerProcessor(PRIORITY.PROCESSOR.STATISTIC):
//                          `mapDataStatisticStageHandler` (chart/map/mapDataStatistic.swift — ported) —
//                          appended in `ECharts.buildDataProcessorHandlers()` (:628), NOT in `installOnce()`.
//   - registerAction:      `dataSelectAction.createLegacyDataSelectAction("map") { ... }`
//                          (legacy/dataSelectAction.swift — ported) — called from `installOnce()` (:989).
