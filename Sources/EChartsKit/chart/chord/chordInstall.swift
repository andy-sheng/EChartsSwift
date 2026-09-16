// Ported from echarts/src/chart/chord/install.ts — keep in sync with upstream
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
//       Orchestrate/Integrate driver — `ECharts.installOnce()` in core/ECharts.swift (same convention as
//       chart/sankey/sankeyInstall.swift).
//   import ChordView from './ChordView';
//       -> chart/chord/ChordView.swift (sibling render-layer port — node Sector arcs + ribbon Path + labels).
//   import ChordSeriesModel from './ChordSeries';                         -> sibling ChordSeries.swift (ported).
//   import dataFilter from '../../processor/dataFilter';                  -> processor/legendDataFilter.swift.
//   import { chordCircularLayoutStageHandler } from './chordLayout';      -> chart/chord/chordLayout.swift
//       (sibling layout-stage port — circular arc layout for nodes + edges).

// export function install(registers: EChartsExtensionInstallRegisters) { ... }
// registration boilerplate belongs to the Orchestrate/Integrate driver (core/ECharts.swift),
//   not this series/render-layer file (same convention as chart/sankey/sankeyInstall.swift). The port does
//   not bridge the upstream `registers` surface to model instantiation, so the aggregate registration
//   entry point is the static `ECharts.installOnce()`, complemented by the `_chartViewFactories` /
//   `_dataFilters` stored properties and the direct stage call in `render()` — see the
//   `-- chart/chord/install.ts (minimal) --` block in core/ECharts.swift; the mapping is tabulated under
//   INTEGRATION SURFACE below. Preserved as commented source for the diffable surface:
//
//     export function install(registers) {
//         registers.registerChartView(ChordView);              // -> ChordView (chart/chord/ChordView.swift)
//         registers.registerSeriesModel(ChordSeriesModel);     // -> ChordSeriesModel (chart/chord/ChordSeries.swift)
//
//         registers.registerLayout(
//             registers.PRIORITY.VISUAL.POST_CHART_LAYOUT,
//             chordCircularLayoutStageHandler                  // -> chordCircularLayoutStageHandler (chordLayout.swift)
//         );
//         // Add data filter processor
//         registers.registerProcessor(dataFilter('chord'));   // -> legendDataFilter (processor/legendDataFilter.swift), wired in ECharts `_dataFilters`
//     }
//
// INTEGRATION SURFACE (wired in core/ECharts.swift — per-registrar locations below; all four are LIVE):
//   - registerSeriesModel: `ComponentModel.registerClass(ChordSeriesModel.self)` inside `installOnce()`
//                                                                (chart/chord/ChordSeries.swift)
//   - registerChartView:   `"chord": { ChordView() },` — an entry in the `_chartViewFactories` stored
//                          property's dictionary literal, NOT in `installOnce()`
//                                                                (chart/chord/ChordView.swift)
//   - registerLayout:      `chordCircularLayout(ecModel, api)` in the LAYOUT section of `render()`
//                          (immediately after the sankey layout/visual pair). Upstream registers the
//                          OVERALL stage handler `chordCircularLayoutStageHandler` at
//                          PRIORITY.VISUAL.POST_CHART_LAYOUT; the ported driver has no priority-ordered
//                          layout registrar, so it invokes the bare 2-arg `chordCircularLayout` directly
//                          in the layout section of `render()` (mirrors `sankeyLayout(ecModel, api)` at
//                          core/ECharts.swift:2048; note graph instead goes through
//                          `graph*LayoutStageHandler.overallReset`). Ordering is not load-bearing:
//                          `chordCircularLayout` (chordLayout.swift:53) reads only `api` dimensions and
//                          series options via `layout.getCircleLayout`, and no other stage reads or writes
//                          chord node/edge layout, so it is independent of the upstream
//                          POST_CHART_LAYOUT priority slot. `chordCircularLayoutStageHandler` remains
//                          defined for the eventual registrar route (chart/chord/chordLayout.swift)
//   - registerProcessor:   `legendDataFilter(SERIES_TYPE_CHORD)` — an entry in the `_dataFilters` stored
//                          property, run per matching series in the data-processor stage (assembled into
//                          the Scheduler handler list, before the layout/visual/view stages)
//                                                                (processor/legendDataFilter.swift)
