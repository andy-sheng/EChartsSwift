// END-TO-END RENDER TEST for the Phase-14 gauge vertical (coordless). Drives ECharts with a real
// gauge option and asserts the scene graph contains the axis arc (Sector), the split lines + ticks (Line),
// the pointer needle (PointerPath) and the title/detail text (ZRText). The pointer-angle assertion guards
// the Int-vs-Double startAngle trap (defaultOption startAngle:225 / endAngle:-45 are boxed as numbers): a
// mid-range value (50 of [0,100]) over the default 225°->-45° span must land the needle near vertical
// (pointing up). If the Int-boxed startAngle were silently dropped to 0, the needle would point elsewhere.
import XCTest
import ZRenderKit
@testable import EChartsKit

final class GaugeRenderTests: XCTestCase {
    override func setUp() {
        super.setUp()
        ComponentModel.registerClass(GaugeSeriesModel.self)
    }

    func testGaugeRendersSceneGraph() {
        let ec = ECharts(width: 460, height: 340)
        ec.setOption([
            "series": [["type": "gauge",
                        "min": 0.0, "max": 100.0,
                        "data": [["value": 50.0, "name": "SCORE"]]] as [String: Any]]
        ])

        var sectors: [ZRenderKit.Sector] = []
        var lines: [ZRenderKit.Line] = []
        var pointers: [PointerPath] = []
        var texts: [ZRenderKit.ZRText] = []
        _ = ec.getRoot().traverse { el in
            if let s = el as? ZRenderKit.Sector { sectors.append(s) }
            else if let l = el as? ZRenderKit.Line { lines.append(l) }
            else if let p = el as? PointerPath { pointers.append(p) }
            else if let t = el as? ZRenderKit.ZRText { texts.append(t) }
            return false
        }

        // Axis line: default axisLine.lineStyle.color is a single [[1, color]] stop → 1 Sector band.
        XCTAssertGreaterThanOrEqual(sectors.count, 1, "gauge axis arc band → at least one Sector")
        // splitNumber 10 → 11 split lines, plus axis ticks → many Line elements.
        XCTAssertGreaterThanOrEqual(lines.count, 11, "gauge split lines + ticks → >= 11 Line elements")
        // Exactly one datum → exactly one pointer needle.
        XCTAssertEqual(pointers.count, 1, "one gauge datum → one PointerPath needle")
        // Tick labels (11) + title ('SCORE') + detail ('50') → many ZRText elements. Assert the detail
        //   and title texts are present.
        let allText = texts.compactMap { $0.textStyle?.text }
        XCTAssertTrue(allText.contains("SCORE"), "title text 'SCORE' present; got \(allText)")
        XCTAssertTrue(allText.contains("50"), "detail text '50' present; got \(allText)")

        // ---- Pointer-angle geometry (Int-vs-Double startAngle guard) ----
        // The needle is drawn straight up in local space (shape.angle = -pi/2 → local tip at (0, -r)),
        //   then the whole Path is rotated by `rotation`. For value 50 over the default 225°->-45° span
        //   the rotation works out to ≈ -2π, i.e. the needle points straight up (world tip.x ≈ cx,
        //   tip.y < cy). We check the direction via the rotation's sin/cos: near-vertical ⇒ |sin|≈0, cos≈1.
        let rot = pointers[0].rotation
        XCTAssertLessThan(abs(sin(rot)), 0.02,
            "mid-range pointer must be vertical (|sin(rotation)| ≈ 0); rotation=\(rot)")
        XCTAssertGreaterThan(cos(rot), 0.99,
            "mid-range pointer must point UP (cos(rotation) ≈ 1); rotation=\(rot)")
    }
}
