// Ported from echarts/src/component/visualMap/installCommon.ts — keep in sync with upstream
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

// import { EChartsExtensionInstallRegisters } from '../../extension';
//   -> registrar surface owned by the Orchestrate/Integrate driver (same convention as
//      chart/sankey/sankeyInstall.swift). The stub `EChartsExtensionInstallRegisters`
//      (coord/axisStatistics.swift) does not yet model `registerVisual` / `registerAction` /
//      `registerPreprocessor` / `registerSubTypeDefaulter(...)` / `PRIORITY.VISUAL.COMPONENT`, so the
//      registration is expressed as the INTEGRATION SURFACE below rather than live calls.
// import { VisualMapOption } from './VisualMapModel';          -> VisualMapModel (VisualMapModel.swift).
// import { PiecewiseVisualMapOption } from './PiecewiseModel'; -> PiecewiseModel (PiecewiseModel.swift).
// import { ContinuousVisualMapOption } from './ContinuousModel'; -> ContinuousModel (ContinuousModel.swift).
// import { visualMapActionInfo, visualMapActionHander } from './visualMapAction';
//   -> sibling visualMapAction.swift (`visualMapActionInfo` / `visualMapActionHander`).
// import { visualMapEncodingHandlers } from './visualEncoding';
//   -> sibling visualEncoding.swift (`visualMapEncodingHandlers`).
// import { each } from 'zrender/src/core/util';                -> `util.each` (ZRenderKit).
// import preprocessor from './preprocessor';                   -> sibling preprocessor.swift (`visualMapPreprocessor`).

// let installed = false;
// export default function installCommon(registers: EChartsExtensionInstallRegisters) {
//     if (installed) { return; }
//     installed = true;
//
//     registers.registerSubTypeDefaulter(
//         'visualMap', function (option: VisualMapOption) {
//         // Compatible with ec2, when splitNumber === 0, continuous visualMap will be used.
//         return (
//                 !option.categories
//                 && (
//                     !(
//                         (option as PiecewiseVisualMapOption).pieces
//                             ? ((option as PiecewiseVisualMapOption)).pieces.length > 0
//                             : ((option as PiecewiseVisualMapOption)).splitNumber > 0
//                     )
//                     || (option as ContinuousVisualMapOption).calculable
//                 )
//             )
//             ? 'continuous' : 'piecewise';
//     });
//
//     registers.registerAction(visualMapActionInfo, visualMapActionHander);
//
//     each(visualMapEncodingHandlers, (handler) => {
//         registers.registerVisual(registers.PRIORITY.VISUAL.COMPONENT, handler);
//     });
//     registers.registerPreprocessor(preprocessor);
// }
//
// registration boilerplate lives in the Orchestrate/Integrate driver (ECharts.swift), not this
//   file (same convention as chart/sankey/sankeyInstall.swift). The `installed`-once guard is a JS
//   module singleton; in Swift the driver should call each registration exactly once. The subtype
//   defaulter is the SAME logic as `visualMapSubTypeDefaulter` (typeDefaulter.swift) — do not duplicate
//   it; register that one closure.
//
// INTEGRATION SURFACE (for the driver):
//   1. SubType defaulter:  ComponentModel.registerSubTypeDefaulter("visualMap", visualMapSubTypeDefaulter)
//                          — i.e. call `registerVisualMapSubTypeDefaulter()` (typeDefaulter.swift). Maps
//                          the bare `visualMap` option to 'continuous' | 'piecewise'.
//   2. Action:             registerAction(visualMapActionInfo, visualMapActionHander)  (visualMapAction.swift)
//                          — 'selectDataRange' / event 'dataRangeSelected' (INTERACTION, DEFERRED body).
//   3. Visual stages:      for each handler in `visualMapEncodingHandlers` (visualEncoding.swift):
//                          registerVisual(PRIORITY.VISUAL.COMPONENT, handler)
//                          — VISUAL priority = COMPONENT, so it runs AFTER each series' own visual stage.
//   4. Preprocessor:       registerPreprocessor(visualMapPreprocessor)  (preprocessor.swift)
//                          — array-normalize `visualMap` + `splitList`->`pieces` + piece `start/end`->`min/max`.
