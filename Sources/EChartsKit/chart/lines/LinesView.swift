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

// upstream imports (all deferred except linesLayout math / ChartView / SeriesData / Cartesian2D):
//   import LineDraw from '../helper/LineDraw';            -> PORT-TODO: helper/LineDraw NOT ported.
//       LineDraw.updateData is a per-edge enter/update/leave diff that reuses `Line`/`Polyline`
//       helper instances (each reading `data.getItemLayout(i)`), plus fromSymbol/toSymbol arrow
//       markers (ECLinePath) + label + emphasis/blur state. The static render inlines it: one
//       ZRenderKit `Line` / `BezierCurve` / `Polyline` per data item, geometry set directly (same
//       deviation as GraphView's edge loop / TreeView's links).
//   import EffectLine from '../helper/EffectLine';        -> PORT-TODO: EffectLine NOT ported.
//       The moving-dot / trail EFFECT is ANIMATED (CONVENTIONS §5) — DEFERRED behind PORT-TODO.
//   import Line from '../helper/Line';                    -> PORT-TODO: helper/Line NOT ported (inline shape).
//   import Polyline from '../helper/Polyline';            -> PORT-TODO: helper/Polyline NOT ported (inline shape).
//   import EffectPolyline from '../helper/EffectPolyline';-> PORT-TODO: EffectPolyline NOT ported (effect DEFERRED).
//   import LargeLineDraw from '../helper/LargeLineDraw';  -> PORT-TODO: LargeLineDraw NOT ported (large/progressive DEFERRED).
//   import linesLayout from './linesLayout';              -> the per-item dataToPoint + curveness-control-point
//       math is inlined below (see `render`); the layout STAGE is not run — the view projects coords
//       itself, exactly as ScatterView inlines pointsLayout and LineView inlines dataToPoint.
//   import {createClipPath} from '../helper/createClipPathFromCoordSys';
//       -> PORT-TODO: createClipPathFromCoordSys NOT ported — the `clip` option is DEFERRED (no clip path set).
//   import ChartView from '../../view/Chart';             -> ChartView (view/Chart.swift).
//   import LinesSeriesModel from './LinesSeries';         -> sibling LinesSeries.swift (assumed ported alongside).
//   import GlobalModel from '../../model/Global';         -> GlobalModel.
//   import ExtensionAPI from '../../core/ExtensionAPI';   -> ExtensionAPI.
//   import CanvasPainter from 'zrender/src/canvas/Painter';   -> PORT-TODO: motion-blur layer config (effect trail) DEFERRED.
//   import { StageHandlerProgressParams, StageHandlerProgressExecutor } from '../../util/types';
//       -> PORT-TODO: incremental/progressive pipeline (incrementalRender/updateTransform) DEFERRED.
//   import SeriesData from '../../data/SeriesData';       -> SeriesData.
//   import type Polar from '../../coord/polar/Polar';     -> Polar (polar lines are PORT-TODO below).
//   import type Cartesian2D from '../../coord/cartesian/Cartesian2D';   -> Cartesian2D.
//   import Element from 'zrender/src/Element';            -> Element (eachRendered — DEFERRED).
//   import { getIncrementalId } from '../../util/model';  -> PORT-TODO: incremental pipeline DEFERRED.
//   import { getCurrentCanvasPainter } from '../../util/graphic';   -> PORT-TODO: canvas-layer clear (effect) DEFERRED.
//   import { ILineDraw } from '../helper/baseDraw';       -> PORT-TODO: helper/baseDraw NOT ported.

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
    //   PORT-TODO: _lineDraw (LineDraw/LargeLineDraw diff) + the effect/large/incremental flags are
    //   DEFERRED — the static render rebuilds the group each pass, so none of that state is needed.
    private var _data: SeriesData?

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
        // PORT-TODO: `getCurrentCanvasPainter` layer clear + `configLayer` motion-blur (the trail effect's
        //   `lastFrameAlpha`) — DEFERRED (effect is animated, CONVENTIONS §5).
        // PORT-TODO: `_showEffect`/`trailLength` → EffectLine/EffectPolyline moving-dot render — DEFERRED.
        // PORT-TODO: `seriesModel.get('clip')` → createClipPath(coordSys) + group.setClipPath — DEFERRED
        //   (helper/createClipPathFromCoordSys not ported).

        // PORT-TODO: polar / geo lines DEFERRED (only Cartesian2D wired). Upstream's coord system is
        //   `Polar | Cartesian2D | Geo`; linesLayout calls `coordSys.dataToPoint(coord)` generically —
        //   the same call works for Polar once its lines path is exercised, but geo is not ported.
        guard let coord = seriesModelBase.coordinateSystem as? Cartesian2D else { return }

        let data: SeriesData = seriesModel.getData()

        // const isPolyline = !!seriesModel.get('polyline');
        let isPolyline = linesTruthy(seriesModel.get("polyline", false))

        // upstream: this._hasEffet = seriesModel.get(['effect', 'show']); — when set, the LineDraw draws
        //   `EffectLine`/`EffectPolyline` (a moving trail symbol) instead of a plain `Line`/`Polyline`.
        //   The static port keeps the inline line shapes and ADDS the animated trail symbol (see
        //   chart/lines/EffectLine.swift) per item when the flag is on.
        let hasEffect = linesTruthy(seriesModel.get(["effect", "show"]))

        // Line color: `visualStyleAccessPath = 'lineStyle'`, `visualDrawType = 'stroke'` — the visual/style
        //   stage writes the palette color into the series visual `style` bag under `stroke` (item visuals
        //   override it). Same bridge as GraphView's edge coloring / LineView's `colorString`.
        let seriesLineStyle = data.getVisual("style") as? [String: Any]

        let group = self.group
        _ = group.removeAll()

        // Reused per-item data-space coord buffer — upstream `linesLayout` reuses one `lineCoords: number[][]`
        //   across the whole progress loop; `getLineCoords(i, out)` fills it and returns the point count.
        var lineCoords: [[Double]] = []

        for i in 0..<data.count() {
            // const len = seriesModel.getLineCoords(i, lineCoords);
            let len = seriesModel.getLineCoords(i, &lineCoords)
            if len < 2 { continue }

            // Per-item lineStyle → PathStyleProps (stroke/lineWidth/opacity/…); fill cleared (lines don't
            //   fill). `itemModel.getModel('lineStyle').getLineStyle()` — same as GraphView's edge style.
            let itemModel = data.getItemModel(i)
            let lineStyle = itemModel.getModel("lineStyle").getLineStyle()
            var style = linesLineStyle(lineStyle)
            // Override stroke with the resolved visual color: item visual `style.stroke` first, then the
            //   series visual `style.stroke` (the palette color the visual/style stage stored).
            let itemVisualStyle = (data.getItemVisual(i, "style") as? [String: Any]) ?? seriesLineStyle
            let strokeColorStr = linesColorString(itemVisualStyle?["stroke"])
            if let cs = strokeColorStr { style.stroke = .string(cs) }

            // Pixel point list captured for the (optional) flying-trail effect — mirrors upstream
            //   `data.getItemLayout(idx)`: [p0, p1] (+ control point at index 2 for a curved line), or
            //   all polyline points. Filled by whichever geometry branch runs below.
            var effectPoints: [[Double]] = []

            let el: Path
            if isPolyline {
                // --- Polyline (multi-point) ---------------------------------------------------------
                //   upstream linesLayout (isPolyline branch): pts[j] = coordSys.dataToPoint(lineCoords[j])
                //   for all j; the Polyline helper builds a PolylineShape from that point list.
                var points: [VectorArray] = []
                points.reserveCapacity(len)
                for j in 0..<len {
                    let p = coord.dataToPoint(lineCoords[j])
                    if p.count >= 2 && p[0].isFinite && p[1].isFinite {
                        points.append(VectorArray(p[0], p[1]))
                    }
                }
                if points.count < 2 { continue }
                if hasEffect { effectPoints = points.map { [$0[0], $0[1]] } }
                var shape = PolylineShape()
                shape.points = points
                let polyline = Polyline()
                polyline.setShape(shape)
                el = polyline
            }
            else {
                // --- Line / BezierCurve (two-point, optional curveness) -----------------------------
                //   upstream linesLayout (non-polyline branch):
                //     pts[0] = coordSys.dataToPoint(lineCoords[0]);
                //     pts[1] = coordSys.dataToPoint(lineCoords[1]);
                //     const curveness = itemModel.get(['lineStyle', 'curveness']);
                //     if (+curveness) { pts[2] = [ ...quadratic control point... ]; }
                //   A third (control) point selects a BezierCurve over a straight Line — the same branch
                //   the `Line` helper uses when it reads getItemLayout back out.
                let p0 = coord.dataToPoint(lineCoords[0])
                let p1 = coord.dataToPoint(lineCoords[1])
                if p0.count < 2 || p1.count < 2
                    || !p0[0].isFinite || !p0[1].isFinite
                    || !p1[0].isFinite || !p1[1].isFinite {
                    continue
                }

                // const curveness = itemModel.get(['lineStyle', 'curveness']);  /  if (+curveness)
                let curveness = linesToNumber(itemModel.get(["lineStyle", "curveness"]))
                if curveness != 0 && curveness.isFinite {
                    // pts[2] = [
                    //   (pts[0][0] + pts[1][0]) / 2 - (pts[0][1] - pts[1][1]) * curveness,
                    //   (pts[0][1] + pts[1][1]) / 2 - (pts[1][0] - pts[0][0]) * curveness
                    // ]
                    let cpx = (p0[0] + p1[0]) / 2 - (p0[1] - p1[1]) * curveness
                    let cpy = (p0[1] + p1[1]) / 2 - (p1[0] - p0[0]) * curveness
                    // Curved line → the effect symbol follows the quadratic p0 → (cpx,cpy) → p1.
                    if hasEffect { effectPoints = [[p0[0], p0[1]], [p1[0], p1[1]], [cpx, cpy]] }
                    var shape = BezierCurveShape()
                    shape.x1 = p0[0]
                    shape.y1 = p0[1]
                    shape.x2 = p1[0]
                    shape.y2 = p1[1]
                    // Quadratic: single control point (cpx1/cpy1; cpx2/cpy2 unset) — same as GraphView.
                    shape.cpx1 = cpx
                    shape.cpy1 = cpy
                    let curve = BezierCurve()
                    curve.setShape(shape)
                    el = curve
                }
                else {
                    // Straight line → the effect symbol follows p0 → p1 (midpoint control point).
                    if hasEffect { effectPoints = [[p0[0], p0[1]], [p1[0], p1[1]]] }
                    var shape = LineShape()
                    shape.x1 = p0[0]
                    shape.y1 = p0[1]
                    shape.x2 = p1[0]
                    shape.y2 = p1[1]
                    let line = Line()
                    line.setShape(shape)
                    el = line
                }
            }

            el.name = "line"
            el.useStyle(style)
            // A Polyline/BezierCurve closes visually into a fillable path; `useStyle`→createStyle lays the
            // style over DEFAULT_PATH_STYLE (fill '#000') and SKIPS the nil `fill`, so the intended
            // fill:null is dropped and the line fills solid black (visual-parity trap class 1). Clear it.
            el.pathStyle.fill = nil
            // PORT-TODO: fromSymbol/toSymbol arrow markers (ECLinePath.setLinePoints + Symbol),
            //   per-line label, and setStatesStylesFromModel/emphasis/blur — DEFERRED (states/label,
            //   helper/LinePath, helper/Symbol not ported).
            _ = group.add(el)
            data.setItemGraphicEl(i, el)

            // upstream: when `effect.show`, the LineDraw uses EffectLine/EffectPolyline — a moving trail
            //   symbol animated along the line. The static port keeps the line above and ADDS the animated
            //   symbol here (chart/lines/EffectLine.swift). Per-item effect model (upstream
            //   `lineData.getItemModel(idx).getModel('effect')`).
            if hasEffect && effectPoints.count >= 2 {
                let effectModel = itemModel.getModel("effect")
                EffectLine.add(
                    to: group,
                    points: effectPoints,
                    isPolyline: isPolyline,
                    effectModel: effectModel,
                    idx: i,
                    count: data.count(),
                    strokeColor: strokeColorStr
                )
            }
        }

        self._data = data
    }

    // upstream: incrementalPrepareRender / incrementalRender / updateTransform / eachRendered
    //   -> PORT-TODO: incremental/progressive pipeline + updateLayout DEFERRED (core/task not ported).

    // upstream: remove(ecModel, api) { this._lineDraw && this._lineDraw.remove(); this._lineDraw = null; this._clearLayer(api); }
    open override func remove(_ ecModel: GlobalModel, _ api: ExtensionAPI) {
        // PORT-TODO: _clearLayer (canvas motion-blur layer clear) DEFERRED — effect not ported.
        _ = self.group.removeAll()
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
