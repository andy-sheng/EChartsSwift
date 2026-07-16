// Ported from echarts/src/chart/bar/BarView.ts — keep in sync with upstream
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
//   import Path, {PathProps} from 'zrender/src/graphic/Path';        -> ZRenderKit `Path` / `PathProps`.
//   import Group from 'zrender/src/graphic/Group';                   -> ZRenderKit `Group`.
//   import {extend, each, map} from 'zrender/src/core/util';         -> `util.extend` / `util.each` / `util.map`.
//   import {BuiltinTextPosition} from 'zrender/src/core/types';      -> type-only (label block deferred).
//   import {SectorProps} from 'zrender/src/graphic/shape/Sector';    -> PORT-NOTE: ZRenderKit `Sector` is ported; the polar Sector branch is deferred in this cartesian-only bar view.
//   import {RectProps} from 'zrender/src/graphic/shape/Rect';        -> ZRenderKit `RectProps`.
//   import { Rect, Sector, updateProps, initProps, removeElementWithFadeOut, traverseElements }
//       from '../../util/graphic';
//     -> `Rect` is the ZRenderKit shape (graphic re-exports it). `Sector` (polar) is deferred.
//        `updateProps` / `initProps` / `removeElementWithFadeOut` now resolve to the real ported
//        `animation/basicTransition.swift` (module-level, animated). `traverseElements` == `Group.traverse`.
//   import { getECData } from '../../util/innerStore';               -> `innerStore.getECData`.
//   import { setStatesStylesFromModel, toggleHoverEmphasis } from '../../util/states';
//     -> `states.setStatesStylesFromModel` / `states.toggleHoverEmphasis` (util/states.swift). APPLIED
//        in `updateStyle` (Phase 33): each bar Rect becomes a highDown dispatcher with its emphasis
//        itemStyle so hover highlights it end-to-end.
//   import { setLabelStyle, getLabelStatesModels, setLabelValueAnimation, labelInner }
//       from '../../label/labelStyle';
//     -> PORT-NOTE: `label/labelStyle` is ported; the label block in `updateStyle` is still deferred in this view.
//   import {throttle} from '../../util/throttle';                    -> PORT-NOTE (deferred): requires util/throttle (not ported; large mode only).
//   import {createClipPath} from '../helper/createClipPathFromCoordSys';  -> sibling `createClipPath`.
//   import Sausage from '../../util/shape/sausage';                  -> PORT-NOTE (deferred): requires util/shape/sausage (not ported; polar roundCap only).
//   import ChartView from '../../view/Chart';                        -> `ChartView` (view/Chart.swift).
//   import SeriesData, {DefaultDataVisual} from '../../data/SeriesData';  -> `SeriesData`.
//   import GlobalModel from '../../model/Global';                    -> `GlobalModel`.
//   import ExtensionAPI from '../../core/ExtensionAPI';              -> `ExtensionAPI`.
//   import { StageHandlerProgressParams, ZRElementEvent, ColorString, OrdinalSortInfo, Payload,
//            OrdinalNumber, ParsedValue, ECElement } from '../../util/types';  -> util/types.swift.
//   import BarSeriesModel, {BarDataItemOption, PolarBarLabelPosition} from './BarSeries';  -> `BarSeriesModel`.
//   import type Axis2D from '../../coord/cartesian/Axis2D';          -> `Axis2D`.
//   import type Cartesian2D from '../../coord/cartesian/Cartesian2D'; -> `Cartesian2D`.
//   import type Polar from '../../coord/polar/Polar';                -> PORT-NOTE: coord/polar is ported; polar bars deferred in this view.
//   import type Model from '../../model/Model';                      -> `Model`.
//   import { isCoordinateSystemType } from '../../coord/CoordinateSystem';  -> coord/CoordinateSystem.swift.
//   import { getDefaultLabel, getDefaultInterpolatedLabel } from '../helper/labelHelper';
//     -> PORT-NOTE: `chart/helper/labelHelper` is ported (label block still deferred in this view).
//   import OrdinalScale from '../../scale/Ordinal';                  -> scale/Ordinal.swift (realtimeSort only).
//   import SeriesModel from '../../model/Series';                    -> `SeriesModel`.
//   import {AngleAxisModel, RadiusAxisModel} from '../../coord/polar/AxisModel';  -> PORT-NOTE: ported (coord/polar/PolarAxisModel.swift); polar bars deferred in this view.
//   import CartesianAxisModel from '../../coord/cartesian/AxisModel'; -> coord/cartesian/AxisModel.swift.
//   import {LayoutRect} from '../../util/layout';                    -> util/layout.swift.
//   import {EventCallback} from 'zrender/src/core/Eventful';         -> `EventCallback` (ZRenderKit).
//   import { warn } from '../../util/log';                           -> `log.warn`.
//   import {createSectorCalculateTextPosition, SectorTextPosition, setSectorTextRotation}
//       from '../../label/sectorLabel';                              -> PORT-NOTE (deferred): requires label/sectorLabel (not ported; polar/label).
//   import { saveOldStyle } from '../../animation/basicTransition';  -> animation/basicTransition.saveOldStyle (real since universalTransition landed).
//   import Element from 'zrender/src/Element';                       -> `Element` (ZRenderKit).
//   import { getSectorCornerRadius } from '../helper/sectorHelper';  -> PORT-NOTE: sectorHelper is ported; polar bars deferred in this view.
//   import { getIncrementalId } from '../../util/model';             -> `model.getIncrementalId` (large mode only).
//   import { SERIES_TYPE_BAR } from '../../layout/barCommon';        -> `SERIES_TYPE_BAR`.

// upstream: const mathMax = Math.max; const mathMin = Math.min;
//   Typed `Double` wrappers (a bare `let mathMax = Swift.max` cannot infer the generic parameter).
private func mathMax(_ a: Double, _ b: Double) -> Double { Swift.max(a, b) }
private func mathMin(_ a: Double, _ b: Double) -> Double { Swift.min(a, b) }

// Upstream passes a plain `{x, y, width, height}` object literal into `initProps`/`updateProps`'s
// `{shape: layout}` — a genuine dictionary, which `animateToShallow` recurses into (per-key tracks,
// each field animates independently). Our `RectShape` is a typed struct, not a `[String: Any]`, so
// `util.isObject(targetVal)` on the whole struct is false and the shared helper falls back to
// treating "shape" as one opaque (non-numeric, non-array) value — which the animation system marks
// discrete and jumps to instantly, dropping the animator right after `start()` even when animation
// is enabled. Converting to a partial dict here restores the faithful per-field tween.
private func rectShapeAnimShape(_ s: RectShape) -> [String: Any] {
    ["x": s.x, "y": s.y, "width": s.width, "height": s.height]
}

// upstream:
//   type CoordSysOfBar = BarSeriesModel['coordinateSystem'];   // Cartesian2D | Polar
//   type RectShape = Rect['shape'];                            // == ZRenderKit RectShape
//   type SectorShape = Sector['shape'];                        // PORT-NOTE: Sector ported; polar bars deferred in this view
//   type SectorLayout = SectorShape;                           // PORT-NOTE: Sector ported; polar bars deferred in this view
//   type RectLayout = RectShape;
// PORT-NOTE: `Polar` and `Sector` are ported, but the bar milestone is cartesian-only, so
//   `CoordSysOfBar` collapses to `Cartesian2D` and `RectLayout` to the ZRenderKit `RectShape`.
typealias CoordSysOfBar = Cartesian2D
typealias RectLayout = RectShape

// upstream: type BarPossiblePath = Sector | Rect | Sausage;
//   Cartesian-only → the element is always a `Rect`; the common supertype used at call sites is `Path`.
typealias BarPossiblePath = Path

// upstream:
//   type CartesianCoordArea = ReturnType<Cartesian2D['getArea']>;   // == Cartesian2DArea (BoundingRect)
//   type PolarCoordArea = ReturnType<Polar['getArea']>;             // PORT-NOTE: Polar ported; polar bars deferred in this view
typealias CartesianCoordArea = Cartesian2DArea

// upstream:
//   type RealtimeSortConfig = { baseAxis: Axis2D; otherAxis: Axis2D };
struct RealtimeSortConfig {
    var baseAxis: Axis2D
    var otherAxis: Axis2D
}
// Return a number, based on which the ordinal sorted.
// upstream: type OrderMapping = (dataIndex: number) => number;
typealias OrderMapping = (_ dataIndex: Int) -> Double


// upstream: class BarView extends ChartView
open class BarView: ChartView {
    // upstream: static readonly type = SERIES_TYPE_BAR;
    public static let barType = SERIES_TYPE_BAR
    // upstream: readonly type = SERIES_TYPE_BAR;
    open override var type: String {
        get { SERIES_TYPE_BAR }
        set { /* readonly upstream */ }
    }

    private var _data: SeriesData?

    private var _isLargeDraw: Bool?

    private var _isFirstFrame: Bool = true // First frame after series added
    // upstream: private _onRendered: EventCallback;
    // PORT-NOTE (deferred): requires ExtensionAPI.getZr forwarding + event plumbing (getZr is listed in
    //   ExtensionAPI.availableMethods but the dynamic method binding is deferred to Phase 6b, so
    //   `api.getZr().on('rendered', cb)` is not callable). Kept as a closure slot; realtimeSort is
    //   deferred (see `_enableRealtimeSort`).
    private var _onRendered: (() -> Void)?

    private var _backgroundGroup: Group?

    // upstream: private _backgroundEls: (Rect | Sector)[];
    // PORT-NOTE: upstream is a sparse array indexed by dataIndex; modeled as `[Int: Rect]` (cartesian,
    //   `Rect` only). `.length === 0` → `.isEmpty`; `oldBgEls[oldIndex]` → dict lookup.
    private var _backgroundEls: [Int: Rect] = [:]

    private var _model: BarSeriesModel!

    private var _progressiveEls: [Element]?

    // upstream: constructor() { super(); this._isFirstFrame = true; }
    public override init() {
        super.init()
        self._isFirstFrame = true
    }

    open override func render(
        _ seriesModel: SeriesModel, _ ecModel: GlobalModel, _ api: ExtensionAPI, _ payload: Payload
    ) {
        // upstream typed `seriesModel: BarSeriesModel`; the base override is typed `SeriesModel`.
        let seriesModel = seriesModel as! BarSeriesModel
        self._model = seriesModel

        self._removeOnRenderedListener(api)

        self._updateDrawMode(seriesModel)

        let coordinateSystemType = seriesModel.get("coordinateSystem") as? String

        if coordinateSystemType == "cartesian2d"
            || coordinateSystemType == "polar" {
            // Clear previously rendered progressive elements.
            self._progressiveEls = nil

            if self._isLargeDraw == true {
                self._renderLarge(seriesModel, ecModel, api)
            }
            else {
                self._renderNormal(seriesModel, ecModel, api, payload)
            }
        }
        else if __DEV__ {
            log.warn("Only cartesian2d and polar supported for bar.")
        }
    }

    // upstream: incrementalPrepareRender(seriesModel: BarSeriesModel): void
    open override func incrementalPrepareRender(
        _ seriesModel: SeriesModel, _ ecModel: GlobalModel, _ api: ExtensionAPI, _ payload: Payload
    ) {
        let seriesModel = seriesModel as! BarSeriesModel
        self._clear()
        self._updateDrawMode(seriesModel)
        // incremental also need to clip, otherwise might be overlow.
        // But must not set clip in each frame, otherwise all of the children will be marked redraw.
        self._updateLargeClip(seriesModel)
    }

    // upstream: incrementalRender(params: StageHandlerProgressParams, seriesModel: BarSeriesModel): void
    open override func incrementalRender(
        _ params: StageHandlerProgressParams, _ seriesModel: SeriesModel, _ ecModel: GlobalModel,
        _ api: ExtensionAPI, _ payload: Payload
    ) {
        let seriesModel = seriesModel as! BarSeriesModel
        // Reset for eachRendered
        self._progressiveEls = []
        // Do not support progressive in normal mode.
        self._incrementalRenderLarge(params, seriesModel)
    }

    open override func eachRendered(_ cb: (_ el: Element) -> Bool) {
        // upstream: traverseElements(this._progressiveEls || this.group, cb);
        // PORT-NOTE: `util/graphic.traverseElements` not ported. When `_progressiveEls` exists, traverse
        //   each (large mode, deferred); otherwise traverse the group via `Group.traverse` (visits
        //   children only — see the same note in view/Chart.swift `eachRendered`).
        if let progressiveEls = self._progressiveEls {
            for el in progressiveEls {
                _ = cb(el)
            }
        }
        else {
            self.group.traverse(cb)
        }
    }

    private func _updateDrawMode(_ seriesModel: BarSeriesModel) {
        let isLargeDraw = seriesModel.pipelineContext.large
        if self._isLargeDraw == nil || isLargeDraw != self._isLargeDraw {
            self._isLargeDraw = isLargeDraw
            self._clear()
        }
    }

    private func _renderNormal(
        _ seriesModel: BarSeriesModel,
        _ ecModel: GlobalModel,
        _ api: ExtensionAPI,
        _ payload: Payload
    ) {
        let group = self.group
        let data = seriesModel.getData()
        let oldData = self._data

        // upstream: const coord = seriesModel.coordinateSystem; ... branch on coord.type.
        // Polar bar → radial Sectors (a minimal static reproduction of layout/barPolar + the polar
        //   branch of BarView; the full bar width/offset sharing, stacking, and background are deferred).
        if let polar = seriesModel.coordinateSystem as? Polar {
            self._renderPolarBars(seriesModel, polar, group)
            self._data = data
            return
        }
        guard let coord = seriesModel.coordinateSystem as? Cartesian2D else {
            return
        }
        let baseAxis = coord.getBaseAxis()
        // coord.type === 'cartesian2d' → isHorizontalOrRadial = baseAxis.isHorizontal()
        let isHorizontalOrRadial: Bool = baseAxis.isHorizontal()

        let animationModel: BarSeriesModel? = (seriesModel.isAnimationEnabled() ?? false) ? seriesModel : nil

        let realtimeSortCfg = shouldRealtimeSort(seriesModel, coord)

        if realtimeSortCfg != nil {
            self._enableRealtimeSort(realtimeSortCfg!, data, api)
        }

        let needsClip = ((seriesModel.get("clip", true) as? Bool) ?? false) || (realtimeSortCfg != nil)
        // Both `cartesian2d` and `polar` has `getArea()`.
        let coordSysClipArea = coord.getArea()
        // If there is clipPath created in large mode. Remove it.
        group.removeClipPath()
        // We don't use clipPath in normal mode because we needs a perfect animation
        // And don't want the label are clipped.
        // Instead, `Clipper` is used in normal mode.

        let roundCap = (seriesModel.get("roundCap", true) as? Bool) ?? false

        let drawBackground = (seriesModel.get("showBackground", true) as? Bool) ?? false
        let backgroundModel = seriesModel.getModel("backgroundStyle")
        let barBorderRadius = (backgroundModel.get("borderRadius") as? Double) ?? 0

        var bgEls: [Int: Rect] = [:]
        let oldBgEls = self._backgroundEls

        let isInitSort = (payload.other["isInitSort"] as? Bool) ?? false
        let isChangeOrder = payload.type == "changeAxisOrder"

        // upstream: function createBackground(dataIndex) { ... }
        func createBackground(_ dataIndex: Int) -> Rect? {
            let bgLayout = getLayoutCartesian2D(data, dataIndex, nil)
            if bgLayout == nil {
                return nil
            }
            let bgEl = createBackgroundEl(coord, isHorizontalOrRadial, bgLayout!)
            bgEl.useStyle(barStyleFromDict(backgroundModel.getItemStyle()))
            // Only cartesian2d support borderRadius.
            // upstream: (bgEl as Rect).setShape('r', barBorderRadius);
            _ = bgEl.setShape("r", barBorderRadius)
            bgEls[dataIndex] = bgEl
            return bgEl
        }

        data.diff(oldData)
            .add({ dataIndex in
                let itemModel = data.getItemModel(dataIndex)
                guard var layout = getLayoutCartesian2D(data, dataIndex, itemModel) else {
                    return
                }

                if drawBackground {
                    _ = createBackground(dataIndex)
                }

                // If dataZoom in filteMode: 'empty', the baseValue can be set as NaN in "axisProxy".
                if !data.hasValue(dataIndex) || !isValidLayoutCartesian2D(layout) {
                    return
                }

                var isClipped = false
                if needsClip {
                    // Clip will modify the layout params.
                    // And return a boolean to determine if the shape are fully clipped.
                    isClipped = clipCartesian2D(coordSysClipArea, &layout)
                }

                let el = elementCreatorCartesian2D(
                    seriesModel, data, dataIndex, layout, isHorizontalOrRadial,
                    animationModel, baseAxis.model, false, roundCap
                )
                if realtimeSortCfg != nil {
                    // (el as ECElement).forceLabelAnimation = true;
                    // PORT-NOTE (deferred): ECElement.forceLabelAnimation is only consumed by the label
                    //   animation subsystem, which is deferred in this view (and this branch is
                    //   realtimeSort-gated, itself deferred). No-op until the label block lands.
                }

                updateStyle(
                    el, data, dataIndex, itemModel, layout,
                    seriesModel, isHorizontalOrRadial, false /* coord.type === 'polar' */
                )
                if isInitSort {
                    // upstream: (el as Rect).attr({ shape: layout });
                    _ = el.setShape(layout)
                }
                else if realtimeSortCfg != nil {
                    updateRealtimeAnimation(
                        realtimeSortCfg!, animationModel, el, layout, dataIndex,
                        isHorizontalOrRadial, false, false
                    )
                }
                else {
                    initProps(el, ["shape": rectShapeAnimShape(layout)], seriesModel, dataIndex)
                }

                data.setItemGraphicEl(dataIndex, el)

                _ = group.add(el)
                el.ignore = isClipped
            })
            .update({ newIndex, oldIndex in
                let itemModel = data.getItemModel(newIndex)
                guard let layout = getLayoutCartesian2D(data, newIndex, itemModel) else {
                    return
                }

                if drawBackground {
                    var bgEl: Rect?
                    if oldBgEls.isEmpty {
                        bgEl = createBackground(oldIndex)
                    }
                    else {
                        bgEl = oldBgEls[oldIndex]
                        bgEl?.useStyle(barStyleFromDict(backgroundModel.getItemStyle()))
                        // Only cartesian2d support borderRadius.
                        _ = bgEl?.setShape("r", barBorderRadius)
                        bgEls[newIndex] = bgEl
                    }
                    let bgLayout = getLayoutCartesian2D(data, newIndex, nil)
                    if let bgEl = bgEl, let bgLayout = bgLayout {
                        let shape = createBackgroundShape(isHorizontalOrRadial, bgLayout, coord)
                        updateProps(bgEl, ["shape": rectShapeAnimShape(shape)], animationModel, newIndex)
                    }
                }

                var el = oldData?.getItemGraphicEl(oldIndex) as? BarPossiblePath
                if !data.hasValue(newIndex) || !isValidLayoutCartesian2D(layout) {
                    if let el = el { _ = group.remove(el) }
                    return
                }

                var isClipped = false
                if needsClip {
                    var clipLayout = layout
                    isClipped = clipCartesian2D(coordSysClipArea, &clipLayout)
                    if isClipped, let el = el {
                        _ = group.remove(el)
                    }
                }

                // upstream: roundCapChanged = el && (el.type === 'sector' && roundCap || el.type === 'sausage' && !roundCap)
                // Cartesian elements are always 'rect' → this is false at runtime; the polar
                // (sector/sausage) recreate path is deferred (PORT-NOTE: polar). Read `el.type` at runtime to
                // mirror upstream faithfully rather than hard-coding `false` (which is dead code).
                let elType = el?.type
                let roundCapChanged = elType != nil
                    && ((elType == "sector" && roundCap) || (elType == "sausage" && !roundCap))
                if roundCapChanged {
                    // roundCap changed (polar only): remove old and recreate. PORT-NOTE (polar deferred).
                    if let el = el { removeElementWithFadeOut(el, seriesModel, oldIndex) }
                    el = nil
                }

                if el == nil {
                    el = elementCreatorCartesian2D(
                        seriesModel, data, newIndex, layout, isHorizontalOrRadial,
                        animationModel, baseAxis.model, true, roundCap
                    )
                }
                else {
                    saveOldStyle(el!)
                }

                if realtimeSortCfg != nil {
                    // (el as ECElement).forceLabelAnimation = true;  // PORT-NOTE (deferred: label block).
                }

                if isChangeOrder {
                    // upstream reuses the previous label's prevValue to skip a new label animation.
                    // PORT-NOTE (deferred): label subsystem (labelInner / getTextContent label store).
                }
                // Not change anything if only order changed.
                // Especially not change label.
                else {
                    updateStyle(
                        el!, data, newIndex, itemModel, layout,
                        seriesModel, isHorizontalOrRadial, false /* coord.type === 'polar' */
                    )
                }

                if isInitSort {
                    _ = el!.setShape(layout)
                }
                else if realtimeSortCfg != nil {
                    updateRealtimeAnimation(
                        realtimeSortCfg!, animationModel, el!, layout, newIndex,
                        isHorizontalOrRadial, true, isChangeOrder
                    )
                }
                else {
                    updateProps(el!, ["shape": rectShapeAnimShape(layout)], seriesModel, newIndex)
                }

                data.setItemGraphicEl(newIndex, el!)
                el!.ignore = isClipped
                _ = group.add(el!)
            })
            .remove({ dataIndex in
                let el = oldData?.getItemGraphicEl(dataIndex) as? Path
                if let el = el { removeElementWithFadeOut(el, seriesModel, dataIndex) }
            })
            .execute()

        let bgGroup: Group
        if let existing = self._backgroundGroup {
            bgGroup = existing
        }
        else {
            bgGroup = Group()
            self._backgroundGroup = bgGroup
        }
        _ = bgGroup.removeAll()

        // upstream: for (let i = 0; i < bgEls.length; ++i) { bgGroup.add(bgEls[i]); }
        for i in bgEls.keys.sorted() {
            _ = bgGroup.add(bgEls[i])
        }
        _ = group.add(bgGroup)
        self._backgroundEls = bgEls

        self._data = data
    }

    private func _renderLarge(_ seriesModel: BarSeriesModel, _ ecModel: GlobalModel, _ api: ExtensionAPI) {
        self._clear()
        // upstream: createLarge(seriesModel, this.group);
        //   One LargeBarPath over the barGrid `largePoints` layout, drawn per-bar via the fill boost
        //   (LargeBarPath.swift) — the mouse-event throttle (largePathUpdateDataIndex) is the only piece
        //   still deferred (tooltip hit-testing over the large path), not the draw.
        barCreateLarge(seriesModel, self.group)
        self._updateLargeClip(seriesModel)
    }

    private func _incrementalRenderLarge(_ params: StageHandlerProgressParams, _ seriesModel: BarSeriesModel) {
        self._removeBackground()
        // upstream: createLarge(seriesModel, this.group, this._progressiveEls, true);
        // PORT-NOTE (deferred): large/progressive draw (see `_renderLarge`).
    }

    private func _updateLargeClip(_ seriesModel: BarSeriesModel) {
        // Use clipPath in large mode.
        // upstream: const clipPath = seriesModel.get('clip', true) && createClipPath(...)
        let clip = (seriesModel.get("clip", true) as? Bool) ?? false
        let clipPath: Path? = clip
            ? createClipPath(seriesModel.coordinateSystem as? CoordinateSystem, false, seriesModel)
            : nil
        let group = self.group
        if let clipPath = clipPath {
            group.setClipPath(clipPath)
        }
        else {
            group.removeClipPath()
        }
    }

    // ------------------------------------------------------------------------------------------
    // realtimeSort — PORT-NOTE (deferred): requires ExtensionAPI.getZr forwarding + event/dispatch plumbing.
    //   The methods below need `api.getZr().on('rendered', …)` + `api.dispatchAction(…)` (getZr is listed in
    //   ExtensionAPI.availableMethods but its dynamic binding is deferred) and OrdinalScale sort helpers.
    //   `shouldRealtimeSort` returns
    //   nil for the default (realtimeSort: false) path, so these are unreachable in the common case.
    //   Faithful signatures are preserved for a later mechanical port.
    // ------------------------------------------------------------------------------------------

    private func _enableRealtimeSort(
        _ realtimeSortCfg: RealtimeSortConfig,
        _ data: SeriesData,
        _ api: ExtensionAPI
    ) {
        // PORT-NOTE (deferred): realtimeSort (see the block comment above). Upstream body:
        //   if (!data.count()) return;
        //   if (this._isFirstFrame) { this._dispatchInitSort(...); this._isFirstFrame = false; }
        //   else { register an `orderMapping` + `api.getZr().on('rendered', ...)` listener. }
        _ = (realtimeSortCfg, data, api)
    }

    private func _dataSort(
        _ data: SeriesData,
        _ baseAxis: Axis2D,
        _ orderMapping: OrderMapping
    ) -> OrdinalSortInfo {
        // PORT-NOTE (deferred): realtimeSort (see the block comment above).
        _ = (data, baseAxis, orderMapping)
        return OrdinalSortInfo(ordinalNumbers: [])
    }

    private func _updateSortWithinSameData(
        _ data: SeriesData,
        _ orderMapping: OrderMapping,
        _ baseAxis: Axis2D,
        _ api: ExtensionAPI
    ) {
        // PORT-NOTE (deferred): realtimeSort (see the block comment above).
        _ = (data, orderMapping, baseAxis, api)
    }

    private func _dispatchInitSort(
        _ data: SeriesData,
        _ realtimeSortCfg: RealtimeSortConfig,
        _ api: ExtensionAPI
    ) {
        // PORT-NOTE (deferred): realtimeSort (see the block comment above).
        _ = (data, realtimeSortCfg, api)
    }

    open override func remove(_ ecModel: GlobalModel, _ api: ExtensionAPI) {
        self._clear(self._model)
        self._removeOnRenderedListener(api)
    }

    open override func dispose(_ ecModel: GlobalModel, _ api: ExtensionAPI) {
        self._removeOnRenderedListener(api)
    }

    private func _removeOnRenderedListener(_ api: ExtensionAPI) {
        if self._onRendered != nil {
            // upstream: api.getZr().off('rendered', this._onRendered);
            // PORT-NOTE (deferred): requires ExtensionAPI.getZr forwarding + event plumbing (realtimeSort).
            self._onRendered = nil
        }
    }

    private func _clear(_ model: SeriesModel? = nil) {
        let group = self.group
        let data = self._data
        if let model = model, (model.isAnimationEnabled() ?? false), data != nil, self._isLargeDraw != true {
            self._removeBackground()
            self._backgroundEls = [:]

            data!.eachItemGraphicEl({ el, _ in
                // upstream: removeElementWithFadeOut(el, model, getECData(el).dataIndex);
                if let el = el as? Path {
                    let dataIndex = innerStore.getECData(el).dataIndex
                    removeElementWithFadeOut(el, model, dataIndex.map { Int($0) } ?? -1)
                }
            })
        }
        else {
            _ = group.removeAll()
        }
        self._data = nil
        self._isFirstFrame = true
    }

    private func _removeBackground() {
        if let bg = self._backgroundGroup {
            _ = self.group.remove(bg)
        }
        self._backgroundGroup = nil
    }
}

// ================================================================================================
// upstream: `interface Clipper` + `const clip: { [key in 'cartesian2d' | 'polar']: Clipper }`.
//   The keyed-dispatch object collapses to the cartesian2d entry (polar deferred). Because upstream
//   MUTATES `layout` in place (and Swift structs are value types), the port takes `inout RectShape`,
//   which cannot be stored in a `[String: closure]` map — so this is a free function (documented
//   deviation, same reasoning applies to `elementCreator`/`getLayout`/`isValidLayout` below).
// ================================================================================================
func clipCartesian2D(_ coordSysClipArea: CartesianCoordArea, _ layout: inout RectShape) -> Bool {
    let signWidth: Double = layout.width < 0 ? -1 : 1
    let signHeight: Double = layout.height < 0 ? -1 : 1
    // Needs positive width and height
    if signWidth < 0 {
        layout.x += layout.width
        layout.width = -layout.width
    }
    if signHeight < 0 {
        layout.y += layout.height
        layout.height = -layout.height
    }

    let coordSysX2 = coordSysClipArea.x + coordSysClipArea.width
    let coordSysY2 = coordSysClipArea.y + coordSysClipArea.height
    let x = mathMax(layout.x, coordSysClipArea.x)
    let x2 = mathMin(layout.x + layout.width, coordSysX2)
    let y = mathMax(layout.y, coordSysClipArea.y)
    let y2 = mathMin(layout.y + layout.height, coordSysY2)

    let xClipped = x2 < x
    let yClipped = y2 < y

    // When xClipped or yClipped, the element will be marked as `ignore`.
    // But we should also place the element at the edge of the coord sys bounding rect.
    // Because if data changed and the bar shows again, its transition animation
    // will begin at this place.
    layout.x = (xClipped && x > coordSysX2) ? x2 : x
    layout.y = (yClipped && y > coordSysY2) ? y2 : y
    layout.width = xClipped ? 0 : x2 - x
    layout.height = yClipped ? 0 : y2 - y

    // Reverse back
    if signWidth < 0 {
        layout.x += layout.width
        layout.width = -layout.width
    }
    if signHeight < 0 {
        layout.y += layout.height
        layout.height = -layout.height
    }

    return xClipped || yClipped
}
// PORT-NOTE (deferred): `clip.polar` (polar clip path).

// ================================================================================================
// upstream: `interface ElementCreator` + `const elementCreator: { [key in 'polar' | 'cartesian2d'] }`.
//   Only the cartesian2d entry is ported (polar deferred → free function; see the `clip` note).
// ================================================================================================
func elementCreatorCartesian2D(
    _ seriesModel: BarSeriesModel, _ data: SeriesData, _ newIndex: Int,
    _ layout: RectLayout, _ isHorizontal: Bool,
    _ animationModel: BarSeriesModel?,
    _ axisModel: AxisBaseModel?,
    _ isUpdate: Bool,
    _ roundCap: Bool
) -> BarPossiblePath {
    // upstream: new Rect({ shape: extend({}, layout), z2: 1 })  (RectShape is a value type → copy is implicit)
    let rect = Rect(["shape": layout as PathShape, "z2": Double(1)])
    // upstream: (rect as any).__dataIndex = newIndex;
    // PORT-NOTE (deferred): dynamic `__dataIndex` prop (used by large-mode hit-testing) has no Swift slot;
    //   only needed by the deferred large-draw path.
    _ = newIndex

    rect.name = "item"

    if animationModel != nil {
        var rectShape = rect.shape as! RectShape
        // const animateProperty = isHorizontal ? 'height' : 'width';  rectShape[animateProperty] = 0;
        if isHorizontal {
            rectShape.height = 0
        }
        else {
            rectShape.width = 0
        }
        rect.shape = rectShape
    }
    return rect
}
// PORT-NOTE: `elementCreator.polar` (Sector / Sausage, sector text position) deferred in this cartesian-only bar view (coord/polar itself is ported).

func shouldRealtimeSort(
    _ seriesModel: BarSeriesModel,
    _ coordSys: Cartesian2D
) -> RealtimeSortConfig? {
    let realtimeSortOption = (seriesModel.get("realtimeSort", true) as? Bool) ?? false
    let baseAxis = coordSys.getBaseAxis()
    if __DEV__ {
        if realtimeSortOption {
            if baseAxis.type != "category" {
                log.warn("`realtimeSort` will not work because this bar series is not based on a category axis.")
            }
            if coordSys.type != "cartesian2d" {
                log.warn("`realtimeSort` will not work because this bar series is not on cartesian2d.")
            }
        }
    }
    if realtimeSortOption && baseAxis.type == "category" && coordSys.type == "cartesian2d" {
        return RealtimeSortConfig(
            baseAxis: baseAxis,
            otherAxis: coordSys.getOtherAxis(baseAxis)
        )
    }
    return nil
}

func updateRealtimeAnimation(
    _ realtimeSortCfg: RealtimeSortConfig,
    _ seriesAnimationModel: BarSeriesModel?,
    _ el: Path,
    _ layout: RectLayout,
    _ newIndex: Int,
    _ isHorizontal: Bool,
    _ isUpdate: Bool,
    _ isChangeOrder: Bool
) {
    // upstream splits the layout into an axis-driven target and a series-driven (growth) target and
    // animates them with different animation models. With the no-animation shims both collapse to
    // setting the final shape once — so this is equivalent to `el.setShape(layout)`.
    // PORT-NOTE (deferred): realtimeSort split-target animation (see the realtimeSort block comment).
    _ = (realtimeSortCfg, seriesAnimationModel, newIndex, isHorizontal, isUpdate, isChangeOrder)
    if !isChangeOrder {
        _ = el.setShape(layout)
    }
}

// upstream: function checkPropertiesNotValid<T>(obj: T, props: readonly (keyof T)[]) { ... }
//   Specialized to the cartesian rect layout (the only ported variant).
private func checkPropertiesNotValidCartesian2D(_ layout: RectLayout) -> Bool {
    // upstream: for each prop, if (!isFinite(obj[prop])) return true;
    let props = [layout.x, layout.y, layout.width, layout.height]  // rectPropties: ['x','y','width','height']
    for v in props {
        if !v.isFinite {
            return true
        }
    }
    return false
}

// upstream:
//   const rectPropties = ['x', 'y', 'width', 'height'] as const;
//   const polarPropties = ['cx', 'cy', 'r', 'startAngle', 'endAngle'] as const;  // PORT-NOTE: polar bars deferred in this view.
//   const isValidLayout: Record<'cartesian2d' | 'polar', (layout) => boolean> = { ... }
func isValidLayoutCartesian2D(_ layout: RectLayout) -> Bool {
    return !checkPropertiesNotValidCartesian2D(layout)
}

// upstream: `interface GetLayout` + `const getLayout: { [key in 'cartesian2d' | 'polar']: GetLayout }`.
//   Only the cartesian2d entry is ported (polar deferred → free function; see the `clip` note).
//   `data.getItemLayout(dataIndex)` returns the layout bag stored by layout/barGrid.swift
//   (`["x", "y", "width", "height"]`), which is read into a `RectShape`.
// ================================================================================================
// itemModel is only used to get borderWidth, which is not needed
// when calculating bar background layout.
func getLayoutCartesian2D(_ data: SeriesData, _ dataIndex: Int, _ itemModel: Model?) -> RectLayout? {
    guard let raw = data.getItemLayout(dataIndex) as? [String: Any] else {
        return nil
    }
    // upstream reads `layout.x` / `.y` / `.width` / `.height` off the stored bag.
    var layout = RectShape()
    layout.x = (raw["x"] as? Double) ?? Double.nan
    layout.y = (raw["y"] as? Double) ?? Double.nan
    layout.width = (raw["width"] as? Double) ?? Double.nan
    layout.height = (raw["height"] as? Double) ?? Double.nan

    let fixedLineWidth = itemModel != nil ? getLineWidth(itemModel!, layout) : 0

    // fix layout with lineWidth
    let signX: Double = layout.width > 0 ? 1 : -1
    let signY: Double = layout.height > 0 ? 1 : -1
    var out = RectShape()
    out.x = layout.x + signX * fixedLineWidth / 2
    out.y = layout.y + signY * fixedLineWidth / 2
    out.width = layout.width - signX * fixedLineWidth
    out.height = layout.height - signY * fixedLineWidth
    return out
}
// PORT-NOTE: `getLayout.polar` deferred in this cartesian-only bar view (coord/polar itself is ported).

// upstream: function isZeroOnPolar(layout: SectorLayout) { ... }
// PORT-NOTE (deferred): polar `isZeroOnPolar`; cartesian rect layout has no startAngle/endAngle → always false.

// PORT-NOTE (deferred): `createPolarPositionMapping` (polar/label).

func updateStyle(
    _ el: BarPossiblePath,
    _ data: SeriesData,
    _ dataIndex: Int,
    _ itemModel: Model,
    _ layout: RectLayout,
    _ seriesModel: BarSeriesModel,
    _ isHorizontalOrRadial: Bool,
    _ isPolar: Bool,
    _ polarLayout: SectorShape? = nil
) {
    let style = data.getItemVisual(dataIndex, "style")

    if !isPolar {
        // upstream: const borderRadius = itemModel.get(['itemStyle', 'borderRadius']) as ... || 0;
        //   (el as Rect).setShape('r', borderRadius);
        let borderRadius = (itemModel.get(["itemStyle", "borderRadius"]) as? Double) ?? 0
        // POTENTIAL-BUG: `setShape('r', …)` per-key set is a documented no-op in ZRenderKit Path
        //   (Path.setShape(key,value) only marks dirty; only whole-shape setShape mutates). Corner radius
        //   is therefore silently dropped: itemStyle.borderRadius does not round the bar corners. A local
        //   whole-shape read-modify-write here would still be clobbered by the subsequent
        //   setShape(layout)/initProps(layout) that replace the shape wholesale (the layout RectShape
        //   carries no `r`). The real fix belongs in ZRenderKit (per-key setShape) or by threading `r`
        //   into the layout shape. borderRadius also may be `number[]` (only Double read here).
        _ = el.setShape("r", borderRadius)
    }
    else {
        // PORT-NOTE (deferred): polar cornerRadius (getSectorCornerRadius IS ported in sectorHelper.swift,
        //   but the sector cornerRadius set is threaded through the whole-shape write in the diff loop, not
        //   here — none of the ported polar-bar demos set itemStyle.borderRadius).
    }

    // upstream: el.useStyle(style)
    // PORT-NOTE: the item visual 'style' is a `[String: Any]` bag (visual/style.swift); ZRenderKit
    //   `useStyle` takes a typed `PathStyleProps`. `barStyleFromDict` bridges the common paint keys
    //   (this is what colors the bar) and decal. Gradient/pattern fills and lineDash are not bridged yet.
    el.useStyle(barStyleFromDict(style))

    let cursorStyle = itemModel.getShallow("cursor") as? String
    if let cursorStyle = cursorStyle {
        _ = el.attr("cursor", cursorStyle)
    }

    // upstream: label position + setLabelStyle. The label is ATTACHED to the bar `el` as its
    //   `textContent` (setLabelStyle → el.setTextContent + el.textConfig.position); the painter then
    //   renders it automatically. Cartesian-only here (isPolar is always false on this path); the
    //   polar `labelPositionOutside` (endArc/startArc/endAngle/startAngle) and sector text rotation
    //   are deferred with the rest of the polar block.
    //   DEFERRED (matches label/labelStyle.swift): `setLabelValueAnimation` (number roll-up) is not
    //   ported — see the labelStyle file header.
    // `style.fill` is stored by the visual/style stage as EChartsKit `ZRColor` OR a raw `String`
    //   (see `barStyleFromDict`'s `colorString`); bridge both to the `ColorString` inheritColor.
    let styleDict = style as? [String: Any]
    func inheritColorString(_ v: Any?) -> ColorString? {
        if let s = v as? String { return s }
        if let zr = v as? EChartsKit.ZRColor, case let .color(str) = zr { return str }
        return nil
    }
    // upstream:
    //   const labelPositionOutside = isPolar
    //     ? (isHorizontalOrRadial
    //         ? (layout.r >= layout.r0 ? 'endArc' : 'startArc')
    //         : (layout.endAngle >= layout.startAngle ? 'endAngle' : 'startAngle'))
    //     : (isHorizontalOrRadial ? getLabelPositionForHorizontal : getLabelPositionForVertical);
    let labelPositionOutside: String
    if isPolar {
        if let p = polarLayout {
            labelPositionOutside = isHorizontalOrRadial
                ? (p.r >= p.r0 ? "endArc" : "startArc")
                : (p.endAngle >= p.startAngle ? "endAngle" : "startAngle")
        }
        else {
            labelPositionOutside = "top"
        }
    }
    else if let coordSys = seriesModel.coordinateSystem as? Cartesian2D {
        labelPositionOutside = isHorizontalOrRadial
            ? getLabelPositionForHorizontal(layout, coordSys)
            : getLabelPositionForVertical(layout, coordSys)
    }
    else {
        labelPositionOutside = "top"
    }

    let labelStatesModels = labelStyle.getLabelStatesModels(itemModel)
    var labelOpt = SetLabelStyleOpt()
    labelOpt.labelFetcher = seriesModel
    labelOpt.labelDataIndex = Double(dataIndex)
    labelOpt.defaultText = labelHelper.getDefaultLabel(data, Double(dataIndex))
    labelOpt.inheritColor = inheritColorString(styleDict?["fill"])
    labelOpt.defaultOpacity = styleDict?["opacity"] as? Double
    labelOpt.defaultOutsidePosition = labelPositionOutside
    labelStyle.setLabelStyle(el, labelStatesModels, labelOpt)

    // upstream (BarView.ts:1062-1064):
    //   const emphasisModel = itemModel.getModel(['emphasis']);
    //   toggleHoverEmphasis(el, emphasisModel.get('focus'), emphasisModel.get('blurScope'), emphasisModel.get('disabled'));
    //   setStatesStylesFromModel(el, itemModel);
    // Marks each bar `Rect` a highDown dispatcher carrying its emphasis-state itemStyle, so a hover
    // (enterEmphasisWhenMouseOver) restyles it end-to-end.
    let emphasisModel = itemModel.getModel(["emphasis"])
    let focus: InnerFocus? = emphasisModel.get("focus")
    let blurScope = (emphasisModel.get("blurScope") as? String).flatMap { BlurScope(rawValue: $0) }
    let isDisabled = (emphasisModel.get("disabled") as? Bool) ?? false
    states.toggleHoverEmphasis(el, focus, blurScope, isDisabled)
    states.setStatesStylesFromModel(el, itemModel)
    // PORT-NOTE (deferred): upstream's `isZeroOnPolar(layout)` no-fill state fix-up (BarView.ts:1066-1074)
    //   is polar-only.
}

// In case width or height are too small.
func getLineWidth(
    _ itemModel: Model,
    _ rawLayout: RectLayout
) -> Double {
    // Has no border.
    let borderColor = itemModel.get(["itemStyle", "borderColor"]) as? String
    // upstream: if (!borderColor || borderColor === 'none') return 0;
    if borderColor == nil || borderColor!.isEmpty || borderColor == "none" {
        return 0
    }
    let lineWidth = (itemModel.get(["itemStyle", "borderWidth"]) as? Double) ?? 0
    // width or height may be NaN for empty data
    let width = rawLayout.width.isNaN ? Double.greatestFiniteMagnitude : Swift.abs(rawLayout.width)
    let height = rawLayout.height.isNaN ? Double.greatestFiniteMagnitude : Swift.abs(rawLayout.height)
    return Swift.min(lineWidth, width, height)
}

// upstream: class LargePath / interface LargePathProps / function createLarge / largePathUpdateDataIndex /
//   largePathFindDataIndex — the large/progressive draw path.
// PORT-NOTE (deferred): large/progressive draw. It needs `throttle` (util/throttle, not ported),
//   `model.getIncrementalId`, `data.getLayout('largePoints' | 'size' | ...)`, and a raw
//   `CanvasRenderingContext2D.rect` batch — none of which are on the cartesian normal path.

func createBackgroundShape(
    _ isHorizontalOrRadial: Bool,
    _ layout: RectLayout,
    _ coord: CoordSysOfBar
) -> RectShape {
    // upstream branches on isCoordinateSystemType<Cartesian2D>(coord, 'cartesian2d'); polar deferred.
    let rectShape = layout
    let coordLayout = coord.getArea()
    var out = RectShape()
    out.x = isHorizontalOrRadial ? rectShape.x : coordLayout.x
    out.y = isHorizontalOrRadial ? coordLayout.y : rectShape.y
    out.width = isHorizontalOrRadial ? rectShape.width : coordLayout.width
    out.height = isHorizontalOrRadial ? coordLayout.height : rectShape.height
    return out
    // PORT-NOTE (deferred): the `else` (polar Sector) background branch.
}

func createBackgroundEl(
    _ coord: CoordSysOfBar,
    _ isHorizontalOrRadial: Bool,
    _ layout: RectLayout
) -> Rect {
    // upstream: const ElementClz = coord.type === 'polar' ? Sector : Rect;  (cartesian → Rect)
    return Rect([
        "shape": createBackgroundShape(isHorizontalOrRadial, layout, coord) as PathShape,
        "silent": true,
        "z2": Double(0)
    ])
}

func getLabelPositionForHorizontal(_ layout: RectLayout, _ coordSys: CoordSysOfBar) -> String {
    if layout.height == 0 {
        // For zero height, determine position based on axis inverse status
        let valueAxis = coordSys.getOtherAxis(coordSys.getBaseAxis())
        return valueAxis.inverse ? "bottom" : "top"
    }
    return layout.height > 0 ? "bottom" : "top"
}

func getLabelPositionForVertical(_ layout: RectLayout, _ coordSys: CoordSysOfBar) -> String {
    if layout.width == 0 {
        // For zero width, determine position based on axis inverse status
        let valueAxis = coordSys.getOtherAxis(coordSys.getBaseAxis())
        return valueAxis.inverse ? "left" : "right"
    }
    return layout.width >= 0 ? "right" : "left"
}

// PORT-NOTE: `util/graphic`-level `useStyle(dict)` bridge. The item visual 'style' and the background
//   `getItemStyle()` are `[String: Any]` bags; ZRenderKit `Path.useStyle` takes a typed
//   `PathStyleProps`. This maps the common paint keys (and decal) so bars/backgrounds are actually
//   colored. Gradient/pattern fills and lineDash are not bridged yet.
// Coerce a data-store cell to a Double (NaN for non-numeric / null), mirroring scatterToNumber.
func barToNumber(_ v: Any?) -> Double {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let f = v as? Float { return Double(f) }
    if let s = v as? String, let d = Double(s) { return d }
    return Double.nan
}

func barStyleFromDict(_ style: Any?) -> PathStyleProps {
    var s = PathStyleProps()
    guard let d = style as? [String: Any] else { return s }
    // The visual/style stage stores paint colors as EChartsKit `ZRColor` (e.g. the palette color is
    //   `.color("#...")`) OR as a raw `String`. Bridge both to the ZRenderKit `ZRColor.string`. A
    //   gradient fill — expressed either as an EChartsKit `ZRColor.linearGradient/.radialGradient` or
    //   as the plain option dict `{type:'linear'|'radial', ...}` (echarts accepts the object form of
    //   `new echarts.graphic.LinearGradient(...)`) — is bridged to a ZRenderKit `LinearGradient`/
    //   `RadialGradient` (the painter renders both; see CGRenderer.drawGradient). Pattern/other values
    //   still return nil, falling back to the series solid color.
    if let v = zrPaintFromStyleValue(d["fill"]) { s.fill = v }
    if let v = zrPaintFromStyleValue(d["stroke"]) { s.stroke = v }
    // decal: the `visual/decalVisual` stage stores a generated `Pattern` (tiling texture) under the
    //   item/series 'style' visual's `decal` key. Bridge it to `pathStyle.decal` so `Path.update()`
    //   synthesizes the decal element (`_decalEl`) that the renderer paints over the fill.
    if let pat = d["decal"] as? ZRenderKit.Pattern { s.decal = pat }
    if let v = d["opacity"] as? Double { s.opacity = v }
    if let v = d["fillOpacity"] as? Double { s.fillOpacity = v }
    if let v = d["strokeOpacity"] as? Double { s.strokeOpacity = v }
    if let v = d["lineWidth"] as? Double { s.lineWidth = v }
    if let v = d["lineCap"] as? String { s.lineCap = v }
    if let v = d["lineJoin"] as? String { s.lineJoin = v }
    // lineDash: `getLineStyle` maps the option `type` (solid/dashed/dotted) → the style key `lineDash`
    //   (a string preset OR a number[]); without this the dashed/dotted lineStyle was dropped and every
    //   line/border drew solid (e.g. official-line-style's dashed 4px line rendered solid).
    switch d["lineDash"] {
    case let str as String:
        if str == "dashed" { s.lineDash = .dashed }
        else if str == "dotted" { s.lineDash = .dotted }
        else if str == "solid" { s.lineDash = .solid }
    case let arr as [Double]: s.lineDash = .values(arr)
    case let arri as [Int]: s.lineDash = .values(arri.map(Double.init))
    default: break
    }
    if let v = d["lineDashOffset"] as? Double { s.lineDashOffset = v }
    if let v = d["miterLimit"] as? Double { s.miterLimit = v }
    if let v = d["shadowBlur"] as? Double { s.shadowBlur = v }
    if let v = d["shadowColor"] as? String { s.shadowColor = v }
    if let v = d["shadowOffsetX"] as? Double { s.shadowOffsetX = v }
    if let v = d["shadowOffsetY"] as? Double { s.shadowOffsetY = v }
    return s
}

// Bridge an echarts option color value to a ZRenderKit paint color (`ZRenderKit.ZRColor`).
//   - `String` / EChartsKit `ZRColor.color`   -> `.string`
//   - EChartsKit `ZRColor.linearGradient/.radialGradient` (payload is a `ZRenderKit` gradient object)
//     or the plain option dict `{type:'linear'|'radial', x,y,x2,y2|r, colorStops, global}` -> a
//     `ZRenderKit.LinearGradient`/`RadialGradient`.
//   - pattern / unknown -> nil (caller keeps the fallback solid color).
// Module-internal (not `private`): the shared gradient-aware paint bridge reused by every view whose
//   fill/stroke resolution previously accepted solid colors only (line stroke, custom, large scatter,
//   effectScatter, map, geo, candlestick, heatmap, graph edge, sankey node, matrix). See those sites.
func zrPaintFromStyleValue(_ v: Any?) -> ZRenderKit.ZRColor? {
    if let str = v as? String { return .string(str) }

    if let zr = v as? EChartsKit.ZRColor {
        switch zr {
        case .color(let s):
            return .string(s)
        case .linearGradient(let g):
            let lg = (g as? ZRenderKit.LinearGradient)
                ?? ZRenderKit.LinearGradient(g.x, g.y, g.x2, g.y2, g.colorStops, g.global)
            return .linearGradient(lg)
        case .radialGradient(let g):
            let rg = (g as? ZRenderKit.RadialGradient)
                ?? ZRenderKit.RadialGradient(g.x, g.y, g.r, g.colorStops, g.global)
            return .radialGradient(rg)
        case .pattern:
            return nil
        }
    }

    if let dict = v as? [String: Any], let type = dict["type"] as? String {
        let stops = gradientColorStopsFromAny(dict["colorStops"])
        let global = dict["global"] as? Bool
        if type == "linear" {
            return .linearGradient(ZRenderKit.LinearGradient(
                styleNum(dict["x"]), styleNum(dict["y"]), styleNum(dict["x2"]), styleNum(dict["y2"]),
                stops, global))
        } else if type == "radial" {
            return .radialGradient(ZRenderKit.RadialGradient(
                styleNum(dict["x"]), styleNum(dict["y"]), styleNum(dict["r"]),
                stops, global))
        }
    }

    return nil
}

// Parse `colorStops: [{offset, color}, ...]` (the option-dict gradient form) into ZRenderKit stops.
private func gradientColorStopsFromAny(_ v: Any?) -> [ZRenderKit.GradientColorStop] {
    guard let arr = v as? [Any] else { return [] }
    var out: [ZRenderKit.GradientColorStop] = []
    for item in arr {
        guard let d = item as? [String: Any] else { continue }
        let offset = styleNum(d["offset"]) ?? 0
        let color = (d["color"] as? String) ?? ""
        out.append(ZRenderKit.GradientColorStop(offset: offset, color: color))
    }
    return out
}

// JS-number coercion for a gradient coord/offset option value (Double | Int | NSNumber | numeric String).
private func styleNum(_ v: Any?) -> Double? {
    switch v {
    case let d as Double: return d
    case let i as Int: return Double(i)
    case let n as NSNumber: return n.doubleValue
    case let s as String: return Double(s.trimmingCharacters(in: .whitespacesAndNewlines))
    default: return nil
    }
}

// export default BarView;  -> `open class BarView` above.

// ================================================================================================
// upstream: the `polar` entries of `elementCreator` / `isValidLayout` / `getLayout` + the polar
//   `updateStyle` branch (BarView.ts). This is a faithful port of the polar Sector path, restricted
//   to RADIAL bars (baseAxis.dim === 'angle': a category angle axis + value radius axis — the
//   canonical bar-on-polar and the gallery `bar-polar-radial` demo).
//
// PORT-NOTE (deferred, matching the rest of the polar block):
//   * requires layout/barPolar (not ported), so the Sector layout (band width / bar offset / stacking)
//     is reproduced inline from the axes for the single-series default rather than read back from
//     `data.getItemLayout`. Multi-series bar-width sharing & stacking on polar are deferred.
//   * TANGENTIAL bars (baseAxis.dim === 'radius') are deferred — `_renderPolarBars` returns early.
//   * roundCap → requires util/shape/sausage (Sausage, not ported); roundCap is ignored (always a Sector).
//   * getSectorCornerRadius / sector text rotation / sector label position are deferred (see the
//     `updateStyle` polar PORT-NOTEs).
// ================================================================================================

// upstream (BarView.ts `polarPropties`): ['cx','cy','r','startAngle','endAngle'].
func isValidLayoutPolar(_ layout: SectorShape) -> Bool {
    for v in [layout.cx, layout.cy, layout.r, layout.startAngle, layout.endAngle] {
        if !v.isFinite { return false }
    }
    return true
}

// Partial dict of the animatable Sector fields (mirrors `rectShapeAnimShape`; see that note — a typed
//   struct is opaque to `animateToShallow`, so per-field tweens need a `[String: Any]`).
func sectorShapeAnimShape(_ s: SectorShape) -> [String: Any] {
    ["cx": s.cx, "cy": s.cy, "r0": s.r0, "r": s.r, "startAngle": s.startAngle, "endAngle": s.endAngle]
}

// upstream: `elementCreator.polar` (Sector / Sausage path). Sausage is not ported → always a Sector.
func elementCreatorPolar(
    _ seriesModel: BarSeriesModel,
    _ newIndex: Int,
    _ layout: SectorShape,
    _ isRadial: Bool,
    _ animationModel: BarSeriesModel?,
    _ isUpdate: Bool,
    _ roundCap: Bool
) -> BarPossiblePath {
    // upstream: const ShapeClass = (!isRadial && roundCap) ? Sausage : Sector;  (Sausage not ported)
    let sector = Sector(["shape": layout as PathShape, "z2": Double(1)])
    sector.name = "item"
    _ = (newIndex, isUpdate, roundCap)

    // Animation: collapse the bar at its baseline so the entrance grows it open — radial bars grow
    //   `r` from `r0`, tangential bars sweep `endAngle` from `startAngle` (upstream elementCreator.polar).
    if animationModel != nil {
        var s = sector.shape as! SectorShape
        if isRadial {
            s.r = layout.r0
        }
        else {
            s.endAngle = layout.startAngle
        }
        sector.shape = s
    }
    return sector
}

// upstream: `getLayout.polar` — reads back the SectorShape stored by `layout/barPolar.swift`
//   (`data.setItemLayout(idx, {cx, cy, r0, r, startAngle, endAngle, clockwise})`). Mirrors
//   `getLayoutCartesian2D`. Returns nil when the item has no layout (e.g. filtered/NaN data).
func getLayoutPolar(_ data: SeriesData, _ dataIndex: Int) -> SectorShape? {
    guard let raw = data.getItemLayout(dataIndex) as? [String: Any] else {
        return nil
    }
    var s = SectorShape()
    s.cx = (raw["cx"] as? Double) ?? Double.nan
    s.cy = (raw["cy"] as? Double) ?? Double.nan
    s.r0 = (raw["r0"] as? Double) ?? Double.nan
    s.r = (raw["r"] as? Double) ?? Double.nan
    s.startAngle = (raw["startAngle"] as? Double) ?? Double.nan
    s.endAngle = (raw["endAngle"] as? Double) ?? Double.nan
    s.clockwise = (raw["clockwise"] as? Bool) ?? true
    return s
}

extension BarView {
    // Faithful polar-bar render — mirrors the cartesian `_renderNormal` diff loop, but emits a
    // `Sector` per datum. The per-item Sector geometry (r0/r/startAngle/endAngle/clockwise, including
    // bar width/offset sharing across series + stacking) is computed by the `layout/barPolar.swift`
    // stage handler and read back here via `getLayoutPolar` (exactly as the cartesian path reads
    // `getLayoutCartesian2D`). Handles BOTH radial (angle base) and tangential (radius base) bars.
    // Each Sector is named "item", styled via the shared `updateStyle` (item color + label + emphasis:
    // toggleHoverEmphasis + setStatesStylesFromModel), grown open on entry, and registered with the
    // data store so hover/highlight/remove animations reach it end-to-end.
    //   PORT-NOTE (deferred, matching the rest of the polar block): roundCap → `Sausage` (rounded caps)
    //     is not ported, so a plain `Sector` (square caps) is used for both branches (same convention as
    //     GaugeView); showBackground (polar Sector background) and the sector label rotation subsystem
    //     (setSectorTextRotation / createSectorCalculateTextPosition) are deferred.
    func _renderPolarBars(_ seriesModel: BarSeriesModel, _ polar: Polar, _ group: Group) {
        let data = seriesModel.getData()
        let oldData = self._data
        let baseAxis = polar.getBaseAxis()
        // upstream: coord.type === 'polar' → isHorizontalOrRadial = baseAxis.dim === 'angle'.
        let isHorizontalOrRadial = baseAxis.dim == "angle"

        let animationModel: BarSeriesModel? = (seriesModel.isAnimationEnabled() ?? false) ? seriesModel : nil
        let roundCap = (seriesModel.get("roundCap", true) as? Bool) ?? false  // Sausage not ported → Sector

        data.diff(oldData)
            .add({ dataIndex in
                let itemModel = data.getItemModel(dataIndex)
                guard let layout = getLayoutPolar(data, dataIndex) else { return }
                if !data.hasValue(dataIndex) || !isValidLayoutPolar(layout) { return }

                let el = elementCreatorPolar(
                    seriesModel, dataIndex, layout, isHorizontalOrRadial,
                    animationModel, false, roundCap
                )
                // Shared styling: item color + label + emphasis (isPolar = true).
                updateStyle(
                    el, data, dataIndex, itemModel, RectShape(),
                    seriesModel, isHorizontalOrRadial, true, layout
                )
                initProps(el, ["shape": sectorShapeAnimShape(layout)], seriesModel, dataIndex)

                data.setItemGraphicEl(dataIndex, el)
                _ = group.add(el)
            })
            .update({ newIndex, oldIndex in
                let itemModel = data.getItemModel(newIndex)
                var el = oldData?.getItemGraphicEl(oldIndex) as? BarPossiblePath
                guard let layout = getLayoutPolar(data, newIndex) else {
                    if let el = el { _ = group.remove(el) }
                    return
                }
                if !data.hasValue(newIndex) || !isValidLayoutPolar(layout) {
                    if let el = el { _ = group.remove(el) }
                    return
                }

                // upstream: recreate on roundCap change (sector<->sausage). Sausage not ported → the
                //   element type is always 'sector', so this never fires (kept for provenance).
                if el == nil {
                    el = elementCreatorPolar(
                        seriesModel, newIndex, layout, isHorizontalOrRadial,
                        animationModel, true, roundCap
                    )
                }
                else {
                    saveOldStyle(el!)
                }

                updateStyle(
                    el!, data, newIndex, itemModel, RectShape(),
                    seriesModel, isHorizontalOrRadial, true, layout
                )
                updateProps(el!, ["shape": sectorShapeAnimShape(layout)], seriesModel, newIndex)

                data.setItemGraphicEl(newIndex, el!)
                _ = group.add(el!)
            })
            .remove({ dataIndex in
                let el = oldData?.getItemGraphicEl(dataIndex) as? Path
                if let el = el { removeElementWithFadeOut(el, seriesModel, dataIndex) }
            })
            .execute()

        self._data = data
    }
}
