// Phase 29 regression tests — the action-dispatch round-trip (interaction substrate, Phase A step 1).
// Proves, headlessly (no UIView/pointer host), that:
//   registerAction(...) + ec.dispatchAction(payload) -> doDispatchAction -> actionInfo.action(...)
//   -> update() -> render() actually runs and rebuilds the display list.
import XCTest
import ZRenderKit
@testable import EChartsKit

// Global capture box the test action writes to. registerAction dedups by type (idempotent), so the
// FIRST registration's closure is the one kept — it references this box, which both tests read/reset.
private enum ZZActionProbe {
    static var runCount = 0
    static var sawCorrectModel = false
    static var sawApi = false
    static func reset() { runCount = 0; sawCorrectModel = false; sawApi = false }
}

final class ZZActionDispatchTests: XCTestCase {

    override func setUp() {
        super.setUp()
        ComponentModel.registerClass(BarSeriesModel.self)
        ZZActionProbe.reset()
    }

    private func makeBarChart() -> EChartsSlim {
        let ec = EChartsSlim(width: 400, height: 300)
        ec.setOption([
            "grid": ["left": 50.0, "top": 20.0, "width": 300.0, "height": 200.0] as [String: Any],
            "xAxis": ["type": "category", "data": ["A", "B", "C"]] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [["type": "bar", "data": [10.0, 20.0, 30.0]] as [String: Any]]
        ])
        return ec
    }

    // The full round-trip: a registered plain action runs, receives the right model/api, and drives a
    // re-render that rebuilds the display list.
    func testDispatchActionRunsHandlerAndReRenders() {
        let ec = makeBarChart()

        // A plain action (default update == "update") whose handler records that it ran with the
        // correct ecModel + api, then returns nil (no event object).
        registerAction("zzactionprobe") { payload, ecModel, api in
            ZZActionProbe.runCount += 1
            // getModel() on the ec instance must be the SAME object the round-trip handed the handler.
            ZZActionProbe.sawCorrectModel = (ecModel === ec.getModel())
            ZZActionProbe.sawApi = true
            _ = api
            _ = payload
            return nil
        }

        let before = ec.getStorage().getDisplayList(true, nil)
        XCTAssertGreaterThan(before.count, 0, "setOption should have produced a display list")
        let beforeFirstId = before.first.map { ObjectIdentifier($0) }

        ec.dispatchAction(Payload(type: "zzactionprobe"))

        // (1) handler ran exactly once, with the correct model + api.
        XCTAssertEqual(ZZActionProbe.runCount, 1, "the registered action handler must run once")
        XCTAssertTrue(ZZActionProbe.sawCorrectModel, "handler must receive the ec's own GlobalModel")
        XCTAssertTrue(ZZActionProbe.sawApi, "handler must receive the ExtensionAPI")

        // (2) update() -> render() re-ran: this port rebuilds views from scratch each render, so the
        //     display list is repopulated with FRESH Displayable instances (different identity).
        let after = ec.getStorage().getDisplayList(true, nil)
        XCTAssertGreaterThan(after.count, 0, "re-render must repopulate the display list")
        let afterFirstId = after.first.map { ObjectIdentifier($0) }
        XCTAssertNotEqual(beforeFirstId, afterFirstId,
                          "dispatchAction should have triggered a fresh re-render (rebuilt elements)")
    }

    // An unregistered action type is a silent no-op (upstream: `if (!actions[payload.type]) return`) —
    // the handler never runs and nothing crashes / re-renders.
    func testDispatchUnregisteredActionIsNoOp() {
        let ec = makeBarChart()
        let before = ec.getStorage().getDisplayList(true, nil)
        let beforeFirstId = before.first.map { ObjectIdentifier($0) }

        ec.dispatchAction(Payload(type: "zz_never_registered_action"))

        XCTAssertEqual(ZZActionProbe.runCount, 0, "no handler should run for an unregistered action")
        let after = ec.getStorage().getDisplayList(true, nil)
        let afterFirstId = after.first.map { ObjectIdentifier($0) }
        XCTAssertEqual(beforeFirstId, afterFirstId,
                       "an unregistered action must NOT trigger a re-render")
    }
}
