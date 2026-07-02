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
//   import {SectorProps} from 'zrender/src/graphic/shape/Sector';    -> PORT-TODO: polar Sector deferred.
//   import {RectProps} from 'zrender/src/graphic/shape/Rect';        -> ZRenderKit `RectProps`.
//   import { Rect, Sector, updateProps, initProps, removeElementWithFadeOut, traverseElements }
//       from '../../util/graphic';
//     -> `Rect` is the ZRenderKit shape (graphic re-exports it). `Sector` (polar) is deferred.
//        PORT-TODO: `util/graphic` is NOT ported yet; `updateProps` / `initProps` (== re-exports of
//        `animation/basicTransition`), `removeElementWithFadeOut`, and `traverseElements` are
//        reproduced by the local no-animation shims below (`initProps`/`updateProps`/
//        `removeElementWithFadeOut`) and `Group.traverse` — same deviation as
//        chart/helper/createClipPathFromCoordSys.swift.
//   import { getECData } from '../../util/innerStore';               -> `innerStore.getECData`.
//   import { setStatesStylesFromModel, toggleHoverEmphasis } from '../../util/states';
//     -> PORT-TODO: `util/states` NOT ported (states/emphasis prerequisite); the states block in
//        `updateStyle` is deferred.
//   import { setLabelStyle, getLabelStatesModels, setLabelValueAnimation, labelInner }
//       from '../../label/labelStyle';
//     -> PORT-TODO: `label/labelStyle` NOT ported; the label block in `updateStyle` is deferred.
//   import {throttle} from '../../util/throttle';                    -> PORT-TODO: NOT ported (large mode only).
//   import {createClipPath} from '../helper/createClipPathFromCoordSys';  -> sibling `createClipPath`.
//   import Sausage from '../../util/shape/sausage';                  -> PORT-TODO: NOT ported (polar roundCap only).
//   import ChartView from '../../view/Chart';                        -> `ChartView` (view/Chart.swift).
//   import SeriesData, {DefaultDataVisual} from '../../data/SeriesData';  -> `SeriesData`.
//   import GlobalModel from '../../model/Global';                    -> `GlobalModel`.
//   import ExtensionAPI from '../../core/ExtensionAPI';              -> `ExtensionAPI`.
//   import { StageHandlerProgressParams, ZRElementEvent, ColorString, OrdinalSortInfo, Payload,
//            OrdinalNumber, ParsedValue, ECElement } from '../../util/types';  -> util/types.swift.
//   import BarSeriesModel, {BarDataItemOption, PolarBarLabelPosition} from './BarSeries';  -> `BarSeriesModel`.
//   import type Axis2D from '../../coord/cartesian/Axis2D';          -> `Axis2D`.
//   import type Cartesian2D from '../../coord/cartesian/Cartesian2D'; -> `Cartesian2D`.
//   import type Polar from '../../coord/polar/Polar';                -> PORT-TODO: coord/polar NOT ported.
//   import type Model from '../../model/Model';                      -> `Model`.
//   import { isCoordinateSystemType } from '../../coord/CoordinateSystem';  -> coord/CoordinateSystem.swift.
//   import { getDefaultLabel, getDefaultInterpolatedLabel } from '../helper/labelHelper';
//     -> PORT-TODO: `chart/helper/labelHelper` NOT ported (label block deferred).
//   import OrdinalScale from '../../scale/Ordinal';                  -> scale/Ordinal.swift (realtimeSort only).
//   import SeriesModel from '../../model/Series';                    -> `SeriesModel`.
//   import {AngleAxisModel, RadiusAxisModel} from '../../coord/polar/AxisModel';  -> PORT-TODO: polar deferred.
//   import CartesianAxisModel from '../../coord/cartesian/AxisModel'; -> coord/cartesian/AxisModel.swift.
//   import {LayoutRect} from '../../util/layout';                    -> util/layout.swift.
//   import {EventCallback} from 'zrender/src/core/Eventful';         -> `EventCallback` (ZRenderKit).
//   import { warn } from '../../util/log';                           -> `log.warn`.
//   import {createSectorCalculateTextPosition, SectorTextPosition, setSectorTextRotation}
//       from '../../label/sectorLabel';                              -> PORT-TODO: polar/label deferred.
//   import { saveOldStyle } from '../../animation/basicTransition';  -> PORT-TODO: NOT ported (local no-op shim).
//   import Element from 'zrender/src/Element';                       -> `Element` (ZRenderKit).
//   import { getSectorCornerRadius } from '../helper/sectorHelper';  -> PORT-TODO: polar deferred.
//   import { getIncrementalId } from '../../util/model';             -> `model.getIncrementalId` (large mode only).
//   import { SERIES_TYPE_BAR } from '../../layout/barCommon';        -> `SERIES_TYPE_BAR`.

// upstream: const mathMax = Math.max; const mathMin = Math.min;
//   Typed `Double` wrappers (a bare `let mathMax = Swift.max` cannot infer the generic parameter).
private func mathMax(_ a: Double, _ b: Double) -> Double { Swift.max(a, b) }
private func mathMin(_ a: Double, _ b: Double) -> Double { Swift.min(a, b) }

// upstream:
//   type CoordSysOfBar = BarSeriesModel['coordinateSystem'];   // Cartesian2D | Polar
//   type RectShape = Rect['shape'];                            // == ZRenderKit RectShape
//   type SectorShape = Sector['shape'];                        // PORT-TODO: polar deferred
//   type SectorLayout = SectorShape;                           // PORT-TODO: polar deferred
//   type RectLayout = RectShape;
// PORT-TODO: `Polar` and `Sector` are not ported; the bar milestone is cartesian-only, so
//   `CoordSysOfBar` collapses to `Cartesian2D` and `RectLayout` to the ZRenderKit `RectShape`.
typealias CoordSysOfBar = Cartesian2D
typealias RectLayout = RectShape

// upstream: type BarPossiblePath = Sector | Rect | Sausage;
//   Cartesian-only → the element is always a `Rect`; the common supertype used at call sites is `Path`.
typealias BarPossiblePath = Path

// upstream:
//   type CartesianCoordArea = ReturnType<Cartesian2D['getArea']>;   // == Cartesian2DArea (BoundingRect)
//   type PolarCoordArea = ReturnType<Polar['getArea']>;             // PORT-TODO: polar deferred
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
    // PORT-TODO: realtimeSort uses `api.getZr().on('rendered', cb)`; ExtensionAPI has no `getZr`/event
    //   plumbing here yet. Kept as a closure slot; realtimeSort is deferred (see `_enableRealtimeSort`).
    private var _onRendered: (() -> Void)?

    private var _backgroundGroup: Group?

    // upstream: private _backgroundEls: (Rect | Sector)[];
    // PORT-TODO: upstream is a sparse array indexed by dataIndex; modeled as `[Int: Rect]` (cartesian,
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
        // PORT-TODO: `util/graphic.traverseElements` not ported. When `_progressiveEls` exists, traverse
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
        // PORT-TODO: polar bar is deferred (coord/polar not ported). Only `cartesian2d` is handled;
        //   a non-cartesian coordinate system short-circuits (the `polar` branch of `render` above
        //   still routes here, but there is no polar coordinate system to downcast to yet).
        guard let coord = seriesModel.coordinateSystem as? Cartesian2D else {
            // PORT-TODO: polar `_renderNormal` deferred.
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
                    // PORT-TODO: ECElement.forceLabelAnimation (label animation) deferred with the label block.
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
                    initProps(el, ["shape": layout as PathShape], seriesModel, dataIndex)
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
                        updateProps(bgEl, ["shape": shape as PathShape], animationModel, newIndex)
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
                // (sector/sausage) recreate path is deferred (PORT-TODO). Read `el.type` at runtime to
                // mirror upstream faithfully rather than hard-coding `false` (which is dead code).
                let elType = el?.type
                let roundCapChanged = elType != nil
                    && ((elType == "sector" && roundCap) || (elType == "sausage" && !roundCap))
                if roundCapChanged {
                    // roundCap changed (polar only): remove old and recreate. PORT-TODO (polar deferred).
                    if let el = el { removeElementWithFadeOut(el, seriesModel, oldIndex, group) }
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
                    // (el as ECElement).forceLabelAnimation = true;  // PORT-TODO (label block deferred).
                }

                if isChangeOrder {
                    // upstream reuses the previous label's prevValue to skip a new label animation.
                    // PORT-TODO: label subsystem (labelInner / getTextContent label store) deferred.
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
                    updateProps(el!, ["shape": layout as PathShape], seriesModel, newIndex)
                }

                data.setItemGraphicEl(newIndex, el!)
                el!.ignore = isClipped
                _ = group.add(el!)
            })
            .remove({ dataIndex in
                let el = oldData?.getItemGraphicEl(dataIndex) as? Path
                if let el = el { removeElementWithFadeOut(el, seriesModel, dataIndex, group) }
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
        // PORT-TODO: large/progressive draw (LargePath, data.getLayout('largePoints'), throttle) is
        //   deferred per the bar milestone scope. Only the clip is updated.
        self._updateLargeClip(seriesModel)
    }

    private func _incrementalRenderLarge(_ params: StageHandlerProgressParams, _ seriesModel: BarSeriesModel) {
        self._removeBackground()
        // upstream: createLarge(seriesModel, this.group, this._progressiveEls, true);
        // PORT-TODO: large/progressive draw deferred (see `_renderLarge`).
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
    // realtimeSort — PORT-TODO (deferred per the bar milestone scope).
    //   The methods below need `api.getZr().on('rendered', …)` + `api.dispatchAction(…)` (ExtensionAPI
    //   has no event/dispatch plumbing yet) and OrdinalScale sort helpers. `shouldRealtimeSort` returns
    //   nil for the default (realtimeSort: false) path, so these are unreachable in the common case.
    //   Faithful signatures are preserved for a later mechanical port.
    // ------------------------------------------------------------------------------------------

    private func _enableRealtimeSort(
        _ realtimeSortCfg: RealtimeSortConfig,
        _ data: SeriesData,
        _ api: ExtensionAPI
    ) {
        // PORT-TODO: realtimeSort deferred (see the block comment above). Upstream body:
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
        // PORT-TODO: realtimeSort deferred (see the block comment above).
        _ = (data, baseAxis, orderMapping)
        return OrdinalSortInfo(ordinalNumbers: [])
    }

    private func _updateSortWithinSameData(
        _ data: SeriesData,
        _ orderMapping: OrderMapping,
        _ baseAxis: Axis2D,
        _ api: ExtensionAPI
    ) {
        // PORT-TODO: realtimeSort deferred (see the block comment above).
        _ = (data, orderMapping, baseAxis, api)
    }

    private func _dispatchInitSort(
        _ data: SeriesData,
        _ realtimeSortCfg: RealtimeSortConfig,
        _ api: ExtensionAPI
    ) {
        // PORT-TODO: realtimeSort deferred (see the block comment above).
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
            // PORT-TODO: ExtensionAPI has no `getZr`/event plumbing yet (realtimeSort deferred).
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
                    removeElementWithFadeOut(el, model, dataIndex.map { Int($0) } ?? -1, group)
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
// PORT-TODO: animation/basicTransition shims — `util/graphic` (which re-exports `initProps` /
//   `updateProps` from `animation/basicTransition`) and `basicTransition` itself are not ported.
//   These reproduce the NO-ANIMATION branch faithfully (matching `animateOrSetProps`'s `else`:
//   `el.attr(props); during && during(1); cb && cb();`) — the element is set to its final shape
//   immediately, then `during(1)`/`done()` fire once. The wipe/grow transition is skipped (final
//   geometry is correct). Restore the real calls once `util/graphic` + `basicTransition` land.
//   Same deviation as chart/helper/createClipPathFromCoordSys.swift.
// ================================================================================================
private func initProps(
    _ el: Path, _ props: [String: Any], _ animatableModel: Any? = nil,
    _ dataIndex: Int? = nil, _ cb: (() -> Void)? = nil, _ during: ((Double) -> Void)? = nil
) {
    if let shape = props["shape"] as? PathShape {
        _ = el.setShape(shape)
    }
    during?(1)
    cb?()
}

private func updateProps(
    _ el: Path, _ props: [String: Any], _ animatableModel: Any? = nil,
    _ dataIndex: Int? = nil, _ cb: (() -> Void)? = nil, _ during: ((Double) -> Void)? = nil
) {
    if let shape = props["shape"] as? PathShape {
        _ = el.setShape(shape)
    }
    during?(1)
    cb?()
}

// PORT-TODO: `animation/basicTransition.saveOldStyle` not ported; upstream saves the current style
//   onto the element for the next transition. No-op until basicTransition lands.
private func saveOldStyle(_ el: Element) {
    _ = el
}

// PORT-TODO: `util/graphic.removeElementWithFadeOut` not ported; upstream fades the element out then
//   removes it from its parent. Reproduce the terminal effect (immediate removal from `group`).
private func removeElementWithFadeOut(_ el: Element, _ seriesModel: SeriesModel, _ dataIndex: Int, _ group: Group) {
    _ = (seriesModel, dataIndex)
    _ = group.remove(el)
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
// PORT-TODO: `clip.polar` deferred (polar not ported).

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
    // PORT-TODO: dynamic `__dataIndex` prop (used by large-mode hit-testing) has no Swift slot; deferred.
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
// PORT-TODO: `elementCreator.polar` (Sector / Sausage, sector text position) deferred (polar not ported).

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
    // PORT-TODO: realtimeSort split-target animation deferred (see the realtimeSort block comment).
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
//   const polarPropties = ['cx', 'cy', 'r', 'startAngle', 'endAngle'] as const;  // PORT-TODO: polar deferred.
//   const isValidLayout: Record<'cartesian2d' | 'polar', (layout) => boolean> = { ... }
func isValidLayoutCartesian2D(_ layout: RectLayout) -> Bool {
    return !checkPropertiesNotValidCartesian2D(layout)
}

// ================================================================================================
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
// PORT-TODO: `getLayout.polar` deferred (polar not ported).

// upstream: function isZeroOnPolar(layout: SectorLayout) { ... }
// PORT-TODO: polar deferred; cartesian rect layout has no startAngle/endAngle → always false.

// PORT-TODO: `createPolarPositionMapping` deferred (polar/label not ported).

func updateStyle(
    _ el: BarPossiblePath,
    _ data: SeriesData,
    _ dataIndex: Int,
    _ itemModel: Model,
    _ layout: RectLayout,
    _ seriesModel: BarSeriesModel,
    _ isHorizontalOrRadial: Bool,
    _ isPolar: Bool
) {
    let style = data.getItemVisual(dataIndex, "style")

    if !isPolar {
        // upstream: const borderRadius = itemModel.get(['itemStyle', 'borderRadius']) as ... || 0;
        //   (el as Rect).setShape('r', borderRadius);
        let borderRadius = (itemModel.get(["itemStyle", "borderRadius"]) as? Double) ?? 0
        // PORT-TODO: `setShape('r', …)` per-key set on a typed shape struct is a documented no-op in
        //   Path (only whole-shape setShape). Corner radius therefore not applied yet.
        _ = el.setShape("r", borderRadius)
    }
    else {
        // PORT-TODO: polar cornerRadius (getSectorCornerRadius) deferred.
    }

    // upstream: el.useStyle(style)
    // PORT-TODO: the item visual 'style' is a `[String: Any]` bag (visual/style.swift); ZRenderKit
    //   `useStyle` takes a typed `PathStyleProps`. `barStyleFromDict` bridges the common keys (this is
    //   what colors the bar). Gradient/pattern fills, decal, and lineDash are not bridged yet.
    el.useStyle(barStyleFromDict(style))

    let cursorStyle = itemModel.getShallow("cursor") as? String
    if let cursorStyle = cursorStyle {
        _ = el.attr("cursor", cursorStyle)
    }

    // upstream: label position + setLabelStyle + label value animation + emphasis/blur + statesStyles.
    // PORT-TODO: the label + states blocks are deferred — `label/labelStyle` (setLabelStyle,
    //   getLabelStatesModels, setLabelValueAnimation), `chart/helper/labelHelper` (getDefaultLabel,
    //   getDefaultInterpolatedLabel), and `util/states` (toggleHoverEmphasis, setStatesStylesFromModel)
    //   are not ported. The `getLabelPositionForHorizontal`/`getLabelPositionForVertical` helpers below
    //   are ported for the eventual label block. `isZeroOnPolar` no-fill fix is polar-only (deferred).
    _ = isHorizontalOrRadial
    _ = seriesModel
    _ = layout
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
// PORT-TODO: large/progressive draw deferred per the bar milestone scope. It needs `throttle`,
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
    // PORT-TODO: the `else` (polar Sector) branch is deferred (polar not ported).
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

// PORT-TODO: `util/graphic`-level `useStyle(dict)` bridge. The item visual 'style' and the background
//   `getItemStyle()` are `[String: Any]` bags; ZRenderKit `Path.useStyle` takes a typed
//   `PathStyleProps`. This maps the common paint keys so bars/backgrounds are actually colored.
//   Gradient/pattern fills, decal, and lineDash are not bridged yet.
func barStyleFromDict(_ style: Any?) -> PathStyleProps {
    var s = PathStyleProps()
    guard let d = style as? [String: Any] else { return s }
    // The visual/style stage stores paint colors as EChartsKit `ZRColor` (e.g. the palette color is
    //   `.color("#...")`) OR as a raw `String`. Bridge both to the ZRenderKit `ZRColor.string` (only
    //   solid colors are bridged; gradient/pattern are out of the bar-render scope).
    func colorString(_ v: Any?) -> String? {
        if let str = v as? String { return str }
        if let zr = v as? EChartsKit.ZRColor, case let .color(str) = zr { return str }
        return nil
    }
    if let v = colorString(d["fill"]) { s.fill = .string(v) }
    if let v = colorString(d["stroke"]) { s.stroke = .string(v) }
    if let v = d["opacity"] as? Double { s.opacity = v }
    if let v = d["fillOpacity"] as? Double { s.fillOpacity = v }
    if let v = d["strokeOpacity"] as? Double { s.strokeOpacity = v }
    if let v = d["lineWidth"] as? Double { s.lineWidth = v }
    if let v = d["lineCap"] as? String { s.lineCap = v }
    if let v = d["lineJoin"] as? String { s.lineJoin = v }
    if let v = d["miterLimit"] as? Double { s.miterLimit = v }
    if let v = d["shadowBlur"] as? Double { s.shadowBlur = v }
    if let v = d["shadowColor"] as? String { s.shadowColor = v }
    if let v = d["shadowOffsetX"] as? Double { s.shadowOffsetX = v }
    if let v = d["shadowOffsetY"] as? Double { s.shadowOffsetY = v }
    return s
}

// export default BarView;  -> `open class BarView` above.
