// Ported from echarts/src/chart/lines/install.ts — keep in sync with upstream
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
//   import { EChartsExtensionInstallRegisters } from '../../extension';   -> registrar surface owned by the
//       Orchestrate/Integrate driver (same convention as sankeyInstall.swift / sunburstInstall.swift).
//   import LinesView from './LinesView';
//       -> chart/lines/LinesView.swift (ported) — the STATIC render
//          layer (one Polyline per polyline line, or a straight Line / quadratic BezierCurve per two-point
//          line, drawn inline via ZRenderKit shapes exactly like GraphView's edges). The effect (moving
//          dot / trail) and the large draw path are ANIMATED/DEFERRED (CONVENTIONS §5).
//   import LinesSeriesModel from './LinesSeries';                         -> sibling LinesSeries.swift (ported here).
//   import linesLayout from './linesLayout';                             -> sibling linesLayout.swift (ported here).
//   import linesVisual from './linesVisual';
//       -> PORT-NOTE (deferred): requires chart/lines/linesVisual — the lines visual stage (per-line stroke color
//          from the palette + `symbol`/`symbolSize` for the endpoint arrows) lands with its own phase. Until
//          then the series relies on the shared visual/style stage (lineStyle -> stroke) like the line chart.

// export function install(registers: EChartsExtensionInstallRegisters) { ... }
// PORT-NOTE: registration boilerplate belongs to the Orchestrate/Integrate driver, not this
//   render-layer file (same convention as sankeyInstall.swift). `LinesView` and `linesVisual` land with
//   their own (later) port phases. Preserved as commented source for the diffable surface:
//
//     export function install(registers) {
//         registers.registerChartView(LinesView);          // -> LinesView (LinesView.swift, ported)
//         registers.registerSeriesModel(LinesSeriesModel);  // -> LinesSeriesModel (LinesSeries.swift)
//         registers.registerLayout(linesLayout);            // -> linesLayout (linesLayout.swift)
//         registers.registerVisual(linesVisual);            // PORT-NOTE (deferred): requires linesVisual
//     }
//
// INTEGRATION SURFACE (for the driver):
//   - registerSeriesModel: `LinesSeriesModel`  (chart/lines/LinesSeries.swift — ported here)
//   - registerLayout:      `linesLayout`       (chart/lines/linesLayout.swift — ported here; StageHandler
//                                                with seriesType 'lines', per-series reset → progress)
//   - registerChartView:   `LinesView`         (chart/lines/LinesView.swift — later phase)
//   - registerVisual:      `linesVisual`       (chart/lines/linesVisual.swift — later phase)
