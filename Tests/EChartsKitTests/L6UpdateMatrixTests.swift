import XCTest
@testable import EChartsKit

// L6: the lighter update methods dispatchAction routes to. They reuse persistent views and do NOT
// re-derive series data (no restoreData / performSeriesTasks), so the DataStore from the last full
// update() survives.
final class L6UpdateMatrixTests: XCTestCase {
    func testUpdateViewReusesViewsAndKeepsDataStore() {
        let ec = EChartsSlim(width: 400, height: 300)
        ec.setOption(["xAxis": ["type": "category", "data": ["a", "b"]],
                      "yAxis": ["type": "value"], "series": [["type": "bar", "data": [1, 2]]]])
        let view1 = ec.testChartViews.first
        let store1 = ec.testModel?.getSeries().first?.getData()
        ec.updateView()
        let view2 = ec.testChartViews.first
        let store2 = ec.testModel?.getSeries().first?.getData()
        XCTAssertTrue(view1 === view2, "updateView reuses the chart view")
        XCTAssertTrue(store1 === store2, "updateView must not recreate the DataStore")
        XCTAssertEqual(ec.testChartViews.count, 1, "no duplicate views")
    }

    func testUpdateVisualReusesViewsAndKeepsDataStore() {
        let ec = EChartsSlim(width: 400, height: 300)
        ec.setOption(["xAxis": ["type": "category", "data": ["a", "b"]],
                      "yAxis": ["type": "value"], "series": [["type": "bar", "data": [1, 2]]]])
        let view1 = ec.testChartViews.first
        let store1 = ec.testModel?.getSeries().first?.getData()
        ec.updateVisual()
        XCTAssertTrue(view1 === ec.testChartViews.first, "updateVisual reuses the chart view")
        XCTAssertTrue(store1 === ec.testModel?.getSeries().first?.getData(),
                      "updateVisual must not recreate the DataStore")
    }
}
