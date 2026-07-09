import XCTest
@testable import EChartsKit

final class L5ModelReuseTests: XCTestCase {
    // Two merge-mode setOption calls must REUSE the same GlobalModel + the same SeriesModel
    // instance (identity), so the series keeps its prior getData() reference for diffing.
    func testMergeReusesModelAndSeries() {
        let ec = ECharts(width: 400, height: 300)
        ec.setOption([
            "xAxis": ["type": "category", "data": ["a", "b", "c"]],
            "yAxis": ["type": "value"],
            "series": [["type": "bar", "data": [1, 2, 3]]]
        ])
        let model1 = ec.testModel
        let series1 = model1?.getSeries().first
        XCTAssertNotNil(series1)

        // Merge-mode update (default notMerge:false): new data, same structure.
        ec.setOption(["series": [["type": "bar", "data": [4, 5, 6]]]])
        let model2 = ec.testModel
        let series2 = model2?.getSeries().first

        XCTAssertTrue(model1 === model2, "merge must reuse the same GlobalModel")
        XCTAssertTrue(series1 === series2, "merge must reuse the same SeriesModel instance")
    }

    // notMerge:true must REPLACE the model (fresh instance) — the demo-switch path.
    func testNotMergeReplacesModel() {
        let ec = ECharts(width: 400, height: 300)
        ec.setOption(["xAxis": ["type": "category", "data": ["a", "b", "c"]],
                      "yAxis": ["type": "value"],
                      "series": [["type": "bar", "data": [1, 2, 3]]]])
        let model1 = ec.testModel
        ec.setOption(["xAxis": ["type": "category", "data": ["a", "b"]],
                      "yAxis": ["type": "value"],
                      "series": [["type": "line", "data": [9, 9]]]], notMerge: true)
        let model2 = ec.testModel
        XCTAssertFalse(model1 === model2, "notMerge must create a fresh GlobalModel")
    }
}
