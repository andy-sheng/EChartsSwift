// Phase 52 regression test — coordinate markLine now RENDERS. The Phase-51 axis witnesses let the
// marker helpers resolve `coordSys.getAxis`/`dataToPoint`, so a `markLine:{data:[{yAxis:v}]}` produces a
// horizontal reference Polyline. (Statistic markers — min/max/average — still approximate their anchor
// dataIndex via the stubbed indicesOfNearest; the coordinate-value markers are exact.)
import XCTest
import ZRenderKit
@testable import EChartsKit

final class ZZMarkerTests: XCTestCase {

    override func setUp() {
        super.setUp()
        ComponentModel.registerClass(BarSeriesModel.self)
    }

    private func makeChart(_ markLine: [String: Any]) -> EChartsView {
        let view = EChartsView(width: 460, height: 300)
        view.setOption([
            "grid": ["left": 50.0, "top": 20.0, "width": 380.0, "height": 240.0] as [String: Any],
            "xAxis": ["type": "category", "data": ["A","B","C","D","E"]] as [String: Any],
            "yAxis": ["type": "value", "min": 0.0, "max": 20.0] as [String: Any],
            "series": [["type": "bar", "data": [5.0, 9, 7, 12, 6], "markLine": markLine] as [String: Any]]
        ])
        return view
    }

    // Collect the markLine Polylines from the live display list (series bars are Rects, not Polylines).
    private func polylines(_ view: EChartsView) -> [Polyline] {
        _ = view.zr.storage.getDisplayList(true)
        return view.zr.storage.getDisplayList(false).compactMap { $0 as? Polyline }
    }

    // ---- a coordinate markLine at yAxis:8 renders one horizontal reference Polyline ----
    func testCoordinateMarkLineRenders() {
        // The markLine component must be auto-enabled (preprocessor) and its view registered.
        let view = makeChart(["data": [["yAxis": 8.0] as [String: Any]]])
        XCTAssertNotNil(view.ec.getModel()?.getComponent("markLine"),
                        "a series markLine must auto-enable the master markLine component")

        let lines = polylines(view)
        XCTAssertGreaterThanOrEqual(lines.count, 1, "a {yAxis:8} markLine must render a reference Polyline")

        // The line is horizontal: both endpoints share ~the same y (the pixel for value 8), and it spans
        // a meaningful x width across the grid.
        guard let shape = lines.first?.shape as? PolylineShape, let pts = shape.points, pts.count >= 2 else {
            XCTFail("markLine Polyline must carry a 2-point shape"); return
        }
        let y0 = pts[0][1], y1 = pts[pts.count - 1][1]
        XCTAssertEqual(y0, y1, accuracy: 1.0, "a {yAxis:v} markLine must be horizontal (equal endpoint y)")
        // value 8 of [0,20] over a 240px plot from top=20 → y ≈ 20 + (1 - 8/20)*240 = 20 + 144 = 164.
        XCTAssertEqual(y0, 164.0, accuracy: 12.0, "the line sits at the pixel for value 8 on the y-axis")
        let xSpan = abs(pts[pts.count - 1][0] - pts[0][0])
        XCTAssertGreaterThan(xSpan, 100.0, "the markLine spans across the grid width")
    }

    // ---- a STATISTIC markLine (type:'average') renders at the computed average value ----
    func testAverageMarkLineRenders() {
        // data [5,9,7,12,6] → average = 7.8. Line pixel y ≈ 20 + (1 - 7.8/20)*240 ≈ 166.4.
        let view = makeChart(["data": [["type": "average"] as [String: Any]]])
        let lines = polylines(view)
        XCTAssertGreaterThanOrEqual(lines.count, 1, "a type:'average' markLine must render a reference line")
        guard let shape = lines.first?.shape as? PolylineShape, let pts = shape.points, pts.count >= 2 else {
            XCTFail("average markLine must carry a 2-point shape"); return
        }
        let y0 = pts[0][1], y1 = pts[pts.count - 1][1]
        XCTAssertEqual(y0, y1, accuracy: 1.0, "an average markLine is horizontal")
        XCTAssertEqual(y0, 166.4, accuracy: 12.0, "the line sits at the pixel for the average value 7.8")
    }

    // ---- no markLine option → no markLine component, no reference Polyline ----
    func testNoMarkLineNoComponent() {
        let view = makeChart([String: Any]())   // empty markLine → no data → submodel skipped
        // With no data the master component may still exist (preprocessor injects it), but it renders nothing.
        XCTAssertEqual(polylines(view).count, 0, "an empty markLine must not draw any reference line")
    }
}
