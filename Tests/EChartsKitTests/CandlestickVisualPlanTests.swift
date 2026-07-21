import XCTest
@testable import EChartsKit

// Covers the `plan: createRenderPlanner()` wiring of `chart/candlestick/candlestickVisual.swift`
// (upstream echarts/src/chart/candlestick/candlestickVisual.ts). Mirrors LinesLayoutPlanTests: the
// planner must return `.reset` when the series' pipelineContext `large` / `progressiveRender` flag
// FLIPS and `nil` otherwise, with the per-series previous-state carried by the planner's `makeInner`
// bag — so the planner instance must be created ONCE and captured by the `handler.plan` closure.
//
// NOTE: the plan is dormant on the live render path (ECharts.runSeriesStageHandler ignores
// `handler.plan`), so no PNG/visual oracle would catch a regression back to `handler.plan = nil`
// or to a per-call `createRenderPlanner()`. These asserts are the only guard.

private final class CandlestickVisualPlanTestEChartsInstance: EChartsType {}
private final class CandlestickVisualPlanTestAPI: ExtensionAPI {
    init() { super.init(ecInstance: CandlestickVisualPlanTestEChartsInstance()) }
}

final class CandlestickVisualPlanTests: XCTestCase {

    private func makeSeries(large: Bool, progressive: Bool = false) -> SeriesModel {
        let sm = SeriesModel(nil, nil, nil)
        sm.pipelineContext = PipelineContext(
            progressiveRender: progressive, large: large, modDataCount: nil
        )
        return sm
    }

    func testCandlestickVisualHasPlan() {
        XCTAssertNotNil(candlestickVisual.plan, "candlestickVisual must wire createRenderPlanner()")
        XCTAssertEqual(candlestickVisual.seriesType, SERIES_TYPE_CANDLESTICK)
    }

    // nil (no change) -> .reset (large flipped) -> nil (unchanged again).
    func testPlanResetsOnLargeFlip() throws {
        let plan = try XCTUnwrap(candlestickVisual.plan)
        let ecModel = GlobalModel()
        let api = CandlestickVisualPlanTestAPI()
        let seriesModel = makeSeries(large: false)

        XCTAssertNil(plan(seriesModel, ecModel, api, nil), "first pass: large=false matches the initial state")

        seriesModel.pipelineContext.large = true
        XCTAssertEqual(plan(seriesModel, ecModel, api, nil), .reset, "large false->true must request a reset")

        XCTAssertNil(plan(seriesModel, ecModel, api, nil), "large unchanged at true: no reset")

        seriesModel.pipelineContext.large = false
        XCTAssertEqual(plan(seriesModel, ecModel, api, nil), .reset, "large true->false must request a reset")
    }

    // progressiveRender is the second half of the planner's condition.
    func testPlanResetsOnProgressiveFlip() throws {
        let plan = try XCTUnwrap(candlestickVisual.plan)
        let ecModel = GlobalModel()
        let api = CandlestickVisualPlanTestAPI()
        let seriesModel = makeSeries(large: false, progressive: false)

        XCTAssertNil(plan(seriesModel, ecModel, api, nil))

        seriesModel.pipelineContext.progressiveRender = true
        XCTAssertEqual(plan(seriesModel, ecModel, api, nil), .reset)
        XCTAssertNil(plan(seriesModel, ecModel, api, nil))
    }

    // The planner's state is per-series (makeInner keyed by the model), not global.
    func testPlanStateIsPerSeries() throws {
        let plan = try XCTUnwrap(candlestickVisual.plan)
        let ecModel = GlobalModel()
        let api = CandlestickVisualPlanTestAPI()
        let a = makeSeries(large: false)
        let b = makeSeries(large: true)

        XCTAssertNil(plan(a, ecModel, api, nil))
        // `b` starts large -> its own (false) initial inner state flips -> reset.
        XCTAssertEqual(plan(b, ecModel, api, nil), .reset)
        // `a` is untouched by `b`'s pass.
        XCTAssertNil(plan(a, ecModel, api, nil))
    }
}
