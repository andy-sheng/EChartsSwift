// END-TO-END RENDER TEST for the cartesian LINE vertical (sibling of BarChartRenderTests). Drives the
// slim ECharts with a line option and inspects the ZRenderKit scene: one `Polyline` (name "line")
// with a point per datum, within the grid rect, x strictly increasing, y monotone-ish with the data,
// and a palette stroke. Phase 6c: uses the REAL LineSeriesModel (data built from the option's own
// series.data via the ported SourceManager) — no test double.

import XCTest
import ZRenderKit
@testable import EChartsKit

final class LineChartRenderTests: XCTestCase {
    // Re-register the real line model (global registry may hold doubles from other suites).
    override func setUp() { super.setUp(); ComponentModel.registerClass(LineSeriesModel.self) }

    func testLineChartRendersPolyline() {
        let width = 400.0, height = 300.0
        let ec = ECharts(width: width, height: height)
        ec.setOption([
            "grid": ["left": 50.0, "top": 20.0, "width": 300.0, "height": 200.0] as [String: Any],
            "xAxis": ["type": "category", "data": ["A", "B", "C", "D"]] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [["type": "line", "data": [10.0, 20.0, 15.0, 40.0]] as [String: Any]]
        ])

        // Collect the line Polyline(s).
        var lines: [Polyline] = []
        _ = ec.getRoot().traverse { el in
            if let p = el as? Polyline, p.name == "line" { lines.append(p) }
            return false
        }
        XCTAssertEqual(lines.count, 1, "a single line series should emit one Polyline")
        guard let line = lines.first, let shape = line.shape as? PolylineShape,
              let pts = shape.points else {
            XCTFail("polyline has no points"); return
        }
        XCTAssertEqual(pts.count, 4, "one point per datum")

        // Grid rect from the injected coordinate system.
        var grid: BoundingRect?
        ec.getModel()?.eachSeries { s, _ in
            if let c = s.coordinateSystem as? Cartesian2D { grid = c.getArea() }
        }
        guard let g = grid else { XCTFail("no cartesian area"); return }
        let tol = 0.5
        for p in pts {
            XCTAssertTrue(p.x.isFinite && p.y.isFinite, "finite point")
            XCTAssertGreaterThanOrEqual(p.x, g.x - tol); XCTAssertLessThanOrEqual(p.x, g.x + g.width + tol)
            XCTAssertGreaterThanOrEqual(p.y, g.y - tol); XCTAssertLessThanOrEqual(p.y, g.y + g.height + tol)
        }
        // x strictly increasing (A→D).
        for i in 1..<pts.count { XCTAssertLessThan(pts[i - 1].x, pts[i].x) }
        // y is screen-space (down = larger): value 40 (tallest) → smallest y; value 10 → largest y.
        XCTAssertLessThan(pts[3].y, pts[0].y, "value 40 point sits above value 10 point")

        // Stroke is a real palette color (not the #000 default).
        guard case let .string(stroke)? = line.pathStyle?.stroke else {
            XCTFail("line should have a stroke color"); return
        }
        XCTAssertFalse(stroke.isEmpty)
        XCTAssertNotEqual(stroke, "#000", "line stroke should be a palette color")
        let palette = (ec.getModel()?.get("color", true) as? [String]) ?? []
        XCTAssertTrue(palette.contains(stroke), "stroke \(stroke) should come from the palette")
    }
}
