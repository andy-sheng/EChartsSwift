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
// PORT-TODO: registration boilerplate lives in the slim Orchestrate/Integrate driver (EChartsSlim.swift),
//   not this render-layer file (same convention as boxplotInstall.swift). The wiring is:
//     registers.registerChartView(PictorialBarView);           → `_chartViewFactories["pictorialBar"]`
//     registers.registerSeriesModel(PictorialBarSeriesModel);  → `ComponentModel.registerClass(PictorialBarSeriesModel.self)`
//     registers.registerLayout(VISUAL.LAYOUT, createCrossSeriesLayoutHandler(pictorialBar));
//         → `_pictorialBarLayoutHandler` (bandWidth/offset/size on each series' data layout)
//     registers.registerLayout(PROGRESSIVE_LAYOUT, createProgressiveLayout(pictorialBar));
//         → `_pictorialBarProgressiveLayoutHandler` (per-item rect x/y/width/height layout, which
//            PictorialBarView reads back via data.getItemLayout)
//     registerBarGridAxisHandlers(registers);   → already invoked for 'pictorialBar' by the bar wiring
//         (registerBarGridAxisHandlers registers BOTH 'bar' and 'pictorialBar' axis handlers).
//
//   The two layout handlers + the series/view registration are performed in EChartsSlim.installOnce()
//   and the layout stage; see the `-- chart/bar/installPictorialBar.ts --` block there.
