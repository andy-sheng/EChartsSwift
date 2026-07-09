// END-TO-END RENDER TEST for the Phase-13 polar vertical: the polar COORDINATE SYSTEM (Polar +
// AngleAxis/RadiusAxis, the second non-cartesian coord sys wired) + the `angleAxis`/`radiusAxis`
// component backdrop (AngleAxisView draws the angle ring axisLine Circle + split lines + labels;
// RadiusAxisView draws the radial axis line + ticks + split lines) + ScatterView placing each datum
// on polar via `dataToPoint([radius, angle])`. Drives ECharts with a real polar option and asserts
// BOTH the backdrop (the angle-axis ring Circle + split/tick Lines) and the scatter symbols reach the
// ZRenderKit scene graph.
import XCTest
import ZRenderKit
@testable import EChartsKit

final class PolarChartRenderTests: XCTestCase {

    private func makePolarChart() -> ECharts {
        let ec = ECharts(width: 460, height: 360)
        ec.setOption([
            "polar": [
                "center": ["50%", "54%"],
                "radius": "70%"
            ] as [String: Any],
            "angleAxis": [
                "type": "value",
                "startAngle": 0.0
            ] as [String: Any],
            "radiusAxis": [
                "type": "value"
            ] as [String: Any],
            "series": [[
                "type": "scatter",
                "coordinateSystem": "polar",
                "symbolSize": 10.0,
                "data": [
                    [1.0, 0.0], [2.0, 40.0], [3.0, 80.0], [4.0, 120.0],
                    [5.0, 160.0], [6.0, 200.0], [7.0, 240.0], [8.0, 280.0],
                    [9.0, 320.0], [10.0, 360.0]
                ]
            ] as [String: Any]]
        ])
        return ec
    }

    func testPolarRendersBackdropAndScatter() {
        let ec = makePolarChart()

        var scatterItems = 0      // scatter symbols: Path named "item" (ScatterView)
        var ringCircles = 0       // angle-axis ring: full-360 axisLine Circle (AngleAxisView), NOT a scatter symbol
        var mergedPaths = 0       // split lines / ticks merged via mergePath (AngleAxisView/RadiusAxisView)
        var lines = 0             // any non-merged Line (radial axis line / ticks)
        _ = ec.getRoot().traverse { el in
            if el.name == "item", el is Path { scatterItems += 1 }
            else if let c = el as? ZRenderKit.Circle, c.name != "item" { ringCircles += 1 }
            else if el is ZRenderKit.Line { lines += 1 }
            else if el is Path { mergedPaths += 1 }
            return false
        }

        // Scatter: 10 data points → 10 symbols.
        XCTAssertEqual(scatterItems, 10, "polar scatter → one symbol Path per datum")
        // Backdrop: the full-360 angle-axis ring is drawn as a Circle.
        XCTAssertGreaterThan(ringCircles, 0, "polar backdrop → angle-axis ring Circle")
        // Backdrop: split lines / ticks reach the scene graph (merged Paths and/or raw Lines).
        XCTAssertGreaterThan(lines + mergedPaths, 0, "polar backdrop → radius/angle split + tick geometry")
    }
}
