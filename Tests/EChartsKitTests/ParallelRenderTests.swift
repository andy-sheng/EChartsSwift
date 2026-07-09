// END-TO-END RENDER TEST for the Phase-17 parallel-coordinates vertical (the FIFTH coordinate system):
// each `parallelAxis` component is drawn by a registered ParallelAxisView (AxisBuilder → an axisLine Line
// per axis, laid out left-to-right by the Parallel coord), and the chart-side ParallelView draws one
// Polyline per data item connecting its value on every axis (points from Parallel.dataToPoint per
// dimension). Drives ECharts with a real parallel option (4 value axes × 3 data lines) and asserts
// BOTH the N-axis backdrop (axis Lines >= number of axes) AND the series polylines (one Polyline per data
// item) reach the ZRenderKit scene graph, plus a GEOMETRY guard: the axis x-positions are distinct and
// strictly increasing across the 4 axes (read off each polyline's per-axis vertices).
import XCTest
import ZRenderKit
@testable import EChartsKit

final class ParallelRenderTests: XCTestCase {
    func testParallelRendersAxisBackdropAndSeriesPolylines() {
        let w = 520.0, h = 380.0
        let ec = ECharts(width: w, height: h)
        // 4 value axes (Price/Amount/Volume/Score) × 3 data lines.
        let axisCount = 4
        let lineCount = 3
        ec.setOption([
            "parallelAxis": [
                ["dim": 0, "name": "Price"]  as [String: Any],
                ["dim": 1, "name": "Amount"] as [String: Any],
                ["dim": 2, "name": "Volume"] as [String: Any],
                ["dim": 3, "name": "Score"]  as [String: Any]
            ],
            "parallel": ["left": "10%", "right": "12%",
                         "top": "10%", "bottom": "10%"] as [String: Any],
            "series": [["type": "parallel",
                        "lineStyle": ["width": 2] as [String: Any],
                        "data": [
                            [12.0, 230.0,  8.0, 90.0],
                            [24.0, 140.0, 15.0, 60.0],
                            [ 6.0, 320.0,  3.0, 75.0]
                        ]] as [String: Any]]
        ])

        var axisLines = 0                       // parallelAxis backdrops: axisLine / tick Line elements
        var polylines: [ZRenderKit.Polyline] = [] // one Polyline per data item
        _ = ec.getRoot().traverse { el in
            if let pl = el as? ZRenderKit.Polyline {
                polylines.append(pl)
            }
            else if el is ZRenderKit.Line {
                axisLines += 1
            }
            return false
        }

        // Backdrop: the N parallelAxis components reach the scene graph as at least N axis Lines
        // (each ParallelAxisView draws an axisLine, plus ticks; >= axisCount is the floor).
        XCTAssertGreaterThanOrEqual(axisLines, axisCount,
            "parallel backdrop → at least one axis Line per axis (>= \(axisCount))")

        // One Polyline per data item (3 data lines).
        XCTAssertEqual(polylines.count, lineCount, "parallel series → one Polyline per data item")

        // GEOMETRY GUARD: every polyline connects one vertex per axis (4 axes → 4 points), all finite and
        // inside the view rect; and the per-axis x-positions are DISTINCT and strictly INCREASING left to
        // right (horizontal layout — the axes are spread across the coord rect by the Parallel coord).
        for pl in polylines {
            guard let shape = pl.shape as? ZRenderKit.PolylineShape,
                  let points = shape.points else {
                return XCTFail("series line must carry a ZRenderKit.PolylineShape with points")
            }
            XCTAssertEqual(points.count, axisCount, "one polyline vertex per axis")
            // Accumulate any parent-group translation (the data group is added to the view group).
            var groupX = 0.0, groupY = 0.0
            var node: Transformable? = pl.parent
            while let n = node {
                groupX += n.x
                groupY += n.y
                node = n.parent
            }
            for p in points {
                XCTAssertTrue(p.x.isFinite && p.y.isFinite, "vertex must be finite")
                let gx = p.x + groupX
                let gy = p.y + groupY
                XCTAssertTrue(gx >= -1 && gx <= w + 1, "vertex x \(gx) within view width \(w)")
                XCTAssertTrue(gy >= -1 && gy <= h + 1, "vertex y \(gy) within view height \(h)")
            }
            // Axis x-positions strictly increasing across the 4 axes.
            for i in 1..<points.count {
                XCTAssertGreaterThan(points[i].x, points[i - 1].x,
                    "axis \(i) x (\(points[i].x)) must exceed axis \(i - 1) x (\(points[i - 1].x))")
            }
        }
    }
}
