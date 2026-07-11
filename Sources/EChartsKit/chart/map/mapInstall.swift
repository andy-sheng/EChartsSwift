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
//       -> PORT-TODO: legacy/dataSelectAction.ts NOT ported (select actions deferred).
//   import {install as installGeo} from '../../component/geo/install';
//       -> the geo component install (geoCreator + GeoModel + GeoView). Wired by the driver via `use`.
//   import { mapSymbolLayoutStageHandler } from './mapSymbolLayout';
//       -> mapSymbolLayoutStageHandler (chart/map/mapSymbolLayout.swift, ported) — the map symbol layout
//          stage that places the per-region series symbols.
//   import { mapDataStatisticStageHandler } from './mapDataStatistic';
//       -> `mapDataStatisticStageHandler` (sibling mapDataStatistic.swift, ported).

// export function install(registers: EChartsExtensionInstallRegisters) { ... }
// PORT-NOTE: registration boilerplate belongs to the Orchestrate/Integrate driver, not this
//   render-layer file (same convention as chart/sankey/sankeyInstall.swift). `MapView` and
//   `mapSymbolLayoutStageHandler` are ported; `createLegacyDataSelectAction` (select actions) is
//   still DEFERRED. Preserved as commented source for the diffable surface:
//
//     export function install(registers) {
//         use(installGeo);                                        // -> geo component (geoCreator/GeoModel/GeoView)
//
//         registers.registerChartView(MapView);                  // PORT-NOTE: MapView (ported)
//         registers.registerSeriesModel(MapSeries);              // -> MapSeriesModel (MapSeries.swift)
//
//         registers.registerLayout(mapSymbolLayoutStageHandler); // PORT-NOTE: mapSymbolLayout (ported)
//         registers.registerProcessor(
//             registers.PRIORITY.PROCESSOR.STATISTIC,
//             mapDataStatisticStageHandler                        // -> mapDataStatisticStageHandler (mapDataStatistic.swift)
//         );
//
//         createLegacyDataSelectAction('map', registers.registerAction);   // DEFERRED (select actions)
//     }
//
// INTEGRATION SURFACE (for the driver, once MapView + mapSymbolLayout land):
//   - use:                 the geo component install (geoCreator + GeoModel + GeoView)
//   - registerSeriesModel: `MapSeriesModel`               (chart/map/MapSeries.swift — ported here)
//   - registerChartView:   `MapView`                      (chart/map/MapView.swift — later phase)
//   - registerLayout:      `mapSymbolLayoutStageHandler`  (chart/map/mapSymbolLayout.swift — later phase)
//   - registerProcessor(PRIORITY.PROCESSOR.STATISTIC):
//                          `mapDataStatisticStageHandler` (chart/map/mapDataStatistic.swift — ported here)
//   - registerAction:      `createLegacyDataSelectAction('map', ...)`  (legacy select — DEFERRED)
