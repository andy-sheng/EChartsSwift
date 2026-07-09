// Ported from echarts/src/chart/custom/install.ts — keep in sync with upstream
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
//   import { EChartsExtensionInstallRegisters } from '../../extension';   -> the registration surface is owned
//       by the Orchestrate/Integrate driver (core/ECharts.swift), not this render-layer file
//       (same convention as chart/effectScatter/effectScatterInstall.swift, chart/boxplot/boxplotInstall.swift).
//   import CustomSeriesModel from './CustomSeries';                       -> sibling CustomSeries.swift (ported).
//   import CustomChartView from './CustomView';                          -> sibling CustomView.swift
//       (STATIC render layer — DEFERRED per the CUSTOM port brief; enter/update/leave transition +
//        animation + morphing + group-DIFF + emphasis/blur/select states + clipPath animation +
//        legacy-echarts compat are all PORT-TODOs).

// export function install(registers: EChartsExtensionInstallRegisters) {
//     registers.registerChartView(CustomChartView);
//     registers.registerSeriesModel(CustomSeriesModel);
// }
// PORT-TODO: registration boilerplate belongs to the Orchestrate/Integrate driver
//   (core/ECharts.swift), not this render-layer file. The integration points are:
//     - ComponentModel.registerClass(CustomSeriesModel.self)      // registerSeriesModel(CustomSeriesModel)
//     - _chartViewFactories["custom"] = { CustomView() }          // registerChartView(CustomChartView)
//   Preserved as commented source for the diffable surface:
//
//     export function install(registers) {
//         registers.registerChartView(CustomChartView);
//         registers.registerSeriesModel(CustomSeriesModel);
//     }
