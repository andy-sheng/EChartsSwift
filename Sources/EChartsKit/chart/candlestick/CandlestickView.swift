// Ported from echarts/src/chart/candlestick/CandlestickView.ts — keep in sync with upstream
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
//   import * as zrUtil from 'zrender/src/core/util';                 -> `util` (each).
//   import ChartView from '../../view/Chart';                        -> `ChartView` (view/Chart.swift).
//   import * as graphic from '../../util/graphic';                   -> ZRenderKit shapes + graphic shims.
//     `initProps` / `updateProps` resolve to the shared `animation/basicTransition.swift` module
//     functions (see PORT-TODO at the call sites re: struct-shape snap-to-final deviation);
//     `traverseElements` is not used here.
//   import { setStatesStylesFromModel, toggleHoverEmphasis } from '../../util/states';
//     -> PORT-TODO: `util/states` NOT ported (states/emphasis prerequisite); the states block in
//        `setBoxCommon` is deferred (same deviation as BarView.swift `updateStyle`).
//   import Path, { PathProps } from 'zrender/src/graphic/Path';      -> ZRenderKit `Path` / `PathProps`.
//   import { createClipPath, SHAPE_CLIP_KIND_FULLY_CLIPPED, SHAPE_CLIP_KIND_NOT_CLIPPED,
//            SHAPE_CLIP_KIND_PARTIALLY_CLIPPED, updateClipPath } from '../helper/createClipPathFromCoordSys';
//     -> sibling `createClipPath` / `SHAPE_CLIP_KIND_*` / `updateClipPath`.
//   import CandlestickSeriesModel, { SERIES_TYPE_CANDLESTICK, CandlestickDataItemOption } from './CandlestickSeries';
//   import GlobalModel from '../../model/Global';                    -> `GlobalModel`.
//   import ExtensionAPI from '../../core/ExtensionAPI';              -> `ExtensionAPI`.
//   import { StageHandlerProgressParams } from '../../util/types';   -> `StageHandlerProgressParams`.
//   import SeriesData from '../../data/SeriesData';                  -> `SeriesData`.
//   import {CandlestickItemLayout} from './candlestickLayout';       -> `CandlestickItemLayout`.
//   import Model from '../../model/Model';                           -> `Model`.
//   import { saveOldStyle } from '../../animation/basicTransition';  -> shared module `saveOldStyle`
//     (`animation/basicTransition.swift`), still a B1 no-op stub (see comment there) but no longer
//     a local shim.
//   import Element from 'zrender/src/Element';                       -> `Element` (ZRenderKit).
//   import { getBorderColor, getColor } from './candlestickVisual';  -> sibling `getBorderColor` / `getColor`.
//   import { resolveNormalBoxClipping } from '../helper/whiskerBoxCommon';
//     -> PORT-TODO: `chart/helper/whiskerBoxCommon.ts` NOT ported; `resolveNormalBoxClipping` is
//        stubbed to `SHAPE_CLIP_KIND_NOT_CLIPPED` below (per-item partial-clip fix deferred).
//   import { getIncrementalId } from '../../util/model';             -> `model.getIncrementalId` (large mode only).

// const SKIP_PROPS = ['color', 'borderColor'] as const;
private let SKIP_PROPS = ["color", "borderColor"]

// upstream: class CandlestickView extends ChartView
open class CandlestickView: ChartView {

    // static readonly type = SERIES_TYPE_CANDLESTICK;
    public static let candlestickType = SERIES_TYPE_CANDLESTICK
    // readonly type = CandlestickView.type;
    open override var type: String {
        get { SERIES_TYPE_CANDLESTICK }
        set { /* readonly upstream */ }
    }

    private var _isLargeDraw: Bool?

    private var _data: SeriesData?

    private var _progressiveEls: [Element]?

    // upstream: render(seriesModel: CandlestickSeriesModel, ecModel: GlobalModel, api: ExtensionAPI)
    open override func render(
        _ seriesModel: SeriesModel, _ ecModel: GlobalModel, _ api: ExtensionAPI, _ payload: Payload
    ) {
        // upstream typed `seriesModel: CandlestickSeriesModel`; the base override is typed `SeriesModel`.
        let seriesModel = seriesModel as! CandlestickSeriesModel

        // If there is clipPath created in large mode. Remove it.
        self.group.removeClipPath()
        // Clear previously rendered progressive elements.
        self._progressiveEls = nil

        self._updateDrawMode(seriesModel)

        // this._isLargeDraw ? this._renderLarge(seriesModel) : this._renderNormal(seriesModel);
        if self._isLargeDraw == true {
            self._renderLarge(seriesModel)
        }
        else {
            self._renderNormal(seriesModel)
        }
    }

    // upstream: incrementalPrepareRender(seriesModel, ecModel, api)
    open override func incrementalPrepareRender(
        _ seriesModel: SeriesModel, _ ecModel: GlobalModel, _ api: ExtensionAPI, _ payload: Payload
    ) {
        let seriesModel = seriesModel as! CandlestickSeriesModel
        self._clear()
        self._updateDrawMode(seriesModel)
    }

    // upstream: incrementalRender(params, seriesModel, ecModel, api)
    open override func incrementalRender(
        _ params: StageHandlerProgressParams, _ seriesModel: SeriesModel, _ ecModel: GlobalModel,
        _ api: ExtensionAPI, _ payload: Payload
    ) {
        let seriesModel = seriesModel as! CandlestickSeriesModel
        self._progressiveEls = []
        // this._isLargeDraw ? this._incrementalRenderLarge(...) : this._incrementalRenderNormal(...)
        if self._isLargeDraw == true {
            self._incrementalRenderLarge(params, seriesModel)
        }
        else {
            self._incrementalRenderNormal(params, seriesModel)
        }
    }

    // upstream: eachRendered(cb: (el: Element) => boolean | void)
    open override func eachRendered(_ cb: (_ el: Element) -> Bool) {
        // upstream: graphic.traverseElements(this._progressiveEls || this.group, cb);
        // PORT-TODO: `util/graphic.traverseElements` not ported. When `_progressiveEls` exists, traverse
        //   each (large/progressive mode, deferred); otherwise traverse the group via `Group.traverse`
        //   (same note as BarView.swift `eachRendered`).
        if let progressiveEls = self._progressiveEls {
            for el in progressiveEls {
                _ = cb(el)
            }
        }
        else {
            self.group.traverse(cb)
        }
    }

    // upstream: _updateDrawMode(seriesModel: CandlestickSeriesModel)
    private func _updateDrawMode(_ seriesModel: CandlestickSeriesModel) {
        let isLargeDraw = seriesModel.pipelineContext.large
        if self._isLargeDraw == nil || isLargeDraw != self._isLargeDraw {
            self._isLargeDraw = isLargeDraw
            self._clear()
        }
    }

    // upstream: _renderNormal(seriesModel: CandlestickSeriesModel)
    private func _renderNormal(_ seriesModel: CandlestickSeriesModel) {
        let data = seriesModel.getData()
        let oldData = self._data
        let group = self.group
        let isSimpleBox = (data.getLayout("isSimpleBox") as? Bool) ?? false

        let needClip = (seriesModel.get("clip", true) as? Bool) ?? true
        let coordSys = seriesModel.coordinateSystem as? Cartesian2D
        // const clipArea = coordSys.getArea && coordSys.getArea();
        let clipArea: Any? = coordSys?.getArea()
        // const clipPath = needClip && createClipPath(coordSys, false, seriesModel);
        let clipPath: Path? = needClip
            ? createClipPath(seriesModel.coordinateSystem as? CoordinateSystem, false, seriesModel)
            : nil

        // There is no old data only when first rendering or switching from
        // stream mode to normal mode, where previous elements should be removed.
        if self._data == nil {
            _ = group.removeAll()
        }

        let transPointDim = getTransPointDimension(seriesModel)

        data.diff(oldData)
            .add({ newIdx in
                if data.hasValue(newIdx) {
                    // PORT-TODO: force-unwrap — normalProgress only writes CandlestickItemLayout.
                    let itemLayout = data.getItemLayout(newIdx) as! CandlestickItemLayout

                    let clipKind = needClip
                        ? resolveNormalBoxClipping(clipArea, itemLayout) : SHAPE_CLIP_KIND_NOT_CLIPPED
                    if clipKind == SHAPE_CLIP_KIND_FULLY_CLIPPED {
                        return
                    }

                    let el = createNormalBox(itemLayout, newIdx, transPointDim, true)
                    var initShape = NormalBoxPathShape()
                    initShape.points = itemLayout.ends
                    // PORT-TODO: candle entrance-grow deferred. `initProps` treats the whole
                    //   `NormalBoxPathShape` struct passed under "shape" as one opaque discrete
                    //   value (no per-field tween), so the box snaps to its final geometry instead
                    //   of animating in — same end state as before this task's wiring, just now
                    //   routed through the shared basicTransition infra (enable/disable via
                    //   getAnimationConfig). A real grow needs per-key `points`-array animation on
                    //   NormalBoxPathShape, which is not implemented.
                    initProps(el, ["shape": initShape as PathShape], seriesModel, newIdx)

                    // When an item is partially inside and partially outside the Cartesian bounding rect,
                    // the disappearance of the entire item may confuse users. Therefore, clipping is needed.
                    // Consider performance of zr Element['clipPath'], only set to partially clipped elements.
                    updateClipPath(clipKind == SHAPE_CLIP_KIND_PARTIALLY_CLIPPED, el, clipPath)

                    setBoxCommon(el, data, newIdx, isSimpleBox)

                    _ = group.add(el)

                    data.setItemGraphicEl(newIdx, el)
                }
            })
            .update({ newIdx, oldIdx in
                var el = oldData?.getItemGraphicEl(oldIdx) as? NormalBoxPath

                // Empty data
                if !data.hasValue(newIdx) {
                    if let el = el { _ = group.remove(el) }
                    return
                }

                let itemLayout = data.getItemLayout(newIdx) as! CandlestickItemLayout

                let clipKind = needClip
                    ? resolveNormalBoxClipping(clipArea, itemLayout) : SHAPE_CLIP_KIND_NOT_CLIPPED
                if clipKind == SHAPE_CLIP_KIND_FULLY_CLIPPED {
                    if let el = el { _ = group.remove(el) }
                    return
                }

                if el == nil {
                    el = createNormalBox(itemLayout, newIdx, transPointDim)
                }
                else {
                    var shape = NormalBoxPathShape()
                    shape.points = itemLayout.ends
                    // PORT-TODO: same struct-shape snap-to-final deviation as the `initProps` call
                    //   above — see comment there. Deferred until NormalBoxPathShape supports per-key
                    //   `points` animation.
                    updateProps(el!, ["shape": shape as PathShape], seriesModel, newIdx)

                    saveOldStyle(el!)
                }

                setBoxCommon(el!, data, newIdx, isSimpleBox)

                // See `updateClipPath` in `add`.
                updateClipPath(clipKind == SHAPE_CLIP_KIND_PARTIALLY_CLIPPED, el!, clipPath)

                _ = group.add(el!)
                data.setItemGraphicEl(newIdx, el!)
            })
            .remove({ oldIdx in
                let el = oldData?.getItemGraphicEl(oldIdx)
                if let el = el { _ = group.remove(el) }
            })
            .execute()

        self._data = data
    }

    // upstream: _renderLarge(seriesModel: CandlestickSeriesModel)
    private func _renderLarge(_ seriesModel: CandlestickSeriesModel) {
        self._clear()

        createLarge(seriesModel, self.group)

        // const clipPath = seriesModel.get('clip', true) ? createClipPath(...) : null;
        let clipPath: Path? = ((seriesModel.get("clip", true) as? Bool) ?? true)
            ? createClipPath(seriesModel.coordinateSystem as? CoordinateSystem, false, seriesModel)
            : nil
        updateClipPath(clipPath != nil, self.group, clipPath)
    }

    // upstream: _incrementalRenderNormal(params, seriesModel)
    private func _incrementalRenderNormal(_ params: StageHandlerProgressParams, _ seriesModel: CandlestickSeriesModel) {
        let data = seriesModel.getData()
        let isSimpleBox = (data.getLayout("isSimpleBox") as? Bool) ?? false

        let transPointDim = getTransPointDimension(seriesModel)

        // let dataIndex; while ((dataIndex = params.next()) != null) { ... }
        while let dataIndexD = params.next?() {
            let dataIndex = Int(dataIndexD)
            let itemLayout = data.getItemLayout(dataIndex) as! CandlestickItemLayout
            let el = createNormalBox(itemLayout, dataIndex, transPointDim)
            setBoxCommon(el, data, dataIndex, isSimpleBox)

            // el.incremental = getIncrementalId(seriesModel);
            // PORT-TODO: `Element.incremental` / `model.getIncrementalId` (incremental/large-mode rendering)
            //   deferred; the element is still added to the group so the geometry renders.
            _ = group.add(el)

            self._progressiveEls?.append(el)
        }
    }

    // upstream: _incrementalRenderLarge(params, seriesModel)
    private func _incrementalRenderLarge(_ params: StageHandlerProgressParams, _ seriesModel: CandlestickSeriesModel) {
        createLarge(seriesModel, self.group, &self._progressiveEls, true)
    }

    // upstream: remove(ecModel: GlobalModel)
    open override func remove(_ ecModel: GlobalModel, _ api: ExtensionAPI) {
        self._clear()
    }

    // upstream: _clear()
    private func _clear() {
        _ = self.group.removeAll()
        updateClipPath(false, self.group, nil)
        self._data = nil
    }
}

// upstream: class NormalBoxPathShape { points: number[][]; }
//   A plain parameter bag (no identity) → `struct` conforming to the `PathShape` marker (CONVENTIONS §4).
public struct NormalBoxPathShape: PathShape {
    // 8 points: body corners (0..3, closed quad) + whisker ends (4..7). Defaults to empty (upstream
    //   leaves `points` undefined on a fresh shape; buildPath is only called once `points` is set).
    public var points: [[Double]] = []

    public init() {}

    // PORT-TODO: upstream animates `points` via path morphing (dividePath/morphPath); the keyed
    //   numeric-field animation seam does not cover a `number[][]`. Left inert (no-op default).
}

// upstream: interface NormalBoxPathProps extends PathProps { shape?: Partial<NormalBoxPathShape> }
// PORT-TODO: typed-interface fidelity dropped — PathProps is the dynamic `[String: Any]` prop bag
//   (== DisplayableProps); the `shape?` field is set via the `"shape"` key (see Path._init).
public typealias NormalBoxPathProps = PathProps

// upstream: class NormalBoxPath extends Path<NormalBoxPathProps>
public final class NormalBoxPath: Path {

    // readonly type = 'normalCandlestickBox';  (set on the instance in init — see below)

    // upstream: shape: NormalBoxPathShape — narrows the inherited `shape: PathShape!`.

    // __simpleBox: boolean;
    public var __simpleBox: Bool = false

    // upstream: constructor(opts?: NormalBoxPathProps) { super(opts); }
    public override init(_ opts: ElementProps? = nil) {
        super.init(opts)
        self.type = "normalCandlestickBox"
    }

    public override func getDefaultShape() -> PathShape {
        return NormalBoxPathShape()
    }

    public override func buildPath(_ ctx: PathProxy, _ shape: PathShape, _ inBatch: Bool) {
        let shape = shape as! NormalBoxPathShape
        let ends = shape.points

        if self.__simpleBox {
            _ = ctx.moveTo(ends[4][0], ends[4][1])
            _ = ctx.lineTo(ends[6][0], ends[6][1])
        }
        else {
            _ = ctx.moveTo(ends[0][0], ends[0][1])
            _ = ctx.lineTo(ends[1][0], ends[1][1])
            _ = ctx.lineTo(ends[2][0], ends[2][1])
            _ = ctx.lineTo(ends[3][0], ends[3][1])
            _ = ctx.closePath()

            _ = ctx.moveTo(ends[4][0], ends[4][1])
            _ = ctx.lineTo(ends[5][0], ends[5][1])
            _ = ctx.moveTo(ends[6][0], ends[6][1])
            _ = ctx.lineTo(ends[7][0], ends[7][1])
        }
    }
}


// upstream: function createNormalBox(itemLayout, dataIndex, constDim, isInit?)
private func createNormalBox(
    _ itemLayout: CandlestickItemLayout,
    _ dataIndex: Int,
    _ constDim: Int,
    _ isInit: Bool = false
) -> NormalBoxPath {
    let ends = itemLayout.ends
    var shape = NormalBoxPathShape()
    shape.points = isInit
        ? transInit(ends, constDim, itemLayout)
        : ends
    return NormalBoxPath([
        "shape": shape as PathShape,
        "z2": Double(100)
    ])
}

// upstream: function setBoxCommon(el: NormalBoxPath, data: SeriesData, dataIndex: number, isSimpleBox?)
private func setBoxCommon(_ el: NormalBoxPath, _ data: SeriesData, _ dataIndex: Int, _ isSimpleBox: Bool = false) {
    let itemModel = data.getItemModel(dataIndex)

    // el.useStyle(data.getItemVisual(dataIndex, 'style'));
    // PORT-TODO: the item visual 'style' is a `[String: Any]` bag (candlestickVisual.swift); ZRenderKit
    //   `useStyle` takes a typed `PathStyleProps`. `candlestickStyleFromDict` bridges the common paint
    //   keys (this is what colors the body/whiskers bull/bear). Gradient/pattern fills not bridged.
    el.useStyle(candlestickStyleFromDict(data.getItemVisual(dataIndex, "style")))
    // el.style.strokeNoScale = true;
    el.pathStyle.strokeNoScale = true

    // const cursorStyle = itemModel.getShallow('cursor'); cursorStyle && el.attr('cursor', cursorStyle);
    let cursorStyle = itemModel.getShallow("cursor")
    if candlestickViewTruthy(cursorStyle) {
        _ = el.attr("cursor", cursorStyle)
    }

    el.__simpleBox = isSimpleBox

    // upstream: setStatesStylesFromModel(el, itemModel);
    //   Populates el.states.emphasis/blur/select with each state's `itemStyle` and marks `el` a highDown
    //   dispatcher below, so a hover (enterEmphasisWhenMouseOver) restyles the box.
    states.setStatesStylesFromModel(el, itemModel)

    // upstream:
    //   const sign = data.getItemLayout(dataIndex).sign;
    //   zrUtil.each(el.states, (state, stateName) => {
    //       const stateModel = itemModel.getModel(stateName);
    //       const color = getColor(sign, stateModel);
    //       const borderColor = getBorderColor(sign, stateModel) || color;
    //       const stateStyle = state.style || (state.style = {});
    //       color && (stateStyle.fill = color);
    //       borderColor && (stateStyle.stroke = borderColor);
    //   });
    //   Overrides each state's fill/stroke with the sign-specific bull/bear color from that state's model.
    let sign = (data.getItemLayout(dataIndex) as? CandlestickItemLayout)?.sign ?? 0
    for (stateName, state) in el.states {
        let stateModel = itemModel.getModel([stateName])
        let color = getColor(sign, stateModel)
        let borderColor = candlestickViewTruthy(getBorderColor(sign, stateModel))
            ? getBorderColor(sign, stateModel) : color
        var stateStyle = state.style ?? [:]
        if candlestickViewTruthy(color) { stateStyle["fill"] = color }
        if candlestickViewTruthy(borderColor) { stateStyle["stroke"] = borderColor }
        state.style = stateStyle
    }

    // upstream:
    //   const emphasisModel = itemModel.getModel('emphasis');
    //   toggleHoverEmphasis(el, emphasisModel.get('focus'), emphasisModel.get('blurScope'),
    //       emphasisModel.get('disabled'));
    let emphasisModel = itemModel.getModel(["emphasis"])
    let focus: InnerFocus? = emphasisModel.get("focus")
    let blurScope = (emphasisModel.get("blurScope") as? String).flatMap { BlurScope(rawValue: $0) }
    let isDisabled = (emphasisModel.get("disabled") as? Bool) ?? false
    states.toggleHoverEmphasis(el, focus, blurScope, isDisabled)

    _ = SKIP_PROPS
}

// upstream: function transInit(points: number[][], dim: number, itemLayout: CandlestickItemLayout)
private func transInit(_ points: [[Double]], _ dim: Int, _ itemLayout: CandlestickItemLayout) -> [[Double]] {
    return util.map(points) { point, _ in
        var point = point   // point.slice()
        point[dim] = itemLayout.initBaseline
        return point
    }
}

// upstream: function getTransPointDimension(seriesModel: CandlestickSeriesModel): number
//   Returns a dimension INDEX (0 or 1) used to subscript a point; kept as `Int` (genuine index).
private func getTransPointDimension(_ seriesModel: CandlestickSeriesModel) -> Int {
    return seriesModel.getWhiskerBoxesLayout() == "horizontal" ? 1 : 0
}



// ================================================================================================
// PORT-TODO: LARGE / PROGRESSIVE DRAW PATH — DEFERRED (per task scope + CONVENTIONS §5).
//   The large-mode `LargeBoxPath` custom shape and `createLarge` / `setLargeStyle` batch-draw one
//   `LargeBoxPath` per sign (1 / -1 / 0) over the flat `largePoints` buffer produced by
//   candlestickLayout.swift's `largeProgress`. It needs `ignoreCoarsePointer`, `Element.incremental`
//   / `model.getIncrementalId`, and per-key `getItemStyle(SKIP_PROPS)` — none of which are on the
//   normal render path. `createLarge` is stubbed to a no-op below so `_renderLarge` /
//   `_incrementalRenderLarge` compile; wire up when the large draw milestone lands.
//
//   Upstream (verbatim reference):
//     class LargeBoxPathShape { points: ArrayLike<number>; }
//     interface LargeBoxPathProps extends PathProps { shape?: Partial<LargeBoxPathShape>; __sign?: number }
//     class LargeBoxPath extends Path {
//         readonly type = 'largeCandlestickBox';
//         shape: LargeBoxPathShape;
//         __sign: number;
//         constructor(opts?) { super(opts); }
//         getDefaultShape() { return new LargeBoxPathShape(); }
//         buildPath(ctx, shape) {
//             const points = shape.points;
//             for (let i = 0; i < points.length;) {
//                 if (this.__sign === points[i++]) {
//                     const x = points[i++];
//                     ctx.moveTo(x, points[i++]);
//                     ctx.lineTo(x, points[i++]);
//                 } else { i += 3; }
//             }
//         }
//     }
//     function setLargeStyle(sign, el, seriesModel, data) {
//         const borderColor = getBorderColor(sign, seriesModel) || getColor(sign, seriesModel);
//         const itemStyle = seriesModel.getModel('itemStyle').getItemStyle(SKIP_PROPS);
//         el.useStyle(itemStyle);
//         el.style.fill = null;
//         el.style.stroke = borderColor;
//         const cursorStyle = seriesModel.get('cursor'); cursorStyle && el.attr('cursor', cursorStyle);
//     }
// ================================================================================================
// upstream: function createLarge(seriesModel, group, progressiveEls?, incremental?)
private func createLarge(
    _ seriesModel: CandlestickSeriesModel,
    _ group: Group,
    _ progressiveEls: inout [Element]?,
    _ incremental: Bool = false
) {
    // PORT-TODO: large draw deferred (see the block comment above).
    _ = (seriesModel, group, incremental)
    _ = progressiveEls
}

// Overload matching the `_renderLarge` call site (no progressiveEls / incremental).
private func createLarge(_ seriesModel: CandlestickSeriesModel, _ group: Group) {
    // PORT-TODO: large draw deferred (see the block comment above).
    _ = (seriesModel, group)
}

// export default CandlestickView;  -> `open class CandlestickView` above.

// ================================================================================================
// PORT-TODO: local helpers (NOT in upstream CandlestickView.ts).
// ================================================================================================

// PORT-TODO: `resolveNormalBoxClipping` from `chart/helper/whiskerBoxCommon.ts` is not ported (the
//   mixin file is folded per-client — see CandlestickSeries.swift). Stubbed to NOT_CLIPPED so a box
//   straddling the coord-sys edge is drawn unclipped rather than dropped. The per-item partial-clip
//   fix (setClipPath on partially-clipped boxes) is deferred with it.
private func resolveNormalBoxClipping(_ clipArea: Any?, _ itemLayout: CandlestickItemLayout) -> ShapeClipKind {
    _ = (clipArea, itemLayout)
    return SHAPE_CLIP_KIND_NOT_CLIPPED
}

// PORT-TODO: `util/graphic`-level `useStyle(dict)` bridge. The item visual 'style' is a `[String: Any]`
//   bag (candlestickVisual.swift stores `fill`/`stroke` via getColor/getBorderColor); ZRenderKit
//   `Path.useStyle` takes a typed `PathStyleProps`. Mirrors BarView.swift's `barStyleFromDict`.
private func candlestickStyleFromDict(_ style: Any?) -> PathStyleProps {
    var s = PathStyleProps()
    guard let d = style as? [String: Any] else { return s }
    // Paint colors are stored as EChartsKit `ZRColor` (`.color("#...")`) OR a raw `String`; bridge
    //   both to the ZRenderKit `ZRColor.string` (only solid colors; gradient/pattern out of scope).
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

// JS truthiness for `cursorStyle && el.attr('cursor', cursorStyle)` (nil/''/false are falsy).
private func candlestickViewTruthy(_ v: Any?) -> Bool {
    switch v {
    case nil: return false
    case is NSNull: return false
    case let b as Bool: return b
    case let s as String: return !s.isEmpty
    case let d as Double: return d != 0 && !d.isNaN
    default: return true
    }
}
