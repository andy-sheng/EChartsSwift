// Ported from echarts/src/chart/themeRiver/install.ts — keep in sync with upstream
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
//   import { EChartsExtensionInstallRegisters } from '../../extension';    -> registrar surface owned by
//       the slim Orchestrate/Integrate driver (same convention as chart/sankey/sankeyInstall.swift).
//   import ThemeRiverView from './ThemeRiverView';
//       -> sibling ThemeRiverView.swift (ported — the streamgraph band Polygons + labels render layer).
//   import ThemeRiverSeriesModel, { SERIES_TYPE_THEME_RIVER } from './ThemeRiverSeries';
//       -> sibling ThemeRiverSeries.swift (ported).
//   import dataFilter from '../../processor/dataFilter';
//       -> `legendDataFilter` (processor/legendDataFilter.swift) — the `SERIES_TYPE_THEME_RIVER` processor,
//          wired into the slim driver's data-processor stage (see EChartsSlim `_dataFilters`).
//   import { themeRiverLayoutStageHandler } from './themeRiverLayout';
//       -> sibling themeRiverLayout.swift (ported).

// export function install(registers: EChartsExtensionInstallRegisters) { ... }
// PORT-TODO: registration boilerplate belongs to the slim Orchestrate/Integrate driver, not this
//   render-layer file (same convention as chart/sankey/sankeyInstall.swift). Preserved as commented
//   source for the diffable surface:
//
//     export function install(registers) {
//         registers.registerChartView(ThemeRiverView);                    // -> ThemeRiverView (ThemeRiverView.swift)
//         registers.registerSeriesModel(ThemeRiverSeriesModel);           // -> ThemeRiverSeriesModel (ThemeRiverSeries.swift)
//
//         registers.registerLayout(themeRiverLayoutStageHandler);         // -> themeRiverLayoutStageHandler (themeRiverLayout.swift)
//         registers.registerProcessor(dataFilter(SERIES_TYPE_THEME_RIVER));
//     }
//
// INTEGRATION SURFACE (for the driver):
//   - registerSeriesModel: `ThemeRiverSeriesModel`        (chart/themeRiver/ThemeRiverSeries.swift)
//   - registerChartView:   `ThemeRiverView`               (chart/themeRiver/ThemeRiverView.swift — ported)
//   - registerLayout:      `themeRiverLayoutStageHandler` (chart/themeRiver/themeRiverLayout.swift — ported here)
//   - registerProcessor:   `dataFilter(SERIES_TYPE_THEME_RIVER)`  // -> legendDataFilter (processor/legendDataFilter.swift), wired in EChartsSlim `_dataFilters`
//   - DEPENDENCY: the `singleAxis` component + the Single coordinate system (coord/single/ — Single.swift /
//     SingleAxis.swift land with the Single coord-sys phase; ThemeRiverSeriesModel.dependencies == ['singleAxis']).
