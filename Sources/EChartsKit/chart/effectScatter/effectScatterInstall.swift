// Ported from echarts/src/chart/effectScatter/install.ts — keep in sync with upstream
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
//   import EffectScatterView from './EffectScatterView';                      -> sibling EffectScatterView.swift (ported, STATIC).
//   import EffectScatterSeriesModel from './EffectScatterSeries';             -> sibling EffectScatterSeries.swift (ported).
//   import layoutPoints from '../../layout/points';
//       -> PORT-TODO: layout/points.ts NOT ported. The static EffectScatterView inlines per-datum
//          `coord.dataToPoint` placement (same deviation as ScatterView), so the `registerLayout(layoutPoints)`
//          stage is not wired. Register once layout/points.swift lands.

// export function install(registers: EChartsExtensionInstallRegisters) { ... }
// PORT-NOTE: registration boilerplate belongs to the Orchestrate/Integrate driver
//   (core/ECharts.swift), not this render-layer file (same convention as chart/boxplot/boxplotInstall.swift).
//   The integration points are:
//     - ComponentModel.registerClass(EffectScatterSeriesModel.self)   // registerSeriesModel(EffectScatterSeriesModel)
//     - _chartViewFactories["effectScatter"] = { EffectScatterView() } // registerChartView(EffectScatterView)
//     - registerLayout(layoutPoints('effectScatter'))                  // PORT-TODO: layout/points not ported.
//   Preserved as commented source for the diffable surface:
//
//     export function install(registers) {
//         registers.registerChartView(EffectScatterView);
//         registers.registerSeriesModel(EffectScatterSeriesModel);
//         registers.registerLayout(layoutPoints('effectScatter'));
//     }
