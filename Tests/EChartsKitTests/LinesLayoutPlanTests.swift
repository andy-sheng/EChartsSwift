import XCTest
@testable import EChartsKit

// Covers the `plan: createRenderPlanner()` wiring of `chart/lines/linesLayout.swift` (upstream
// echarts/src/chart/lines/linesLayout.ts). The stage's only job here is: return `.reset` when the
// series' pipelineContext `large` / `progressiveRender` flag FLIPS, and `nil` otherwise, with the
// per-series previous-state carried by the planner's `makeInner` bag (so the planner instance must
// be created once and reused, which the `handler.plan` closure captures).

private final class LinesPlanTestEChartsInstance: EChartsType {}
private final class LinesPlanTestAPI: ExtensionAPI {
    init() { super.init(ecInstance: LinesPlanTestEChartsInstance()) }
}

final class LinesLayoutPlanTests: XCTestCase {

    private func makeSeries(large: Bool, progressive: Bool = false) -> SeriesModel {
        let sm = SeriesModel(nil, nil, nil)
        sm.pipelineContext = PipelineContext(
            progressiveRender: progressive, large: large, modDataCount: nil
        )
        return sm
    }

    // The stage must actually have a plan — a regression to `handler.plan = nil` (the deviation the
    // four sibling stages still carry) would make lines never reset on a large-mode toggle.
    func testLinesLayoutHasPlan() {
        XCTAssertNotNil(linesLayout.plan, "linesLayout must wire createRenderPlanner()")
        XCTAssertEqual(linesLayout.seriesType, "lines")
    }

    // nil (no change) -> .reset (large flipped) -> nil (unchanged again).
    func testPlanResetsOnLargeFlip() throws {
        let plan = try XCTUnwrap(linesLayout.plan)
        let ecModel = GlobalModel()
        let api = LinesPlanTestAPI()
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
        let plan = try XCTUnwrap(linesLayout.plan)
        let ecModel = GlobalModel()
        let api = LinesPlanTestAPI()
        let seriesModel = makeSeries(large: false, progressive: false)

        XCTAssertNil(plan(seriesModel, ecModel, api, nil))

        seriesModel.pipelineContext.progressiveRender = true
        XCTAssertEqual(plan(seriesModel, ecModel, api, nil), .reset)
        XCTAssertNil(plan(seriesModel, ecModel, api, nil))
    }

    // The planner's state is per-series (makeInner keyed by the model), not global.
    func testPlanStateIsPerSeries() throws {
        let plan = try XCTUnwrap(linesLayout.plan)
        let ecModel = GlobalModel()
        let api = LinesPlanTestAPI()
        let a = makeSeries(large: false)
        let b = makeSeries(large: true)

        XCTAssertNil(plan(a, ecModel, api, nil))
        // `b` starts large -> its own (false) initial inner state flips -> reset.
        XCTAssertEqual(plan(b, ecModel, api, nil), .reset)
        // `a` is untouched by `b`'s pass.
        XCTAssertNil(plan(a, ecModel, api, nil))
    }
}
