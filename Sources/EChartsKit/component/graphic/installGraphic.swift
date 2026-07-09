// Ported from echarts/src/component/graphic/install.ts — keep in sync with upstream
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

// import { isArray } from 'zrender/src/core/util';                    -> `util.isArray` (ZRenderKit).
// import { EChartsExtensionInstallRegisters } from '../../extension'; -> PORT-TODO: registers/install
//   boilerplate deferred to the Orchestrate driver (matches component/grid/installSimple.swift).
// import { GraphicComponentModel, GraphicComponentOption } from './GraphicModel'; -> sibling GraphicModel.swift.
// import { GraphicComponentView } from './GraphicView';               -> sibling GraphicView.swift.

// upstream:
//   export function install(registers: EChartsExtensionInstallRegisters) {
//       registers.registerComponentModel(GraphicComponentModel);
//       registers.registerComponentView(GraphicComponentView);
//       registers.registerPreprocessor(function (option) { ... });
//   }
//
// PORT-TODO: registration boilerplate (registerComponentModel / registerComponentView /
//   registerPreprocessor) belongs to the later Orchestrate driver, not this render-layer file.
//   The preprocessor is real option-normalization logic, so it is ported as the standalone
//   `graphicOptionPreprocessor` function below for the driver to register.

/// Normalizes the `graphic` option into its canonical `[{ elements: [...] }]` shape. Mutates the raw
/// top-level option bag in place (upstream mutates `option.graphic`).
///
/// upstream: `registers.registerPreprocessor(function (option) { ... })`
public func graphicOptionPreprocessor(_ option: inout [String: Any]) {
    let graphicOption = option["graphic"]

    // Convert
    // {graphic: [{left: 10, type: 'circle'}, ...]}
    // or
    // {graphic: {left: 10, type: 'circle'}}
    // to
    // {graphic: [{elements: [{left: 10, type: 'circle'}, ...]}]}
    if util.isArray(graphicOption) {
        let arr = (graphicOption as? [Any]) ?? []
        // if (!graphicOption[0] || !graphicOption[0].elements)
        let first = arr.first
        let firstHasElements = ((first as? [String: Any])?["elements"]) != nil
        if first == nil || !firstHasElements || !jsTruthyPreproc(first) {
            option["graphic"] = [["elements": arr]]
        }
        else {
            // Only one graphic instance can be instantiated. (We don't
            // want that too many views are created in echarts._viewMap.)
            option["graphic"] = [arr[0]]
        }
    }
    else if graphicOption != nil && !(graphicOption is NSNull)
        && ((graphicOption as? [String: Any])?["elements"]) == nil {
        // graphicOption && !graphicOption.elements
        option["graphic"] = [["elements": [graphicOption as Any]]]
    }
}

// JS truthiness for `graphicOption[0]` (an object/nil).
private func jsTruthyPreproc(_ v: Any?) -> Bool {
    switch v {
    case nil: return false
    case is NSNull: return false
    case let b as Bool: return b
    default: return true
    }
}
