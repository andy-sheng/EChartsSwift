// END-TO-END ENCODING TEST for the visualMap VISUAL stage (Phase 21).
// Drives ECharts with a value×value scatter series + a CONTINUOUS visualMap that colors the series by
// value, then asserts that the visualEncoding stage actually SET the per-datum visual color — i.e. the
// value->visual encoding ran end-to-end and the mapped `style.fill` VARIES across the value range (rather
// than every datum sharing the single palette color). The ENCODING is the key deliverable of this phase;
// this test asserts IT works even if the control widget does not fully render.
import XCTest
import ZRenderKit
@testable import EChartsKit

final class VisualMapEncodingTests: XCTestCase {

    /// The continuous visualMap maps each datum's value dimension (y, the last non-calc dim) through the
    /// inRange color gradient, so the four ascending values must receive four DISTINCT colors.
    func testContinuousVisualMapColorsSeriesByValue() {
        let ec = ECharts(width: 400, height: 300)
        ec.setOption([
            "grid": ["left": 50.0, "top": 20.0, "width": 300.0, "height": 200.0] as [String: Any],
            "xAxis": ["type": "value"] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "visualMap": [
                "type": "continuous",
                "min": 0.0,
                "max": 100.0,
                "calculable": true,
                "inRange": ["color": ["#50a3ba", "#eac736", "#d94e5d"]] as [String: Any]
            ] as [String: Any],
            "series": [["type": "scatter", "symbolSize": 12.0,
                        "data": [[10.0, 0.0], [20.0, 33.0], [30.0, 66.0], [40.0, 100.0]]] as [String: Any]]
        ])

        // The visualMap component resolved to the continuous subtype and loaded.
        var visualMapCount = 0
        ec.getModel()?.eachComponent("visualMap") { model, _ in
            XCTAssertEqual(model.type, "visualMap.continuous", "bare visualMap → continuous subtype")
            visualMapCount += 1
        }
        XCTAssertEqual(visualMapCount, 1, "one visualMap component should load")

        // Real data pipeline built 4 rows.
        guard let seriesModel = firstSeries(ec) else {
            return XCTFail("no series model")
        }
        let data = seriesModel.getData()
        XCTAssertEqual(data.count(), 4, "scatter should build 4 rows")

        // The encoding stage set each datum's `style.fill` (drawType 'fill' for scatter). Collect them.
        var fills: [String] = []
        for i in 0..<data.count() {
            let style = data.getItemVisual(i, "style") as? [String: Any]
            if let fill = style?["fill"] as? String, !fill.isEmpty {
                fills.append(fill)
            }
        }

        XCTAssertEqual(fills.count, 4, "every datum should carry an encoded style.fill")
        // The KEY assertion: the visualMap encoding produced DISTINCT colors across the value range (not the
        // single palette color a plain scatter would share). Ascending values → distinct gradient samples.
        XCTAssertEqual(Set(fills).count, 4, "continuous visualMap should map the 4 values to 4 distinct colors")

        // The endpoints must match the gradient endpoints (value 0 → first stop, value 100 → last stop).
        // color.parse/stringify normalize '#50a3ba' → 'rgb(80,163,186)' etc., so compare parsed RGB.
        XCTAssertEqual(parseRGB(fills.first!), parseRGB("#50a3ba"), "min value → first inRange color")
        XCTAssertEqual(parseRGB(fills.last!), parseRGB("#d94e5d"), "max value → last inRange color")
    }

    /// The `colorFromPalette` item-visual flag must be cleared once the encoding overwrites the color, so a
    /// later palette pass does not clobber the encoded color.
    func testEncodingClearsColorFromPalette() {
        let ec = ECharts(width: 400, height: 300)
        ec.setOption([
            "grid": ["left": 50.0, "top": 20.0, "width": 300.0, "height": 200.0] as [String: Any],
            "xAxis": ["type": "value"] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "visualMap": [
                "type": "continuous", "min": 0.0, "max": 100.0,
                "inRange": ["color": ["#000", "#fff"]] as [String: Any]
            ] as [String: Any],
            "series": [["type": "scatter",
                        "data": [[10.0, 0.0], [40.0, 100.0]]] as [String: Any]]
        ])
        guard let data = firstSeries(ec)?.getData() else { return XCTFail("no data") }
        for i in 0..<data.count() {
            let fromPalette = data.getItemVisual(i, "colorFromPalette") as? Bool
            XCTAssertEqual(fromPalette, false, "encoded datum should no longer be colorFromPalette")
        }
    }

    // MARK: helpers
    private func firstSeries(_ ec: ECharts) -> SeriesModel? {
        var found: SeriesModel?
        ec.getModel()?.eachSeries { s, _ in if found == nil { found = s } }
        return found
    }

    private func parseRGB(_ s: String) -> [Double]? {
        guard let arr = color.parse(s) else { return nil }
        return [arr[0], arr[1], arr[2]]
    }
}
