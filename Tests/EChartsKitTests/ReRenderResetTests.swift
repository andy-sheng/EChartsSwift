// Guards against stale chart accumulation when ONE ECharts/EChartsView instance is reused across
// successive setOption calls (the live EChartsHostView path — switching demos). Upstream `prepareView`
// disposes views whose model is gone; the port originally skipped that ("fresh model each call"),
// so switching from a bar demo to a pie demo left the bar Rects lingering in the root. render() now
// resets the view registries + root each full render, so each setOption rebuilds clean.
import XCTest
@testable import EChartsKit
@testable import ZRenderKit

final class ReRenderResetTests: XCTestCase {

    private func countKind(_ el: Element, _ match: (Element) -> Bool) -> Int {
        var n = match(el) ? 1 : 0
        if let g = el as? Group {
            for c in g.children() { n += countKind(c, match) }
        }
        return n
    }

    private let barOption: [String: Any] = [
        "xAxis": ["type": "category", "data": ["a", "b", "c"]],
        "yAxis": ["type": "value"],
        "series": [["type": "bar", "data": [1.0, 2.0, 3.0]]]
    ]
    private let pieOption: [String: Any] = [
        "series": [["type": "pie", "radius": "50%",
                    "data": [["value": 1.0, "name": "x"], ["value": 2.0, "name": "y"]]]]
    ]

    func test_switching_bar_to_pie_leaves_no_stale_bar_rects() {
        let ec = ECharts(width: 400, height: 300)

        ec.setOption(barOption)
        let barsAfterBar = countKind(ec.getRoot()) { $0 is Rect }
        XCTAssertGreaterThan(barsAfterBar, 0, "bar demo should render Rect bars")

        // Switch to a pie demo on the SAME instance — bars must not linger.
        ec.setOption(pieOption)
        let barsAfterPie = countKind(ec.getRoot()) { $0 is Rect }
        let sectorsAfterPie = countKind(ec.getRoot()) { $0 is Sector }
        XCTAssertEqual(barsAfterPie, 0, "stale bar Rects lingered after switching to the pie demo")
        XCTAssertGreaterThan(sectorsAfterPie, 0, "pie demo should render Sector slices")
    }
}
