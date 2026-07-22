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

    // MarkAreaView implements the transform-only hook. Two things must hold, both regressed silently
    // before: (a) the hook is DISPATCHED through the 4-param `ComponentView.updateTransform` base
    // signature (a narrower 3-param method does not override and is never called — the Swift
    // protocol/override-witness trap), and (b) it reports "handled in place" as `false`, upstream's
    // void-from-an-implemented-hook (`nil` is the base "no hook" value → full render).
    // The call below goes through a `ComponentView`-typed reference, so it only reaches MarkAreaView's
    // body via dynamic dispatch; the item layout it rewrites must stay the typed MarkAreaItemLayout
    // (a raw `[[Double]]` there would trap the `as?`/reader contract) and must preserve `allClipped`.
    func testUpdateTransformIsDispatchedAndHandledInPlaceByMarkArea() {
        let ec = ECharts(width: 400, height: 300)
        ec.setOption(["xAxis": ["type": "value"], "yAxis": ["type": "value"],
                      "series": [["type": "line", "data": [[1, 1], [2, 2], [3, 3]],
                                  "markArea": ["data": [[["xAxis": 1], ["xAxis": 2]]]]]]])
        guard let maView = ec.testComponentViews.first(where: { $0 is MarkAreaView }) else {
            return XCTFail("no markArea view")
        }
        guard let ecModel = ec.testModel, let seriesModel = ecModel.getSeries().first,
              let maModel = MarkerModel.getMarkerModelFromSeries(seriesModel, "markArea")
        else { return XCTFail("no markArea model") }

        let areaData = maModel.getData()
        let layoutBefore = areaData.getItemLayout(0) as? MarkAreaItemLayout
        XCTAssertNotNil(layoutBefore, "renderSeries writes a typed MarkAreaItemLayout")
        // Wipe the layout so a no-op (never-dispatched) hook cannot pass by accident; keep a
        // distinctive allClipped so the preserve-the-flag contract is observable.
        areaData.setItemLayout(0, MarkAreaItemLayout(points: [], allClipped: true))

        let handled = maView.updateTransform(maModel, ecModel, ec.testExtensionAPIForTests,
                                             Payload(type: ""))

        XCTAssertEqual(handled, false, "implemented transform-only hook returns false (upstream void)")
        guard let layoutAfter = areaData.getItemLayout(0) as? MarkAreaItemLayout else {
            return XCTFail("updateTransform must keep the typed MarkAreaItemLayout, not a raw array")
        }
        XCTAssertEqual(layoutAfter.points.count, 4, "the hook ran and re-laid out the 4 corners")
        XCTAssertEqual(layoutAfter.points, layoutBefore?.points, "same transform → same pixel corners")
        XCTAssertTrue(layoutAfter.allClipped, "allClipped preserved (upstream's raw write drops it)")
    }
}

extension ECharts {
    /// Test-only accessor: a fresh ExtensionAPI bound to this instance (the driver's `_api` is private).
    var testExtensionAPIForTests: ExtensionAPI { EChartsExtensionAPI(ec: self) }
}
