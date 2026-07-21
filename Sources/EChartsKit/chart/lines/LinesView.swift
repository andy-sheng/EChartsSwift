// Ported (STATIC SUBSET) from echarts/src/chart/lines/LinesView.ts — keep in sync with upstream.
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
//   import LineDraw from '../helper/LineDraw';            -> ported as chart/helper/LineDraw.swift and WIRED.
//       LineDraw.updateData is a per-edge enter/update/leave diff that reuses `ECLine` instances (each
//       reading `data.getItemLayout(i)` via `ECLine.setLinePoints`), plus fromSymbol/toSymbol arrow
//       markers + label + emphasis/blur state. `_lineDraw` below owns the straight/curved (non-polyline)
//       lines: its group is added once (`_lineDrawAdded`) and driven by `_lineDraw.updateData(data)`.
//       PORT-NOTE: the POLYLINE mode is still inlined (ECLine models only a 2/3-point Line/BezierCurve),
//       so an N-point `Polyline` per data item is built directly.
//   import EffectLine from '../helper/EffectLine';        -> PORT-NOTE: ported as chart/lines/EffectLine.swift.
//       The moving-dot / trail EFFECT is ANIMATED (CONVENTIONS §5) and is wired (see render + EffectLine.swift).
//   import Line from '../helper/Line';                    -> PORT-NOTE: ported as chart/helper/ECLine.swift
//       (renamed to avoid colliding with the ZRenderKit `Line` SHAPE); driven via LineDraw.
//   import Polyline from '../helper/Polyline';            -> PORT-NOTE: helper/Polyline NOT ported (inline shape).
//   import EffectPolyline from '../helper/EffectPolyline';-> PORT-NOTE: ported (in chart/lines/EffectLine.swift); effect wired.
//   import LargeLineDraw from '../helper/LargeLineDraw';  -> ported as chart/helper/LargeLineDraw.swift and
//       WIRED: `_updateLineDraw`'s `isLargeDraw` branch draws the whole series into ONE `LargeLinesPath`
//       built from the packed `linesPoints` layout that the `linesLayout` STAGE produces (see the large
//       branch in `render`). The PROGRESSIVE half (incrementalPrepareUpdate / incrementalUpdate) stays
//       DEFERRED with the incremental pipeline.
//   import linesLayout from './linesLayout';              -> the layout STAGE IS run by this driver
//       (`runSeriesStageHandler(linesLayout, …)` in ECharts.render(), before renderSeries) and is the sole
//       producer of the LARGE-mode `linesPoints` buffer consumed below. For the NON-large modes the
//       per-item dataToPoint + curveness-control-point math is ADDITIONALLY inlined in `render` (the same
//       deviation as ScatterView inlining pointsLayout and LineView inlining dataToPoint) — that inlining
//       writes only per-ITEM layouts and never touches the `linesPoints` key.
//   import {createClipPath} from '../helper/createClipPathFromCoordSys';
//       -> PORT-NOTE: createClipPathFromCoordSys is ported; the `clip` option is not wired in this static view (no clip path set).
//   import ChartView from '../../view/Chart';             -> ChartView (view/Chart.swift).
//   import LinesSeriesModel from './LinesSeries';         -> sibling LinesSeries.swift (assumed ported alongside).
//   import GlobalModel from '../../model/Global';         -> GlobalModel.
//   import ExtensionAPI from '../../core/ExtensionAPI';   -> ExtensionAPI.
//   import CanvasPainter from 'zrender/src/canvas/Painter';   -> PORT-NOTE: motion-blur layer config (effect trail) is applied by the live host (EChartsView._setupLinesEffectLayers / configLayer).
//   import { StageHandlerProgressParams, StageHandlerProgressExecutor } from '../../util/types';
//       -> PORT-NOTE (deferred): incremental/progressive pipeline (incrementalRender/updateTransform) DEFERRED for lines.
//   import SeriesData from '../../data/SeriesData';       -> SeriesData.
//   import type Polar from '../../coord/polar/Polar';     -> Polar (polar lines are a PORT-NOTE deferral below).
//   import type Cartesian2D from '../../coord/cartesian/Cartesian2D';   -> Cartesian2D.
//   import Element from 'zrender/src/Element';            -> Element (eachRendered — DEFERRED).
//   import { getIncrementalId } from '../../util/model';  -> PORT-NOTE (deferred): getIncrementalId is ported (util/modelUtil), but the incremental pipeline usage for lines is DEFERRED.
//   import { getCurrentCanvasPainter } from '../../util/graphic';   -> PORT-NOTE: motion-blur layer config is host-managed (EChartsView.configLayer); getCurrentCanvasPainter is unused natively.
//   import { ILineDraw } from '../helper/baseDraw';       -> PORT-NOTE: helper/baseDraw NOT ported.

// upstream: class LinesView extends ChartView
open class LinesView: ChartView {

    // upstream: static readonly type = 'lines';  /  readonly type = LinesView.type;
    //   The base `ChartView.type` is a settable stored `var` (default "chart"), so it is assigned in
    //   `init` (can't override a read-write stored property with a read-only computed one) — same
    //   convention as ScatterView.
    public static let type = "lines"

    public override init() {
        super.init()
        self.type = LinesView.type
    }

    // upstream fields: _lastZlevel / _finished / _lineDraw / _hasEffet / _isPolyline / _isLargeDraw.
    //   PORT-NOTE (deferred): the incremental flags (_finished) are DEFERRED; `_isLargeDraw` IS wired.
    private var _data: SeriesData?

    // upstream: `this._lineDraw = new LineDraw()` — the straight/curved (non-polyline) lines are now
    //   routed through the shared `chart/helper/LineDraw`, which DIFFS `data` (enter/update/leave) and
    //   reuses + tweens each ECLine across a merge-mode setOption. Its group is added to `self.group`
    //   once (`_lineDrawAdded`). PORT-NOTE: ECLine models only a 2/3-point Line/BezierCurve, so the
    //   POLYLINE (N-point) mode keeps the inline persist-and-morph reuse below; geo/polar lines stay
    //   DEFERRED (only Cartesian2D is wired). The (ported) LargeLineDraw IS wired — see below.
    private let _lineDraw = LineDraw()
    private var _lineDrawAdded = false

    // upstream `_updateLineDraw`: `lineDraw = isLargeDraw ? new LargeLineDraw() : new LineDraw(...)` —
    //   the two draws are held in one `_lineDraw` field there (typed `ILineDraw`, which is NOT ported);
    //   this port keeps them in two fields and switches on `_isLargeDraw`, exactly as ScatterView holds
    //   `_symbolDraw` + `_largeSymbolDraw`. Like ScatterView's `_largeSymbolDraw`, it is created LAZILY
    //   on first entry into large mode (nil ⇒ never added to `self.group`), so the vast majority of
    //   `lines` series never allocate it or its Group; non-nil doubles as the "already added" flag.
    private var _largeLineDraw: LargeLineDraw?
    private var _isLargeDraw = false

    // View REUSE for the POLYLINE mode (ECLine can't model an N-point polyline): the per-item Polyline
    //   elements are PERSISTED (keyed by data index) and MORPHED, gated by `_prevCount`/`_prevIsPolyline`.
    private var _lineEls: [Int: Path] = [:]
    private var _prevCount = -1
    private var _prevIsPolyline = false
    // The effect TRAIL symbols are ANIMATED (looping) — kept rebuilding each render (their morph is a
    //   documented PORT-NOTE deferral). Persisted only so the previous render's symbols can be removed before the
    //   base lines are reused (otherwise they would accumulate when the group is no longer wiped).
    private var _effectSymbols: [Path] = []

    // upstream: render(seriesModel: LinesSeriesModel, ecModel: GlobalModel, api: ExtensionAPI)
    open override func render(
        _ seriesModelBase: SeriesModel, _ ecModel: GlobalModel, _ api: ExtensionAPI, _ payload: Payload
    ) {
        // upstream typed `seriesModel: LinesSeriesModel`; the base override is typed `SeriesModel`.
        //   `getLineCoords` (the flat/coords accessor) lives on LinesSeriesModel, so the cast is required.
        guard let seriesModel = seriesModelBase as? LinesSeriesModel else { return }

        // upstream delegates to `LineDraw` (or `LargeLineDraw`), whose group is added under `this.group`
        //   and whose `updateData(data)` reads `data.getItemLayout(i)` — the pixel point list the
        //   `linesLayout` STAGE stored. The static port skips the layout stage and the draw helper: it
        //   projects each data-space coord through the coord system itself (like ScatterView/LineView),
        //   then adds one shape per item to `this.group` (rebuilt from scratch each render).
        //
        // PORT-NOTE: `configLayer` motion-blur (the trail effect's `lastFrameAlpha`) is applied by the
        //   live host (EChartsView._setupLinesEffectLayers); no in-view `getCurrentCanvasPainter` clear.
        // PORT-NOTE: `_showEffect`/`trailLength` → EffectLine/EffectPolyline moving-dot render is wired (see below).
        // PORT-NOTE: `seriesModel.get('clip')` → createClipPath(coordSys) + group.setClipPath is not wired
        //   in this static view (helper/createClipPathFromCoordSys IS ported).

        // PORT-NOTE (deferred): polar / geo lines DEFERRED (only Cartesian2D wired). Upstream's coord system is
        //   `Polar | Cartesian2D | Geo`; linesLayout calls `coordSys.dataToPoint(coord)` generically —
        //   the same call works for Polar once its lines path is exercised, but geo is not ported.
        guard let coord = seriesModelBase.coordinateSystem as? Cartesian2D else {
            // Coord system missing / changed away from cartesian → drop the persistent line + effect
            //   elements so a later reuse can't stitch onto a stale coord projection.
            self.resetPersistentElements()
            // upstream applies clip unconditionally; with no cartesian coord there is nothing to draw,
            //   so just drop any clip path left over from a prior render.
            self.group.removeClipPath()
            return
        }

        let data: SeriesData = seriesModel.getData()

        // const isPolyline = !!seriesModel.get('polyline');
        let isPolyline = linesTruthy(seriesModel.get("polyline", false))

        // upstream: this._hasEffet = seriesModel.get(['effect', 'show']); — when set, the LineDraw draws
        //   `EffectLine`/`EffectPolyline` (a moving trail symbol) instead of a plain `Line`/`Polyline`.
        //   PORT DEVIATION: upstream picks the per-item ctor at construction time
        //   (`new LineDraw(hasEffect ? EffectLine : Line)`); this port always uses LineDraw's default
        //   `ECLine` ctor for the non-polyline lines and ADDS the trail symbol alongside them (see the
        //   `hasEffect` block after `_lineDraw.updateData(data)`, and chart/lines/EffectLine.swift).
        //   The POLYLINE branch still keeps the inline `Polyline` shapes and gets the trail the same way.
        let hasEffect = linesTruthy(seriesModel.get(["effect", "show"]))

        // Line color: `visualStyleAccessPath = 'lineStyle'`, `visualDrawType = 'stroke'` — the visual/style
        //   stage writes the palette color into the series visual `style` bag under `stroke` (item visuals
        //   override it). Same bridge as GraphView's edge coloring / LineView's `colorString`.
        let seriesLineStyle = data.getVisual("style") as? [String: Any]

        let group = self.group
        let count = data.count()

        // The effect trail symbols are ANIMATED (looping) and rebuilt each render (their morph is a
        //   PORT-NOTE deferral). With the group no longer wiped, remove the previous render's symbols first so
        //   they don't accumulate when the base lines are reused.
        for s in _effectSymbols { _ = group.remove(s) }
        _effectSymbols.removeAll()

        // NOTE: the per-zlevel motion-blur config (upstream LinesView.render's `zr.configLayer(zlevel,
        //   {motionBlur, lastFrameAlpha})`) is applied by the LIVE host, not here: this driver is zr-less
        //   at render time (`group.__zr` is nil until EChartsView._syncRoot runs AFTER render), the same
        //   reason roam is wired in EChartsView. See EChartsView._setupLinesEffectLayers.

        // Reused per-item data-space coord buffer — upstream `linesLayout` reuses one `lineCoords: number[][]`
        //   across the whole progress loop; `getLineCoords(i, out)` fills it and returns the point count.
        var lineCoords: [[Double]] = []

        // === LARGE mode → the shared LargeLineDraw (one path for the whole series) ===================
        //   upstream `_updateLineDraw`: `const isLargeDraw = pipelineContext.large;`.
        //   SINGLE SOURCE OF TRUTH: read the ported `pipelineContext` rather than re-deriving the
        //   predicate from raw options. `Scheduler.updateStreamModes` (→ modelUtil.preparePipelineContext,
        //   which computes `large` from `large` + `largeThreshold`) runs for every series in
        //   `ECharts.render()` BEFORE the layout stages and `renderSeries`, so the context is populated
        //   here — the same read BarView (`seriesModel.pipelineContext.large`) and layout/barGrid use.
        //   This matters beyond tidiness: `linesLayout` — the PRODUCER of the `linesPoints` buffer this
        //   branch consumes — branches on `seriesModel.pipelineContext.large` too, so producer and
        //   consumer cannot disagree (a `__preparePipelineContext` override, or a differing coercion of
        //   `largeThreshold`, would otherwise feed a large-mode draw from a per-item layout pass).
        //   Optional-chained because `pipelineContext` is an implicitly-unwrapped `PipelineContext!`
        //   (nil in any driver path that skips updateStreamModes; there the non-large path is correct,
        //   since linesLayout would not have packed a buffer either).
        let isLargeDraw = seriesModel.pipelineContext?.large ?? false

        if isLargeDraw {
            // upstream (__DEV__): `if (hasEffect && isLargeDraw) console.warn('Large lines not support
            //   effect')` — the effect pass is skipped below, same as upstream (LargeLineDraw has no trail).
            if __DEV__ {
                if hasEffect {
                    log.warn("Large lines not support effect")
                }
            }

            // Only the normal → large TRANSITION drops the LineDraw / persisted Polyline / effect
            //   elements; upstream `_updateLineDraw` likewise re-creates the draw only when the mode
            //   actually flips (cf. ScatterView's `if _largeSymbolDraw == nil || _isLargeDraw != …`).
            //   `_lineDraw.reset()` (not `.remove()`) also clears its DIFF state, so that a later
            //   large → normal flip enters elements fresh, exactly as upstream's brand-new LineDraw does.
            if !_isLargeDraw {
                self.resetPersistentElements()
            }

            // NO PACKING HERE — the packed `linesPoints` buffer is produced by the `linesLayout` STAGE,
            //   exactly as upstream: `linesLayout`'s large branch allocates the fixed-size
            //   `Float32Array` (polyline → `[len, x0,y0, …]` per item; otherwise `[x0,y0,x1,y1]` per
            //   item) and does `lineData.setLayout('linesPoints', points)`. That stage IS run by this
            //   driver — `runSeriesStageHandler(linesLayout, ecModel, api)` in `ECharts.render()`, full
            //   range, before `renderSeries` — and it branches on the SAME `pipelineContext.large` read
            //   above, so whenever this branch is taken the buffer exists and is well-formed (the
            //   LAYOUT INVARIANT LargeLinesPath.buildPath / findDataIndex rely on). Upstream's LinesView
            //   likewise packs nothing; it only calls `lineDraw.updateData(data)`.
            //   (The per-item projection the NON-large branches below inline is a separate, additive
            //   deviation — it does not touch this key.)

            // upstream `_updateLineDraw`: `lineDraw = new LargeLineDraw()` — created lazily on first
            //   entry into large mode (the ScatterView `_largeSymbolDraw` precedent), so the
            //   overwhelming majority of `lines` series never allocate it or its Group.
            let largeLineDraw: LargeLineDraw
            if let existing = _largeLineDraw {
                largeLineDraw = existing
            }
            else {
                largeLineDraw = LargeLineDraw()
                _largeLineDraw = largeLineDraw
                _ = group.add(largeLineDraw.group)
            }
            // upstream: lineDraw.updateData(data) — reads the packed layout + the series lineStyle/stroke.
            largeLineDraw.updateData(data)

            _isLargeDraw = true
            _prevCount = count
            _prevIsPolyline = isPolyline
            self._data = data
            applyClipPath(seriesModel)
            return
        }

        // Toggle back from large → normal: drop the large path so it can't linger under the reused group,
        //   and RESET the LineDraw's diff state — upstream builds a brand-new `LineDraw` on the flip, so
        //   its first `updateData` sees `oldLineData == nil` and enters every element fresh; reusing this
        //   instance would otherwise diff against (and tween from) the data captured before large mode.
        if _isLargeDraw {
            _largeLineDraw?.remove()
            _lineDraw.reset()
            _isLargeDraw = false
        }

        if !isPolyline {
            // === Straight / curved lines → the shared LineDraw (enter/update/leave DIFF) =============
            //   Project each item's coords to pixels, store them as its item LAYOUT (`[[x1,y1],[x2,y2]]`,
            //   +[cpx,cpy] when curveness bends it into a quadratic) and stamp the resolved lineStyle
            //   (incl. the palette stroke) as its 'style' visual — exactly what ECLine reads back. Then
            //   `updateData(data)` reuses + tweens each ECLine across a merge-mode setOption.
            //   A mode flip from polyline drops the persisted Polyline reuse cache first.
            if !_lineEls.isEmpty {
                for (_, old) in _lineEls { _ = group.remove(old) }
                _lineEls.removeAll()
            }

            // Effect points captured per index for the (optional) flying-trail pass after updateData.
            var effectByIdx: [(points: [[Double]], stroke: String?)] = []
            if hasEffect { effectByIdx = Array(repeating: ([], nil), count: count) }

            for i in 0..<count {
                let itemModel = data.getItemModel(i)
                // Resolved lineStyle bag (stroke/lineWidth/opacity/lineDash …) → the item 'style' visual.
                var styleDict = itemModel.getModel("lineStyle").getLineStyle()
                let itemVisualStyle = (data.getItemVisual(i, "style") as? [String: Any]) ?? seriesLineStyle
                let strokeColorStr = linesColorString(itemVisualStyle?["stroke"])
                if let cs = strokeColorStr { styleDict["stroke"] = cs }
                styleDict["fill"] = nil
                data.setItemVisual(i, "style", styleDict)

                let len = seriesModel.getLineCoords(i, &lineCoords)
                if len < 2 { data.setItemLayout(i, nil); continue }
                let p0 = coord.dataToPoint(lineCoords[0])
                let p1 = coord.dataToPoint(lineCoords[1])
                if p0.count < 2 || p1.count < 2
                    || !p0[0].isFinite || !p0[1].isFinite
                    || !p1[0].isFinite || !p1[1].isFinite {
                    data.setItemLayout(i, nil); continue
                }

                var pts: [[Double]] = [[p0[0], p0[1]], [p1[0], p1[1]]]
                let curveness = linesToNumber(itemModel.get(["lineStyle", "curveness"]))
                if curveness != 0 && curveness.isFinite {
                    // pts[2] = quadratic control point (same formula as GraphView's curved edge).
                    let cpx = (p0[0] + p1[0]) / 2 - (p0[1] - p1[1]) * curveness
                    let cpy = (p0[1] + p1[1]) / 2 - (p1[0] - p0[0]) * curveness
                    pts.append([cpx, cpy])
                }
                data.setItemLayout(i, pts)
                if hasEffect { effectByIdx[i] = (pts, strokeColorStr) }
            }

            if !_lineDrawAdded {
                _ = group.add(_lineDraw.group)
                _lineDrawAdded = true
            }
            _lineDraw.updateData(data)

            // Flying-trail effect symbols (chart/lines/EffectLine.swift) — added alongside the LineDraw,
            //   rebuilt each render (their looping animation morph is a documented deferral).
            if hasEffect {
                for i in 0..<count {
                    let e = effectByIdx[i]
                    guard e.points.count >= 2 else { continue }
                    let effectModel = data.getItemModel(i).getModel("effect")
                    if let sym = EffectLine.add(
                        to: group, points: e.points, isPolyline: false,
                        effectModel: effectModel, idx: i, count: count, strokeColor: e.stroke
                    ) {
                        _effectSymbols.append(sym)
                    }
                }
            }

            _prevCount = count
            _prevIsPolyline = false
            self._data = data
            applyClipPath(seriesModel)
            return
        }

        // === Polyline (N-point) — inline persist-and-morph (ECLine models only 2/3-point lines) =======
        //   Clear any LineDraw content from a mode flip, then morph the persisted Polyline elements.
        if _lineDrawAdded { _lineDraw.remove() }

        // Morph iff we already drew the same number of polylines (only values changed); else rebuild.
        let canMorph = !_lineEls.isEmpty && _prevCount == count && _prevIsPolyline == isPolyline
        if !canMorph {
            for (_, old) in _lineEls { _ = group.remove(old) }
            _lineEls.removeAll()
        }

        for i in 0..<count {
            let len = seriesModel.getLineCoords(i, &lineCoords)
            if len < 2 { removeLineEl(i); continue }

            let itemModel = data.getItemModel(i)
            let lineStyle = itemModel.getModel("lineStyle").getLineStyle()
            var style = linesLineStyle(lineStyle)
            let itemVisualStyle = (data.getItemVisual(i, "style") as? [String: Any]) ?? seriesLineStyle
            let strokeColorStr = linesColorString(itemVisualStyle?["stroke"])
            if let cs = strokeColorStr { style.stroke = .string(cs) }

            var points: [VectorArray] = []
            points.reserveCapacity(len)
            for j in 0..<len {
                let p = coord.dataToPoint(lineCoords[j])
                if p.count >= 2 && p[0].isFinite && p[1].isFinite {
                    points.append(VectorArray(p[0], p[1]))
                }
            }
            if points.count < 2 { removeLineEl(i); continue }

            let el: Path
            if let poly = _lineEls[i] as? Polyline {
                poly.useStyle(style)
                poly.pathStyle.fill = nil
                let ptsD = points.map { [$0.x, $0.y] }
                updateProps(poly, ["shape": ["points": ptsD]], seriesModel)
                el = poly
            } else {
                removeLineEl(i)
                var shape = PolylineShape()
                shape.points = points
                let poly = Polyline()
                poly.setShape(shape)
                el = poly
                finishBuildLine(el, i, style)
            }

            data.setItemGraphicEl(i, el)

            if hasEffect {
                let effectModel = itemModel.getModel("effect")
                if let sym = EffectLine.add(
                    to: group, points: points.map { [$0[0], $0[1]] }, isPolyline: true,
                    effectModel: effectModel, idx: i, count: count, strokeColor: strokeColorStr
                ) {
                    _effectSymbols.append(sym)
                }
            }
        }

        _prevCount = count
        _prevIsPolyline = isPolyline
        self._data = data
        applyClipPath(seriesModel)
    }

    // upstream:
    //   const clipPath = seriesModel.get('clip', true) && createClipPath(
    //       (seriesModel.coordinateSystem as Polar | Cartesian2D), false, seriesModel
    //   );
    //   if (clipPath) { this.group.setClipPath(clipPath); } else { this.group.removeClipPath(); }
    // `createClipPath` (helper/createClipPathFromCoordSys) is ported; it handles cartesian2d + polar and
    //   returns nil for anything else (→ removeClipPath). Polar is intentionally NOT a `CoordinateSystem`
    //   conformer (its `dataToPoint(data, clamp?)` doesn't witness the protocol), so the `as? CoordinateSystem`
    //   cast yields nil for polar-based lines → no clip (they draw nothing here anyway).
    private func applyClipPath(_ seriesModel: SeriesModel) {
        let clip = (seriesModel.get("clip", true) as? Bool) ?? true
        let clipPath: Path? = clip
            ? createClipPath(seriesModel.coordinateSystem as? CoordinateSystem, false, seriesModel)
            : nil
        if let clipPath = clipPath {
            self.group.setClipPath(clipPath)
        }
        else {
            self.group.removeClipPath()
        }
    }

    // Finish a freshly-built line element: name it, apply the style, clear the spurious black fill
    //   (Polyline/BezierCurve close into a fillable path; useStyle→createStyle drops the intended
    //   fill:null — visual-parity trap class 1), add it to the group and record it as persisted.
    // PORT-NOTE (deferred): fromSymbol/toSymbol arrow markers, per-line label, and emphasis/blur states DEFERRED.
    private func finishBuildLine(_ el: Path, _ i: Int, _ style: PathStyleProps) {
        el.name = "line"
        el.useStyle(style)
        el.pathStyle.fill = nil
        _ = self.group.add(el)
        _lineEls[i] = el
    }

    // Drop the persisted line element at index `i` (a datum that no longer yields a valid line, or whose
    //   element type changed) so a stale shape can't linger in the reused group.
    private func removeLineEl(_ i: Int) {
        if let old = _lineEls[i] {
            _ = self.group.remove(old)
            _lineEls[i] = nil
        }
    }

    // Drop ALL persisted line + effect elements (coord-system change / remove / dispose).
    private func resetPersistentElements() {
        // `reset()` (not `remove()`): the LineDraw's elements are being dropped, so its DIFF state must go
        //   with them — upstream reaches this path by constructing a fresh LineDraw.
        _lineDraw.reset()
        _largeLineDraw?.remove()
        _isLargeDraw = false
        for (_, old) in _lineEls { _ = self.group.remove(old) }
        _lineEls.removeAll()
        for s in _effectSymbols { _ = self.group.remove(s) }
        _effectSymbols.removeAll()
        _prevCount = -1
        _prevIsPolyline = false
    }

    // upstream: incrementalPrepareRender / incrementalRender / updateTransform / eachRendered
    //   -> PORT-NOTE: incremental/progressive pipeline + updateLayout are not wired in this static view (the core/task pipeline itself is ported).

    // upstream: remove(ecModel, api) { this._lineDraw && this._lineDraw.remove(); this._lineDraw = null; this._clearLayer(api); }
    open override func remove(_ ecModel: GlobalModel, _ api: ExtensionAPI) {
        // PORT-NOTE: _clearLayer (canvas motion-blur layer clear) is host-managed (EChartsView configLayer); the trail symbols are dropped by group.removeAll() below.
        _ = self.group.removeAll()
        // group.removeAll() also detached the LineDraw group — clear its content + the re-add flag so a
        //   later render re-attaches it. Clear the polyline/effect bookkeeping too.
        _lineDraw.reset()
        _lineDrawAdded = false
        // …and likewise the LargeLineDraw (upstream's single `_lineDraw` field holds whichever draw is
        //   active and is nulled out here). Dropping the instance also drops the "added to group" state,
        //   so a later large render re-creates + re-attaches it.
        _largeLineDraw?.remove()
        _largeLineDraw = nil
        _isLargeDraw = false
        _lineEls.removeAll()
        _effectSymbols.removeAll()
        _prevCount = -1
        _prevIsPolyline = false
    }

    // upstream: dispose(ecModel, api) { this.remove(ecModel, api); }
    open override func dispose(_ ecModel: GlobalModel, _ api: ExtensionAPI) {
        self.remove(ecModel, api)
    }
}

// export default LinesView;  -> `open class LinesView` above.

// ---- STATIC-port helpers (not upstream functions) --------------------------------------------------

// `zrUtil`-style lineStyle bag → PathStyleProps (stroke / lineWidth / opacity / lineDash / …), fill
//   cleared (a line/curve/polyline has no fill). Reuses the shared visual-style → PathStyleProps bridge
//   (barStyleFromDict) — the same construction GraphView uses for its edge style (minus strokeNoScale,
//   which the lines `Line` helper does not set).
private func linesLineStyle(_ lineStyle: [String: Any]) -> PathStyleProps {
    var s = barStyleFromDict(lineStyle)
    s.fill = nil
    return s
}

// The palette color lands under the item/series visual style as an EChartsKit `ZRColor.color(String)`
//   or a raw `String`. Bridge both to a solid color string (same bridge as GraphView / LineView).
//   Gradient / pattern out of scope.
private func linesColorString(_ v: Any?) -> String? {
    if let str = v as? String { return str }
    if let zr = v as? EChartsKit.ZRColor, case let .color(str) = zr { return str }
    return nil
}

// INT-vs-DOUBLE-safe numeric coercion for a dynamic option value (curveness may arrive as a bare `Int`
//   literal, `Double`, or `NSNumber`). A bare `as? Double` would silently drop an Int `0`/`1`. Mirrors
//   JS `+curveness`: a missing / non-numeric value yields NaN (treated as "no curve" by the caller).
private func linesToNumber(_ v: Any?) -> Double {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let n = v as? NSNumber { return n.doubleValue }
    return Double.nan
}

// JS truthiness for the `polyline` option (`!!seriesModel.get('polyline')`): Bool as-is, non-zero
//   number, or a non-empty string is truthy; nil / false / 0 / "" is falsy.
private func linesTruthy(_ v: Any?) -> Bool {
    guard let v = v else { return false }
    if let b = v as? Bool { return b }
    if let i = v as? Int { return i != 0 }
    if let d = v as? Double { return d != 0 }
    if let n = v as? NSNumber { return n.doubleValue != 0 }
    if let s = v as? String { return !s.isEmpty }
    return true
}
