// END-TO-END RENDER TEST for the CUSTOM series (renderItem) vertical (sibling of Bar/Scatter render tests).
// Drives ECharts with a custom series on a cartesian2d grid whose `renderItem` closure returns one
// `rect` element per datum (a hand-rolled bar), then inspects the ZRenderKit scene: one `Rect` per datum,
// each with a finite, in-view shape. Phase 26.
import XCTest
import ZRenderKit
@testable import EChartsKit

final class CustomRenderTests: XCTestCase {
    override func setUp() { super.setUp(); ComponentModel.registerClass(CustomSeriesModel.self) }

    func testCustomRendersOneRectPerDatum() {
        let W = 400.0, H = 300.0
        let ec = ECharts(width: W, height: H)

        // renderItem returns a rect bar per datum, sized from api.coord/api.size (cartesian2d).
        //   Carried directly on the series option under "renderItem" typed EXACTLY CustomSeriesRenderItem
        //   (CustomSeriesModel.getRenderItem casts it back). util.clone passes closures through untouched.
        let renderItem: CustomSeriesRenderItem = { _, api in
            let x = (api.value(0.0, nil) as? Double) ?? 0
            let y = (api.value(1.0, nil) as? Double) ?? 0
            let top = api.coord([x, y], nil)
            let base = api.coord([x, 0.0], nil)
            guard top.count >= 2, base.count >= 2 else { return nil }
            let unitWidth = (api.size([1.0, 0.0], nil) as? [Double])?.first ?? 10.0
            let width = unitWidth * 0.6
            return [
                "type": "rect",
                "shape": [
                    "x": top[0] - width / 2,
                    "y": top[1],
                    "width": width,
                    "height": base[1] - top[1]
                ] as [String: Any],
                "style": ["fill": "#5470c6"] as [String: Any]
            ] as [String: Any]
        }

        ec.setOption([
            "grid": ["left": 50.0, "top": 20.0, "width": 300.0, "height": 200.0] as [String: Any],
            "xAxis": ["type": "value"] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [["type": "custom",
                        "renderItem": renderItem,
                        "data": [[0.0, 5.0], [1.0, 8.0], [2.0, 4.0], [3.0, 9.0], [4.0, 6.0]]] as [String: Any]]
        ])

        // Real data pipeline built 5 rows.
        var count = -1
        ec.getModel()?.eachSeries { s, _ in count = s.getData().count() }
        XCTAssertEqual(count, 5, "custom should build 5 rows from series.data")

        // The renderItem closure was resolved off the option bag (getRenderItem cast held).
        var resolved = false
        ec.getModel()?.eachSeries { s, _ in
            if let cs = s as? CustomSeriesModel, cs.getRenderItem() != nil { resolved = true }
        }
        XCTAssertTrue(resolved, "getRenderItem() should resolve the option-carried closure")

        // Collect the Rect elements the CustomChartView built into the scene graph.
        var rects: [Rect] = []
        _ = ec.getRoot().traverse { el in
            if let r = el as? Rect { rects.append(r) }
            return false
        }
        XCTAssertEqual(rects.count, 5, "custom should emit one Rect per datum")
        XCTAssertGreaterThan(rects.count, 0, "custom must emit at least one Rect")

        // Each Rect carries a finite, in-view shape (positioned via api.coord/api.size).
        for r in rects {
            guard let shape = r.shape as? RectShape else {
                XCTFail("custom Rect must carry a RectShape"); continue
            }
            XCTAssertTrue(shape.x.isFinite && shape.y.isFinite
                && shape.width.isFinite && shape.height.isFinite,
                "rect shape must be finite: \(shape)")
            XCTAssertTrue(shape.x >= 0 && shape.x <= W, "rect x in-view: \(shape.x)")
            XCTAssertTrue(shape.y >= 0 && shape.y <= H, "rect y in-view: \(shape.y)")
            XCTAssertGreaterThan(shape.width, 0, "rect width positive: \(shape.width)")
        }

        // Rects carry the fill the renderItem style bag set.
        var fills: [String] = []
        for r in rects {
            if case let .string(s)? = r.pathStyle?.fill, !s.isEmpty { fills.append(s) }
        }
        XCTAssertEqual(fills.count, 5, "each custom Rect carries the renderItem fill")
        XCTAssertEqual(Set(fills), ["#5470c6"], "custom rects use the renderItem-specified fill")
    }
}
