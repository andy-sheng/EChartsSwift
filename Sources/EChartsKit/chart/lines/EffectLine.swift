// Ported from echarts/src/chart/helper/EffectLine.ts (+ EffectPolyline.ts) — keep in sync with upstream.
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

// upstream: `class EffectLine extends graphic.Group` — a per-edge Group that holds the static line
//   (`createLine`) PLUS a moving `createSymbol` symbol animated ALONG the line via `symbol.animate('',
//   loop).when(period, {__t: 1}).during(() => this._updateSymbolPosition(symbol))`. `EffectPolyline`
//   subclasses it, overriding the point-parametrization to walk a multi-segment polyline by arc-length.
//
// DEVIATIONS (documented — same class as the rest of the static lines port):
//   1. The static `LinesView` already builds the line shapes inline (no `helper/Line`), so this port is
//      a caseless-enum HELPER that only adds the *moving symbol* + its looping animator to the view
//      group — the `EffectLine`/`EffectPolyline` Group wrapper is collapsed into that call site.
//   2. Upstream drives a synthetic `symbol.__t` TRACK (0→1, or 0→2 for roundTrip) and reads it back in
//      the `during` callback. `Element.animationGet/animationSet` are `public` (not `open`) so a synthetic
//      `__t` key cannot be witnessed from EChartsKit; instead the animator runs with `duration()` (a
//      forced, track-less looping clip) and the `during` callback's `percent` parameter IS `__t / maxT`.
//      Mathematically identical: `__t = percent * maxT`.
//   3. The `line`/`rect`/`roundRect` "continuity trail" (stretch scaleY between frames) tracks
//      `__lastT`/`__lastPos`/`symbolScale`/`symbolType` in the per-symbol `State` (see below). It only
//      applies to those three symbolTypes; the default effect symbol is `circle`, unaffected.

import Foundation
import ZRenderKit

// caseless-enum namespace for the (upstream class) EffectLine / EffectPolyline logic.
public enum EffectLine {

    // Per-symbol animation geometry — the port's analog of upstream's `symbol.__p1/__p2/__cp1` (quadratic)
    //   and EffectPolyline's `this._points/_offsets/_length` (arc-length walk). Captured by the `during`
    //   closure and reused every frame (upstream mutates the same fields in place).
    private final class State {
        // Quadratic (non-polyline): p1 → cp1 → p2.
        var p1: [Double] = [0, 0]
        var p2: [Double] = [0, 0]
        var cp1: [Double] = [0, 0]
        // Polyline: the pixel points + normalized cumulative arc-length offsets (0…1).
        var points: [[Double]] = []
        var offsets: [Double] = []
        var isPolyline = false
        // roundTrip → animate __t over 0…2 (out and back); otherwise 0…1.
        var maxT: Double = 1
        // EffectPolyline frame-walk cursors (upstream `_lastFrame` / `_lastFramePercent`).
        var lastFrame = 0
        var lastFramePercent: Double = 0
        // Continuity-trail state (upstream `symbol.__lastT` / `EffectLine._symbolType` / `_symbolScale`).
        //   `lastT` is `undefined` until the first frame — nil here mirrors that.
        var lastT: Double?
        var symbolType = "circle"
        var symbolScaleY: Double = 1
    }

    /// Build the moving trail symbol for one line item, add it to `group`, and start its looping
    /// animator. Mirrors `EffectLine._updateEffectSymbol` + `_updateEffectAnimation` + `_animateSymbol`.
    ///
    /// - points: the pixel point list (upstream `data.getItemLayout(idx)`). Non-polyline: `[p0, p1]`
    ///   with an optional curve control point at index 2. Polyline: all polyline pixel points.
    /// - effectModel: the item/series `effect` sub-model (upstream `itemModel.getModel('effect')`).
    /// - strokeColor: the resolved line stroke color string (upstream `lineStyle.stroke` fallback).
    @discardableResult
    public static func add(
        to group: Group,
        points: [[Double]],
        isPolyline: Bool,
        effectModel: Model,
        idx: Int,
        count: Int,
        strokeColor: String?
    ) -> Path? {
        guard points.count >= 2 else { return nil }

        // ---- _updateEffectSymbol ---------------------------------------------------------------------
        // let size = effectModel.get('symbolSize'); if (!isArray) size = [size, size];
        let (sizeW, sizeH) = symbol.normalizeSymbolSize(effectModel.get("symbolSize") ?? 3.0)
        // const symbolType = effectModel.get('symbol');
        let symbolType = (effectModel.get("symbol") as? String) ?? "circle"
        // const color = effectModel.get('color') || (lineStyle && lineStyle.stroke);
        let colorStr = (effectModel.get("color") as? String) ?? strokeColor

        // createSymbol(symbolType, -0.5, -0.5, 1, 1, color) — a UNIT symbol centered on the local origin;
        //   scaleX/scaleY apply symbolSize (upstream), and x/y translate it along the line each frame.
        let colorZR: ZRenderKit.ZRColor? = colorStr.map { .string($0) }
        guard let sym = symbol.createSymbol(symbolType, -0.5, -0.5, 1, 1, colorZR) as? Path else {
            return nil
        }
        sym.name = "effectSymbol"
        sym.z2 = 100
        sym.scaleX = sizeW
        sym.scaleY = sizeH
        // Shadow color is same with color in default (upstream setStyle('shadowColor', color)).
        if let colorStr = colorStr { sym.pathStyle.shadowColor = colorStr }
        // upstream: symbol.setStyle(effectModel.getItemStyle(['color']));  — merge the effect
        //   sub-model's item-style props (opacity/border/shadow…) onto the trail symbol. `color`
        //   is excluded so the fill set by createSymbol is preserved.
        applyEffectItemStyle(sym, effectModel.getItemStyle(["color"]))

        // ---- _updateEffectAnimation ------------------------------------------------------------------
        // let period = effectModel.get('period') * 1000;
        var period = (effectNum(effectModel.get("period")) ?? 4.0) * 1000
        let loop = effectTruthy(effectModel.get("loop"), default: true)
        let roundTrip = effectTruthy(effectModel.get("roundTrip"), default: false)
        let constantSpeed = effectNum(effectModel.get("constantSpeed")) ?? 0

        let state = State()
        state.isPolyline = isPolyline
        state.maxT = roundTrip ? 2 : 1
        state.symbolType = symbolType          // upstream EffectLine._symbolType
        state.symbolScaleY = sizeH             // upstream EffectLine._symbolScale[1]
        updateAnimationPoints(state, points)

        // if (constantSpeed > 0) period = lineLength / constantSpeed * 1000;
        if constantSpeed > 0 {
            let lineLength = getLineLength(state)
            if lineLength > 0 { period = lineLength / constantSpeed * 1000 }
        }

        // const delayExpr = retrieve(effectModel.get('delay'), idx => idx/count * period/3);
        let delayNum: Double
        if let d = effectNum(effectModel.get("delay")) {
            delayNum = d
        } else {
            delayNum = count > 0 ? Double(idx) / Double(count) * period / 3 : 0
        }

        // Establish a visible baseline (t = 0) so the symbol shows at the line start even if the
        //   animation loop never ticks (upstream sets ignore=true and waits for the first `during`;
        //   the static PNG oracle advances every clip, but a plain render should still show the dot).
        updateSymbolPosition(state, sym, percent: 0)

        _ = group.add(sym)

        // ---- _animateSymbol --------------------------------------------------------------------------
        // symbol.animate('', loop).when(roundTrip ? period*2 : period, {__t: roundTrip ? 2 : 1})
        //   .delay(delayNum).during(() => _updateSymbolPosition(symbol));  if (!loop) animator.done(remove)
        if period > 0 {
            let life = roundTrip ? period * 2 : period
            let animator = sym.animate("", loop)
                .duration(life)                 // track-less forced clip (see DEVIATION 2)
                .delay(delayNum)
                .during { [weak sym] _, percent in
                    guard let sym = sym else { return }
                    updateSymbolPosition(state, sym, percent: percent)
                }
            if !loop {
                animator.done { [weak group, weak sym] in
                    guard let group = group, let sym = sym else { return }
                    _ = group.remove(sym)
                }
            }
            animator.start()
        }

        return sym
    }

    // upstream EffectLine._updateAnimationPoints / EffectPolyline._updateAnimationPoints
    private static func updateAnimationPoints(_ state: State, _ points: [[Double]]) {
        if state.isPolyline {
            state.points = points
            var accLen: [Double] = [0]
            var len: Double = 0
            for i in 1..<points.count {
                len += dist(points[i - 1], points[i])
                accLen.append(len)
            }
            if len == 0 {
                state.offsets = []
                return
            }
            for i in 0..<accLen.count { accLen[i] /= len }
            state.offsets = accLen
        } else {
            state.p1 = points[0]
            state.p2 = points[1]
            // symbol.__cp1 = points[2] || midpoint(p1, p2)
            if points.count > 2 {
                state.cp1 = points[2]
            } else {
                state.cp1 = [
                    (points[0][0] + points[1][0]) / 2,
                    (points[0][1] + points[1][1]) / 2
                ]
            }
        }
    }

    // upstream EffectLine._getLineLength / EffectPolyline._getLineLength
    private static func getLineLength(_ state: State) -> Double {
        if state.isPolyline {
            // The EffectPolyline `_length` (total arc length) — recomputed from the points.
            guard state.points.count >= 2 else { return 0 }
            var len: Double = 0
            for i in 1..<state.points.count { len += dist(state.points[i - 1], state.points[i]) }
            return len
        }
        // Not so accurate: dist(p1,cp1) + dist(cp1,p2)
        return dist(state.p1, state.cp1) + dist(state.cp1, state.p2)
    }

    // upstream EffectLine._updateSymbolPosition / EffectPolyline._updateSymbolPosition.
    //   `percent` (0…1 per loop) is the port's `__t / maxT` (see DEVIATION 2), so `__t = percent * maxT`.
    private static func updateSymbolPosition(_ state: State, _ sym: Path, percent: Double) {
        let tt = percent * state.maxT               // upstream symbol.__t (0…1, or 0…2 roundTrip)
        let t = tt <= 1 ? tt : 2 - tt

        if state.isPolyline {
            let offsets = state.offsets
            let points = state.points
            let len = points.count
            if offsets.isEmpty { return }   // has length 0

            var frame: Int
            if t < state.lastFramePercent {
                let start = Swift.min(state.lastFrame + 1, len - 1)
                frame = start
                while frame >= 0 {
                    if offsets[frame] <= t { break }
                    frame -= 1
                }
                frame = Swift.max(0, Swift.min(frame, len - 2))
            } else {
                frame = state.lastFrame
                while frame < len {
                    if offsets[frame] > t { break }
                    frame += 1
                }
                frame = Swift.min(frame - 1, len - 2)
                frame = Swift.max(0, frame)
            }

            let p = (t - offsets[frame]) / (offsets[frame + 1] - offsets[frame])
            let p0 = points[frame]
            let p1 = points[frame + 1]
            sym.x = p0[0] * (1 - p) + p * p1[0]
            sym.y = p0[1] * (1 - p) + p * p1[1]

            let tx = tt <= 1 ? p1[0] - p0[0] : p0[0] - p1[0]
            let ty = tt <= 1 ? p1[1] - p0[1] : p0[1] - p1[1]
            sym.rotation = -atan2(ty, tx) - Double.pi / 2

            state.lastFrame = frame
            state.lastFramePercent = t
        } else {
            let p1 = state.p1
            let p2 = state.p2
            let cp1 = state.cp1
            // upstream: `const pos = [symbol.x, symbol.y]; const lastPos = pos.slice();` — capture the
            //   PREVIOUS pixel position before overwriting, for the continuity-trail stretch below.
            let lastPos = [sym.x, sym.y]
            var posX = curve.quadraticAt(p1[0], cp1[0], p2[0], t)
            var posY = curve.quadraticAt(p1[1], cp1[1], p2[1], t)

            // Tangent
            let tx = tt <= 1 ? curve.quadraticDerivativeAt(p1[0], cp1[0], p2[0], t)
                             : curve.quadraticDerivativeAt(p2[0], cp1[0], p1[0], 1 - t)
            let ty = tt <= 1 ? curve.quadraticDerivativeAt(p1[1], cp1[1], p2[1], t)
                             : curve.quadraticDerivativeAt(p2[1], cp1[1], p1[1], 1 - t)
            sym.rotation = -atan2(ty, tx) - Double.pi / 2

            // enable continuity trail for 'line', 'rect', 'roundRect' symbolType
            if state.symbolType == "line" || state.symbolType == "rect" || state.symbolType == "roundRect" {
                if let lastT = state.lastT, lastT < tt {
                    sym.scaleY = dist(lastPos, [posX, posY]) * 1.05
                    // make sure the last segment render within endPoint
                    if t == 1 {
                        posX = lastPos[0] + (posX - lastPos[0]) / 2
                        posY = lastPos[1] + (posY - lastPos[1]) / 2
                    }
                } else if state.lastT == 1 {
                    // After first loop, __t does NOT start with 0, so connect p1 to pos directly.
                    sym.scaleY = 2 * dist(p1, [posX, posY])
                } else {
                    sym.scaleY = state.symbolScaleY
                }
            }
            state.lastT = tt                    // upstream symbol.__lastT = symbol.__t
            sym.x = posX
            sym.y = posY
        }
    }

    // upstream: `symbol.setStyle(effectModel.getItemStyle(['color']))` — MERGE the effect sub-model's
    //   item-style props onto the trail symbol's existing style (the `color`/`fill` set by createSymbol
    //   is preserved because 'color' is excluded from the mapper). Only keys the mapper actually
    //   produced (i.e. the user set on `effect`) are present, so this merges just those fields — the
    //   analog of upstream's dynamic-key `setStyle(obj)` extend. Numeric option values may box as Int
    //   OR Double (see effectNum), so route numbers through the coercion helper.
    private static func applyEffectItemStyle(_ sym: Path, _ dict: [String: Any]) {
        if dict.isEmpty { return }
        if let v = zrPaintFromStyleValue(dict["stroke"]) { sym.pathStyle.stroke = v }
        if let v = effectNum(dict["lineWidth"]) { sym.pathStyle.lineWidth = v }
        if let v = effectNum(dict["opacity"]) { sym.pathStyle.opacity = v }
        if let v = effectNum(dict["shadowBlur"]) { sym.pathStyle.shadowBlur = v }
        if let v = effectNum(dict["shadowOffsetX"]) { sym.pathStyle.shadowOffsetX = v }
        if let v = effectNum(dict["shadowOffsetY"]) { sym.pathStyle.shadowOffsetY = v }
        if let v = dict["shadowColor"] as? String { sym.pathStyle.shadowColor = v }
        switch dict["lineDash"] {
        case let str as String:
            if str == "dashed" { sym.pathStyle.lineDash = .dashed }
            else if str == "dotted" { sym.pathStyle.lineDash = .dotted }
            else if str == "solid" { sym.pathStyle.lineDash = .solid }
        case let arr as [Double]: sym.pathStyle.lineDash = .values(arr)
        case let arri as [Int]: sym.pathStyle.lineDash = .values(arri.map(Double.init))
        default: break
        }
        if let v = effectNum(dict["lineDashOffset"]) { sym.pathStyle.lineDashOffset = v }
        if let v = dict["lineCap"] as? String { sym.pathStyle.lineCap = v }
        if let v = dict["lineJoin"] as? String { sym.pathStyle.lineJoin = v }
        if let v = effectNum(dict["miterLimit"]) { sym.pathStyle.miterLimit = v }
        sym.dirtyStyle()
    }

    // vec2.dist for a [x, y] point pair.
    private static func dist(_ a: [Double], _ b: [Double]) -> Double {
        let dx = a[0] - b[0]
        let dy = a[1] - b[1]
        return (dx * dx + dy * dy).squareRoot()
    }
}

// INT-vs-DOUBLE-safe read of a numeric effect option (period/constantSpeed/delay/symbolSize may box as
//   Int OR Double). A bare `as? Double` drops an Int literal — route through Int/Double/NSNumber.
private func effectNum(_ v: Any?) -> Double? {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let n = v as? NSNumber { return n.doubleValue }
    return nil
}

// JS truthiness with an explicit default when the key is absent (loop defaults true, roundTrip false).
private func effectTruthy(_ v: Any?, default def: Bool) -> Bool {
    guard let v = v else { return def }
    if let b = v as? Bool { return b }
    if let i = v as? Int { return i != 0 }
    if let d = v as? Double { return d != 0 }
    if let n = v as? NSNumber { return n.doubleValue != 0 }
    if let s = v as? String { return !s.isEmpty }
    return true
}
