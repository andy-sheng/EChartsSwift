// Ported (MINIMAL SUBSET) from echarts/src/chart/line/LineView.ts — keep in sync with upstream.
//
// Draws a cartesian line series as a single `Polyline` through the data points. This is the minimal
// slice: no symbols, areaStyle, step, stacking, clipping, or draw-on animation (all documented
// PORT-TODOs). It mirrors upstream's core — build the point array from `coord.dataToPoint` per datum,
// create the polyline, and stroke it with the series' visual color — enough for the line vertical to
// render end-to-end (matching the echarts.js reference in EChartsDemoGallery).

import Foundation
import ZRenderKit

// upstream: class LineView extends ChartView { static type = 'line'; type = LineView.type; ... }
open class LineView: ChartView {

    private var _data: SeriesData?

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
        // PORT-TODO: only cartesian2d + polar are handled (geo/single/calendar line deferred).
        guard let coord = seriesModel.coordinateSystem as? Cartesian2D else { return }

        let data = seriesModel.getData()
        let baseAxis = coord.getBaseAxis()
        let valueAxis = coord.getOtherAxis(baseAxis)
        // PORT-TODO: `mapDimension` is force-unwrapped — a line's base/value dims are always present.
        let baseDimName = data.mapDimension(baseAxis.dim)!
        let valueDimName = data.mapDimension(valueAxis.dim)!
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
        group.removeAll()
        if points.count < 2 { self._data = data; return }

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

        // ── areaStyle pass ──────────────────────────────────────────────────────────────────────
        // upstream LineView builds an `ECPolygon` between the line points and `stackedOnPoints`
        //   (the baseline). Minimal port: a Polygon whose ring is the line points followed by the
        //   reversed baseline points. Baseline = the stackedOver value per datum for a stacked area,
        //   else the value-axis origin (0 clamped into the scale extent). Added BEFORE the polyline so
        //   it sits underneath. PORT-TODO: `origin` option ('start'/'end'/number), gradient decal.
        let areaStyleModel = seriesModel.getModel("areaStyle")
        if !areaStyleModel.isEmpty() {
            let sExtent = valueAxis.scale.getExtent()
            let origin = Swift.min(Swift.max(0, sExtent[0]), sExtent[1])
            let stackedOverDimName = data.getCalculationInfo("stackedOverDimension") as? String
            let stackedOverDimIdx = stackedOverDimName.map { data.getDimensionIndex($0) }
            var baselinePts: [VectorArray] = []
            for i in 0..<data.count() {
                let baseVal = lineToNumber(store.get(baseDimIdx, i))
                let baselineVal: Double = (stacked && stackedOverDimIdx != nil)
                    ? lineToNumber(store.get(stackedOverDimIdx!, i))
                    : origin
                let bp = isValueAxisH ? coord.dataToPoint([baselineVal, baseVal]) : coord.dataToPoint([baseVal, baselineVal])
                if bp.count >= 2 && bp[0].isFinite && bp[1].isFinite {
                    baselinePts.append(VectorArray(bp[0], bp[1]))
                }
            }
            if baselinePts.count == points.count {
                // Area top edge follows the same step staircase as the line (when stepped).
                let topPts = steppedPoints ?? points
                var polyPts = topPts
                polyPts.append(contentsOf: baselinePts.reversed())
                var pShape = PolygonShape()
                pShape.points = polyPts
                if steppedPoints == nil { pShape.smooth = smoothVal }
                let areaPoly = Polygon()
                areaPoly.setShape(pShape)
                areaPoly.name = "area"
                var areaDict = areaStyleModel.getAreaStyle()
                if areaDict["opacity"] == nil { areaDict["opacity"] = 0.7 }
                var aStyle = barStyleFromDict(areaDict)
                // Fill defaults to the series color; gradient/pattern area fills (not bridged) also fall
                //   back to the solid series color so the area is never the spurious black default.
                if aStyle.fill == nil { aStyle.fill = .string(stroke) }
                aStyle.stroke = nil
                areaPoly.useStyle(aStyle)
                areaPoly.pathStyle.stroke = nil
                _ = group.add(areaPoly)
            }
        }

        var shape = PolylineShape()
        if let steppedPoints = steppedPoints {
            shape.points = steppedPoints   // step overrides smooth
        } else {
            shape.points = points
            shape.smooth = smoothVal
        }
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

        // ── SymbolDraw pass (statically inlined) ────────────────────────────────────────────────
        // upstream: LineView creates a `SymbolDraw` and calls `symbolDraw.updateData(data, {...})`,
        //   which enters/updates one `Symbol` (graphic.Path) per datum. We omit the diff/animation
        //   machinery and just build a symbol per point when `showSymbol` is truthy and the resolved
        //   symbol type is not 'none' — enough for a static render.
        // PORT-TODO: SymbolDraw enter/leave animation, symbolRotate/symbolOffset, endLabel, and
        //   showAllSymbol / 'auto' sampling (upstream hides symbols when points are dense) — the
        //   static port always shows them when showSymbol != false. emphasis/label = PORT-TODO.
        let showSymbol = seriesModel.get("showSymbol")
        // upstream truthiness: draw unless showSymbol is explicitly false.
        if (showSymbol as? Bool) != false {
            let seriesSymbol = (seriesModel.get("symbol") as? String) ?? "emptyCircle"
            let seriesSymbolSize: Any = seriesModel.get("symbolSize") ?? 4.0
            // Re-project per datum (rather than reusing `points`) so each symbol tracks its own datum
            //   even where a non-finite coord was dropped from the polyline point array above.
            for i in 0..<data.count() {
                let baseVal = lineToNumber(store.get(baseDimIdx, i))
                let value = lineToNumber(store.get(valueDimIdx, i))
                let p = isValueAxisH ? coord.dataToPoint([value, baseVal]) : coord.dataToPoint([baseVal, value])
                if !(p.count >= 2 && p[0].isFinite && p[1].isFinite) { continue }

                // upstream resolves the per-item symbol/size via the symbol visual stage
                //   (data.getItemVisual(i, 'symbol' / 'symbolSize')), falling back to the series option.
                let symbolType = (data.getItemVisual(i, "symbol") as? String) ?? seriesSymbol
                if symbolType == "none" { continue }
                let symbolSizeVisual = data.getItemVisual(i, "symbolSize") ?? seriesSymbolSize
                let (w, h) = symbol.normalizeSymbolSize(symbolSizeVisual)

                // Color the symbol with the line's resolved stroke (matches upstream, where the symbol
                //   adopts the line's visual color): emptyCircle → stroke=lineColor/fill=neutral00/lw=2,
                //   solid → fill=lineColor. createSymbol positions the symbol's top-left at (x, y), so
                //   offset by half the size to center it on the point.
                let el = symbol.createSymbol(symbolType, p[0] - w / 2, p[1] - h / 2, w, h, ZRenderKit.ZRColor.string(stroke))
                if let element = el as? Path {
                    element.name = "symbol"

                    // upstream (SymbolDraw/Symbol._updateCommon): each data-point symbol is marked a
                    //   highDown dispatcher carrying its emphasis-state itemStyle, so a hover restyles
                    //   it. Mirror BarView.updateStyle's block. PORT-TODO: the line PATH itself also gets
                    //   line-emphasis upstream (LineView emphasis lineStyle) — deferred; only the
                    //   data-point symbols are dispatchers here.
                    let itemModel = data.getItemModel(i)
                    let emphasisModel = itemModel.getModel(["emphasis"])
                    let focus: InnerFocus? = emphasisModel.get("focus")
                    let blurScope = (emphasisModel.get("blurScope") as? String).flatMap { BlurScope(rawValue: $0) }
                    let isDisabled = (emphasisModel.get("disabled") as? Bool) ?? false
                    states.toggleHoverEmphasis(element, focus, blurScope, isDisabled)
                    states.setStatesStylesFromModel(element, itemModel)

                    // upstream SymbolDraw calls `data.setItemGraphicEl(idx, symbolEl)`; needed so the
                    //   live Handler hit-test / tooltip can resolve the per-point element.
                    data.setItemGraphicEl(i, element)
                    _ = group.add(element)   // added AFTER the polyline so symbols sit on top
                }
            }
        }

        self._data = data
    }

    // Minimal polar line: project each datum through the polar coord (radius/angle dims, like
    //   ScatterView's polar branch) and stroke a polyline through the points, then place the data
    //   symbols. areaStyle/step/stacking + line emphasis are deferred on polar.
    private func renderPolarLine(_ seriesModel: SeriesModel, _ coord: Polar) {
        let data = seriesModel.getData()
        let store = data.getStore()
        let group = self.group
        group.removeAll()

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
