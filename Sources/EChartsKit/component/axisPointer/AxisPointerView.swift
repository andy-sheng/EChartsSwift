// Ported from echarts/src/component/axisPointer/AxisPointerView.ts — keep in sync with upstream
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

// upstream imports (resolved to the ported modules):
// import * as globalListener from './globalListener';        -> globalListener.swift (same module)
// import ComponentView from '../../view/Component';           -> view/ComponentView.swift
// import AxisPointerModel from './AxisPointerModel';          -> AxisPointerModel.swift (same module)
// import GlobalModel from '../../model/Global';               -> model/Global.swift
// import ExtensionAPI from '../../core/ExtensionAPI';         -> core/ExtensionAPI.swift
// import TooltipModel from '../tooltip/TooltipModel';         -> component/tooltip/TooltipModel.swift

// upstream: class AxisPointerView extends ComponentView { static type = 'axisPointer'; ... }
//
//   HOST-SEAM DEVIATION: upstream `render` registers the ONE global `axisPointer` zr listener set
//   (`globalListener.register('axisPointer', api, handler)`) whose fan-out dispatches
//   `updateAxisPointer`. In THIS slim port, `EChartsView._bindAxisPointerListeners` (Phase 35) ALREADY
//   owns that `globalListener.register("axisPointer", ...)` binding against the live zr (documented in
//   EChartsView — the views have no live zr at render time). Registering again here would double-bind
//   the same key. So this view's `render` is a documented no-op: it exists to satisfy the component/view
//   registry (`registerComponentView(AxisPointerView)`), while the actual listener + the per-axis
//   crosshair pointer managers (`CartesianAxisPointer` / `BaseAxisPointer`) are driven by `EChartsView`
//   / `axisTrigger`. The crosshair `Group` each pointer manager builds is hosted in the live zr via the
//   manager's `hostAdd` / `hostRemove` seam (see `BaseAxisPointer`).
public final class AxisPointerView: ComponentView {

    // static type = 'axisPointer' as const;
    public static let type = "axisPointer"
    // type = AxisPointerView.type;
    public let type = "axisPointer"

    public override init() {
        super.init()
    }

    // upstream: render(globalAxisPointerModel, ecModel, api) { globalListener.register('axisPointer', ...) }
    public override func render(
        _ model: ComponentModel,
        _ ecModel: GlobalModel,
        _ api: ExtensionAPI,
        _ payload: Payload
    ) {
        // No-op — see the HOST-SEAM DEVIATION note on the class. The global `axisPointer` listener is
        //   owned by `EChartsView._bindAxisPointerListeners`. Faithful body (for reference):
        //     let globalTooltipModel = ecModel.getComponent('tooltip') as TooltipModel;
        //     let triggerOn = globalAxisPointerModel.get('triggerOn')
        //         || (globalTooltipModel && globalTooltipModel.get('triggerOn')) || 'mousemove|click|mousewheel';
        //     globalListener.register('axisPointer', api, (currTrigger, e, dispatchAction) => {
        //         if (triggerOn !== 'none'
        //             && (currTrigger === 'leave' || triggerOn.indexOf(currTrigger) >= 0)) {
        //             dispatchAction({ type: 'updateAxisPointer', currTrigger, x: e && e.offsetX, y: e && e.offsetY });
        //         }
        //     });
        _ = (model, ecModel, api, payload)
    }

    // upstream: remove(ecModel, api) { globalListener.unregister('axisPointer', api); }
    //   PORT-NOTE: the ported `ComponentView` base exposes `dispose` (not `remove`); upstream's `remove`
    //   only unregisters the global listener, which `EChartsView` owns here, so both fold into `dispose`.
    public override func dispose(_ ecModel: GlobalModel, _ api: ExtensionAPI) {
        // upstream: globalListener.unregister('axisPointer', api);
        //   The listener is owned/unregistered by `EChartsView` (see the class note), so this is a no-op.
        _ = (ecModel, api)
    }
}

// export default AxisPointerView;  -> `final class AxisPointerView` above.
