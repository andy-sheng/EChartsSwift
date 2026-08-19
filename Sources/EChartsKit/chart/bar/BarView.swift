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
//   import {SectorProps} from 'zrender/src/graphic/shape/Sector';    -> PORT-NOTE: ZRenderKit `Sector` is ported; the polar Sector branch lives in the polar block at the bottom of this file.
//   import {RectProps} from 'zrender/src/graphic/shape/Rect';        -> ZRenderKit `RectProps`.
//   import { Rect, Sector, updateProps, initProps, removeElementWithFadeOut, traverseElements }
//       from '../../util/graphic';
//     -> `Rect` is the ZRenderKit shape (graphic re-exports it). `Sector` (polar) is used by
//        `elementCreatorPolar` in the polar block at the bottom of this file.
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
//   import {throttle} from '../../util/throttle';                    -> `throttleUtil.throttle` (util/throttle.swift),
//     used by `largePathUpdateDataIndex` in LargeBarPath.swift (large mode only).
//   import {createClipPath} from '../helper/createClipPathFromCoordSys';  -> sibling `createClipPath`.
//   import Sausage from '../../util/shape/sausage';                  -> `SausagePath` (chart/gauge/Sausage.swift; location deviation documented there). Used by the polar roundCap branch of `elementCreatorPolar`.
//   import ChartView from '../../view/Chart';                        -> `ChartView` (view/Chart.swift).
//   import SeriesData, {DefaultDataVisual} from '../../data/SeriesData';  -> `SeriesData`.
//   import GlobalModel from '../../model/Global';                    -> `GlobalModel`.
//   import ExtensionAPI from '../../core/ExtensionAPI';              -> `ExtensionAPI`.
//   import { StageHandlerProgressParams, ZRElementEvent, ColorString, OrdinalSortInfo, Payload,
//            OrdinalNumber, ParsedValue, ECElement } from '../../util/types';  -> util/types.swift.
//   import BarSeriesModel, {BarDataItemOption, PolarBarLabelPosition} from './BarSeries';  -> `BarSeriesModel`.
//   import type Axis2D from '../../coord/cartesian/Axis2D';          -> `Axis2D`.
//   import type Cartesian2D from '../../coord/cartesian/Cartesian2D'; -> `Cartesian2D`.
//   import type Polar from '../../coord/polar/Polar';                -> PORT-NOTE: coord/polar is ported; polar bars are rendered by `_renderPolarBars`.
//   import type Model from '../../model/Model';                      -> `Model`.
//   import { isCoordinateSystemType } from '../../coord/CoordinateSystem';  -> coord/CoordinateSystem.swift.
//   import { getDefaultLabel, getDefaultInterpolatedLabel } from '../helper/labelHelper';
//     -> PORT-NOTE: `chart/helper/labelHelper` is ported (label block still deferred in this view).
//   import OrdinalScale from '../../scale/Ordinal';                  -> scale/Ordinal.swift (realtimeSort only).
//   import SeriesModel from '../../model/Series';                    -> `SeriesModel`.
//   import {AngleAxisModel, RadiusAxisModel} from '../../coord/polar/AxisModel';  -> PORT-NOTE: ported (coord/polar/PolarAxisModel.swift); used via the polar coordinate system in `_renderPolarBars`.
//   import CartesianAxisModel from '../../coord/cartesian/AxisModel'; -> coord/cartesian/AxisModel.swift.
//   import {LayoutRect} from '../../util/layout';                    -> util/layout.swift.
//   import {EventCallback} from 'zrender/src/core/Eventful';         -> `EventCallback` (ZRenderKit).
//   import { warn } from '../../util/log';                           -> `log.warn`.
//   import {createSectorCalculateTextPosition, SectorTextPosition, setSectorTextRotation}
//       from '../../label/sectorLabel';                              -> PORT-NOTE (deferred): requires label/sectorLabel (not ported; polar/label).
//   import { saveOldStyle } from '../../animation/basicTransition';  -> animation/basicTransition.saveOldStyle (real since universalTransition landed).
//   import Element from 'zrender/src/Element';                       -> `Element` (ZRenderKit).
//   import { getSectorCornerRadius } from '../helper/sectorHelper';  -> `getSectorCornerRadius`
//     (chart/helper/sectorHelper.swift); wired in the `isPolar` branch of `updateStyle`.
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
//   type SectorShape = Sector['shape'];                        // PORT-NOTE: ported; see the polar block at the bottom of this file
//   type SectorLayout = SectorShape;                           // PORT-NOTE: ported; see the polar block at the bottom of this file
//   type RectLayout = RectShape;
// PORT-NOTE: the generic `CoordSysOfBar`/`RectLayout` aliases collapse to the cartesian pair; the polar
//   path is typed concretely (`Polar` + `SectorShape`) in the polar block at the bottom of this file.
typealias CoordSysOfBar = Cartesian2D
typealias RectLayout = RectShape

// upstream: type BarPossiblePath = Sector | Rect | Sausage;
//   The element is a `Rect` (cartesian), a `Sector` (polar) or a `SausagePath` (polar + roundCap);
//   the common supertype used at call sites is `Path`.
typealias BarPossiblePath = Path

// upstream:
//   type CartesianCoordArea = ReturnType<Cartesian2D['getArea']>;   // == Cartesian2DArea (BoundingRect)
//   type PolarCoordArea = ReturnType<Polar['getArea']>;             // PORT-NOTE: Polar ported; the polar bar path does not use getArea() (no polar clip — deferred)
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
    //   The realtimeSort "rendered" listener. `api.getZr()` is now wired (resolves through the root
    //   group's `__zr` back-pointer; nil in pure headless), so this holds the stable registration token
    //   returned by `_enableRealtimeSort` for later removal in `_removeOnRenderedListener`.
    private var _onRenderedToken: EventHandlerToken?

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
        // PORT-NOTE: `util/graphic.traverseElements` is not ported, so the collected elements are visited
        //   WITHOUT descending into their children — harmless today because `_progressiveEls` only ever
        //   holds `LargeBarPath`s, which have no children. `_progressiveEls` is populated by the
        //   progressive `barCreateLarge` overload via `_incrementalRenderLarge` (dormant until the
        //   progressive render-task routing lands — see the note there); otherwise traverse the group via
        //   `Group.traverse` (visits children only — see the same note in view/Chart.swift `eachRendered`).
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
        // Polar bar → `Sector` / `SausagePath` per datum, radial (angle base) and tangential (radius
        //   base) alike; the geometry (band width / bar offset / stacking) comes from the registered
        //   `layout/barPolar.swift` stage and is read back via `getLayoutPolar`.
        // PORT-NOTE (deferred): `showBackground` + sector label rotation/position.
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
            // Whole-shape write (per-key `setShape('r', …)` is a no-op — see `updateStyle`).
            if var bgShape = bgEl.shape as? RectShape {
                bgShape.r = .number(barBorderRadius)
                _ = bgEl.setShape(bgShape)
            }
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
                guard var layout = getLayoutCartesian2D(data, newIndex, itemModel) else {
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
                        // Whole-shape write (per-key `setShape('r', …)` is a no-op — see `updateStyle`).
                        if let bg = bgEl, var bgShape = bg.shape as? RectShape {
                            bgShape.r = .number(barBorderRadius)
                            _ = bg.setShape(bgShape)
                        }
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
                    // upstream (BarView.ts:352): "Clip will modify the layout params" — the clip MUST
                    // mutate the REAL layout, because updateStyle/setShape/updateRealtimeAnimation/
                    // updateProps below all consume it. An earlier version clipped a discarded copy, so
                    // after a dataZoom the surviving bars animated to their UNCLAMPED geometry (base
                    // extrapolated to value 0, far below the grid) while upstream clamps them to the
                    // axis window. The `.add` branch always clipped in place; only re-used bars drifted.
                    isClipped = clipCartesian2D(coordSysClipArea, &layout)
                    if isClipped, let el = el {
                        _ = group.remove(el)
                    }
                }

                // upstream: roundCapChanged = el && (el.type === 'sector' && roundCap || el.type === 'sausage' && !roundCap)
                // Cartesian elements are always 'rect' → this is false at runtime; the sector<->sausage
                // recreate actually fires in the polar path (`_renderPolarBars`). Read `el.type` at runtime to
                // mirror upstream faithfully rather than hard-coding `false` (which is dead code).
                let elType = el?.type
                let roundCapChanged = elType != nil
                    && ((elType == "sector" && roundCap) || (elType == "sausage" && !roundCap))
                if roundCapChanged {
                    // roundCap changed: no way to animate sector -> sausage, so remove the old element
                    //   and create a new shape (fires only on the polar path, `_renderPolarBars`;
                    //   cartesian elements are always 'rect').
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

                // LabelManager's overall animation pass is not part of the lightweight native render
                // pipeline yet. Bar labels still need the upstream valueAnimation contract: after
                // updateStyle snapshots prevValue/targetValue, drive the attached text with the SAME
                // series update duration/easing as the bar's value-direction geometry. Without this,
                // race bars tween while their numbers jump straight to the final value.
                if !isChangeOrder, let label = el!.getTextContent() {
                    labelStyle.animateLabelValue(
                        label, Double(newIndex), data, animationModel, seriesModel
                    )
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
        //   (LargeBarPath.swift); the throttled mouse-event hit-test (largePathUpdateDataIndex) is wired
        //   inside `barCreateLarge` for tooltip/highDown over the large path.
        barCreateLarge(seriesModel, self.group)
        self._updateLargeClip(seriesModel)
    }

    // PORT-TODO (DORMANT — not reachable in the current build, so UNVERIFIED): `incrementalRender` (and
    //   therefore this method) is only ever invoked from `renderTaskReset`'s progressive branch
    //   (view/Chart.swift `progressMethodMap("incrementalPrepareRender")`), which runs off the Scheduler's
    //   piped render task. `ECharts.renderSeries` (core/ECharts.swift:2341) currently BYPASSES
    //   `renderTask.perform` and calls `chartView.render(...)` directly, and `Scheduler.prepareView` is a
    //   documented no-op pending sub-project C2 — so a large bar series always takes `_renderLarge`, never
    //   this path, even though `updateStreamModes` does set `progressiveRender = true` for it. The
    //   progressive `barCreateLarge` overload below is therefore ported-but-unexercised; verify it when
    //   progressive stage routing lands. Watch in particular for upstream's chunk-local vs GLOBAL index
    //   mismatch in `layout/barGrid` (`largeDataIndices[dataIndex]` written into a CHUNK-sized buffer,
    //   barGrid.ts:490) — under chunking that write goes out of range and will trap loudly here, which is
    //   the intended signal; `largePathFindDataIndex` reads the CHUNK-RELATIVE slot `idxOffset / 3`.
    private func _incrementalRenderLarge(_ params: StageHandlerProgressParams, _ seriesModel: BarSeriesModel) {
        self._removeBackground()
        // upstream: createLarge(seriesModel, this.group, this._progressiveEls, true);
        barCreateLarge(seriesModel, self.group, &self._progressiveEls, true)
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
    // realtimeSort — faithful port of the bar-racing sort/reorder pipeline. Uses `api.getZr()` (wired;
    //   nil in pure headless → the "rendered" listener path is dormant there) and `api.dispatchAction`.
    //   The reorder is realized cross-file by the `changeAxisOrder` action handler (registered in bar
    //   install upstream); dispatching an unregistered action is a silent no-op here (see
    //   ECharts.dispatchAction), so this pipeline is inert until that handler lands — but the BarView
    //   side is now ported faithfully rather than stubbed. Gated behind `realtimeSort: true` on a
    //   category baseAxis + cartesian2d (see `shouldRealtimeSort`), so default charts never reach it.
    // ------------------------------------------------------------------------------------------

    private func _enableRealtimeSort(
        _ realtimeSortCfg: RealtimeSortConfig,
        _ data: SeriesData,
        _ api: ExtensionAPI
    ) {
        // If no data in the first frame, wait for data to initSort
        if data.count() == 0 {
            return
        }

        let baseAxis = realtimeSortCfg.baseAxis

        if self._isFirstFrame {
            self._dispatchInitSort(data, realtimeSortCfg, api)
            self._isFirstFrame = false
        }
        else {
            let orderMapping: OrderMapping = { idx in
                guard let el = data.getItemGraphicEl(idx) as? Rect,
                      let shape = el.shape as? RectShape else {
                    return 0
                }
                // The result should be consistent with the initial sort by data value.
                // Do not support the case that both positive and negative exist.
                let v = Swift.abs(baseAxis.isHorizontal() ? shape.height : shape.width)
                // If data is NaN, shape.xxx may be NaN, so use || 0 here in case
                return v.isNaN ? 0 : v
            }
            let handler: EventCallback = { [weak self] _, _ in
                self?._updateSortWithinSameData(data, orderMapping, baseAxis, api)
                return nil
            }
            self._onRenderedToken = api.getZr()?.onWithToken("rendered", handler)
        }
    }

    private func _dataSort(
        _ data: SeriesData,
        _ baseAxis: Axis2D,
        _ orderMapping: @escaping OrderMapping
    ) -> OrdinalSortInfo {
        // type SortValueInfo = { dataIndex, mappedValue, ordinalNumber }
        struct SortValueInfo {
            var dataIndex: Int
            var mappedValue: Double
            var ordinalNumber: OrdinalNumber
        }
        var info: [SortValueInfo] = []
        let dim = data.mapDimension(baseAxis.dim)
        data.each(dim != nil ? [dim!] : []) { args in
            // (ordinalNumber, dataIdx)
            let ordinalNumber = (args[0] as? Double) ?? Double.nan
            let dataIdx = Int((args[1] as? Double) ?? 0)
            // upstream: mappedValue == null ? NaN : mappedValue (OrderMapping already returns Double)
            let mappedValue = orderMapping(dataIdx)
            info.append(SortValueInfo(
                dataIndex: dataIdx, mappedValue: mappedValue, ordinalNumber: ordinalNumber
            ))
        }

        // upstream: info.sort((a, b) => b.mappedValue - a.mappedValue) — descending.
        //   NaN is treated as the min value (upstream comment); a NaN-safe strict weak ordering is used
        //   here (Swift's `sort(by:)` traps on a non-total order, unlike JS's tolerant comparator).
        info.sort { a, b in
            if a.mappedValue.isNaN { return false }
            if b.mappedValue.isNaN { return true }
            return a.mappedValue > b.mappedValue
        }

        return OrdinalSortInfo(ordinalNumbers: info.map { $0.ordinalNumber })
    }

    private func _isOrderChangedWithinSameData(
        _ data: SeriesData,
        _ orderMapping: OrderMapping,
        _ baseAxis: Axis2D
    ) -> Bool {
        let scale = baseAxis.scale as! OrdinalScale
        let ordinalDataDim = data.mapDimension(baseAxis.dim) ?? ""

        var lastValue = Double.greatestFiniteMagnitude // Number.MAX_VALUE
        let len = scale.getOrdinalMeta().categories.count
        var tickNum = 0
        while tickNum < len {
            let rawIdx = data.rawIndexOf(ordinalDataDim, scale.getRawOrdinalNumber(Double(tickNum)))
            let value = rawIdx < 0
                // If some tick have no bar, the tick will be treated as min.
                ? Double.leastNonzeroMagnitude // Number.MIN_VALUE (smallest positive)
                // PENDING: if dataZoom on baseAxis exits, is it a performance issue?
                : orderMapping(data.indexOfRawIndex(rawIdx))
            if value > lastValue {
                return true
            }
            lastValue = value
            tickNum += 1
        }
        return false
    }

    /*
     * Consider the case when A and B changed order, whose representing
     * bars are both out of sight, we don't wish to trigger reorder action
     * as long as the order in the view doesn't change.
     */
    private func _isOrderDifferentInView(
        _ orderInfo: OrdinalSortInfo,
        _ baseAxis: Axis2D
    ) -> Bool {
        let scale = baseAxis.scale as! OrdinalScale
        let extent = scale.getExtent()

        var tickNum = Int(Swift.max(0, extent[0]))
        let tickMax = Int(Swift.min(extent[1], Double(scale.getOrdinalMeta().categories.count - 1)))
        while tickNum <= tickMax {
            if orderInfo.ordinalNumbers[tickNum] != scale.getRawOrdinalNumber(Double(tickNum)) {
                return true
            }
            tickNum += 1
        }
        return false
    }

    private func _updateSortWithinSameData(
        _ data: SeriesData,
        _ orderMapping: @escaping OrderMapping,
        _ baseAxis: Axis2D,
        _ api: ExtensionAPI
    ) {
        if !self._isOrderChangedWithinSameData(data, orderMapping, baseAxis) {
            return
        }

        let sortInfo = self._dataSort(data, baseAxis, orderMapping)

        if self._isOrderDifferentInView(sortInfo, baseAxis) {
            self._removeOnRenderedListener(api)
            var payload = Payload(type: "changeAxisOrder")
            payload.other["componentType"] = baseAxis.dim + "Axis"
            payload.other["axisId"] = baseAxis.index
            payload.other["sortInfo"] = sortInfo
            api.dispatchAction(payload)
        }
    }

    private func _dispatchInitSort(
        _ data: SeriesData,
        _ realtimeSortCfg: RealtimeSortConfig,
        _ api: ExtensionAPI
    ) {
        let baseAxis = realtimeSortCfg.baseAxis
        let otherDim = data.mapDimension(realtimeSortCfg.otherAxis.dim) ?? ""
        let sortResult = self._dataSort(data, baseAxis) { dataIdx in
            barToNumber(data.get(otherDim, dataIdx))
        }
        var payload = Payload(type: "changeAxisOrder")
        payload.other["isInitSort"] = true
        payload.other["componentType"] = baseAxis.dim + "Axis"
        payload.other["axisId"] = baseAxis.index
        payload.other["sortInfo"] = sortResult
        api.dispatchAction(payload)
    }

    open override func remove(_ ecModel: GlobalModel, _ api: ExtensionAPI) {
        self._clear(self._model)
        self._removeOnRenderedListener(api)
    }

    open override func dispose(_ ecModel: GlobalModel, _ api: ExtensionAPI) {
        self._removeOnRenderedListener(api)
    }

    private func _removeOnRenderedListener(_ api: ExtensionAPI) {
        if let token = self._onRenderedToken {
            // Swift closures have no comparable identity, so ZRenderKit exposes a stable registration
            // token for the same precise unsubscription that upstream performs with function identity.
            api.getZr()?.off("rendered", token: token)
            self._onRenderedToken = nil
        }
    }

    private func _clear(_ model: SeriesModel? = nil) {
        let group = self.group
        let data = self._data

        // PORT-NOTE (no upstream counterpart — ARC): `barCreateLarge` binds mousedown/mousemove on each
        //   `LargeBarPath`, and ZRenderKit's `Eventful` holds the handler's `ctx` (here the element
        //   itself, via `Element.on`'s `context ?? self`) STRONGLY — so a large path self-retains through
        //   its own event table and `group.removeAll()` alone would leak it, together with its packed
        //   `points`/`largeDataIndices` buffers (~12 MB per re-render at the 500k-bar scale this path
        //   exists for). Unbind before dropping. JS needs none of this: its GC collects the cycle.
        _ = group.traverse({ el in
            if let largePath = el as? LargeBarPath {
                _ = largePath.off()
            }
            return false
        })
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
//   Split into free functions (see the `clip` note): cartesian2d here, polar in `elementCreatorPolar`
//   (polar block at the bottom of this file).
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
// PORT-NOTE: `elementCreator.polar` (Sector / Sausage) is ported below as `elementCreatorPolar` (the polar block at the end of this file); only its sector text position (label/sectorLabel) is deferred.

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
    // Upstream splits the layout into two targets driven by DIFFERENT animation models: the growth
    // along the value direction uses the series' model, while the movement along the base axis uses the
    // AXIS model — that is what makes a bar-race bar slide to its new rank at the axis' tempo while its
    // length grows at the series' tempo. An earlier note here claimed the split was "equivalent to
    // el.setShape(layout)"; that was true only while initProps/updateProps were no-op shims. They are
    // real animations now, so collapsing the two targets meant a realtimeSort chart never animated at
    // all (official-bar-race-country: 0 animators where upstream has 25).
    let axisTarget: [String: Any]
    let seriesTarget: [String: Any]
    if isHorizontal {
        axisTarget = ["x": layout.x, "width": layout.width]
        seriesTarget = ["y": layout.y, "height": layout.height]
    }
    else {
        axisTarget = ["y": layout.y, "height": layout.height]
        seriesTarget = ["x": layout.x, "width": layout.width]
    }

    if !isChangeOrder {
        // Keep the original growth animation if only the axis order changed — do not start a new one.
        if isUpdate {
            updateProps(el, ["shape": seriesTarget], seriesAnimationModel, newIndex)
        } else {
            initProps(el, ["shape": seriesTarget], seriesAnimationModel, newIndex)
        }
    }

    // upstream: `const axisAnimationModel = seriesAnimationModel ? realtimeSortCfg.baseAxis.model : null;`
    //   i.e. a nil series model (animation disabled) also disables the axis leg.
    let axisAnimationModel: Model? = seriesAnimationModel != nil ? realtimeSortCfg.baseAxis.model : nil
    if isUpdate {
        updateProps(el, ["shape": axisTarget], axisAnimationModel, newIndex)
    } else {
        initProps(el, ["shape": axisTarget], axisAnimationModel, newIndex)
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
//   const polarPropties = ['cx', 'cy', 'r', 'startAngle', 'endAngle'] as const;  // ported: see `isValidLayoutPolar` below.
//   const isValidLayout: Record<'cartesian2d' | 'polar', (layout) => boolean> = { ... }
func isValidLayoutCartesian2D(_ layout: RectLayout) -> Bool {
    return !checkPropertiesNotValidCartesian2D(layout)
}

// upstream: `interface GetLayout` + `const getLayout: { [key in 'cartesian2d' | 'polar']: GetLayout }`.
//   Split into free functions (see the `clip` note): cartesian2d here, polar in `getLayoutPolar`.
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
// PORT-NOTE: `getLayout.polar` lives in the polar block at the bottom of this file (`getLayoutPolar`).

// upstream: function isZeroOnPolar(layout: SectorLayout) {
//     return layout.startAngle != null && layout.endAngle != null && layout.startAngle === layout.endAngle;
//   }
// PORT-NOTE: `SectorShape.startAngle` / `.endAngle` are non-Optional `Double`s, so the two `!= null`
//   guards are structurally satisfied (a missing layout is already rejected by `getLayoutPolar`).
func isZeroOnPolar(_ layout: SectorShape) -> Bool {
    return layout.startAngle == layout.endAngle
}

// Upstream `createPolarPositionMapping`: the generic start/end names refer to the radial arcs when
// the category axis is angular, and to the start/end angles when the category axis is radial.
private func mapPolarBarLabelPosition(_ position: String, _ isRadial: Bool) -> String {
    switch position {
    case "start", "insideStart", "end", "insideEnd":
        return position + (isRadial ? "Arc" : "Angle")
    default:
        return position
    }
}

// Upstream `setSectorTextRotation`. Polar bar labels default to automatic rotation even when the
// user does not specify `label.rotate`; cartesian labels keep the normal zero-rotation default.
private func setPolarBarLabelRotation(
    _ el: BarPossiblePath,
    _ layout: SectorShape,
    _ position: String,
    _ isRadial: Bool,
    _ explicitRotate: Any?
) {
    var config = el.textConfig ?? ElementTextConfig()
    config.inside = position == "middle" ? true : nil

    if let degrees = styleNum(explicitRotate) {
        config.rotation = degrees * Double.pi / 180
        el.setTextConfig(config)
        return
    }

    let startAngle = layout.clockwise ? layout.startAngle : layout.endAngle
    let endAngle = layout.clockwise ? layout.endAngle : layout.startAngle
    let middleAngle = (startAngle + endAngle) / 2
    let mapped = mapPolarBarLabelPosition(position, isRadial)
    let anchorAngle: Double
    switch mapped {
    case "startArc", "insideStartArc", "middle", "insideEndArc", "endArc":
        anchorAngle = middleAngle
    case "startAngle", "insideStartAngle":
        anchorAngle = startAngle
    case "endAngle", "insideEndAngle":
        anchorAngle = endAngle
    default:
        config.rotation = 0
        el.setTextConfig(config)
        return
    }

    var rotation = Double.pi * 1.5 - anchorAngle
    if mapped == "middle", rotation > Double.pi / 2, rotation < Double.pi * 1.5 {
        rotation -= Double.pi
    }
    config.rotation = rotation
    el.setTextConfig(config)
}

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
        // upstream: const borderRadius = itemModel.get(['itemStyle', 'borderRadius']) as number | number[] || 0;
        //   (el as Rect).setShape('r', borderRadius);
        // PORT-NOTE: the per-key `setShape('r', …)` is a no-op in ZRenderKit (RectShape.animationSet only
        //   tweens x/y/width/height; `r` is a `RectRadius?` enum with no keyed setter — fixing that seam
        //   belongs in ZRenderKit). Here we faithfully thread the corner radius by a whole-shape
        //   read-modify-write, which SURVIVES the subsequent shape animation: initProps/updateProps pass
        //   only the partial `{x,y,width,height}` dict via `rectShapeAnimShape`, whose per-key
        //   `animationSet` leaves `r` untouched. Supports both the `number` and `number[]` option forms.
        let borderRadius = itemModel.get(["itemStyle", "borderRadius"])
        if let rect = el as? Rect, var rectShape = rect.shape as? RectShape {
            rectShape.r = barRectRadiusFromOption(borderRadius)
            _ = rect.setShape(rectShape)
        }
    }
    // upstream: else if (!seriesModel.get('roundCap')) {
    //     const sectorShape = (el as Sector).shape;
    //     const cornerRadius = getSectorCornerRadius(itemModel.getModel('itemStyle'), sectorShape, true);
    //     extend(sectorShape, cornerRadius);
    //     (el as Sector).setShape(sectorShape);
    //   }
    // PORT-NOTE: same whole-shape read-modify-write idiom as the cartesian `r` branch above —
    //   `SectorShape.cornerRadius` has no keyed setter and is NOT part of `sectorShapeAnimShape`, so the
    //   value survives the subsequent init/updateProps shape animation. `extend(shape, cornerRadius)` is
    //   the `{cornerRadius, innerCornerRadius}` merge; the Swift helper returns the `cornerRadius`
    //   (`innerCornerRadius` has no SectorShape counterpart, same as PieView/ChordPiece).
    else if !((seriesModel.get("roundCap", true) as? Bool) ?? false) {
        if let sector = el as? Sector, var sectorShape = sector.shape as? SectorShape {
            if let cornerRadius = getSectorCornerRadius(itemModel.getModel("itemStyle"), sectorShape, true) {
                sectorShape.cornerRadius = cornerRadius
            }
            _ = sector.setShape(sectorShape)
        }
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
    //   `setLabelValueAnimation` (number roll-up) IS now ported (label/labelStyle.swift) and wired below.
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

    let label = el.getTextContent()
    if isPolar, label != nil, let polarLayout {
        let rawPosition = itemModel.get(["label", "position"])
        let position = (rawPosition as? String) == "outside"
            ? labelPositionOutside
            : ((rawPosition as? String) ?? "inside")
        setPolarBarLabelRotation(
            el,
            polarLayout,
            position,
            isHorizontalOrRadial,
            itemModel.get(["label", "rotate"])
        )
    }
    // upstream (BarView.ts:1055): snapshot the value + interpolated-text getter on the attached label so
    //   the label number ROLLS UP from its previous value to the new one (gated on `label.valueAnimation`,
    //   default false; the actual per-frame roll is driven by the label animation stage). `setLabelStyle`
    //   attached the label as `el`'s textContent above, so `getTextContent()` returns it here.
    labelStyle.setLabelValueAnimation(
        label,
        labelStatesModels,
        seriesModel.getRawValue(Double(dataIndex)),
        { value in labelHelper.getDefaultInterpolatedLabel(data, value) }
    )

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
    // upstream (BarView.ts:1066-1074):
    //   if (isZeroOnPolar(layout as SectorLayout)) {
    //       el.style.fill = 'none';
    //       el.style.stroke = 'none';
    //       each(el.states, (state) => { if (state.style) { state.style.fill = state.style.stroke = 'none'; } });
    //   }
    // Polar-only (a cartesian RectLayout has no startAngle/endAngle → isZeroOnPolar is always false),
    //   so it reads the `polarLayout` side-channel. `'none'` maps to `ZRColor.string("none")`, which
    //   ZRenderKit's `Path` honours as "no paint" (see `colorIsNone`); state styles are the untyped
    //   `[String: Any]` bag consumed by `applyElementStates`, so the raw "none" string goes in there.
    if isPolar, let polarLayout = polarLayout, isZeroOnPolar(polarLayout) {
        el.pathStyle.fill = .string("none")
        el.pathStyle.stroke = .string("none")
        for key in el.states.keys {
            if let state = el.states[key], state.style != nil {
                state.style?["fill"] = "none"
                state.style?["stroke"] = "none"
            }
        }
    }
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

// upstream: `itemModel.get(['itemStyle', 'borderRadius']) as number | number[] || 0` fed to
//   `(el as Rect).setShape('r', …)`. Bridges the option value (number | number[]) to the ZRenderKit
//   `RectRadius` tagged enum; anything unparseable falls back to `.number(0)` (mirrors `|| 0`, i.e. no
//   rounding).
func barRectRadiusFromOption(_ v: Any?) -> RectRadius {
    switch v {
    case let d as Double: return .number(d)
    case let i as Int: return .number(Double(i))
    case let n as NSNumber: return .number(n.doubleValue)
    case let arr as [Double]: return .array(arr)
    case let arri as [Int]: return .array(arri.map(Double.init))
    case let arrn as [NSNumber]: return .array(arrn.map { $0.doubleValue })
    case let arrAny as [Any]: return .array(arrAny.map { barToNumber($0) })
    default: return .number(0)
    }
}

// upstream: class LargePath / interface LargePathProps / function createLarge / largePathUpdateDataIndex /
//   largePathFindDataIndex — the large/progressive draw path. Ported in LargeBarPath.swift
//   (`LargeBarPath` / `LargeBarPathShape` / `barCreateLarge` / `largePathUpdateDataIndex` /
//   `largePathFindDataIndex`), throttle via util/throttle.

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
        case .pattern(let p):
            // Image pattern (`{image, repeat}`): the only ported PatternObject arm (SVG patterns are
            //   the deferred svg-backend seam). Bridge it to a ZRenderKit `Pattern` the painter tiles.
            if let ip = p as? ImagePatternObject {
                return .pattern(zrPatternFromImagePattern(ip))
            }
            return nil
        }
    }

    if let dict = v as? [String: Any] {
        // Image-pattern option object: `{image: <dataURI|url>, repeat, x, y, rotation, scaleX, scaleY}`
        //   (zrender's ImagePatternObject, the object form of `color: {image, repeat}`). The painter
        //   already tiles a `ZRColor.pattern` (CGRenderer.fillPatternClipped/tilePattern) and decodes a
        //   `data:`/URL image string (loadCGImage); the only missing link was this option→ZRColor bridge.
        if let pat = zrPatternFromDict(dict) {
            return .pattern(pat)
        }
        if let type = dict["type"] as? String {
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
    }

    return nil
}

// Build a ZRenderKit `Pattern` from an image-pattern option dict `{image, repeat, x, y, rotation,
//   scaleX, scaleY}`. Returns nil unless a usable image string is present (the `image` arm — a
//   `data:` URI or URL/path; the DOM/`ImageLike` and SVG arms are the deferred backend seam).
private func zrPatternFromDict(_ dict: [String: Any]) -> ZRenderKit.Pattern? {
    guard let image = dict["image"] as? String, !image.isEmpty else { return nil }
    let repeatMode = (dict["repeat"] as? String).flatMap { ImagePatternRepeat(rawValue: $0) } ?? .repeat
    let pat = ZRenderKit.Pattern(.url(image), repeatMode)
    if let x = styleNum(dict["x"]) { pat.x = x }
    if let y = styleNum(dict["y"]) { pat.y = y }
    if let r = styleNum(dict["rotation"]) { pat.rotation = r }
    if let sx = styleNum(dict["scaleX"]) { pat.scaleX = sx }
    if let sy = styleNum(dict["scaleY"]) { pat.scaleY = sy }
    return pat
}

// Bridge an EChartsKit `ImagePatternObject` (the typed arm of `ZRColor.pattern`) to a ZRenderKit
//   `Pattern`. Same fields as `zrPatternFromDict`, carried from the protocol accessors.
private func zrPatternFromImagePattern(_ ip: ImagePatternObject) -> ZRenderKit.Pattern {
    // `ImagePatternObject.image` is a separate symbol still typed `String` (the string arm only),
    //   so it is lifted into the `ImageSource` union here.
    let pat = ZRenderKit.Pattern(.url(ip.image), ip.`repeat` ?? .repeat)
    if let x = ip.x { pat.x = x }
    if let y = ip.y { pat.y = y }
    if let r = ip.rotation { pat.rotation = r }
    if let sx = ip.scaleX { pat.scaleX = sx }
    if let sy = ip.scaleY { pat.scaleY = sy }
    return pat
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
//   `updateStyle` branch (BarView.ts). This is a faithful port of the polar bar path.
//
// PORTED:
//   * the Sector layout (band width / bar offset / stacking) is produced by `layout/barPolar.swift`
//     and read back here via `getLayoutPolar` (`data.getItemLayout`), mirroring the cartesian path.
//   * BOTH radial (angle base — the canonical bar-on-polar / gallery `bar-polar-radial` demo) and
//     tangential (radius base) bars are rendered (see `_renderPolarBars`).
//   * roundCap → honoured: `SausagePath` (upstream util/shape/sausage) is ported and used for tangential
//     bars exactly as upstream (`(!isRadial && roundCap) ? Sausage : Sector`).
//   * `getSectorCornerRadius` (helper/sectorHelper) — wired in the `isPolar` branch of `updateStyle`,
//     behind upstream's `!seriesModel.get('roundCap')` guard.
//   * `isZeroOnPolar` — the zero-value no-paint fix-up, applied at the end of `updateStyle`.
//
// PORT-NOTE (deferred):
//   * sector text rotation / position: `createSectorCalculateTextPosition` +
//     `createPolarPositionMapping` (label/sectorLabel) are not ported.
//   * `showBackground` on the polar path.
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

// PORT-NOTE: local port helper (NOT in upstream). Upstream passes the WHOLE `layout` object to
//   `initProps`/`updateProps` (`{shape: layout}`), and zrender's `animateTo` steps non-numeric props
//   straight to their final value — so `clockwise` retargets along with the angles. `sectorShapeAnimShape`
//   can only carry the tweenable `Double` fields (`animationSet` is keyed on numbers), so the Bool is
//   written directly by a whole-shape read-modify-write BEFORE the animation is scheduled; the per-key
//   `animationSet` used by the tween then leaves `clockwise` alone. Without this a reused element keeps a
//   stale sweep direction when `angleAxis.clockwise`/`inverse` flips on a merge `setOption`.
func setPolarClockwise(_ el: BarPossiblePath, _ layout: SectorShape) {
    if var s = el.shape as? SectorShape {
        s.clockwise = layout.clockwise
        _ = el.setShape(s)
    }
    else if var s = el.shape as? SausageShape {
        s.clockwise = layout.clockwise
        _ = el.setShape(s)
    }
}

// PORT-NOTE: local port helper (NOT in upstream) — bridges a polar bar's `SectorShape` layout onto the
//   `SausageShape` the round-cap path consumes (upstream passes the SAME untyped `layout` object to
//   either shape class — `new ShapeClass({shape:
//   layout})` — which is untyped in JS; the Swift shapes are distinct structs, so the shared fields
//   are copied over. `cornerRadius` has no Sausage counterpart upstream either).
private func sausageShapeFromSector(_ layout: SectorShape) -> SausageShape {
    var s = SausageShape()
    s.cx = layout.cx
    s.cy = layout.cy
    s.r0 = layout.r0
    s.r = layout.r
    s.startAngle = layout.startAngle
    s.endAngle = layout.endAngle
    s.clockwise = layout.clockwise
    return s
}

private func currentPolarBarShape(_ sector: Path) -> SectorShape? {
    if let shape = sector.shape as? SectorShape { return shape }
    if let shape = sector.shape as? SausageShape {
        var result = SectorShape()
        result.cx = shape.cx; result.cy = shape.cy
        result.r0 = shape.r0; result.r = shape.r
        result.startAngle = shape.startAngle; result.endAngle = shape.endAngle
        result.clockwise = shape.clockwise
        return result
    }
    return nil
}

private func installPolarBarTextPosition(_ sector: Path, _ isRadial: Bool, _ isRoundCap: Bool) {
    sector.calculateTextPosition = { [unowned sector] out, config, rect in
        guard let position = config.position as? String,
              let shape = currentPolarBarShape(sector) else {
            var opts = CalculateTextPositionOpts()
            opts.position = (config.position as? String).flatMap(BuiltinTextPosition.init(rawValue:)).map {
                .position($0)
            }
            opts.distance = config.distance
            return ZRenderKit.text.calculateTextPosition(out, opts, rect)
        }

        let mapped = mapPolarBarLabelPosition(position, isRadial)
        let distance = config.distance ?? 5
        let middleR = (shape.r + shape.r0) / 2
        let middleAngle = (shape.startAngle + shape.endAngle) / 2
        let extraDistance = isRoundCap ? abs(shape.r - shape.r0) / 2 : 0
        var x = shape.cx + shape.r * cos(shape.startAngle)
        var y = shape.cy + shape.r * sin(shape.startAngle)
        var align: TextAlign = .left
        var verticalAlign: TextVerticalAlign = .top

        func angleDX(_ angle: Double, _ distance: Double, _ isEnd: Bool) -> Double {
            distance * sin(angle) * (isEnd ? -1 : 1)
        }
        func angleDY(_ angle: Double, _ distance: Double, _ isEnd: Bool) -> Double {
            distance * cos(angle) * (isEnd ? 1 : -1)
        }

        switch mapped {
        case "startArc":
            x = shape.cx + (shape.r0 - distance) * cos(middleAngle)
            y = shape.cy + (shape.r0 - distance) * sin(middleAngle)
            align = .center; verticalAlign = .top
        case "insideStartArc":
            x = shape.cx + (shape.r0 + distance) * cos(middleAngle)
            y = shape.cy + (shape.r0 + distance) * sin(middleAngle)
            align = .center; verticalAlign = .bottom
        case "startAngle":
            x = shape.cx + middleR * cos(shape.startAngle)
                + angleDX(shape.startAngle, distance + extraDistance, false)
            y = shape.cy + middleR * sin(shape.startAngle)
                + angleDY(shape.startAngle, distance + extraDistance, false)
            align = .right; verticalAlign = .middle
        case "insideStartAngle":
            x = shape.cx + middleR * cos(shape.startAngle)
                + angleDX(shape.startAngle, -distance + extraDistance, false)
            y = shape.cy + middleR * sin(shape.startAngle)
                + angleDY(shape.startAngle, -distance + extraDistance, false)
            align = .left; verticalAlign = .middle
        case "middle":
            x = shape.cx + middleR * cos(middleAngle)
            y = shape.cy + middleR * sin(middleAngle)
            align = .center; verticalAlign = .middle
        case "endArc":
            x = shape.cx + (shape.r + distance) * cos(middleAngle)
            y = shape.cy + (shape.r + distance) * sin(middleAngle)
            align = .center; verticalAlign = .bottom
        case "insideEndArc":
            x = shape.cx + (shape.r - distance) * cos(middleAngle)
            y = shape.cy + (shape.r - distance) * sin(middleAngle)
            align = .center; verticalAlign = .top
        case "endAngle":
            x = shape.cx + middleR * cos(shape.endAngle)
                + angleDX(shape.endAngle, distance + extraDistance, true)
            y = shape.cy + middleR * sin(shape.endAngle)
                + angleDY(shape.endAngle, distance + extraDistance, true)
            align = .left; verticalAlign = .middle
        case "insideEndAngle":
            x = shape.cx + middleR * cos(shape.endAngle)
                + angleDX(shape.endAngle, -distance + extraDistance, true)
            y = shape.cy + middleR * sin(shape.endAngle)
                + angleDY(shape.endAngle, -distance + extraDistance, true)
            align = .right; verticalAlign = .middle
        default:
            var opts = CalculateTextPositionOpts()
            opts.position = BuiltinTextPosition(rawValue: position).map { .position($0) }
            opts.distance = config.distance
            return ZRenderKit.text.calculateTextPosition(out, opts, rect)
        }

        out.x = x; out.y = y
        out.align = align; out.verticalAlign = verticalAlign
        return out
    }
}

// upstream: `elementCreator.polar` (Sector / Sausage path).
func elementCreatorPolar(
    _ seriesModel: BarSeriesModel,
    _ data: SeriesData,
    _ newIndex: Int,
    _ layout: SectorShape,
    _ isRadial: Bool,
    _ animationModel: BarSeriesModel?,
    _ axisModel: AxisBaseModel?,
    _ isUpdate: Bool,
    _ roundCap: Bool
) -> BarPossiblePath {
    // upstream: const ShapeClass = (!isRadial && roundCap) ? Sausage : Sector;
    //   `Sausage` == the ported `SausagePath` (chart/gauge/Sausage.swift, upstream util/shape/sausage.ts).
    let isRoundCap = !isRadial && roundCap
    let sector: Path = isRoundCap
        ? SausagePath(["shape": sausageShapeFromSector(layout) as PathShape, "z2": Double(1)])
        : Sector(["shape": layout as PathShape, "z2": Double(1)])
    sector.name = "item"
    installPolarBarTextPosition(sector, isRadial, isRoundCap)
    // PORT-NOTE: upstream also runs `(isUpdate ? updateProps : initProps)(sector, {shape: animateTarget},
    //   animationModel)` here; the port performs the equivalent whole-shape init/updateProps at the two
    //   call sites in `_renderPolarBars`, so `newIndex`/`isUpdate` are unused here. `data`/`axisModel`
    //   are likewise unused by upstream's polar creator (only cartesian2d reads them); all four are kept
    //   so both halves of the shared `ElementCreator` interface have the same arity as the TS.
    _ = (data, newIndex, axisModel, isUpdate)

    // upstream:
    //   const positionMap = createPolarPositionMapping(isRadial);
    //   sector.calculateTextPosition = createSectorCalculateTextPosition(positionMap, {isRoundCap: ShapeClass === Sausage});
    // PORT-NOTE (deferred): `label/sectorLabel` (createSectorCalculateTextPosition /
    //   createPolarPositionMapping) is not ported — see the polar block header.

    // Animation: collapse the bar at its baseline so the entrance grows it open — radial bars grow
    //   `r` from `r0`, tangential bars sweep `endAngle` from `startAngle` (upstream elementCreator.polar).
    //   Keyed via `PathShape.animationSet` so the SAME code drives `SectorShape` and `SausageShape`
    //   (upstream writes `sectorShape[animateProperty]` on either shape class).
    if animationModel != nil {
        var s: PathShape = sector.shape
        s.animationSet(isRadial ? "r" : "endAngle", isRadial ? layout.r0 : layout.startAngle)
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
    //   `roundCap` is honoured for tangential bars via the ported `SausagePath` (upstream
    //     `elementCreator.polar`'s `ShapeClass`), including the sector<->sausage recreate on change.
    //   PORT-NOTE (deferred, matching the rest of the polar block): showBackground (polar Sector
    //     background) and the sector label rotation subsystem (setSectorTextRotation /
    //     createSectorCalculateTextPosition) are deferred.
    func _renderPolarBars(_ seriesModel: BarSeriesModel, _ polar: Polar, _ group: Group) {
        let data = seriesModel.getData()
        let oldData = self._data
        let baseAxis = polar.getBaseAxis()
        // upstream: coord.type === 'polar' → isHorizontalOrRadial = baseAxis.dim === 'angle'.
        let isHorizontalOrRadial = baseAxis.dim == "angle"

        let animationModel: BarSeriesModel? = (seriesModel.isAnimationEnabled() ?? false) ? seriesModel : nil
        let roundCap = (seriesModel.get("roundCap", true) as? Bool) ?? false

        data.diff(oldData)
            .add({ dataIndex in
                let itemModel = data.getItemModel(dataIndex)
                guard let layout = getLayoutPolar(data, dataIndex) else { return }
                if !data.hasValue(dataIndex) || !isValidLayoutPolar(layout) { return }

                let el = elementCreatorPolar(
                    seriesModel, data, dataIndex, layout, isHorizontalOrRadial,
                    animationModel, baseAxis.model, false, roundCap
                )
                // Shared styling: item color + label + emphasis (isPolar = true).
                updateStyle(
                    el, data, dataIndex, itemModel, RectShape(),
                    seriesModel, isHorizontalOrRadial, true, layout
                )
                setPolarClockwise(el, layout)
                initProps(el, ["shape": sectorShapeAnimShape(layout)], seriesModel, dataIndex)

                data.setItemGraphicEl(dataIndex, el)
                _ = group.add(el)
            })
            .update({ newIndex, oldIndex in
                let itemModel = data.getItemModel(newIndex)
                var el = oldData?.getItemGraphicEl(oldIndex) as? BarPossiblePath
                // upstream: `const layout = getLayout[coord.type](data, newIndex, itemModel);
                //   if (!layout) { return; }` — NO element removal (mirrors `_renderNormal`).
                guard let layout = getLayoutPolar(data, newIndex) else { return }
                if !data.hasValue(newIndex) || !isValidLayoutPolar(layout) {
                    if let el = el { _ = group.remove(el) }
                    return
                }

                // upstream: const roundCapChanged = el && (el.type === 'sector' && roundCap
                //   || el.type === 'sausage' && !roundCap);
                // roundCap changed: there is no way to animate from a `sector` to a `sausage` shape,
                //   so remove the old one and create a new shape.
                // PORT-NOTE: upstream has no `isRadial` guard here, so a RADIAL bar with `roundCap: true`
                //   (which never becomes a Sausage — the creator uses `(!isRadial && roundCap)`) matches
                //   `sector && roundCap` and is recreated on every update instead of tweened. Upstream
                //   quirk (BarView.ts:358), reproduced verbatim.
                let elType = el?.type
                let roundCapChanged = elType != nil
                    && ((elType == "sector" && roundCap) || (elType == "sausage" && !roundCap))
                if roundCapChanged {
                    if let el = el { removeElementWithFadeOut(el, seriesModel, oldIndex) }
                    el = nil
                }

                if el == nil {
                    el = elementCreatorPolar(
                        seriesModel, data, newIndex, layout, isHorizontalOrRadial,
                        animationModel, baseAxis.model, true, roundCap
                    )
                }
                else {
                    saveOldStyle(el!)
                }

                updateStyle(
                    el!, data, newIndex, itemModel, RectShape(),
                    seriesModel, isHorizontalOrRadial, true, layout
                )
                setPolarClockwise(el!, layout)
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
