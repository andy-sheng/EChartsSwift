// Ported (MINIMAL SUBSET) from echarts/src/chart/line/LineView.ts — keep in sync with upstream.
//
// Draws a cartesian (and polar) line series as a `Polyline` through the data points. Symbols, areaStyle,
// step, stacking, clipping, and the draw-on reveal animation are now ported. It mirrors upstream's core
// — build the point array from `coord.dataToPoint` per datum, create the polyline, and stroke it with
// the series' visual color — rendering the line vertical end-to-end (matching the echarts.js reference
// in EChartsDemoGallery).

import Foundation
import ZRenderKit

// upstream: class LineView extends ChartView { static type = 'line'; type = LineView.type; ... }
open class LineView: ChartView {

    private var _data: SeriesData?
    // Persistent line elements (upstream `this._lineGroup`/`_polyline`/`_polygon`/`_symbolDraw`) so a
    //   merge-mode setOption morphs the line rather than rebuilding it. Kept across renders; the outer
    //   `group` is no longer wiped. `_prevPointCount` gates morph-vs-rebuild (a point add/remove or a
    //   coord-system change rebuilds fresh with the draw-on clip; a same-count value change morphs).
    private var _lineGroup: Group?
    private var _polyline: Polyline?
    private var _polygon: ThemeRiverBand?
    private var _symbolDraw: SymbolDraw?
    private var _prevPointCount: Int = -1

    open override func render(
        _ seriesModel: SeriesModel, _ ecModel: GlobalModel, _ api: ExtensionAPI, _ payload: Payload
    ) {
        // Polar line: project each datum via the polar coord and draw a polyline + symbols (no
        //   areaStyle/step/stacking on polar — those stay cartesian-only for now).
        if let polar = seriesModel.coordinateSystem as? Polar {
            self.renderPolarLine(seriesModel, polar)
            self._data = seriesModel.getData()
            return
        }
        // PORT-NOTE (deferred): only cartesian2d + polar are handled here; geo/single/calendar line
        //   coordinate systems are not yet wired into this view's render path.
        guard let coord = seriesModel.coordinateSystem as? Cartesian2D else { return }

        let data = seriesModel.getData()
        let baseAxis = coord.getBaseAxis()
        let valueAxis = coord.getOtherAxis(baseAxis)
        // A line's base/value dims are normally always present; guard rather than force-unwrap so a
        //   missing dimension no-ops (matching JS's non-crashing behavior) instead of trapping.
        guard let baseDimName = data.mapDimension(baseAxis.dim),
              let valueDimName = data.mapDimension(valueAxis.dim) else { return }
        let baseDimIdx = data.getDimensionIndex(baseDimName)
        // For a `stack`ed line the point follows the cumulative stack result dimension (getStackedDimension
        //   returns valueDimName unchanged when the series is not stacked). Without this the stacked lines
        //   render at their raw values instead of the accumulated totals.
        let stacked = isDimensionStacked(data, valueDimName)
        let lineValueDimName = getStackedDimension(data, valueDimName)
        let valueDimIdx = data.getDimensionIndex(lineValueDimName)
        let store = data.getStore()

        // Build the polyline points: one per datum, via the cartesian `dataToPoint`. `isHorizontal`
        //   decides which coord slot the base (category) value drives, mirroring barGrid's ordering.
        let isValueAxisH = valueAxis.isHorizontal()
        var points: [VectorArray] = []
        for i in 0..<data.count() {
            let baseVal = lineToNumber(store.get(baseDimIdx, i))
            let value = lineToNumber(store.get(valueDimIdx, i))
            let p = isValueAxisH ? coord.dataToPoint([value, baseVal]) : coord.dataToPoint([baseVal, value])
            if p.count >= 2 && p[0].isFinite && p[1].isFinite {
                points.append(VectorArray(p[0], p[1]))
            }
        }

        let group = self.group
        // View REUSE (L5 fidelity): the outer group is NOT wiped; the line elements persist so a
        //   same-count value change morphs. Too few points → drop any prior line elements and bail.
        if points.count < 2 {
            if let lg = _lineGroup { _ = group.remove(lg) }
            if let sd = _symbolDraw { _ = group.remove(sd.group) }
            _lineGroup = nil; _polyline = nil; _polygon = nil; _symbolDraw = nil
            _prevPointCount = -1
            self._data = data
            return
        }

        // smooth: a truthy `smooth` renders the line/area as a spline. echarts maps `true` → 0.5 and
        //   uses a number directly. `step` (below) takes precedence and disables smoothing.
        let smoothVal: Double = {
            let s = seriesModel.get("smooth")
            if let b = s as? Bool { return b ? 0.5 : 0 }
            if let d = s as? Double { return d }
            if let i = s as? Int { return Double(i) }
            return 0
        }()
        // step: staircase point list ('start'|'middle'|'end', or true→'start'). Applied to the line
        //   (and area top edge) point list before shaping.
        let steppedPoints = lineStepPoints(points, seriesModel.get("step"), isValueAxisH)

        // Color: the visual/style stage stored the palette color in the series' visual `style` bag
        //   (colorKey 'fill' for a basic line — see visual/style.swift). The value is an EChartsKit
        //   `ZRColor.color(String)` (or a raw String); extract the solid color and use it as the LINE
        //   STROKE (same bridge as BarView's `barStyleFromDict`; gradient/pattern out of scope).
        func colorString(_ v: Any?) -> String? {
            if let str = v as? String { return str }
            if let zr = v as? EChartsKit.ZRColor, case let .color(str) = zr { return str }
            return nil
        }
        var stroke = "#000"
        if let style = data.getVisual("style") as? [String: Any] {
            if let s = colorString(style["stroke"]) { stroke = s }
            else if let f = colorString(style["fill"]) { stroke = f }
        }

        // upstream `this._lineGroup` — a child Group holding the polyline (+ area), clipped by a growing
        //   Rect so the line "draws on" (createGridClipPath). PERSISTED across renders (L5 fidelity), so a
        //   same-count value change morphs the line; a first render or a point add/remove (re)builds it
        //   fresh (with the draw-on clip). Symbols are added to `group` directly (unclipped).
        let linePoints = steppedPoints ?? points
        let hasAnimation = seriesModel.isAnimationEnabled() ?? false
        // Morph iff we already have a polyline with the same point count (values changed). A count change
        //   or first render rebuilds fresh — the full add/remove point diff (lineAnimationDiff) is deferred.
        let canMorph = _polyline != nil && _lineGroup != nil && _prevPointCount == linePoints.count
        let lineGroup: Group
        if canMorph {
            lineGroup = _lineGroup!
        } else {
            if let old = _lineGroup { _ = group.remove(old) }
            lineGroup = Group()
            _lineGroup = lineGroup
            _polyline = nil
            _polygon = nil
            _ = group.add(lineGroup)
        }

        // ── areaStyle pass ──────────────────────────────────────────────────────────────────────
        //   Baseline = the stackedOver value per datum for a stacked area, else the value-axis origin
        //   (0 clamped into the scale extent). The band morphs (upperPoints/lowerPoints) on reuse.
        let areaStyleModel = seriesModel.getModel("areaStyle")
        if !areaStyleModel.isEmpty() {
            let sExtent = valueAxis.scale.getExtent()
            let origin = Swift.min(Swift.max(0, sExtent[0]), sExtent[1])
            let stackedOverDimName = data.getCalculationInfo("stackedOverDimension") as? String
            let stackedOverDimIdx = stackedOverDimName.map { data.getDimensionIndex($0) }
            var baselinePts: [VectorArray] = []
            for i in 0..<data.count() {
                let baseVal = lineToNumber(store.get(baseDimIdx, i))
                // The bottom series of a stack has a NaN `stackedOver` (nothing below it); upstream
                //   `getStackedOnPoints` renders those points on the value-axis start, so fall back to
                //   `origin` when the stacked baseline is non-finite.
                var baselineVal: Double = origin
                if stacked, let soIdx = stackedOverDimIdx {
                    let sv = lineToNumber(store.get(soIdx, i))
                    if sv.isFinite { baselineVal = sv }
                }
                let bp = isValueAxisH ? coord.dataToPoint([baselineVal, baseVal]) : coord.dataToPoint([baseVal, baselineVal])
                if bp.count >= 2 && bp[0].isFinite && bp[1].isFinite {
                    baselinePts.append(VectorArray(bp[0], bp[1]))
                }
            }
            if baselinePts.count == points.count {
                // Area top edge follows the same step staircase as the line (when stepped). Uses the
                //   ECPolygon-style band (see ThemeRiverView): the top edge is smoothed while the baseline
                //   edge and the vertical end caps stay straight.
                let topPts = steppedPoints ?? points
                let areaSmooth = steppedPoints == nil ? smoothVal : 0
                var areaDict = areaStyleModel.getAreaStyle()
                if areaDict["opacity"] == nil { areaDict["opacity"] = 0.7 }
                var aStyle = barStyleFromDict(areaDict)
                // Fill defaults to the series color; gradient/pattern area fills (not bridged) also fall
                //   back to the solid series color so the area is never the spurious black default.
                if aStyle.fill == nil { aStyle.fill = .string(stroke) }
                aStyle.stroke = nil
                if let poly = _polygon, canMorph {
                    poly.useStyle(aStyle)
                    poly.pathStyle.stroke = nil
                    // Target points as [[Double]] — the shape the Animator's 2D-array interpolation
                    //   consumes (matches animationGet's return); a [VectorArray] target snaps instead.
                    let upperD = topPts.map { [$0.x, $0.y] }
                    let lowerD = baselinePts.map { [$0.x, $0.y] }
                    updateProps(poly, ["shape": ["upperPoints": upperD, "lowerPoints": lowerD, "smooth": areaSmooth]], seriesModel)
                } else {
                    if let old = _polygon { _ = lineGroup.remove(old) }
                    var bandShape = ThemeRiverBandShape()
                    bandShape.upperPoints = topPts
                    bandShape.lowerPoints = baselinePts
                    bandShape.smooth = areaSmooth
                    let areaPoly = ThemeRiverBand(["shape": bandShape as PathShape])
                    areaPoly.name = "area"
                    areaPoly.useStyle(aStyle)
                    areaPoly.pathStyle.stroke = nil
                    _ = lineGroup.add(areaPoly)
                    _polygon = areaPoly
                }
            } else if let old = _polygon {
                _ = lineGroup.remove(old); _polygon = nil
            }
        } else if let old = _polygon {
            _ = lineGroup.remove(old); _polygon = nil
        }

        // ── polyline ── (morph its shape.points on reuse, else create with the draw-on clip)
        let lineSmooth = steppedPoints == nil ? smoothVal : 0
        var st = PathStyleProps()
        st.stroke = .string(stroke)
        st.fill = .string("none")
        st.lineWidth = 2
        applyLineStyleOption(&st, seriesModel)
        if let polyline = _polyline, canMorph {
            polyline.useStyle(st)   // colour may have changed (visual/style re-ran)
            // Target points as [[Double]] (Animator 2D-array interpolation shape); [VectorArray] snaps.
            let ptsD = linePoints.map { [$0.x, $0.y] }
            updateProps(polyline, ["shape": ["points": ptsD, "smooth": lineSmooth]], seriesModel)
        } else {
            var shape = PolylineShape()
            shape.points = linePoints
            shape.smooth = lineSmooth
            let polyline = Polyline()
            polyline.setShape(shape)
            polyline.name = "line"
            polyline.useStyle(st)
            polyline.z2 = 10   // upstream ECPolyline z2; keeps the line above a co-gridded bar series (z2 1)
            _ = lineGroup.add(polyline)
            _polyline = polyline
            // upstream: this._lineGroup.setClipPath(createGridClipPath(...)); the clip Rect grows to full
            //   size via initProps — the "draw on" entrance. Set only on (re)build; a morph reuse leaves
            //   the clip at full size (no re-collapse).
            let clipPath = createGridClipPath(coord, hasAnimation, seriesModel)
            lineGroup.setClipPath(clipPath)
        }
        _prevPointCount = linePoints.count

        // ── line/area hover wiring ── (upstream LineView.ts:827-851, 887-890)
        let emphasisModel = seriesModel.getModel(["emphasis"])
        let focus: InnerFocus? = emphasisModel.get("focus")
        let blurScope = (emphasisModel.get("blurScope") as? String).flatMap { BlurScope(rawValue: $0) }
        let emphasisDisabled = (emphasisModel.get("disabled") as? Bool) ?? false

        if let polyline = _polyline {
            states.setStatesStylesFromModel(polyline, seriesModel, "lineStyle")
            // `emphasis.lineStyle.width === 'bolder'` → normal width + 1 (LineView.ts:844-847).
            if (polyline.pathStyle?.lineWidth ?? 0) > 0,
               (seriesModel.get(["emphasis", "lineStyle", "width"]) as? String) == "bolder" {
                let emphasisState = polyline.ensureState("emphasis")
                var st = emphasisState.style ?? [:]
                st["lineWidth"] = (polyline.pathStyle?.lineWidth ?? 0) + 1
                emphasisState.style = st
            }
            // Needs seriesIndex for focus.
            innerStore.getECData(polyline).seriesIndex = seriesModel.seriesIndex
            states.toggleHoverEmphasis(polyline, focus, blurScope, emphasisDisabled)
        }
        if let polygon = _polygon {
            states.setStatesStylesFromModel(polygon, seriesModel, "areaStyle")
            // Needs seriesIndex for focus.
            innerStore.getECData(polygon).seriesIndex = seriesModel.seriesIndex
            states.toggleHoverEmphasis(polygon, focus, blurScope, emphasisDisabled)
        }

        // ── SymbolDraw pass ─────────────────────────────────────────────────────────────────────
        // The shared SymbolDraw draws the line's data-point symbols — PERSISTED so the symbols morph via
        //   their own data.diff (positions slide) on reuse rather than fading in fresh each render.
        // upstream: `showSymbol && !isCoordSysPolar && getIsIgnoreFunc(...)` gates the per-point symbol.
        //   `showAllSymbol: 'auto'` (the LineSeries default) hides symbols when the category line is dense.
        let showSymbol = seriesModel.get("showSymbol")
        // upstream truthiness: draw unless showSymbol is explicitly false.
        if (showSymbol as? Bool) != false {
            // Symbol-visual stages populate the symbol / symbolSize / symbolRotate / symbolOffset /
            //   symbolKeepAspect data + item visuals that SymbolDraw reads (LineSeries.hasSymbolVisual).
            symbolVisual.seriesSymbolTask(seriesModel, ecModel)
            symbolVisual.dataSymbolTask(seriesModel)

            // upstream: const isIgnoreFunc = showSymbol && !isCoordSysPolar && getIsIgnoreFunc(...)
            let isIgnoreFunc = lineGetIsIgnoreFunc(seriesModel, data, coord)

            let symbolDraw: SymbolDraw
            if let sd = _symbolDraw {
                symbolDraw = sd
            } else {
                symbolDraw = SymbolDraw()
                _symbolDraw = symbolDraw
                _ = group.add(symbolDraw.group)   // added AFTER the lineGroup so symbols sit on top
            }
            var opt = SymbolDrawUpdateOpt()
            opt.isIgnore = isIgnoreFunc
            // Re-project per datum (rather than reusing `points`) so each symbol tracks its own datum
            //   even where a non-finite coord was dropped from the polyline point array above.
            opt.getSymbolPoint = { i in
                let baseVal = lineToNumber(store.get(baseDimIdx, i))
                let value = lineToNumber(store.get(valueDimIdx, i))
                let p = isValueAxisH ? coord.dataToPoint([value, baseVal]) : coord.dataToPoint([baseVal, value])
                return (p.count >= 2 && p[0].isFinite && p[1].isFinite) ? p : nil
            }
            symbolDraw.updateData(data, opt)
        } else if let sd = _symbolDraw {
            _ = group.remove(sd.group); _symbolDraw = nil
        }

        // upstream (LineView.ts:893-900): a data symbol's hover-state change flips the polyline/area
        //   with it (and the polyline's own change flips the area) — the "hover a point highlights
        //   the whole line" link.
        data.eachItemGraphicEl { el, _ in
            states.getHighDownInner(el).onHoverStateChange = { [weak self] toState in
                self?._changePolyState(toState)
            }
        }
        if let polyline = _polyline {
            states.getHighDownInner(polyline).onHoverStateChange = { [weak self] toState in
                self?._changePolyState(toState)
            }
        }

        self._data = data
    }

    // upstream: `_changePolyState(toState)` (LineView.ts:1029-1033) — flag the polyline + area polygon.
    //   Upstream is flag-only (applyChangedStates runs next frame); this port applies states eagerly
    //   (see the states.swift doChangeHoverState deviation), so apply here too.
    private func _changePolyState(_ toState: DisplayState) {
        if let polyline = _polyline {
            states.setStatesFlag(polyline, toState)
            states.applyElementStates(polyline)
        }
        if let polygon = _polygon {
            states.setStatesFlag(polygon, toState)
            states.applyElementStates(polygon)
        }
    }

    // upstream: `highlight`/`downplay` (LineView.ts:937-1023) also flip the poly state before the
    //   base per-datum symbol highlight. PORT-NOTE (deferred): the temporary-symbol branch (creating a
    //   Symbol for a dataIndex whose point has no element, #11360 clip guard) is not yet ported.
    open override func highlight(
        _ seriesModel: SeriesModel, _ ecModel: GlobalModel, _ api: ExtensionAPI, _ payload: Payload
    ) {
        _changePolyState(.emphasis)
        super.highlight(seriesModel, ecModel, api, payload)
    }

    open override func downplay(
        _ seriesModel: SeriesModel, _ ecModel: GlobalModel, _ api: ExtensionAPI, _ payload: Payload
    ) {
        _changePolyState(.normal)
        super.downplay(seriesModel, ecModel, api, payload)
    }

    // Minimal polar line: project each datum through the polar coord (radius/angle dims, like
    //   ScatterView's polar branch) and stroke a polyline through the points, then place the data
    //   symbols. areaStyle/step/stacking + line emphasis are deferred on polar.
    private func renderPolarLine(_ seriesModel: SeriesModel, _ coord: Polar) {
        let data = seriesModel.getData()
        let store = data.getStore()
        let group = self.group
        group.removeAll()
        // The polar branch rebuilds into the bare group each render; drop the cartesian persistent
        //   elements (they were just detached by removeAll) so a coord-system switch can't reuse them.
        _lineGroup = nil; _polyline = nil; _polygon = nil; _symbolDraw = nil; _prevPointCount = -1

        guard let radiusDimName = data.mapDimension("radius"),
              let angleDimName = data.mapDimension("angle") else { return }
        let radiusDimIdx = data.getDimensionIndex(radiusDimName)
        let angleDimIdx = data.getDimensionIndex(angleDimName)

        func pointAt(_ i: Int) -> [Double] {
            let radiusVal = lineToNumber(store.get(radiusDimIdx, i))
            let angleVal = lineToNumber(store.get(angleDimIdx, i))
            return coord.dataToPoint([radiusVal, angleVal])
        }

        var points: [VectorArray] = []
        for i in 0..<data.count() {
            let p = pointAt(i)
            if p.count >= 2 && p[0].isFinite && p[1].isFinite { points.append(VectorArray(p[0], p[1])) }
        }
        if points.count < 2 { return }

        func colorString(_ v: Any?) -> String? {
            if let str = v as? String { return str }
            if let zr = v as? EChartsKit.ZRColor, case let .color(str) = zr { return str }
            return nil
        }
        var stroke = "#000"
        if let style = data.getVisual("style") as? [String: Any] {
            if let s = colorString(style["stroke"]) { stroke = s }
            else if let f = colorString(style["fill"]) { stroke = f }
        }

        var shape = PolylineShape()
        shape.points = points
        let smoothVal = (seriesModel.get("smooth") as? Bool) == true ? 0.5 : ((seriesModel.get("smooth") as? Double) ?? 0)
        shape.smooth = smoothVal
        let polyline = Polyline()
        polyline.setShape(shape)
        polyline.name = "line"
        var st = PathStyleProps()
        st.stroke = .string(stroke)
        st.fill = .string("none")
        st.lineWidth = 2
        applyLineStyleOption(&st, seriesModel)
        polyline.useStyle(st)
        _ = group.add(polyline)

        // Symbols (unless showSymbol:false / symbol:'none').
        if (seriesModel.get("showSymbol") as? Bool) != false {
            let seriesSymbol = (seriesModel.get("symbol") as? String) ?? "emptyCircle"
            let seriesSymbolSize: Any = seriesModel.get("symbolSize") ?? 4.0
            for i in 0..<data.count() {
                let p = pointAt(i)
                if !(p.count >= 2 && p[0].isFinite && p[1].isFinite) { continue }
                let symbolType = (data.getItemVisual(i, "symbol") as? String) ?? seriesSymbol
                if symbolType == "none" { continue }
                let (w, h) = symbol.normalizeSymbolSize(data.getItemVisual(i, "symbolSize") ?? seriesSymbolSize)
                if let el = symbol.createSymbol(symbolType, p[0] - w / 2, p[1] - h / 2, w, h, ZRenderKit.ZRColor.string(stroke)) as? Path {
                    el.name = "symbol"
                    data.setItemGraphicEl(i, el)
                    _ = group.add(el)
                }
            }
        }
    }
}

// Turn a point list into a step (staircase) path — a faithful reduction of echarts' turnPointsIntoStep.
//   `stepOpt` is 'start' | 'middle'/'center' | 'end' (or `true` → 'start'). `isValueAxisH` selects the
//   base axis: when the value axis is horizontal the base (category) axis is Y (index 1), else X (0).
//   Returns nil when no step is requested.
private func lineStepPoints(_ points: [VectorArray], _ stepOpt: Any?, _ isValueAxisH: Bool) -> [VectorArray]? {
    let step: String
    if let s = stepOpt as? String, !s.isEmpty { step = s }
    else if let b = stepOpt as? Bool, b { step = "start" }
    else { return nil }
    if points.count < 2 { return nil }

    let bi = isValueAxisH ? 1 : 0   // base (category) axis index
    let vi = 1 - bi                 // value axis index
    func comp(_ p: VectorArray, _ idx: Int) -> Double { idx == 0 ? p.x : p.y }
    func make(_ base: Double, _ value: Double) -> VectorArray { bi == 0 ? VectorArray(base, value) : VectorArray(value, base) }

    var out: [VectorArray] = [points[0]]
    for i in 1..<points.count {
        let prev = points[i - 1]
        let cur = points[i]
        switch step {
        case "end":
            // horizontal to the next base coord at the previous value, then vertical to the next point.
            out.append(make(comp(cur, bi), comp(prev, vi)))
        case "middle", "center":
            let mid = (comp(prev, bi) + comp(cur, bi)) / 2
            out.append(make(mid, comp(prev, vi)))
            out.append(make(mid, comp(cur, vi)))
        default: // "start"
            out.append(make(comp(prev, bi), comp(cur, vi)))
        }
        out.append(cur)
    }
    return out
}

// upstream: function getIsIgnoreFunc(seriesModel, data, coordSys) — returns the per-point "should this
//   symbol be hidden?" predicate (or nil when every symbol is shown). `showAllSymbol === true` never
//   ignores; `'auto'` (the default) ignores densely-packed category symbols so a 10k-point line does not
//   materialise 10k Symbol groups. A non-category (value/time) axis returns nil (nothing to thin against).
private func lineGetIsIgnoreFunc(
    _ seriesModel: SeriesModel, _ data: SeriesData, _ coordSys: Cartesian2D
) -> ((Int) -> Bool)? {
    let showAllSymbol = seriesModel.get("showAllSymbol")
    let isAuto = (showAllSymbol as? String) == "auto"

    // showAllSymbol truthy and not 'auto' → explicit "show all" → never ignore.
    if lineTruthyOpt(showAllSymbol) && !isAuto {
        return nil
    }

    guard let categoryAxis = coordSys.getAxesByScale("ordinal").first else {
        return nil
    }

    // Note that category label interval strategy might bring some weird effect in some scenario: users
    //   may wonder why some of the symbols are not displayed. So we show all symbols as possible as we can.
    if isAuto
        // Simplify the logic, do not determine label overlap here.
        && lineCanShowAllSymbolForCategory(categoryAxis, data) {
        return nil
    }

    // Otherwise follow the label interval strategy on category axis.
    guard let categoryDataDim = data.mapDimension(categoryAxis.dim) else { return nil }
    var labelMap = Set<Double>()
    for labelItem in categoryAxis.getViewLabels() {
        if labelItem.tick.offInterval != true {
            labelMap.insert(axisHelper.getTickValueOutermost(categoryAxis.scale, labelItem.tick))
        }
    }

    return { dataIndex in
        return !labelMap.contains(lineToNumber(data.get(categoryDataDim, dataIndex)))
    }
}

// upstream: function canShowAllSymbolForCategory(categoryAxis, data) — estimate (by sampling ≤5 symbol
//   sizes against the per-category available pixel width) whether every symbol fits without overlap.
private func lineCanShowAllSymbolForCategory(_ categoryAxis: Axis2D, _ data: SeriesData) -> Bool {
    // In most cases, line is monotonous on category axis, and the label size is close with each other.
    //   So we check the symbol size and some of the label size alone with the category axis to estimate
    //   whether all symbol can be shown without overlap.
    let axisExtent = categoryAxis.getExtent()
    let count = (categoryAxis.scale as? OrdinalScale)?.count() ?? 0
    var availSize = abs(axisExtent[1] - axisExtent[0]) / count
    if availSize.isNaN { availSize = 0 }   // 0/0 is NaN.

    // Sampling some points, max 5.
    let dataLen = data.count()
    let step = Swift.max(1, Int((Double(dataLen) / 5).rounded()))
    let sizeIdx = categoryAxis.isHorizontal() ? 1 : 0
    var dataIndex = 0
    while dataIndex < dataLen {
        // Only for cartesian, where `isHorizontal` exists. Empirical number 1.5.
        if Symbol.getSymbolSize(data, dataIndex)[sizeIdx] * 1.5 > availSize {
            return false
        }
        dataIndex += step
    }

    return true
}

// JS truthiness for the `showAllSymbol` option: a non-empty string (e.g. 'auto') or `true` is truthy.
private func lineTruthyOpt(_ v: Any?) -> Bool {
    if let b = v as? Bool { return b }
    if let s = v as? String { return !s.isEmpty }
    return v != nil
}

// `store.get(...)` returns `ParsedValue` (Any); numeric series data is stored as `Double`. Mirrors the
//   `barGridToNumber` coercion in layout/barGrid.swift.
private func lineToNumber(_ v: Any?) -> Double {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let n = v as? NSNumber { return n.doubleValue }
    return Double.nan
}

// upstream: `lineGroup.setStyle(lineStyleModel.getLineStyle())` — the series `lineStyle` option overrides
//   the polyline width / dash type / color. We read the raw option bag (the static port has no
//   Model.getLineStyle) and apply the common keys onto the polyline style. `color: 'inherit'`/nil leaves
//   the visual stroke in place; an explicit color wins (line-item-color). `type: 'dashed' | 'dotted' |
//   number[]` maps to LineDash (line-dashed).
private func applyLineStyleOption(_ st: inout PathStyleProps, _ seriesModel: SeriesModel) {
    guard let ls = seriesModel.get("lineStyle") as? [String: Any] else { return }
    if let w = ls["width"] as? Double { st.lineWidth = w }
    else if let wi = ls["width"] as? Int { st.lineWidth = Double(wi) }
    if let c = ls["color"] as? String, c != "inherit", c != "auto", !c.isEmpty {
        st.stroke = .string(c)
    }
    if let op = ls["opacity"] as? Double { st.strokeOpacity = op }
    switch ls["type"] {
    case let s as String:
        if s == "dashed" { st.lineDash = .dashed }
        else if s == "dotted" { st.lineDash = .dotted }
        else if s == "solid" { st.lineDash = .solid }
    case let arr as [Double]:
        st.lineDash = .values(arr)
    case let arri as [Int]:
        st.lineDash = .values(arri.map { Double($0) })
    default:
        break
    }
}
