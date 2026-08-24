import XCTest
@testable import EChartsDemoCore
@testable import EChartsKit

@MainActor
private final class GraphForceDynamicChartSpy: EChartsDemoChart {
    var interval: (@MainActor () -> Void)?
    var updates: [[String: Any]] = []

    func setOption(_ option: [String: Any], notMerge: Bool) { updates.append(option) }
    func every(_ seconds: Double, _ body: @escaping @MainActor () -> Void) { interval = body }
    func after(_ seconds: Double, _ body: @escaping @MainActor () -> Void) {}
    func dispatch(_ payload: [String: Any]) {}
    func on(_ event: String, _ handler: @escaping @MainActor (ECEventParams) -> Void) {}
}

final class OfficialGraphForceDynamicInteractionTests: XCTestCase {
    @MainActor
    func testLogicalTicksUseTheDeterministicWebEndpointSequence() throws {
        let demo = try XCTUnwrap(EChartsDemoRegistry.byName("official-graph-force-dynamic"))
        let drive = try XCTUnwrap(demo.drive)
        let chart = GraphForceDynamicChartSpy()
        drive(chart)
        let tick = try XCTUnwrap(chart.interval)

        tick()
        var series = try XCTUnwrap(chart.updates.last?["series"] as? [[String: Any]])
        XCTAssertEqual((series[0]["data"] as? [[String: Any]])?.count, 2)
        XCTAssertEqual((series[0]["edges"] as? [[String: Any]])?.count, 0)

        tick()
        series = try XCTUnwrap(chart.updates.last?["series"] as? [[String: Any]])
        XCTAssertEqual((series[0]["data"] as? [[String: Any]])?.count, 3)
        let edges = try XCTUnwrap(series[0]["edges"] as? [[String: Any]])
        XCTAssertEqual(edges.count, 1)
        XCTAssertEqual(edges[0]["source"] as? Int, 1)
        XCTAssertEqual(edges[0]["target"] as? Int, 0)
    }
}
