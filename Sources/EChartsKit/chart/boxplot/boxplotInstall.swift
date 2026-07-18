// Ported from echarts/src/chart/boxplot/install.ts — keep in sync with upstream
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
//   import { EChartsExtensionInstallRegisters } from '../../extension';       -> EChartsExtensionInstallRegisters
//       (stub registrar; the full registerSeriesModel/registerChartView/registerLayout/registerTransform
//        surface is owned by the Orchestrate/Integrate driver, not this file).
//   import BoxplotSeriesModel from './BoxplotSeries';                         -> sibling BoxplotSeries.swift (ported).
//   import BoxplotView from './BoxplotView';
//       -> sibling BoxplotView.swift (ported); hosts the BoxPath custom shape.
//   import {boxplotLayoutStageHandler, registerBoxplotAxisHandlers} from './boxplotLayout';
//       -> sibling boxplotLayout.swift (ported): `boxplotLayoutStageHandler` / `registerBoxplotAxisHandlers`.
//   import { boxplotTransform } from './boxplotTransform';
//       -> sibling boxplotTransform.swift (ported): the `echarts:boxplot` dataset transform.

// export function install(registers: EChartsExtensionInstallRegisters) { ... }
// PORT-NOTE: registration boilerplate belongs to the later Orchestrate/Integrate driver, not this
//   render-layer file (same convention as chart/themeRiver/themeRiverInstall.swift and
//   component/grid/installSimple.swift). The base `EChartsExtensionInstallRegisters` only exposes
//   registerProcessor/PRIORITY; registerSeriesModel/registerChartView/registerLayout/registerTransform
//   are owned by the driver's factory registration (core/ECharts.swift). All four boxplot siblings ARE
//   ported and ready to wire: BoxplotSeriesModel, BoxplotView, boxplotLayoutStageHandler, boxplotTransform;
//   `registerBoxplotAxisHandlers` is ported and callable against the registrar. Preserved as commented
//   source for the diffable surface:
//
//     export function install(registers) {
//         registers.registerSeriesModel(BoxplotSeriesModel);
//         registers.registerChartView(BoxplotView);
//         registers.registerLayout(boxplotLayoutStageHandler);
//         registers.registerTransform(boxplotTransform);
//
//         registerBoxplotAxisHandlers(registers);
//     }
//
// INTEGRATION SURFACE (for the driver):
//   - registerSeriesModel: `BoxplotSeriesModel`          (chart/boxplot/BoxplotSeries.swift — ported)
//   - registerChartView:   `BoxplotView`                 (chart/boxplot/BoxplotView.swift — ported)
//   - registerLayout:      `boxplotLayoutStageHandler`   (chart/boxplot/boxplotLayout.swift — ported)
//   - registerTransform:   `boxplotTransform`            (chart/boxplot/boxplotTransform.swift — ported)
//   - registerBoxplotAxisHandlers(registers)             (chart/boxplot/boxplotLayout.swift — ported, callable)
