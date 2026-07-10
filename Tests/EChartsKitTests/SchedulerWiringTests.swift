import XCTest
@testable import EChartsKit
@testable import ZRenderKit

// Sub-project C1 (T1+T2): the ported Scheduler is now constructed on the first setOption and its
// pipelines are (re)built each setOption via restorePipelines + prepareStageTasks — matching upstream
// prepare() (echarts.ts:1675-1676). update() does NOT yet route through it (that is C1-T3+), so this
// only asserts the pipeline machinery runs without corrupting the render (the full suite stays green)
// and that the getTargetSeries side-effect (dataZoom AxisProxy creation) now happens at setOption.
final class SchedulerWiringTests: XCTestCase {

    func testSchedulerBuildsOnePipelinePerSeries() {
        let ec = ECharts(width: 400, height: 300)
        ec.setOption([
            "xAxis": ["type": "category", "data": ["A", "B", "C"]],
            "yAxis": ["type": "value"],
            "series": [
                ["type": "bar", "data": [1, 2, 3]] as [String: Any],
                ["type": "line", "data": [3, 2, 1]] as [String: Any]
            ]
        ])
        XCTAssertNotNil(ec.testScheduler, "Scheduler is constructed on the first setOption")
        XCTAssertEqual(ec.testScheduler?.testPipelineCount, 2,
                       "restorePipelines builds one pipeline per series (2 series here)")
    }

    func testPipelinesRebuildOnMergeSetOption() {
        let ec = ECharts(width: 400, height: 300)
        ec.setOption([
            "xAxis": ["type": "category", "data": ["A", "B"]],
            "yAxis": ["type": "value"],
            "series": [["type": "bar", "data": [1, 2]] as [String: Any]]
        ])
        XCTAssertEqual(ec.testScheduler?.testPipelineCount, 1)

        // A merge-mode setOption adding a second series must rebuild the pipelines (not crash / stale).
        ec.setOption([
            "series": [
                ["type": "bar", "data": [1, 2]] as [String: Any],
                ["type": "line", "data": [2, 1]] as [String: Any]
            ]
        ])
        XCTAssertEqual(ec.testScheduler?.testPipelineCount, 2,
                       "prepareStageTasks re-runs each setOption; pipelines track the current series count")
    }

    func testDataZoomAxisProxyCreatedAtSetOption() {
        // prepareStageTasks runs dataZoomProcessor.getTargetSeries, whose side-effect creates the
        // AxisProxy on the target axis model. It must exist right after setOption (before any update
        // re-derives it), proving the Scheduler's overall-stage-task machinery executed.
        let ec = ECharts(width: 400, height: 300)
        ec.setOption([
            "xAxis": ["type": "category", "data": ["A", "B", "C", "D"]],
            "yAxis": ["type": "value"],
            "dataZoom": [["type": "inside", "xAxisIndex": 0] as [String: Any]],
            "series": [["type": "bar", "data": [1, 2, 3, 4]] as [String: Any]]
        ])
        let xAxisModel = ec.testModel?.getComponent("xAxis", 0) as? AxisBaseModel
        XCTAssertNotNil(xAxisModel, "xAxis model exists")
        XCTAssertNotNil(getAxisProxyFromModel(xAxisModel),
                        "dataZoom AxisProxy is created by prepareStageTasks' getTargetSeries at setOption")
    }
}
