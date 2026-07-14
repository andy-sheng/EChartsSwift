// Ported from echarts/src/component/brush/BrushView.ts — keep in sync with upstream
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

// import * as zrUtil from 'zrender/src/core/util';
// import BrushController, { BrushControllerEvents, BrushCoverConfig } from '../helper/BrushController';
// import {layoutCovers} from './visualEncoding';   -> layoutCovers (brushVisual.swift)
// import BrushModel from './BrushModel';
// import GlobalModel from '../../model/Global';
// import ExtensionAPI from '../../core/ExtensionAPI';
// import { Payload } from '../../util/types';
// import ComponentView from '../../view/Component';

// class BrushView extends ComponentView
public final class BrushView: ComponentView {

    // static type = 'brush'; readonly type = BrushView.type;
    public static let type = "brush"

    // ecModel: GlobalModel; api: ExtensionAPI; model: BrushModel;
    var ecModel: GlobalModel?
    var api: ExtensionAPI?
    var model: BrushModel?

    // private _brushController: BrushController;
    private var _brushController: BrushController?

    // init(ecModel, api): void
    public override func `init`(_ ecModel: GlobalModel, _ api: ExtensionAPI) {
        self.ecModel = ecModel
        self.api = api

        // (this._brushController = new BrushController(api.getZr())).on('brush', bind(this._onBrush, this)).mount();
        //
        // PORT-NOTE (zr availability): upstream's `ECharts` OWNS the ZRender, so `api.getZr()` is live in
        //   `init`. This port's `ECharts` driver is host-independent and owns none — the live host
        //   (`EChartsView`) owns it and wires `ec.getRoot()` into it AFTER the first `setOption`
        //   (`_syncRoot`), so `api.getZr()` (which resolves the zr through the root's `__zr` back-pointer)
        //   is nil during the FIRST render's `init` and live from then on. The controller is therefore
        //   created lazily here AND in `_updateController` (idempotent). USER-VISIBLE CONSEQUENCE: none —
        //   covers only exist after a brush action/drag, both of which post-date the first frame. In a
        //   pure headless `ECharts` (no host zr at all) no controller is created: the brush still SELECTS
        //   (brushVisual runs on the data), but no cover is drawn and no drag is possible.
        _ensureController()
    }

    @discardableResult
    private func _ensureController() -> BrushController? {
        if let c = self._brushController { return c }
        guard let zr = self.api?.getZr() else { return nil }
        let controller = BrushController(zr)
        _ = controller.on("brush", { [weak self] _, args in
            guard let self = self, let eventParam = args.first as? BrushControllerBrushEvent else { return nil }
            self._onBrush(eventParam)
            return nil
        })
        controller.mount()
        self._brushController = controller
        return controller
    }

    // render(brushModel, ecModel, api, payload): void
    public override func render(
        _ model: ComponentModel, _ ecModel: GlobalModel, _ api: ExtensionAPI, _ payload: Payload
    ) {
        guard let brushModel = model as? BrushModel else { return }
        self.model = brushModel
        self._updateController(brushModel, ecModel, api, payload)
    }

    // updateTransform(brushModel, ecModel, api, payload)
    public func updateTransform(
        _ brushModel: BrushModel, _ ecModel: GlobalModel, _ api: ExtensionAPI, _ payload: Payload
    ) {
        // PENDING: `updateTransform` is a little tricky, whose layout need
        // to be calculate mandatorily and other stages will not be performed.
        // Take care the correctness of the logic. See #11754 .
        layoutCovers(ecModel)
        self._updateController(brushModel, ecModel, api, payload)
    }

    // updateVisual(brushModel, ecModel, api, payload)
    public override func updateVisual(
        _ model: ComponentModel, _ ecModel: GlobalModel, _ api: ExtensionAPI, _ payload: Payload
    ) {
        guard let brushModel = model as? BrushModel else { return }
        self.updateTransform(brushModel, ecModel, api, payload)
    }

    // updateView(brushModel, ecModel, api, payload)
    public override func updateView(
        _ model: ComponentModel, _ ecModel: GlobalModel, _ api: ExtensionAPI, _ payload: Payload
    ) {
        guard let brushModel = model as? BrushModel else { return }
        self._updateController(brushModel, ecModel, api, payload)
    }

    // private _updateController(brushModel, ecModel, api, payload)
    private func _updateController(
        _ brushModel: BrushModel, _ ecModel: GlobalModel, _ api: ExtensionAPI, _ payload: Payload?
    ) {
        self.ecModel = ecModel
        self.api = api
        guard let brushController = self._ensureController() else { return }

        // See `applyTakeGlobalCursor`'s PORT-NOTE (stage order): upstream's visual stage has already run
        //   `setBrushOption` by the time this view renders; in this driver it has not, so arm the paint
        //   cursor here as well (idempotent — brushVisual makes the identical call later in the frame).
        applyTakeGlobalCursor(brushModel, payload)

        // Do not update controller when drawing.
        // (!payload || payload.$from !== brushModel.id) && this._brushController
        //     .setPanels(brushModel.brushTargetManager.makePanelOpts(api))
        //     .enableBrush(brushModel.brushOption)
        //     .updateCovers(brushModel.areas.slice() as BrushCoverConfig[]);
        let from = payload?.other["$from"] as? String
        if payload == nil || from != brushModel.id {
            _ = brushController
                .setPanels(brushModel.brushTargetManager?.makePanelOpts(api))
                .enableBrush(BrushCoverCreatorConfig(brushModel.brushOption))
                .updateCovers(brushModel.areas)
        }
    }

    // updateLayout: updateController,

    // updateVisual: updateController,

    // dispose()
    public override func dispose(_ ecModel: GlobalModel, _ api: ExtensionAPI) {
        self._brushController?.dispose()
        self._brushController = nil
    }

    // private _onBrush(eventParam: BrushControllerEvents['brush']): void
    private func _onBrush(_ eventParam: BrushControllerBrushEvent) {
        guard let model = self.model, let ecModel = self.ecModel, let api = self.api else { return }
        let modelId = model.id

        // const areas = this.model.brushTargetManager.setOutputRanges(eventParam.areas, this.ecModel);
        let areas = model.brushTargetManager?.setOutputRanges(eventParam.areas, ecModel) ?? []

        // Action is not dispatched on drag end, because the drag end
        // emits the same params with the last drag move event, and
        // may have some delay when using touch pad, which makes
        // animation not smooth (when using debounce).
        // (!eventParam.isEnd || eventParam.removeOnClick) && this.api.dispatchAction({
        //     type: 'brush', brushId: modelId, areas: zrUtil.clone(areas), $from: modelId
        // });
        if !eventParam.isEnd || eventParam.removeOnClick {
            var p = Payload(type: "brush")
            p.other["brushId"] = modelId
            p.other["areas"] = areas
            p.other["$from"] = modelId
            api.dispatchAction(p)
        }
        // eventParam.isEnd && this.api.dispatchAction({
        //     type: 'brushEnd', brushId: modelId, areas: zrUtil.clone(areas), $from: modelId
        // });
        if eventParam.isEnd {
            var p = Payload(type: "brushEnd")
            p.other["brushId"] = modelId
            p.other["areas"] = areas
            p.other["$from"] = modelId
            api.dispatchAction(p)
        }
    }
}

// export default BrushView;  -> `public final class BrushView` above.
