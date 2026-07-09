// Ported from echarts/src/chart/heatmap/install.ts — keep in sync with upstream
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
//   import { EChartsExtensionInstallRegisters } from '../../extension';       -> the registration surface is
//       owned by the Orchestrate/Integrate driver (core/ECharts.swift), not this render-layer file.
//   import HeatmapView from './HeatmapView';                                  -> sibling HeatmapView.swift (STATIC render; see Phase 21 heatmap view).
//   import HeatmapSeriesModel from './HeatmapSeries';                         -> sibling HeatmapSeries.swift (ported).

// export function install(registers: EChartsExtensionInstallRegisters) { ... }
// PORT-TODO: registration boilerplate belongs to the Orchestrate/Integrate driver
//   (core/ECharts.swift), not this render-layer file (same convention as chart/effectScatter/effectScatterInstall.swift).
//   The integration points are:
//     - _chartViewFactories["heatmap"] = { HeatmapView() }              // registerChartView(HeatmapView)
//     - ComponentModel.registerClass(HeatmapSeriesModel.self)           // registerSeriesModel(HeatmapSeriesModel)
//   IMPORTANT: heatmap colors each cell from the per-datum color that the visualMap ENCODING wrote
//   (visualEncoding.swift -> data.getItemVisual(idx, "color")); a `visualMap` component MUST be present in
//   the option for the cells to receive a color. Register the visualMap component alongside heatmap.
//   Preserved as commented source for the diffable surface:
//
//     export function install(registers) {
//         registers.registerChartView(HeatmapView);
//         registers.registerSeriesModel(HeatmapSeriesModel);
//     }
