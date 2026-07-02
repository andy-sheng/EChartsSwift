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
        // PORT-TODO: polar line deferred (coord/polar not ported). Only cartesian2d is handled.
        guard let coord = seriesModel.coordinateSystem as? Cartesian2D else { return }

        let data = seriesModel.getData()
        let baseAxis = coord.getBaseAxis()
        let valueAxis = coord.getOtherAxis(baseAxis)
        // PORT-TODO: `mapDimension` is force-unwrapped — a line's base/value dims are always present.
        let baseDimIdx = data.getDimensionIndex(data.mapDimension(baseAxis.dim)!)
        let valueDimIdx = data.getDimensionIndex(data.mapDimension(valueAxis.dim)!)
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

        var shape = PolylineShape()
        shape.points = points
        let polyline = Polyline()
        polyline.setShape(shape)
        polyline.name = "line"

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
        var st = PathStyleProps()
        st.stroke = .string(stroke)
        st.fill = .string("none")
        st.lineWidth = 2
        polyline.useStyle(st)

        _ = group.add(polyline)
        self._data = data
    }
}

// `store.get(...)` returns `ParsedValue` (Any); numeric series data is stored as `Double`. Mirrors the
//   `barGridToNumber` coercion in layout/barGrid.swift.
private func lineToNumber(_ v: Any?) -> Double {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let n = v as? NSNumber { return n.doubleValue }
    return Double.nan
}
