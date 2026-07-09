// Ported from echarts/src/component/brush/install.ts (the `brush` / `brushSelect` / `brushEnd`
// action registrations + the visual-stage registration) — keep in sync with upstream.
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

// upstream imports (install.ts):
//   import { brushVisualStageHandler } from './visualEncoding';  -> brushVisual.swift
//   import BrushModel, { BrushAreaParam } from './BrushModel';   -> Task-1 BrushModel (BrushModelLike)
//   import { noop } from 'zrender/src/core/util';                -> the `nil` handler / no-op below
//
// DEFERRED (marked TODO/`// TODO` upstream too):
//   registers.registerComponentView(BrushView) / registerComponentModel(BrushModel)  (Task 1 / view phase)
//   registers.registerPreprocessor(brushPreprocessor)                                 (Task 1)
//   registerFeature('brush', BrushFeature)  — the toolbox brush button.               (deferred by scope)

// upstream: export function install(registers) { ... }
//   This ports the ACTION + VISUAL-stage part of install.ts. Model/view/preprocessor/feature
//   registration is Task-1 / later-phase wiring.
//
// PORT-NOTE: like `installDataZoomAction`, the `EChartsExtensionInstallRegisters` stub does not model
//   `registerVisual`; the driver invokes `brushVisualStageHandler.overallReset?(ecModel, api, payload)`
//   directly in its visual stage (same pattern as the sunburst/tree overall visual handlers). Here we only
//   register the three actions via the Phase-29 module-level `registerAction`.
public func installBrushAction(_ registers: EChartsExtensionInstallRegisters) {
    _ = registers

    // registers.registerVisual(PRIORITY.VISUAL.BRUSH, brushVisualStageHandler);
    //   -> the integrator invokes `brushVisualStageHandler` in performVisualStage (see brushVisual.swift).

    // registerAction({type:'brush', event:'brush', update:'updateVisual'}, handler)
    var brushInfo = ActionInfo(type: "brush")
    brushInfo.event = "brush"
    brushInfo.update = "updateVisual"
    registerAction(brushInfo) { payload, ecModel, _ in
        // ecModel.eachComponent({mainType:'brush', query: payload}, brushModel => brushModel.setAreas(payload.areas))
        // PORT-TODO: the `query: payload` filter (match by brushId/brushIndex/brushName) is simplified to
        //   "every brush component" — sufficient for the single-brush cartesian scope. Restore the
        //   QueryConditionKindA finder when multi-brush selection lands.
        let areas = brushPayloadAreas(payload.other["areas"])
        ecModel.eachComponent("brush") { brushModel, _ in
            guard let brush = brushModel as? BrushModelLike else { return }
            // If `areas` is nil/undefined, setAreas keeps the current range state (upstream contract).
            brush.setAreas(areas)
        }
        return nil
    }

    // registerAction({type:'brushSelect', event:'brushSelected', update:'none'}, noop)
    var brushSelectInfo = ActionInfo(type: "brushSelect")
    brushSelectInfo.event = "brushSelected"
    brushSelectInfo.update = "none"
    registerAction(brushSelectInfo, brushNoopAction)

    // registerAction({type:'brushEnd', event:'brushEnd', update:'none'}, noop)
    var brushEndInfo = ActionInfo(type: "brushEnd")
    brushEndInfo.event = "brushEnd"
    brushEndInfo.update = "none"
    registerAction(brushEndInfo, brushNoopAction)
}

// upstream: `noop` handler — the action only publishes an event; it mutates no model.
private let brushNoopAction: ActionHandler = { _, _, _ in nil }

// Coerce `payload.areas` (dynamic bag) to `[[String: Any]]?`. `nil` (absent) means "keep current areas".
private func brushPayloadAreas(_ v: Any?) -> [[String: Any]]? {
    if v == nil || v is NSNull { return nil }
    if let arr = v as? [[String: Any]] { return arr }
    if let arr = v as? [Any] { return arr.compactMap { $0 as? [String: Any] } }
    return nil
}
