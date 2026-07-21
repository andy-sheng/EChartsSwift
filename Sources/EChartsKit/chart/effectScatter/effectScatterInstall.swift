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
//   import EffectScatterView from './EffectScatterView';                      -> sibling EffectScatterView.swift (ported).
//   import EffectScatterSeriesModel from './EffectScatterSeries';             -> sibling EffectScatterSeries.swift (ported).
//   import layoutPoints from '../../layout/points';                           -> `pointsLayout` (layout/points.swift, ported).

// export function install(registers: EChartsExtensionInstallRegisters) { ... }
// PORT-NOTE: registration boilerplate belongs to the Orchestrate/Integrate driver
//   (core/ECharts.swift), not this render-layer file (same convention as chart/boxplot/boxplotInstall.swift).
//   All three registrations are performed there — see the `-- chart/effectScatter/install.ts --` block in
//   `installOnce()`, the `_chartViewFactories` stored dictionary literal, and the LAYOUT section of
//   `render()`; the mapping is tabulated under INTEGRATION SURFACE below.
//   Preserved as commented source for the diffable surface:
//
//     export function install(registers) {
//         registers.registerChartView(EffectScatterView);
//         registers.registerSeriesModel(EffectScatterSeriesModel);
//         registers.registerLayout(layoutPoints('effectScatter'));
//     }
//
// INTEGRATION SURFACE (all PORTED and WIRED in core/ECharts.swift — per-registrar locations below):
//   - registerSeriesModel: `ComponentModel.registerClass(EffectScatterSeriesModel.self)` inside
//                          `installOnce()`         (chart/effectScatter/EffectScatterSeries.swift)
//   - registerChartView:   `"effectScatter": { EffectScatterView() },` — an entry in the
//                          `_chartViewFactories` stored property's dictionary literal, NOT in
//                          `installOnce()`         (chart/effectScatter/EffectScatterView.swift).
//                          The view delegates to the shared `SymbolDraw(EffectSymbol)` — base symbol +
//                          animated ripple rings (chart/helper/EffectSymbolElement.swift).
//   - registerLayout(layoutPoints('effectScatter')):
//                          `runSeriesStageHandler(pointsLayout("effectScatter"), ecModel, api)` in the
//                          LAYOUT section of `render()` (layout/points.swift), alongside the sibling
//                          `pointsLayout("scatter")` / `pointsLayout("line", true)` stages. It writes each
//                          datum's pixel position with `data.setItemLayout(i, point)`, which
//                          `EffectScatterSeriesModel#brushSelector` reads back via
//                          `data.getItemLayout(dataIndex)` — without this stage a brush over an
//                          effectScatter selects nothing. `EffectScatterView.updateTransform` re-runs the
//                          same stage on roam (as upstream does), so the brush region stays in sync.
//                          PORT-NOTE (deviation, identical to ScatterView): EffectScatterView does NOT read
//                          that item layout for drawing; it inlines the equivalent `coordSys.dataToPoint`
//                          math per datum (`getSymbolPoint`, including the stage's stackResultDimension
//                          substitution for stacked series) so roam repositioning can run without a full
//                          re-layout. The stage output is therefore consumed only by the brush selector.
