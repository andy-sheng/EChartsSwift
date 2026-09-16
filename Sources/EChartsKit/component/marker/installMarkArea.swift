// Ported from echarts/src/component/marker/installMarkArea.ts — keep in sync with upstream
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

import ZRenderKit
// import { EChartsExtensionInstallRegisters } from '../../extension';
//   -> note: the registration registry (`EChartsExtensionInstallRegisters`) is owned by the
//      Orchestrate driver (Integrate stage / core/ECharts.swift), not this render-layer file (same
//      convention as component/title/install.swift and component/grid/installSimple.swift).
// import checkMarkerInSeries from './checkMarkerInSeries';  -> sibling `checkMarkerInSeries` (ported).
// import MarkAreaModel from './MarkAreaModel';              -> sibling `MarkAreaModel` (ported).
// import MarkAreaView from './MarkAreaView';                -> sibling `MarkAreaView` (ported).

// export function install(registers: EChartsExtensionInstallRegisters) {
//     registers.registerComponentModel(MarkAreaModel);
//     registers.registerComponentView(MarkAreaView);
//
//     registers.registerPreprocessor(function (opt) {
//         if (checkMarkerInSeries(opt.series, 'markArea')) {
//             // Make sure markArea component is enabled
//             opt.markArea = opt.markArea || {};
//         }
//     });
// }
//
// registration + preprocessor wiring now lives in the Orchestrate driver (ECharts.swift
//   registers MarkAreaView and calls `markAreaPreprocessor` in setOption). The faithful preprocessor
//   body is the free function below; `checkMarkerInSeries` is already ported.
public func markAreaPreprocessor(_ opt: inout [String: Any]) {
    // if (checkMarkerInSeries(opt.series, 'markArea'))
    if checkMarkerInSeries(opt["series"], "markArea") {
        // Make sure markArea component is enabled
        // opt.markArea = opt.markArea || {};
        if opt["markArea"] == nil {
            opt["markArea"] = [String: Any]()
        }
    }
}
