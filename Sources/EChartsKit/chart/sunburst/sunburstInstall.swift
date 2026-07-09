// Ported from echarts/src/chart/sunburst/install.ts — keep in sync with upstream
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
//   import { EChartsExtensionInstallRegisters } from '../../extension';       -> registrar surface owned by
//       the slim Orchestrate/Integrate driver (same convention as chart/boxplot/install.swift).
//   import SunburstView from './SunburstView';                               -> sibling SunburstView.swift (ported).
//   import SunburstSeriesModel from './SunburstSeries';                      -> sibling SunburstSeries.swift (ported).
//   import { sunburstVisualStageHandler } from './sunburstVisual';           -> sibling sunburstVisual.swift (ported).
//   import { installSunburstAction } from './sunburstAction';
//       -> sibling sunburstAction.swift (ported: `sunburstRootToNode` drill-down/roll-up; the deprecated
//          `sunburstHighlight`/`sunburstUnhighlight` aliases stay DEFERRED). Registered from EChartsSlim
//          .installOnce via `installSunburstAction(_registers)`.
//   import { sunburstLayoutStageHandler } from './sunburstLayout';           -> sibling sunburstLayout.swift (ported).

// export function install(registers: EChartsExtensionInstallRegisters) { ... }
// PORT-TODO: registration boilerplate belongs to the slim Orchestrate/Integrate driver, not this
//   render-layer file (same convention as chart/boxplot/install.swift). `installSunburstAction`
//   (`sunburstRootToNode`) IS now ported and called from EChartsSlim.installOnce. Preserved as
//   commented source for the diffable surface:
//
//     export function install(registers) {
//         registers.registerChartView(SunburstView);
//         registers.registerSeriesModel(SunburstSeriesModel);
//         registers.registerLayout(sunburstLayoutStageHandler);
//         registers.registerVisual(sunburstVisualStageHandler);
//         installSunburstAction(registers);
//     }
