// chart/graph/createView.swift — the pure box/scale computation (`createViewCoordSys`).
// Both cases below are SILENT-failure classes: they render a plausible-looking chart rather than
// crashing, so they need explicit assertions.
//   (a) an empty graph must fall through the `isNaN(aspect)` branch to the VIEW RECT, not to the
//       (-1, -1, 2, 2) box a zero-seeded bbox would produce;
//   (b) a JS-`null` coordinate must coerce to 0 (`+null === 0`), not NaN — a single NaN taints the
//       whole `bbox.fromPoints` accumulation and flips the entire series onto the fallback.
import XCTest
@testable import EChartsKit
@testable import ZRenderKit

final class GraphCreateViewTests: XCTestCase {

    private func graphCoordSys(_ ec: ECharts) -> GraphViewCoordSys? {
        var cs: GraphViewCoordSys?
        ec.getModel()?.eachSeriesByType("graph") { s, _ in
            cs = (s as? GraphSeriesModel)?.coordinateSystem as? GraphViewCoordSys
        }
        return cs
    }

    // (a) `data: []` -> no positions -> min/max stay NaN -> aspect NaN -> the view-rect fallback.
    func test_empty_graph_box_falls_back_to_view_rect() {
        let ec = ECharts(width: 400, height: 300)
        ec.setOption([
            "animation": false,
            "series": [[
                "type": "graph", "layout": "none",
                "left": "10%", "right": "10%", "top": "10%", "bottom": "10%",
                "data": [] as [Any]
            ] as [String: Any]]
        ])

        guard let cs = graphCoordSys(ec),
              let box = cs.getBoundingRect(), let viewRect = cs.getViewRect() else {
            return XCTFail("graph series must carry a view coord sys")
        }
        XCTAssertEqual(box.x, viewRect.x, accuracy: 1e-9)
        XCTAssertEqual(box.y, viewRect.y, accuracy: 1e-9)
        XCTAssertEqual(box.width, viewRect.width, accuracy: 1e-9)
        XCTAssertEqual(box.height, viewRect.height, accuracy: 1e-9)
        // Guard the specific regression: a (0,0)-seeded bbox yields the ±1-padded unit box.
        XCTAssertFalse(box.x == -1 && box.y == -1 && box.width == 2 && box.height == 2,
                       "empty graph must not collapse to the (-1, -1, 2, 2) padded-zero box")
    }

    // (b) `x: null` is `+null === 0`, so the node lands at 0 and the bbox stays finite.
    func test_null_coordinate_coerces_to_zero_not_nan() {
        let ec = ECharts(width: 400, height: 300)
        ec.setOption([
            "animation": false,
            "series": [[
                "type": "graph", "layout": "none",
                "left": "10%", "right": "10%", "top": "10%", "bottom": "10%",
                "data": [
                    ["name": "a", "x": 0.0, "y": 0.0] as [String: Any],
                    ["name": "b", "x": NSNull(), "y": 10.0] as [String: Any]
                ]
            ] as [String: Any]]
        ])

        guard let cs = graphCoordSys(ec), let box = cs.getBoundingRect() else {
            return XCTFail("graph series must carry a view coord sys")
        }
        XCTAssertTrue(box.x.isFinite && box.y.isFinite && box.width.isFinite && box.height.isFinite,
                      "a null coordinate must not poison the bbox with NaN, got \(box)")
        // y spans 0...10 (both nodes real); x is degenerate (both 0) so it gets the ±1 padding.
        XCTAssertEqual(box.y, 0.0, accuracy: 1e-9)
        XCTAssertEqual(box.height, 10.0, accuracy: 1e-9)
        XCTAssertEqual(box.width, 2.0, accuracy: 1e-9)
    }
}
