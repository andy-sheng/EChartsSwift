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
// import { enterBlur, leaveBlur } from '../../util/states';         -> util/states.swift (enterBlur/leaveBlur ported; the blur toggling usage is deferred, see below)
// import { traverseUpdateZ, retrieveZInfo } from '../../util/graphic';
//   -> note: `retrieveZInfo` IS ported (component/helper/RoamController.swift). `traverseUpdateZ` is
//      not yet a reusable util/graphic function (only ECharts.swift has a private `doUpdateZ`), so it is
//      reproduced privately at the bottom of this file — a faithful copy of upstream's traverseUpdateZ/
//      doUpdateZ — and the marker-group z/zlevel pass (updateZ below) now propagates. Dedupe once landed.

// const inner = makeInner<{ keep: boolean }, MarkerDraw>();
// `makeInner` requires reference (`AnyObject`) value & host types. The `{ keep: boolean }`
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
    // not initialized at declaration place (upstream caveat); set in `init()`.
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
                    //   (the `if (el)` null-guard is handled inside eachItemGraphicEl).
                    if isBlur {
                        states.enterBlur(el)
                    }
                    else {
                        states.leaveBlur(el)
                    }
                }
            }
        }
    }

    // abstract renderSeries(seriesModel, markerModel, ecModel, api): void
    // abstract method — the per-type subclass (MarkPointView/MarkLineView/MarkAreaView,
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

        // if (markerModel && markerDraw && markerDraw.group) — `markerDraw.group` is non-optional here
        //   (the MarkerDraw protocol requires it), so the guard collapses to markerModel && markerDraw.
        if let markerModel = markerModel, let markerDraw = markerDraw {
            // const { z, zlevel } = retrieveZInfo(markerModel);
            // traverseUpdateZ(markerDraw.group, z, zlevel);
            // `retrieveZInfo` is the ported helper from component/helper/RoamController.swift
            //   (RoamZInfo.z/.zlevel mirror util/graphic.retrieveZInfo). `traverseUpdateZ` is not yet a
            //   shared util/graphic function, so it is reproduced privately below (a faithful copy of
            //   upstream util/graphic.ts `traverseUpdateZ`/`doUpdateZ`); dedupe once it lands as a shared fn.
            let zInfo = retrieveZInfo(markerModel)
            traverseUpdateZ(markerDraw.group, zInfo.z, zInfo.zlevel)
        }
    }
}

// upstream util/graphic.ts `traverseUpdateZ(el, z, zlevel)` — seeds the DFS with maxZ2 = -Infinity.
private func traverseUpdateZ(_ el: Element, _ z: Double, _ zlevel: Double) {
    _ = doUpdateZ(el, z, zlevel, -Double.infinity)
}

// upstream util/graphic.ts `doUpdateZ(el, z, zlevel, maxZ2)`. Sets `z`/`zlevel` on every displayable
//   (preserving `z2`, the intra-view order the painter tie-breaks on) and on each host's attached label /
//   text guide line, lifting the label `z2` above the subtree glyphs so it paints over what it annotates.
//   `ignoreModelZ` (an ExtendedElement flag) is not ported → not checked here (same caveat as
//   ECharts.swift's private `doUpdateZ`).
@discardableResult
private func doUpdateZ(_ el: Element, _ z: Double, _ zlevel: Double, _ maxZ2In: Double) -> Double {
    var maxZ2 = maxZ2In

    // Group may also have textContent.
    let label = el.getTextContent()
    let labelLine = el.getTextGuideLine()

    if el.isGroup {
        // set z & zlevel of children elements of Group
        if let g = el as? Group {
            for child in g.children() {
                maxZ2 = Swift.max(doUpdateZ(child, z, zlevel, maxZ2), maxZ2)
            }
        }
    }
    else if let d = el as? Displayable {
        d.z = z
        d.zlevel = zlevel
        // upstream `el.z2 || 0` — treat a NaN z2 as 0.
        maxZ2 = Swift.max(d.z2.isNaN ? 0 : d.z2, maxZ2)
    }

    // NOTICE: Do not call any method that can set REDRAW_BIT, otherwise progressive rendering is broken.

    // always set z and zlevel if label/labelLine exists
    if let label = label {   // ZRText is a Displayable — no downcast needed.
        label.z = z
        label.zlevel = zlevel
        // lift z2 of text content
        if maxZ2.isFinite { label.z2 = maxZ2 + 2 }
    }
    if let labelLine = labelLine {
        labelLine.z = z
        labelLine.zlevel = zlevel
        if maxZ2.isFinite {
            let showAbove = el.textGuideLineConfig?.showAbove ?? false
            labelLine.z2 = maxZ2 + (showAbove ? 1 : -1)
        }
    }
    return maxZ2
}

// export default MarkerView;  -> `open class MarkerView` above.
