import XCTest
import EChartsDemoCore
import ZRenderKit
@testable import EChartsKit

final class OfficialFlameGraphInteractionTests: XCTestCase {
    @MainActor
    func testOfficialFlameGraphClickDrillsIntoOriginalStackTrace() throws {
        let demo = try XCTUnwrap(EChartsDemoRegistry.byName("official-flame-graph"))
        let drive = try XCTUnwrap(demo.drive)
        let chart = FlameGraphChartSpy()
        drive(chart)
        let click = try XCTUnwrap(chart.handlers["click"])

        var unixEvent = ECElementEvent(type: "click")
        unixEvent.data = ["name": "87f4e512-d5aa-47a0-be9f-93458bc76970"] as [String: Any]
        click(unixEvent)

        XCTAssertFalse(chart.lastNotMerge)
        XCTAssertEqual(chart.lastXAxisMax, 51_908)
        XCTAssertEqual(chart.lastSeriesData?.count, 415,
                       "the root ancestor plus the complete unix sys_syscall subtree must remain")
        XCTAssertEqual(chart.lastSeriesData?.first?["name"] as? String,
                       "29509a5f-d6bc-47c9-8828-f93f5bc71d6b")
        XCTAssertEqual(chart.lastSeriesData?[1]["name"] as? String,
                       "87f4e512-d5aa-47a0-be9f-93458bc76970")

        // A later click must filter the immutable original trace, not the prior rendered subset.
        var openEvent = ECElementEvent(type: "click")
        openEvent.data = ["name": "f245eca3-a5c1-460d-a6d4-0e16f9f4dcc4"] as [String: Any]
        click(openEvent)
        XCTAssertEqual(chart.lastXAxisMax, 49_669)
        XCTAssertEqual(chart.lastSeriesData?.count, 351)
        XCTAssertEqual(chart.lastSeriesData?[2]["name"] as? String,
                       "f245eca3-a5c1-460d-a6d4-0e16f9f4dcc4")
    }

    @MainActor
    func testOfficialFlameGraphIgnoresNonDataClick() throws {
        let demo = try XCTUnwrap(EChartsDemoRegistry.byName("official-flame-graph"))
        let drive = try XCTUnwrap(demo.drive)
        let chart = FlameGraphChartSpy()
        drive(chart)

        try XCTUnwrap(chart.handlers["click"])(ECElementEvent(type: "click"))
        XCTAssertNil(chart.lastOption)
    }

    @MainActor
    func testHoverStateDoesNotLeakIntoDrillDownReuse() throws {
        let demo = try XCTUnwrap(EChartsDemoRegistry.byName("official-flame-graph"))
        let view = EChartsView(width: demo.width, height: demo.height)
        view.setOption(demo.option)
        let chart = LiveFlameGraphChart(view)
        try XCTUnwrap(demo.drive)(chart)

        let originalData = try XCTUnwrap(view.ec.getModel()?.getSeriesByIndex(0)?.getData())
        let target = try XCTUnwrap(originalData.getItemGraphicEl(121) as? Displayable)
        let bounds = try XCTUnwrap(target.getBoundingRect())
        var hitPoint: [Double]?
        for y in 1..<20 where hitPoint == nil {
            for x in 1..<20 {
                let point = target.transformCoordToGlobal(
                    bounds.x + bounds.width * Double(x) / 20,
                    bounds.y + bounds.height * Double(y) / 20
                )
                if target.contain(point[0], point[1]),
                   view.zr.handler.findHover(point[0], point[1]).target === target {
                    hitPoint = point
                    break
                }
            }
        }
        let point = try XCTUnwrap(hitPoint)
        view._injectPointerForTest(type: "mousemove", zrX: point[0], zrY: point[1])
        XCTAssertTrue(target.currentStates.contains("emphasis"))

        view._injectPointerForTest(type: "mousedown", zrX: point[0], zrY: point[1])
        view._injectPointerForTest(type: "mouseup", zrX: point[0], zrY: point[1])
        view._injectPointerForTest(type: "click", zrX: point[0], zrY: point[1])

        let drilledData = try XCTUnwrap(view.ec.getModel()?.getSeriesByIndex(0)?.getData())
        XCTAssertEqual(drilledData.count(), 415)
        XCTAssertTrue(drilledData.getItemGraphicEl(1)?.currentStates.contains("emphasis") == true,
                      "the clicked frame remains hovered while the pointer is still over it")

        view._injectPointerForTest(type: "mousemove", zrX: 1, zrY: 1)
        view._injectGlobalOutForTest()
        var leakedStates: [(Int, [String])] = []
        for index in 0..<drilledData.count() {
            guard let element = drilledData.getItemGraphicEl(index) else { continue }
            if !element.currentStates.isEmpty { leakedStates.append((index, element.currentStates)) }
            if let label = element.getTextContent(), !label.currentStates.isEmpty {
                leakedStates.append((index, label.currentStates))
            }
        }
        XCTAssertTrue(leakedStates.isEmpty,
                      "pointer leave after custom-series reuse must clear all hover states: \(leakedStates)")
    }
}

@MainActor
private final class FlameGraphChartSpy: EChartsDemoChart {
    var handlers: [String: @MainActor (ECEventParams) -> Void] = [:]
    var lastOption: [String: Any]?
    var lastNotMerge = true

    var lastXAxisMax: Double? {
        (lastOption?["xAxis"] as? [String: Any])?["max"] as? Double
    }

    var lastSeriesData: [[String: Any]]? {
        guard let series = lastOption?["series"] as? [[String: Any]],
              let first = series.first else { return nil }
        if let data = first["data"] as? [[String: Any]] { return data }
        return (first["data"] as? [Any])?.compactMap { $0 as? [String: Any] }
    }

    func setOption(_ option: [String: Any], notMerge: Bool) {
        lastOption = option
        lastNotMerge = notMerge
    }
    func every(_ seconds: Double, _ body: @escaping @MainActor () -> Void) {}
    func after(_ seconds: Double, _ body: @escaping @MainActor () -> Void) {}
    func dispatch(_ payload: [String: Any]) {}
    func on(_ event: String, _ handler: @escaping @MainActor (ECEventParams) -> Void) {
        handlers[event] = handler
    }
}

@MainActor
private final class LiveFlameGraphChart: EChartsDemoChart {
    let view: EChartsView
    init(_ view: EChartsView) { self.view = view }

    func setOption(_ option: [String: Any], notMerge: Bool) {
        view.setOption(option, notMerge: notMerge)
    }
    func every(_ seconds: Double, _ body: @escaping @MainActor () -> Void) {}
    func after(_ seconds: Double, _ body: @escaping @MainActor () -> Void) {}
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
