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
//          dot / trail) and the large draw path are ANIMATED/DEFERRED.
//   import LinesSeriesModel from './LinesSeries';                         -> sibling LinesSeries.swift (ported here).
//   import linesLayout from './linesLayout';                             -> sibling linesLayout.swift (ported here).
//   import linesVisual from './linesVisual';
//       -> sibling linesVisual.swift (ported here). Upstream's stage writes NO color: `reset` normalizes
//          `get('symbol')`/`get('symbolSize')` into pairs and stores
//          `data.setVisual('fromSymbol'/'toSymbol'/'fromSymbolSize'/'toSymbolSize', …)`, then returns a
//          per-item `dataEach` (only when `data.hasItemOption`) writing the same four via `setItemVisual`.
//          Those four visuals feed the endpoint symbol markers, and they ARE CONSUMED LIVE on the main
//          (non-polyline) render path: LinesView drives straight/curved lines through `_lineDraw`
//          (LinesView.swift:85/216-220) -> chart/helper/LineDraw.swift -> `ECLine`, whose
//          `makeSymbolTypeValue`/`makeSymbol` read exactly `getItemVisual(idx, 'fromSymbol'|'toSymbol'|
//          'fromSymbolSize'|'toSymbolSize')` (ECLine.swift:69-115, driven from the SYMBOL_CATEGORIES loops
//          at :213/:267/:329). Only the INLINED POLYLINE branch (LinesView.swift `finishBuildLine`, :339 —
//          "fromSymbol/toSymbol arrow markers … DEFERRED") still ignores them. Series default is
//          `symbol: ['none','none']` (LinesSeries.swift:545), so only options that set `symbol`/
//          `symbolSize` on a CARTESIAN2D lines series can change pixels (`symbol: ['none','arrow']` in
//          Demos/official-geo-lines.swift is on a geo series, which LinesView does not render at all yet —
//          verified identical by the oracle below). The palette stroke color comes
//          from the shared dataColorPaletteTask / visual+style stage (lineStyle → stroke), exactly as for
//          the line chart — NOT from linesVisual (which writes no color at all).
//          ORACLE (2026-07-21, native PNG rendered before/after wiring the stage): lines-basic, lines-grid,
//          official-geo-lines, official-geo-svg-lines, official-lines-airline, official-lines-ny are
//          BYTE-IDENTICAL; lines-effect differs by 6 of 614400 px (one antialiased 5×7 patch at 73,584 —
//          the moving trail symbol), no shape/color change. `swift test`: the same 5 pre-existing failures
//          before and after (Chord/Graph/Parallel/Sankey transition + ZZMarker), none lines-related.

// export function install(registers: EChartsExtensionInstallRegisters) { ... }
// registration boilerplate belongs to the Orchestrate/Integrate driver (core/ECharts.swift),
//   not this render-layer file (same convention as sankeyInstall.swift). See the
//   `-- chart/lines/install.ts (minimal) --` block there; the mapping is tabulated under INTEGRATION
//   SURFACE below. Preserved as commented source for the diffable surface:
//
//     export function install(registers) {
//         registers.registerChartView(LinesView);
//         registers.registerSeriesModel(LinesSeriesModel);
//         registers.registerLayout(linesLayout);
//         registers.registerVisual(linesVisual);
//     }
//
// INTEGRATION SURFACE (wired in core/ECharts.swift — per-registrar locations below):
//   - registerSeriesModel: `ComponentModel.registerClass(LinesSeriesModel.self)` inside `installOnce()`
//                                                                (chart/lines/LinesSeries.swift)
//   - registerChartView:   `"lines": { LinesView() },` — an entry in the `_chartViewFactories` stored
//                          property's dictionary literal, NOT in `installOnce()`
//                                                                (chart/lines/LinesView.swift)
//   - registerLayout:      `runSeriesStageHandler(linesLayout, ecModel, api)` in the LAYOUT section of
//                          `render()`                            (chart/lines/linesLayout.swift)
//   - registerVisual:      `runSeriesStageHandler(linesVisual, ecModel, api)` immediately after the
//                          `linesLayout` call in the LAYOUT section of `render()` (same direct-drive
//                          convention as candlestickVisual/treemapVisual). LIVE: its four visuals are
//                          read by ECLine via LineDraw for the non-polyline modes (see the import note)
//                                                                (chart/lines/linesVisual.swift)
//
// note (coord systems — the two stages differ, do not collapse them):
//   `linesLayout` dispatches through the generic `CoordinateSystem.dataToPoint` requirement, so
//   cartesian2d, geo and calendar all lay out (linesLayout.swift, the `as? CoordinateSystem` guard);
//   only `Polar` — which conforms to `CoordinateSystemMaster` with a divergent `dataToPoint(_:clamp:)`
//   signature — fails the cast and produces no layout. `LinesView.render` is cartesian2d-ONLY (its
//   `as? Cartesian2D` guard; polar/geo DEFERRED). NOTE: the summary at ECharts.swift's
//   `-- chart/lines/install.ts (minimal) --` block and its LAYOUT comment still say "only cartesian2d"
//   for the layout stage — that is stale w.r.t. linesLayout.swift; this file is the accurate one.
//
// note (registrar route for linesVisual): upstream `registerVisual` appends to the module-level
//   `visualFuncs` array (echarts.ts:2903) handed to the Scheduler; the ported counterpart is the instance
//   method `buildVisualHandlers()`, which still returns `[]` because the visual stage is a DIRECT call
//   (performVisualStage/performVisualMapStage in `update()`) pending the sub-project C2 stub-outputData
//   passthrough fix. That registrar array is the EVENTUAL form, not a prerequisite: `linesVisual` is a
//   SERIES_STAGE_TASK, so it is driven today exactly like `candlestickVisual`/`treemapVisual` — a direct
//   `runSeriesStageHandler(linesVisual, ecModel, api)` in `render()`. When `buildVisualHandlers()` is
//   populated (C2), move it there and drop the direct call.
