// Ported from echarts/src/component/marker/MarkerView.ts — keep in sync with upstream
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
// import ComponentView from '../../view/Component';                -> EChartsKit `ComponentView` (view/ComponentView.swift)
// import { HashMap, createHashMap, each } from 'zrender/src/core/util';
//   -> `HashMap`/`createHashMap` (util/modelUtil.swift shim); `each` -> ZRenderKit `util.each`
// import MarkerModel from './MarkerModel';                          -> sibling MarkerModel.swift
// import GlobalModel from '../../model/Global';                     -> EChartsKit `GlobalModel`
// import ExtensionAPI from '../../core/ExtensionAPI';               -> EChartsKit `ExtensionAPI`
// import { makeInner } from '../../util/model';                     -> EChartsKit `model.makeInner`
// import SeriesModel from '../../model/Series';                     -> EChartsKit `SeriesModel`
// import Group from 'zrender/src/graphic/Group';                    -> ZRenderKit `Group`
// import { enterBlur, leaveBlur } from '../../util/states';         -> PORT-TODO: util/states.ts not yet ported
// import { traverseUpdateZ, retrieveZInfo } from '../../util/graphic'; -> PORT-TODO: util/graphic.ts not yet ported

// const inner = makeInner<{ keep: boolean }, MarkerDraw>();
// PORT-TODO: `makeInner` requires reference (`AnyObject`) value & host types. The `{ keep: boolean }`
//   bag is wrapped in a reference `MarkerDrawKeep`; `MarkerDraw` is the reference host (protocol).
final class MarkerDrawKeep {
    var keep: Bool = false
    init() {}
}
private let inner: (AnyObject) -> MarkerDrawKeep = model.makeInner { MarkerDrawKeep() }

// interface MarkerDraw { group: Group }
// The concrete `MarkerDraw` class lives in the dependent stage (component/marker/MarkerDraw.ts); the
// abstract view only needs the `group` slot, modeled here as a reference protocol so it can host the
// `makeInner` keep-flag and be used as `HashMap<MarkerDraw>` values.
public protocol MarkerDraw: AnyObject {
    var group: Group { get }
}

// upstream: abstract class MarkerView extends ComponentView
open class MarkerView: ComponentView {

    // static type = 'marker';
    open class var type: String { return "marker" }
    // type = MarkerView.type;
    open var type: String { return Self.type }

    /**
     * Markline grouped by series
     */
    // markerGroupMap: HashMap<MarkerDraw>;
    // PORT-TODO: not initialized at declaration place (upstream caveat); set in `init()`.
    public var markerGroupMap: HashMap<MarkerDraw>!

    // init() { this.markerGroupMap = createHashMap(); }
    open override func `init`(_ ecModel: GlobalModel, _ api: ExtensionAPI) {
        self.markerGroupMap = createHashMap()
    }

    // render(markerModel: MarkerModel, ecModel: GlobalModel, api: ExtensionAPI)
    // Overrides `ComponentView.render(model, ecModel, api, payload)`. The `model` param (the master
    // marker model) is unused inside — the per-series marker model is re-fetched below, faithful to
    // upstream (which likewise never reads its `markerModel` param here).
    open override func render(_ model: ComponentModel, _ ecModel: GlobalModel, _ api: ExtensionAPI, _ payload: Payload) {
        let markerGroupMap = self.markerGroupMap!
        markerGroupMap.each { item, _ in
            inner(item).keep = false
        }

        ecModel.eachSeries { seriesModel, _ in
            let markerModel = MarkerModel.getMarkerModelFromSeries(
                seriesModel,
                self.type   // as 'markPoint' | 'markLine' | 'markArea'
            )
            // markerModel && this.renderSeries(...)
            if let markerModel = markerModel {
                self.renderSeries(seriesModel, markerModel, ecModel, api)
            }
        }

        markerGroupMap.each { item, _ in
            // !inner(item).keep && this.group.remove(item.group);
            if !inner(item).keep {
                _ = self.group.remove(item.group)
            }
        }

        updateZ(ecModel, markerGroupMap, self.type)   // as 'markPoint' | 'markLine' | 'markArea'
    }

    open func markKeep(_ drawGroup: MarkerDraw) {
        inner(drawGroup).keep = true
    }

    open override func toggleBlurSeries(_ seriesModelList: [SeriesModel], _ isBlur: Bool, _ ecModel: GlobalModel) {
        util.each(seriesModelList) { seriesModel, _ in
            let markerModel = MarkerModel.getMarkerModelFromSeries(
                seriesModel,
                self.type   // as 'markPoint' | 'markLine' | 'markArea'
            )
            if let markerModel = markerModel {
                let data = markerModel.getData()
                data.eachItemGraphicEl { el, _ in
                    // if (el) { isBlur ? enterBlur(el) : leaveBlur(el); }
                    // PORT-TODO: `enterBlur`/`leaveBlur` (util/states.ts) not yet ported — emphasis/
                    //   blur state toggling is deferred (interaction, out of static-render scope).
                    _ = (el, isBlur)
                }
            }
        }
    }

    // abstract renderSeries(seriesModel, markerModel, ecModel, api): void
    // PORT-TODO: abstract method — the per-type subclass (MarkPointView/MarkLineView/MarkAreaView,
    //   dependent stage) must override.
    open func renderSeries(
        _ seriesModel: SeriesModel,
        _ markerModel: MarkerModel,
        _ ecModel: GlobalModel,
        _ api: ExtensionAPI
    ) {
        fatalError("renderSeries must be implemented by a MarkerView subclass")
    }
}

private func updateZ(
    _ ecModel: GlobalModel,
    _ markerGroupMap: HashMap<MarkerDraw>,
    _ type: String   // 'markPoint' | 'markLine' | 'markArea'
) {
    ecModel.eachSeries { seriesModel, _ in

        let markerModel = MarkerModel.getMarkerModelFromSeries(
            seriesModel,
            type
        )

        let markerDraw = markerGroupMap.get(seriesModel.id)

        if let markerModel = markerModel, let markerDraw = markerDraw {
            // const { z, zlevel } = retrieveZInfo(markerModel);
            // traverseUpdateZ(markerDraw.group, z, zlevel);
            // PORT-TODO: `retrieveZInfo` / `traverseUpdateZ` (util/graphic.ts) not yet ported — the
            //   z/zlevel propagation onto the marker draw group is deferred until util/graphic lands.
            _ = (markerModel, markerDraw)
        }
    }
}

// export default MarkerView;  -> `open class MarkerView` above.
