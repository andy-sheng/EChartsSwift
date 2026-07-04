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
//       slim Orchestrate/Integrate driver (same convention as chart/sankey/sankeyInstall.swift).
//   import ChordView from './ChordView';
//       -> chart/chord/ChordView.swift (sibling render-layer port — node Sector arcs + ribbon Path + labels).
//   import ChordSeriesModel from './ChordSeries';                         -> sibling ChordSeries.swift (ported).
//   import dataFilter from '../../processor/dataFilter';                  -> processor/dataFilter.swift.
//   import { chordCircularLayoutStageHandler } from './chordLayout';      -> chart/chord/chordLayout.swift
//       (sibling layout-stage port — circular arc layout for nodes + edges).

// export function install(registers: EChartsExtensionInstallRegisters) { ... }
// PORT-TODO: registration boilerplate belongs to the slim Orchestrate/Integrate driver, not this
//   series/render-layer file (same convention as chart/sankey/sankeyInstall.swift). Preserved as commented
//   source for the diffable surface:
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
//         registers.registerProcessor(dataFilter('chord'));   // -> dataFilter (processor/dataFilter.swift)
//     }
//
// INTEGRATION SURFACE (for the driver):
//   - registerSeriesModel: `ChordSeriesModel`                     (chart/chord/ChordSeries.swift — ported here)
//   - registerChartView:   `ChordView`                           (chart/chord/ChordView.swift)
//   - registerLayout:      `chordCircularLayoutStageHandler` at PRIORITY.VISUAL.POST_CHART_LAYOUT
//                                                                 (chart/chord/chordLayout.swift)
//   - registerProcessor:   `dataFilter("chord")`                 (processor/dataFilter.swift)
