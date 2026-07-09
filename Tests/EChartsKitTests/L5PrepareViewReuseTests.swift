import XCTest
@testable import EChartsKit

final class L5PrepareViewReuseTests: XCTestCase {
    // A merge-mode second setOption on the same structure must REUSE the chart view instance.
    func testChartViewReusedAcrossMerge() {
        let ec = EChartsSlim(width: 400, height: 300)
        let opt: [String: Any] = [
            "xAxis": ["type": "category", "data": ["a", "b", "c"]],
            "yAxis": ["type": "value"],
            "series": [["type": "bar", "data": [1, 2, 3]]]
        ]
        ec.setOption(opt)
        let view1 = ec.testChartViews.first
        XCTAssertNotNil(view1)
        ec.setOption(["series": [["type": "bar", "data": [4, 5, 6]]]])
        let view2 = ec.testChartViews.first
        XCTAssertTrue(view1 === view2, "same-structure merge must reuse the chart view")
        XCTAssertEqual(ec.testChartViews.count, 1, "no duplicate views accumulate")
    }

    // A series that changes type (bar→line) in merge mode must NOT reuse the bar view — the old bar
    // view is orphaned (its _ec_<id>_bar viewId no longer resolves) and swept.
    func testDeadViewDisposedOnTypeChange() {
        let ec = EChartsSlim(width: 400, height: 300)
        ec.setOption(["xAxis": ["type": "category", "data": ["a", "b"]],
                      "yAxis": ["type": "value"],
                      "series": [["type": "bar", "data": [1, 2]]]])
        XCTAssertEqual(ec.testChartViews.count, 1)
        XCTAssertTrue(ec.testChartViews.first is BarView)
        // Merge the series to a line: the bar view is now dead and must be swept.
        ec.setOption(["series": [["type": "line", "data": [3, 4]]]])
        XCTAssertEqual(ec.testChartViews.count, 1, "dead bar view swept, one live line view remains")
        XCTAssertTrue(ec.testChartViews.first is LineView, "reused registry now holds a LineView")
    }
}
