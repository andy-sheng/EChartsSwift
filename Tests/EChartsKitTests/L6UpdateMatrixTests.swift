import XCTest
@testable import EChartsKit

// L6: the lighter update methods dispatchAction routes to. They reuse persistent views and do NOT
// re-derive series data (no restoreData / performSeriesTasks), so the DataStore from the last full
// update() survives.
final class L6UpdateMatrixTests: XCTestCase {
    func testUpdateViewReusesViewsAndKeepsDataStore() {
        let ec = ECharts(width: 400, height: 300)
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

    func testUpdateTransformReusesViewsAndKeepsDataStore() {
        let ec = ECharts(width: 400, height: 300)
        ec.setOption(["xAxis": ["type": "value"], "yAxis": ["type": "value"],
                      "series": [["type": "scatter", "data": [[1, 1], [2, 2]]]]])
        let view1 = ec.testChartViews.first
        let store1 = ec.testModel?.getSeries().first?.getData()
        ec.updateTransform()
        XCTAssertTrue(view1 === ec.testChartViews.first, "updateTransform reuses the chart view")
        XCTAssertTrue(store1 === ec.testModel?.getSeries().first?.getData(),
                      "updateTransform must not recreate the DataStore")
    }

    // Routing: sunburstRootToNode declares update:"updateView", so dispatchAction must route it to the
    // light updateView() — which reuses views and does NOT reprocess data. Proof: the series DataStore
    // instance is preserved across the dispatch (a full update() would recreate it via dataTaskReset).
    func testActionRoutesToUpdateViewPreservingDataStore() {
        let ec = ECharts(width: 400, height: 400)
        ec.setOption(["series": [["type": "sunburst",
                                  "data": [["name": "a", "value": 5, "children": [["name": "a1", "value": 3]]],
                                           ["name": "b", "value": 4]]]]])
        guard let model = ec.getModel()?.getSeriesByType("sunburst").first as? SunburstSeriesModel,
              let tree = model.getData().tree else { return XCTFail("no sunburst model/tree") }
        let storeBefore = model.getData()
        let nodeA = tree.root!.children[0]

        var drill = Payload(type: "sunburstRootToNode")
        drill.other["seriesId"] = model.id
        drill.other["targetNode"] = nodeA
        ec.dispatchAction(drill)

        XCTAssertTrue(model.getViewRoot() === nodeA, "drill re-rooted the view (updateView re-rendered)")
        XCTAssertTrue(storeBefore === model.getData(),
                      "update:updateView must be routed to updateView() — DataStore preserved, not reprocessed")
    }

    func testUpdateVisualReusesViewsAndKeepsDataStore() {
        let ec = ECharts(width: 400, height: 300)
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
