// Ported from echarts/src/component/marker/installMarkPoint.ts — keep in sync with upstream
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
// import { EChartsExtensionInstallRegisters } from '../../extension'; -> EChartsKit `EChartsExtensionInstallRegisters`
// import checkMarkerInSeries from './checkMarkerInSeries';            -> sibling checkMarkerInSeries.swift
// import MarkPointModel from './MarkPointModel';                      -> sibling MarkPointModel.swift
// import MarkPointView from './MarkPointView';                        -> sibling MarkPointView.swift

// export function install(registers: EChartsExtensionInstallRegisters) {
//     registers.registerComponentModel(MarkPointModel);
//     registers.registerComponentView(MarkPointView);
//     registers.registerPreprocessor(function (opt) {
//         if (checkMarkerInSeries(opt.series, 'markPoint')) {
//             // Make sure markPoint component is enabled
//             opt.markPoint = opt.markPoint || {};
//         }
//     });
// }
//
// PORT-TODO: registration + preprocessor wiring belongs to the Orchestrate driver (Integrate stage),
//   not this render-layer file (same convention as component/title/install.swift and grid/installSimple).
//   The `install` body is preserved above as commented source for the diffable surface. The preprocessor
//   logic (auto-enable the markPoint component when any series declares `markPoint`) is provided below as
//   a reusable free function so Integrate can register it verbatim.

import ZRenderKit

// The preprocessor closure body, extracted so the Integrate stage can `registers.registerPreprocessor`
//   it. `opt` is the dynamic root option bag (`[String: Any]`); mutated in place (JS `opt.markPoint = ...`).
public func markPointPreprocessor(_ opt: inout [String: Any]) {
    // if (checkMarkerInSeries(opt.series, 'markPoint')) { opt.markPoint = opt.markPoint || {}; }
    if checkMarkerInSeries(opt["series"], "markPoint") {
        // Make sure markPoint component is enabled
        if opt["markPoint"] == nil {
            opt["markPoint"] = [String: Any]()
        }
    }
}
