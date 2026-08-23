import XCTest
@testable import EChartsDemoCore
@testable import EChartsKit

@MainActor
private final class ScatterMapBrushTestChart: EChartsDemoChart {
    let view: EChartsView
    init(_ view: EChartsView) { self.view = view }

    func setOption(_ option: [String: Any], notMerge: Bool) {
        view.setOption(option, notMerge: notMerge)
    }
    func appendData(seriesIndex: Int, data: [Double]) {}
    func every(_ seconds: Double, _ body: @escaping @MainActor () -> Void) {}
    func after(_ seconds: Double, _ body: @escaping @MainActor () -> Void) { body() }
    func dispatch(_ payload: [String: Any]) {
        guard let type = payload["type"] as? String else { return }
        var action = Payload(type: type)
        action.other = payload.filter { $0.key != "type" }
        view.ec.dispatchAction(action)
        view.syncAfterAction()
    }
    func on(_ event: String, _ handler: @escaping @MainActor (ECEventParams) -> Void) {
        view.on(event) { params in MainActor.assumeIsolated { handler(params) } }
    }
}

final class OfficialScatterMapInteractionTests: XCTestCase {
    func testTooltipUsesPM25DimensionInsteadOfLatitude() throws {
        let view = EChartsView(width: 640, height: 420)
        defer { view.dispose() }
        view.setOption(EChartsDemoRegistry.official_scatter_map.option)

        let model = try XCTUnwrap(view.ec.getModel())
        let series = try XCTUnwrap(model.getSeriesByIndex(0))
        let params = series.getDataParams(95)
        XCTAssertEqual(params.name, "三亚")
        let values = try XCTUnwrap(params.value as? [Any])
        XCTAssertEqual(values[1] as? Double, 18.252847)
        XCTAssertEqual(values[2] as? Double, 54)

        let tooltip = try XCTUnwrap(model.getComponent("tooltip"))
        let formatter = try XCTUnwrap(
            tooltip.get("formatter") as? (TooltipCallbackDataParams) -> String
        )
        XCTAssertEqual(formatter(params), "三亚 : 54")
    }

    func testMapBrushVisualHarnessTargetsOwnedGeoAfterArming() throws {
        let demo = EChartsDemoRegistry.official_scatter_map_brush
        for (name, data) in demo.mapRegistrations { ECharts.registerMap(name, data) }
        let view = EChartsView(width: demo.width, height: demo.height)
        defer { view.dispose() }
        view.setOption(demo.option)

        var arm = Payload(type: "takeGlobalCursor")
        arm.other["key"] = "brush"
        arm.other["brushOption"] = [
            "brushType": "rect", "brushMode": "single",
        ] as [String: Any]
        view.ec.dispatchAction(arm)
        let geos = view.ec.getModel()?.findComponents(
            QueryConditionKindA(mainType: "geo")
        ).compactMap { $0 as? GeoModel } ?? []
        XCTAssertEqual(geos.count, 1)
        XCTAssertNotNil(geos.first?.coordinateSystem as? Geo)
        if let rect = (geos.first?.coordinateSystem as? Geo)?.getViewRect() {
            XCTAssertGreaterThan(rect.width, 0)
            XCTAssertGreaterThan(rect.height, 0)
        }
        XCTAssertNotNil(view._injectBrushDragForTest(
            targetType: "geo", componentIndex: 0, brushType: "rect"
        ))
    }

    @MainActor
    func testMapBrushDriveBuildsAndClearsLiveRanking() async throws {
        let demo = EChartsDemoRegistry.official_scatter_map_brush
        for (name, data) in demo.mapRegistrations { ECharts.registerMap(name, data) }
        let view = EChartsView(width: demo.width, height: demo.height)
        defer { view.dispose() }
        view.setOption(demo.option)
        let chart = ScatterMapBrushTestChart(view)
        try XCTUnwrap(demo.drive)(chart)

        let statistic = try XCTUnwrap(view.ec.getModel()?.getComponent("title", 1))
        let ranking = try XCTUnwrap(view.ec.getModel()?.getSeriesByIndex(2))
        XCTAssertTrue((statistic.get("text") as? String)?.hasPrefix("平均: ") == true)
        XCTAssertGreaterThan(ranking.getData().count(), 0,
                             "the initial dispatched polygon must populate the live TOP20 ranking")

        chart.dispatch(["type": "brush", "areas": [[String: Any]]()])
        try await _Concurrency.Task<Never, Never>.sleep(nanoseconds: 400_000_000)
        let clearedStatistic = try XCTUnwrap(view.ec.getModel()?.getComponent("title", 1))
        let clearedRanking = try XCTUnwrap(view.ec.getModel()?.getSeriesByIndex(2))
        XCTAssertEqual(clearedStatistic.get("text") as? String, "")
        XCTAssertEqual(clearedRanking.getData().count(), 0,
                       "clearing the brush must clear the ranking rather than retain a static frame")
    }
}
