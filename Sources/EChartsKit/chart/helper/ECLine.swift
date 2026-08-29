// Ported from echarts/src/chart/helper/Line.ts — keep in sync with upstream.
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
//   import ECLinePath from './LinePath';   -> PORT-NOTE: upstream's ECLinePath is ONE custom Path whose
//       `buildPath` draws a straight segment OR a quadratic curve depending on whether `cpx1`/`cpy1`
//       are finite. This port models it with the two DISTINCT ZRenderKit shapes the golden tests
//       assert: a straight `Line` (no control point) or a `BezierCurve` (control point present), each
//       named "line". `createLine`/`setLineShapePoints` below pick + drive the right one.
//   import * as symbolUtil from '../../util/symbol';   -> `symbol.createSymbol` / `normalizeSymbolSize`.
//   import { toggleHoverEmphasis, enterEmphasis, leaveEmphasis, SPECIAL_STATES } from '../../util/states';
//   import {getLabelStatesModels, setLabelStyle} from '../../label/labelStyle';
//   import {round} from '../../util/number';   -> `number.round`.
//
// PORT-NOTE (beforeUpdate): upstream places the from/to symbols + label along the line EVERY frame in
//   `Element#beforeUpdate`. `beforeUpdate` is `public` (not `open`) in ZRenderKit and cannot be
//   overridden from this module, so `_positionEndsAndLabel` is driven from the `initProps`/`updateProps`
//   `during` callbacks instead. This preserves the enter GROW effect and keeps symbols/labels attached
//   to a reused line while its coordinates tween during relayout.

// upstream: const SYMBOL_CATEGORIES = ['fromSymbol', 'toSymbol'];  — these are the VISUAL-key prefixes
//   (getItemVisual(idx, 'fromSymbol' / 'fromSymbolSize' / …), matching upstream + the markLine visuals).
private let SYMBOL_CATEGORIES = ["fromSymbol", "toSymbol"]

// PORT-NOTE (deviation): upstream names each end symbol 'fromSymbol' / 'toSymbol'; this port names them
//   'from' / 'to' (the convention MarkLineView's former stand-in used, asserted by ZZMarkerTests). Only
//   the child NAME differs; the visual reads still use the full 'fromSymbol' prefix.
private func shortSymbolName(_ category: String) -> String {
    return category == "fromSymbol" ? "from" : "to"
}

// upstream: export interface LineDrawSeriesScope — the per-series style/label/state bag LineDraw
//   computes once (makeSeriesScope) and each ECLine consumes in `_updateCommonStl`.
public struct LineDrawSeriesScope {
    public var lineStyle: [String: Any]?
    public var emphasisLineStyle: [String: Any]?
    public var blurLineStyle: [String: Any]?
    public var selectLineStyle: [String: Any]?
    public var labelStatesModels: LabelStatesModels = [:]
    public var focus: InnerFocus?
    public var blurScope: BlurScope?
    public var emphasisDisabled: Bool = false
    public init() {}
}

// upstream: function makeSymbolTypeValue(name, lineData, idx) — a signature string that changes iff the
//   symbol needs rebuilding (type/size/offset/rotate/keepAspect changed).
private func makeSymbolTypeValue(_ name: String, _ lineData: SeriesData, _ idx: Int) -> String? {
    let symbolType = lineData.getItemVisual(idx, name) as? String
    if symbolType == nil || symbolType == "none" {
        return symbolType
    }
    let symbolSize = lineData.getItemVisual(idx, name + "Size") ?? 0
    let symbolRotate = lineData.getItemVisual(idx, name + "Rotate")
    let symbolOffset = lineData.getItemVisual(idx, name + "Offset")
    let symbolKeepAspect = lineData.getItemVisual(idx, name + "KeepAspect")
    let symbolSizeArr = symbol.normalizeSymbolSize(symbolSize)
    let symbolOffsetArr = symbol.normalizeSymbolOffset(symbolOffset ?? 0, [symbolSizeArr.0, symbolSizeArr.1]) ?? (0, 0)
    return "\(symbolType!)\(symbolSizeArr.0),\(symbolSizeArr.1)\(symbolOffsetArr.0),\(symbolOffsetArr.1)"
        + "\(eclineNumStr(symbolRotate))\(eclineBoolStr(symbolKeepAspect))"
}

// upstream: function createSymbol(name, lineData, idx) — build the from/to end symbol Path (centered at
//   origin so the rotation pivots on the endpoint). Returns (nil, nil) for symbol type 'none'/absent.
//   The second tuple member is upstream's `__specifiedRotation` (radians): a user-set symbolRotate that
//   compulsively overrides the tangent rotation (fix #12388); nil/NaN → follow the tangent.
private func makeSymbol(_ name: String, _ lineData: SeriesData, _ idx: Int) -> (Path?, Double?) {
    let symbolType = lineData.getItemVisual(idx, name) as? String
    guard let symbolType = symbolType, symbolType != "none" else { return (nil, nil) }

    let symbolSize = lineData.getItemVisual(idx, name + "Size") ?? 0
    let symbolRotate = lineData.getItemVisual(idx, name + "Rotate")
    let symbolOffset = lineData.getItemVisual(idx, name + "Offset")
    let symbolKeepAspect = lineData.getItemVisual(idx, name + "KeepAspect") as? Bool

    let symbolSizeArr = symbol.normalizeSymbolSize(symbolSize)
    let symbolOffsetArr = symbol.normalizeSymbolOffset(symbolOffset ?? 0, [symbolSizeArr.0, symbolSizeArr.1]) ?? (0, 0)

    let symbolPath = symbol.createSymbol(
        symbolType,
        -symbolSizeArr.0 / 2 + symbolOffsetArr.0,
        -symbolSizeArr.1 / 2 + symbolOffsetArr.1,
        symbolSizeArr.0,
        symbolSizeArr.1,
        nil,
        symbolKeepAspect
    )

    var specifiedRotation: Double? = nil
    if let r = eclineToNumber(symbolRotate), !r.isNaN {
        specifiedRotation = r * Double.pi / 180
    }

    guard let path = symbolPath as? Path else { return (nil, nil) }
    path.name = shortSymbolName(name)
    return (path, specifiedRotation)
}

// upstream: function createLine(points) — the "line" child. A straight `Line` when there is no control
//   point, a `BezierCurve` (quadratic) when points[2] is present. Named "line", subpixel-optimized.
private func createLine(_ points: [[Double]]) -> Path {
    if pointsAreCurved(points) {
        let curve = BezierCurve()
        curve.name = "line"
        var shape = BezierCurveShape()
        setCurveShapePoints(&shape, points)
        curve.setShape(shape)
        return curve
    }
    let line = Line()
    line.name = "line"
    var shape = LineShape()
    setLineShapePoints(&shape, points)
    line.setShape(shape)
    return line
}

private func pointsAreCurved(_ points: [[Double]]) -> Bool {
    return points.count >= 3 && points[2].count >= 2
        && points[2][0].isFinite && points[2][1].isFinite
}

// upstream: function setLinePoints(targetShape, points) — straight variant.
private func setLineShapePoints(_ shape: inout LineShape, _ points: [[Double]]) {
    shape.x1 = points[0][0]
    shape.y1 = points[0][1]
    shape.x2 = points[1][0]
    shape.y2 = points[1][1]
    shape.percent = 1
}

// upstream: function setLinePoints(targetShape, points) — curve variant (cpx1/cpy1 from points[2]).
private func setCurveShapePoints(_ shape: inout BezierCurveShape, _ points: [[Double]]) {
    shape.x1 = points[0][0]
    shape.y1 = points[0][1]
    shape.x2 = points[1][0]
    shape.y2 = points[1][1]
    shape.percent = 1
    if points.count >= 3, points[2].count >= 2 {
        shape.cpx1 = points[2][0]
        shape.cpy1 = points[2][1]
    } else {
        shape.cpx1 = Double.nan
        shape.cpy1 = Double.nan
    }
}

// upstream: class Line extends graphic.Group  — the per-edge line ELEMENT (Group holding the "line"
//   child + fromSymbol/toSymbol + a textContent label). Renamed `ECLine` in the port so it does not
//   collide with the `Line` SHAPE (ZRenderKit/Graphic/Shape/Line.swift), which is the drawn child here.
public final class ECLine: Group {

    private var _fromSymbolType: String?
    private var _toSymbolType: String?

    // upstream `(symbol as LineECSymbol).__specifiedRotation` lives on the symbol Path; the port's
    //   symbol Path has no such field, so the two end symbols' specified rotations are stored here.
    private var _fromSpecifiedRotation: Double?
    private var _toSpecifiedRotation: Double?

    // Label placement state (upstream stores these as `label.__position` / `__labelDistance` /
    //   `__align` / `__verticalAlign`; there is exactly one label per ECLine, so they live here).
    private var _labelPosition: String?
    private var _labelDistance: [Double] = [5, 5]
    private var _labelAlign: TextAlign?
    private var _labelVerticalAlign: TextVerticalAlign?
    private var _linePoints: [[Double]] = []

    // upstream: constructor(lineData, idx, seriesScope?) { super(); this._createLine(...); }
    public init(_ lineData: SeriesData, _ idx: Int, _ seriesScope: LineDrawSeriesScope?) {
        super.init()
        self._createLine(lineData, idx, seriesScope)
    }

    // upstream: _createLine(lineData, idx, seriesScope?)
    private func _createLine(_ lineData: SeriesData, _ idx: Int, _ seriesScope: LineDrawSeriesScope?) {
        let seriesModel = lineData.hostModel
        let linePoints = eclinePoints(lineData.getItemLayout(idx))
        self._linePoints = linePoints
        let z2 = eclineToNumber(lineData.getItemVisual(idx, "z2"))
        let line = createLine(linePoints)
        // line.shape.percent = 0 — grow from x1,y1 toward x2,y2.
        setChildPercent(line, 0)
        line.z2 = z2 ?? 0
        // graphic.initProps(line, { z2, shape: { percent: 1 } }, seriesModel, idx)
        let during: (Double) -> Void = { [weak self] percent in
            self?._growEnds(line, percent)
        }
        initProps(line, ["shape": ["percent": 1.0] as [String: Any]], seriesModel, idx, nil, during)

        _ = self.add(line)

        // symbols must be added AFTER the line so their position/rotation update is one frame FRESH.
        for symbolCategory in SYMBOL_CATEGORIES {
            let (sym, specifiedRotation) = makeSymbol(symbolCategory, lineData, idx)
            _ = self.add(sym)
            setSpecifiedRotation(symbolCategory, specifiedRotation)
            setSymbolTypeKey(symbolCategory, makeSymbolTypeValue(symbolCategory, lineData, idx))
        }

        self._updateCommonStl(lineData, idx, seriesScope)
        self._positionEndsAndLabel(linePoints)

        // Enter grow (Line.ts: `line.shape.percent = 0` + initProps to 1). Symbols scale in from 0; the
        //   `to` symbol rides the growing line. If animation is disabled, initProps already snapped
        //   percent to 1 — finalize immediately.
        if childPercent(line) >= 1 {
            _growEnds(line, 1)
        } else {
            _growEnds(line, 0)
        }
    }

    // upstream: updateData(lineData, idx, seriesScope)
    public func updateData(_ lineData: SeriesData, _ idx: Int, _ seriesScope: LineDrawSeriesScope?) {
        let seriesModel = lineData.hostModel
        let linePoints = eclinePoints(lineData.getItemLayout(idx))
        self._linePoints = linePoints

        var line = self.childOfName("line") as? Path
        let needCurve = pointsAreCurved(linePoints)
        let isCurrentCurve = line is BezierCurve

        if line == nil || needCurve != isCurrentCurve {
            // Element TYPE changed (straight <-> curved). Distinct ZRenderKit shapes cannot morph
            //   between each other, so drop the old child and build a fresh one (no tween). For the
            //   ported consumers a given line keeps its curveness, so this branch is effectively cold.
            if let old = line { _ = self.remove(old) }
            let fresh = createLine(linePoints)
            fresh.z2 = eclineToNumber(lineData.getItemVisual(idx, "z2")) ?? 0
            _ = self.add(fresh)
            line = fresh
        } else if let line = line {
            // graphic.updateProps(line, { shape: target }, seriesModel, idx) — MORPH the shape.
            var target: [String: Any]
            if line is BezierCurve {
                var shape = BezierCurveShape()
                setCurveShapePoints(&shape, linePoints)
                target = ["x1": shape.x1, "y1": shape.y1, "x2": shape.x2, "y2": shape.y2,
                          "cpx1": shape.cpx1, "cpy1": shape.cpy1, "percent": 1.0]
            } else {
                var shape = LineShape()
                setLineShapePoints(&shape, linePoints)
                target = ["x1": shape.x1, "y1": shape.y1, "x2": shape.x2, "y2": shape.y2, "percent": 1.0]
            }
            // Upstream `Line.beforeUpdate` repositions both end symbols and the label from the
            // line's LIVE shape on every animation frame. Mirror that hook through updateProps'
            // `during` callback so a legend-driven axis relayout cannot leave the arrow at the
            // target endpoint while the line itself is still tweening from the old layout.
            let during: (Double) -> Void = { [weak self, weak line] _ in
                guard let self, let line else { return }
                self._growEnds(line, childPercent(line))
            }
            updateProps(line, ["shape": target], seriesModel, idx, nil, during)
        }

        for symbolCategory in SYMBOL_CATEGORIES {
            let symbolType = makeSymbolTypeValue(symbolCategory, lineData, idx)
            let key = symbolTypeKey(symbolCategory)
            if key != symbolType {
                if let old = self.childOfName(shortSymbolName(symbolCategory)) { _ = self.remove(old) }
                let (sym, specifiedRotation) = makeSymbol(symbolCategory, lineData, idx)
                _ = self.add(sym)
                setSpecifiedRotation(symbolCategory, specifiedRotation)
            }
            setSymbolTypeKey(symbolCategory, symbolType)
        }

        self._updateCommonStl(lineData, idx, seriesScope)
        self._positionEndsAndLabel(linePoints)
        // Keep the synchronous final state expected after `setToFinal`; the update `during` callback
        // rewinds these dependants to the live line shape as soon as the animation starts.
        _growEnds(self.childOfName("line") as? Path, 1)
    }

    // upstream: getLinePath() { return this.childAt(0); }
    public func getLinePath() -> Path? {
        return self.childAt(0) as? Path
    }

    // upstream: _updateCommonStl(lineData, idx, seriesScope?)
    private func _updateCommonStl(_ lineData: SeriesData, _ idx: Int, _ seriesScope: LineDrawSeriesScope?) {
        let seriesModel = lineData.hostModel
        guard let line = self.childOfName("line") as? Path else { return }

        var emphasisLineStyle = seriesScope?.emphasisLineStyle
        var blurLineStyle = seriesScope?.blurLineStyle
        var selectLineStyle = seriesScope?.selectLineStyle
        var labelStatesModels = seriesScope?.labelStatesModels ?? [:]
        var emphasisDisabled = seriesScope?.emphasisDisabled ?? false
        var focus = seriesScope?.focus
        var blurScope = seriesScope?.blurScope

        // Optimization for large dataset — per-item model when there is no scope or per-item options.
        if seriesScope == nil || lineData.hasItemOption {
            let itemModel = lineData.getItemModel(idx)
            let emphasisModel = itemModel.getModel("emphasis")
            emphasisLineStyle = emphasisModel.getModel("lineStyle").getLineStyle()
            blurLineStyle = itemModel.getModel(["blur", "lineStyle"]).getLineStyle()
            selectLineStyle = itemModel.getModel(["select", "lineStyle"]).getLineStyle()
            emphasisDisabled = (emphasisModel.get("disabled") as? Bool) ?? false
            focus = emphasisModel.get("focus")
            blurScope = (emphasisModel.get("blurScope") as? String).flatMap { BlurScope(rawValue: $0) }
            labelStatesModels = labelStyle.getLabelStatesModels(itemModel)
        }

        let lineStyleVisual = lineData.getItemVisual(idx, "style") as? [String: Any]
        let visualColor = eclineColorString(lineStyleVisual?["stroke"])

        // line.useStyle(lineStyle); line.style.fill = null; line.style.strokeNoScale = true;
        line.useStyle(barStyleFromDict(lineStyleVisual))
        line.pathStyle.fill = nil
        line.pathStyle.strokeNoScale = true

        line.ensureState("emphasis").style = emphasisLineStyle
        line.ensureState("blur").style = blurLineStyle
        line.ensureState("select").style = selectLineStyle

        // Share opacity + color with the end symbols; propagate per-state stroke/opacity.
        for symbolCategory in SYMBOL_CATEGORIES {
            guard let sym = self.childOfName(shortSymbolName(symbolCategory)) as? Path else { continue }
            if let visualColor = visualColor {
                (sym as? ECSymbol)?.setColor(.string(visualColor), nil)
            }
            if let opacity = lineStyleVisual?["opacity"] as? Double {
                sym.pathStyle.opacity = opacity
            }
            for stateName in EChartsKit.states.SPECIAL_STATES {
                guard let lineState = line.getState(stateName), let lineStateStyle = lineState.style else { continue }
                let state = sym.ensureState(stateName)
                var stateStyle = state.style ?? [:]
                if let stroke = lineStateStyle["stroke"] {
                    let isEmpty = (sym as? ECSymbol)?.__isEmptyBrush ?? false
                    stateStyle[isEmpty ? "stroke" : "fill"] = stroke
                }
                if let opacity = lineStateStyle["opacity"] {
                    stateStyle["opacity"] = opacity
                }
                state.style = stateStyle
            }
            sym.markRedraw()
        }

        // Label. upstream: setLabelStyle(this, labelStatesModels, { labelDataIndex, labelFetcher,
        //   inheritColor, defaultOpacity, defaultText }). The label is attached as THIS group's
        //   textContent and repositioned along the line in _positionEndsAndLabel.
        let rawVal = eclineRawValue(seriesModel, lineData, idx)
        var labelOpt = SetLabelStyleOpt()
        labelOpt.labelDataIndex = Double(idx)
        // labelFetcher: only a DataFormatMixin host (a real SeriesModel) can format labels. The markLine
        //   host (MarkerModel) is not one — its default text is the stashed value / name instead.
        labelOpt.labelFetcher = seriesModel as? DataFormatMixin
        // upstream: inheritColor: visualColor as ColorString || tokens.color.neutral99
        labelOpt.inheritColor = visualColor ?? tokens.color.neutral99
        labelOpt.defaultOpacity = lineStyleVisual?["opacity"] as? Double
        labelOpt.defaultText = eclineDefaultText(rawVal, lineData, idx)

        labelStyle.setLabelStyle(self, labelStatesModels, labelOpt)

        if let label = self.getTextContent() {
            let labelNormalModel = labelStatesModels[.normal]
            _labelAlign = label.textStyle.align
            _labelVerticalAlign = label.textStyle.verticalAlign
            _labelPosition = (labelNormalModel?.get("position") as? String) ?? "middle"
            let distance = labelNormalModel?.get("distance")
            if let arr = distance as? [Any] {
                let ds = arr.map { eclineToNumber($0) ?? 0 }
                _labelDistance = ds.count >= 2 ? [ds[0], ds[1]] : [ds.first ?? 5, ds.first ?? 5]
            } else if let d = eclineToNumber(distance) {
                _labelDistance = [d, d]
            } else {
                _labelDistance = [5, 5]
            }
        }

        // Can't be inside for a stroke element.
        var tc = ElementTextConfig()
        tc.position = nil
        tc.local = true
        tc.inside = false
        self.setTextConfig(tc)

        EChartsKit.states.toggleHoverEmphasis(self, focus, blurScope, emphasisDisabled)
    }

    // upstream: highlight() { enterEmphasis(this); }
    public func highlight() { EChartsKit.states.enterEmphasis(self) }
    // upstream: downplay() { leaveEmphasis(this); }
    public func downplay() { EChartsKit.states.leaveEmphasis(self) }

    // upstream: updateLayout(lineData, idx) { this.childOfName('line').stopAnimation(); this.setLinePoints(...); }
    public func updateLayout(_ lineData: SeriesData, _ idx: Int) {
        _ = self.childOfName("line")?.stopAnimation()
        let points = eclinePoints(lineData.getItemLayout(idx))
        self._linePoints = points
        self.setLinePoints(points)
        self._positionEndsAndLabel(points)
        _growEnds(self.childOfName("line") as? Path, 1)
    }

    // upstream: setLinePoints(points) { setLinePoints(linePath.shape, points); linePath.dirty(); }
    public func setLinePoints(_ points: [[Double]]) {
        guard let linePath = self.childOfName("line") as? Path else { return }
        if let curve = linePath as? BezierCurve {
            var shape = (curve.shape as? BezierCurveShape) ?? BezierCurveShape()
            setCurveShapePoints(&shape, points)
            curve.setShape(shape)
        } else if let line = linePath as? Line {
            var shape = (line.shape as? LineShape) ?? LineShape()
            setLineShapePoints(&shape, points)
            line.setShape(shape)
        }
        linePath.dirty()
    }

    // ── positioning (upstream `beforeUpdate`, computed at build/update time here) ──────────────────

    // Position the symbols and label on the currently revealed portion of the line.
    private func _positionEndsAndLabel(_ points: [[Double]], _ percent: Double = 1) {
        let symbolFrom = self.childOfName("from") as? Path
        let symbolTo = self.childOfName("to") as? Path
        let label = self.getTextContent()
        if symbolFrom == nil && symbolTo == nil && (label == nil || label!.ignore) {
            return
        }

        let invScale = self._invScale()
        let lineChild = self.childOfName("line") as? Path

        let fromPos = lineChild.map { pointAtOf($0, 0) } ?? points[0]
        let toPos = lineChild.map { pointAtOf($0, percent) } ?? points[1]
        var d = [toPos[0] - fromPos[0], toPos[1] - fromPos[1]]
        let dlen = (d[0] * d[0] + d[1] * d[1]).squareRoot()
        if dlen > 0 { d = [d[0] / dlen, d[1] / dlen] }

        // upstream setSymbolRotation(symbol, percent): tangent = line.tangentAt(percent);
        //   rotation = (percent === 1 ? -1 : 1) * PI/2 - atan2(tangent[1], tangent[0]). For a straight
        //   line tangentAt is constant (the chord); for a curve the two ends differ.
        if let symbolFrom = symbolFrom {
            symbolFrom.setPosition(fromPos)
            let t = lineChild.map { tangentAtOf($0, 0) } ?? d
            symbolFrom.rotation = _fromSpecifiedRotation ?? (Double.pi / 2 - atan2(t[1], t[0]))
            symbolFrom.scaleX = invScale * percent
            symbolFrom.scaleY = invScale * percent
            symbolFrom.markRedraw()
        }
        if let symbolTo = symbolTo {
            symbolTo.setPosition(toPos)
            let t = lineChild.map { tangentAtOf($0, 1) } ?? d
            symbolTo.rotation = _toSpecifiedRotation ?? (-Double.pi / 2 - atan2(t[1], t[0]))
            symbolTo.scaleX = invScale * percent
            symbolTo.scaleY = invScale * percent
            symbolTo.markRedraw()
        }

        guard let label = label, !label.ignore else { return }
        label.x = 0; label.y = 0
        label.originX = 0; label.originY = 0

        var textAlign: TextAlign?
        var textVerticalAlign: TextVerticalAlign?

        let distanceX = _labelDistance[0] * invScale
        let distanceY = _labelDistance[1] * invScale
        // upstream: halfPercent = percent / 2; the label follows the currently revealed portion.
        //   tangent = line.tangentAt(halfPercent). Works for both the straight `Line` and quadratic
        //   `BezierCurve` children (helpers below dispatch on the child type). Falls back to the chord
        //   midpoint/direction only if the line child is missing.
        let halfPercent = percent / 2
        let cp: [Double] = lineChild.map { pointAtOf($0, halfPercent) }
            ?? [(fromPos[0] + toPos[0]) / 2, (fromPos[1] + toPos[1]) / 2]
        let tangent = lineChild.map { tangentAtOf($0, halfPercent) } ?? d
        let dir = tangent[0] < 0 ? -1.0 : 1.0
        let position = _labelPosition ?? "middle"

        if position != "start" && position != "end" {
            var rotation = -atan2(tangent[1], tangent[0])
            if toPos[0] < fromPos[0] { rotation = Double.pi + rotation }
            label.rotation = rotation
        }

        var dy: Double
        switch position {
        case "insideStartTop", "insideMiddleTop", "insideEndTop", "middle":
            dy = -distanceY; textVerticalAlign = .bottom
        case "insideStartBottom", "insideMiddleBottom", "insideEndBottom":
            dy = distanceY; textVerticalAlign = .top
        default:
            dy = 0; textVerticalAlign = .middle
        }

        switch position {
        case "end":
            label.x = d[0] * distanceX + toPos[0]
            label.y = d[1] * distanceY + toPos[1]
            textAlign = d[0] > 0.8 ? .left : (d[0] < -0.8 ? .right : .center)
            textVerticalAlign = d[1] > 0.8 ? .top : (d[1] < -0.8 ? .bottom : .middle)
        case "start":
            label.x = -d[0] * distanceX + fromPos[0]
            label.y = -d[1] * distanceY + fromPos[1]
            textAlign = d[0] > 0.8 ? .right : (d[0] < -0.8 ? .left : .center)
            textVerticalAlign = d[1] > 0.8 ? .bottom : (d[1] < -0.8 ? .top : .middle)
        case "insideStartTop", "insideStart", "insideStartBottom":
            label.x = distanceX * dir + fromPos[0]
            label.y = fromPos[1] + dy
            textAlign = tangent[0] < 0 ? .right : .left
            label.originX = -distanceX * dir
            label.originY = -dy
        case "insideMiddleTop", "insideMiddle", "insideMiddleBottom", "middle":
            label.x = cp[0]
            label.y = cp[1] + dy
            textAlign = .center
            label.originY = -dy
        case "insideEndTop", "insideEnd", "insideEndBottom":
            label.x = -distanceX * dir + toPos[0]
            label.y = toPos[1] + dy
            textAlign = tangent[0] >= 0 ? .right : .left
            label.originX = distanceX * dir
            label.originY = -dy
        default:
            break
        }

        label.scaleX = invScale
        label.scaleY = invScale
        label.textStyle.verticalAlign = _labelVerticalAlign ?? textVerticalAlign
        label.textStyle.align = _labelAlign ?? textAlign
        label.dirty()
    }

    // The entrance grow (Line.ts beforeUpdate `symbol.scaleX = invScale * percent`): scale the end
    //   symbols by `percent` and ride the `to` symbol along the growing line. Called by the initProps
    //   `during` and once at the end of build/update.
    private func _growEnds(_ line: Path?, _ percent: Double) {
        guard line != nil, self._linePoints.count >= 2 else { return }
        self._positionEndsAndLabel(self._linePoints, percent)
    }

    // upstream: invScale = product of 1/parent.scaleX up the tree (parent scale compensation).
    private func _invScale() -> Double {
        var invScale = 1.0
        var node: Transformable? = self.parent
        while let n = node {
            if n.scaleX != 0 { invScale /= n.scaleX }
            node = n.parent
        }
        return invScale
    }

    // ── local storage helpers for the `_fromSymbolType` / `_toSymbolType` keys ─────────────────────
    private func symbolTypeKey(_ category: String) -> String? {
        return category == "fromSymbol" ? _fromSymbolType : _toSymbolType
    }
    private func setSymbolTypeKey(_ category: String, _ value: String?) {
        if category == "fromSymbol" { _fromSymbolType = value } else { _toSymbolType = value }
    }
    private func setSpecifiedRotation(_ category: String, _ value: Double?) {
        if category == "fromSymbol" { _fromSpecifiedRotation = value } else { _toSpecifiedRotation = value }
    }
}

// ── shape-access helpers bridging the two distinct child shapes ────────────────────────────────────

private func setChildPercent(_ el: Path, _ percent: Double) {
    if let curve = el as? BezierCurve {
        var shape = (curve.shape as? BezierCurveShape) ?? BezierCurveShape()
        shape.percent = percent
        curve.setShape(shape)
    } else if let line = el as? Line {
        var shape = (line.shape as? LineShape) ?? LineShape()
        shape.percent = percent
        line.setShape(shape)
    }
}

private func childPercent(_ el: Path) -> Double {
    if let curve = el as? BezierCurve { return (curve.shape as? BezierCurveShape)?.percent ?? 1 }
    if let line = el as? Line { return (line.shape as? LineShape)?.percent ?? 1 }
    return 1
}

private func pointAtOf(_ el: Path, _ t: Double) -> [Double] {
    if let curve = el as? BezierCurve { return curve.pointAt(t) }
    if let line = el as? Line { return line.pointAt(t) }
    return [0, 0]
}

// upstream: ECLinePath.tangentAt(t) — for the straight line the (normalized) tangent is the chord
//   [x2-x1, y2-y1]; for the curve it delegates to BezierCurve.tangentAt (already normalized).
private func tangentAtOf(_ el: Path, _ t: Double) -> [Double] {
    if let curve = el as? BezierCurve { return curve.tangentAt(t) }
    if let line = el as? Line {
        let shape = line.shape as? LineShape
        let x1 = shape?.x1 ?? 0, y1 = shape?.y1 ?? 0
        let x2 = shape?.x2 ?? 0, y2 = shape?.y2 ?? 0
        var p = [x2 - x1, y2 - y1]
        let len = (p[0] * p[0] + p[1] * p[1]).squareRoot()
        if len > 0 { p = [p[0] / len, p[1] / len] }
        return p
    }
    return [0, 0]
}

// ── local coercion helpers ─────────────────────────────────────────────────────────────────────────

// `edge.setLayout([...])` stores `[[x1,y1],[x2,y2]]` (straight) or `[[x1,y1],[x2,y2],[cpx,cpy]]` (curved),
//   each sub-point as `[Double]` / `[Any]` / `[NSNumber]`. Coerce to `[[Double]]`.
private func eclinePoints(_ v: Any?) -> [[Double]] {
    guard let outer = v as? [Any] else {
        if let dd = v as? [[Double]] { return dd }
        return [[Double.nan, Double.nan], [Double.nan, Double.nan]]
    }
    return outer.map { eclineNumArray($0) }
}

private func eclineNumArray(_ v: Any?) -> [Double] {
    if let d = v as? [Double] { return d }
    if let arr = v as? [Any] { return arr.map { eclineToNumber($0) ?? Double.nan } }
    return []
}

private func eclineToNumber(_ v: Any?) -> Double? {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let n = v as? NSNumber { return n.doubleValue }
    return nil
}

private func eclineNumStr(_ v: Any?) -> String {
    if let d = eclineToNumber(v) { return "\(d)" }
    return ""
}

private func eclineBoolStr(_ v: Any?) -> String {
    if let b = v as? Bool { return b ? "1" : "0" }
    return ""
}

private func eclineColorString(_ v: Any?) -> String? {
    if let str = v as? String { return str }
    if let zr = v as? EChartsKit.ZRColor, case let .color(str) = zr { return str }
    return nil
}

// The line's raw value for the default label. A real SeriesModel host formats via getRawValue; the
//   markLine host (MarkerModel) can't — it stashes the merged value under the `__labelValue` visual.
private func eclineRawValue(_ hostModel: Model?, _ lineData: SeriesData, _ idx: Int) -> Any? {
    // MarkerModel now conforms to DataFormatMixin, but this port's lineData stores a typed
    // MarkerPositionOption as its raw item. The generic mixin therefore returns the whole struct,
    // whereas upstream's normalized line item exposes its scalar `value`. MarkLineView stashes that
    // resolved scalar explicitly; prefer it for marker hosts.
    if hostModel is MarkerModel {
        return lineData.getItemVisual(idx, "__labelValue")
    }
    if let series = hostModel as? DataFormatMixin {
        let v = series.getRawValue(Double(idx), lineData.dataType)
        if v != nil { return v }
    }
    return lineData.getItemVisual(idx, "__labelValue")
}

// upstream: defaultText = rawVal == null ? lineData.getName(idx)
//                        : isFinite(rawVal) ? round(rawVal, 10) : rawVal, cast to string.
private func eclineDefaultText(_ rawVal: Any?, _ lineData: SeriesData, _ idx: Int) -> Any? {
    guard let rawVal = rawVal else {
        let name = lineData.getName(idx)
        return name.isEmpty ? nil : name
    }
    if let n = eclineToNumber(rawVal) {
        if n.isFinite { return number.jsString(number.round(n, 10)) }
        return number.jsString(n)
    }
    return "\(rawVal)"
}
