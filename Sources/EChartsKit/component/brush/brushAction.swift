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
//   import brushPreprocessor from './preprocessor';              -> brushPreprocessor.swift
//   import BrushView from './BrushView';                         -> BrushView.swift
//   import BrushModel, { BrushAreaParam } from './BrushModel';   -> BrushModel.swift
//   import { brushVisualStageHandler } from './visualEncoding';  -> brushVisual.swift
//   import BrushFeature from '../toolbox/feature/Brush';         -> ToolboxBrushFeature.swift
//   import { registerFeature } from '../toolbox/featureManager'; -> `registerFeature`
//   import { noop } from 'zrender/src/core/util';                -> the `nil` handler / no-op below

// upstream: export function install(registers) { ... }
//
// PORT-NOTE (registrar shape): the `EChartsExtensionInstallRegisters` stub in this port does not model
//   `registerComponentModel` / `registerComponentView` / `registerVisual` / `registerPreprocessor` — the
//   driver holds those in explicit maps/call sites (see the header of core/ECharts.swift). So:
//     - registerComponentModel(BrushModel)     -> `ComponentModel.registerClass(BrushModel.self)` (ECharts.swift)
//     - registerComponentView(BrushView)       -> the "brush" entry of `_componentViewFactories` (ECharts.swift)
//     - registerVisual(PRIORITY.VISUAL.BRUSH,…) -> the `brushVisual(ecModel, api, payload)` call in render()
//     - registerPreprocessor(brushPreprocessor) -> the `brushPreprocessor(&opt)` call in setOption (ECharts.swift)
//   This function registers the three ACTIONS + the toolbox brush FEATURE, which do have registrars.
public func installBrushAction(_ registers: EChartsExtensionInstallRegisters) {
    _ = registers

    // registers.registerVisual(PRIORITY.VISUAL.BRUSH, brushVisualStageHandler);
    //   -> the integrator invokes `brushVisualStageHandler` in performVisualStage (see brushVisual.swift).

    // registerAction({type:'brush', event:'brush', update:'updateVisual'}, handler)
    var brushInfo = ActionInfo(type: "brush")
    brushInfo.event = "brush"
    brushInfo.update = "updateVisual"
    registerAction(brushInfo) { payload, ecModel, _ in
        // ecModel.eachComponent(
        //     {mainType: 'brush', query: payload},
        //     function (brushModel: BrushModel) { brushModel.setAreas(payload.areas); }
        // );
        //   The finder query is the payload itself (brushId / brushIndex / brushName), so a
        //   `dispatchAction({type:'brush', brushId: ...})` only reaches that brush component. The
        //   payload's dynamic bag IS the ModelFinderObject (same convention as the rest of the port).
        let areas = brushPayloadAreas(payload.other["areas"])
        ecModel.eachComponent(
            QueryConditionKindA(mainType: "brush", query: payload.other),
            { brushModel, _ in
                guard let brush = brushModel as? BrushModel else { return }
                // If `areas` is nil/undefined, setAreas keeps the current range state (upstream contract).
                brush.setAreas(areas)
            }
        )
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

    // registerFeature('brush', BrushFeature);
    //   The toolbox brush BUTTONS (rect / polygon / lineX / lineY / keep / clear). Clicking one dispatches
    //   `takeGlobalCursor` with a `brushOption`, which is what ARMS the paint cursor — i.e. this is how a
    //   user starts a brush in the official examples (`brush: { toolbox: [...] }`; the button list itself is
    //   injected into the toolbox option by `brushPreprocessor`).
    registerFeature("brush", ToolboxFeatureRegistration(
        create: { ToolboxBrushFeature() },
        getDefaultOption: { ecModel in ToolboxBrushFeature.getDefaultOption(ecModel) }
    ))
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
