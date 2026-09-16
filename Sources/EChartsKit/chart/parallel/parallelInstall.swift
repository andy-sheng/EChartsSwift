// Ported from echarts/src/chart/parallel/install.ts — keep in sync with upstream
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
//   import { EChartsExtensionInstallRegisters, use } from '../../extension';   -> registrar surface owned by
//       the Orchestrate/Integrate driver (same convention as chart/boxplot/install.swift).
//   import ParallelView from './ParallelView';                                 -> sibling ParallelView.swift
//       (the CHART view — named ParallelView.swift; the COMPONENT view is ParallelComponentView.swift, to
//       avoid the SwiftPM single-target basename collision).
//   import ParallelSeriesModel from './ParallelSeries';                        -> sibling ParallelSeries.swift.
//   import parallelVisual from './parallelVisual';                             -> sibling parallelVisual.swift.
//   import {install as installParallelComponent} from '../../component/parallel/install';
//       -> component/parallel install surface (parallel COORDINATE SYSTEM + parallelAxis component).

// export function install(registers: EChartsExtensionInstallRegisters) { ... }
// registration boilerplate belongs to the Orchestrate/Integrate driver, not this
//   render-layer file (same convention as chart/boxplot/install.swift, chart/sunburst/sunburstInstall.swift).
//   Preserved as commented source for the diffable surface:
//
//     export function install(registers) {
//         use(installParallelComponent);
//
//         registers.registerChartView(ParallelView);
//         registers.registerSeriesModel(ParallelSeriesModel);
//         registers.registerVisual(registers.PRIORITY.VISUAL.BRUSH, parallelVisual);
//     }
//
// Integration checklist (driver wiring):
//   • `use(installParallelComponent)` — pull in the parallel coordinate system + parallelAxis component
//     (component/parallel: Parallel / ParallelModel / ParallelAxis / ParallelAxisModel /
//     ParallelComponentView + coordinate-system creator, registered via CoordinateSystemManager.register).
//   • registers.registerChartView(ParallelView)      — the chart polyline view (ParallelView.swift).
//   • registers.registerSeriesModel(ParallelSeriesModel).
//   • registers.registerVisual(PRIORITY.VISUAL.BRUSH, parallelVisual) — the line opacity visual stage.
