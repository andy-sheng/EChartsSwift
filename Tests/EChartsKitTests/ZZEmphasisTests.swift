// Phase 30 regression tests — the emphasis/blur/select STATE ENGINE + the highlight/downplay
// dispatchAction round-trip (interaction layer, Phase 30).
//
// Proves, headlessly (no UIView / pointer host), that:
//   (1) the ported `states` engine actually pushes/pops the ZR "emphasis" state on an element, and
//   (2) `ec.dispatchAction(Payload(type:"highlight"))` -> doDispatchAction -> updateDirectly ->
//       ChartView.highlight -> toggleHighlight -> elSetState -> states.enterEmphasis LANDS the
//       emphasis state on the targeted data element, and `downplay` returns it to normal.
//
// NOTE on the dispatcher gate: `elSetState` only enters/leaves emphasis when the target element is a
// highDown DISPATCHER (`states.isHighDownDispatcher(el)`). Upstream marks each bar slice a dispatcher
// inside `BarView.updateStyle` via `toggleHoverEmphasis`, but that states-block is a documented
// PORT-TODO in BarView (label/states subsystem deferred). So the test marks the target element a
// dispatcher explicitly (`states.setAsHighDownDispatcher(el, true)`) — exactly what the deferred bar
// wiring will do — then drives the real dispatch round-trip end to end.
import XCTest
import ZRenderKit
@testable import EChartsKit

final class ZZEmphasisTests: XCTestCase {

    override func setUp() {
        super.setUp()
        ComponentModel.registerClass(BarSeriesModel.self)
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

    // ---- (1) direct engine proof: enterEmphasis/leaveEmphasis push/pop the ZR "emphasis" state ----
    // Independent of the dispatcher gate and the full round-trip — proves util/states.swift itself works.
    func testStatesEngineEnterLeaveEmphasis() {
        let el = Group()
        XCTAssertFalse(el.hasState(), "fresh element has no state")

        states.enterEmphasis(el)
        XCTAssertTrue(el.currentStates.contains("emphasis"), "enterEmphasis must push the emphasis state")
        XCTAssertTrue(el.hasState())

        states.leaveEmphasis(el)
        XCTAssertTrue(el.currentStates.isEmpty, "leaveEmphasis must clear the emphasis state")
        XCTAssertFalse(el.hasState())
    }

    // enterEmphasis is ref-counted per highlight DIGIT (__highByOuter bitmask): a leave on one digit
    // must NOT drop emphasis while another digit still holds it (states.ts leaveEmphasis semantics).
    func testEnterEmphasisIsRefCountedByDigit() {
        let el = Group()
        states.enterEmphasis(el, 0)
        states.enterEmphasis(el, 1)
        XCTAssertTrue(el.currentStates.contains("emphasis"))

        states.leaveEmphasis(el, 0)
        XCTAssertTrue(el.currentStates.contains("emphasis"),
                      "still highlighted by digit 1 — must remain in emphasis")

        states.leaveEmphasis(el, 1)
        XCTAssertTrue(el.currentStates.isEmpty, "last digit cleared — now leaves emphasis")
    }

    // ---- (2) the full dispatchAction highlight/downplay round-trip lands emphasis on the data el ----
    func testHighlightDispatchEntersEmphasisOnTargetElement() {
        let ec = makeBarChart()
        let series = ec.getModel()!.getSeriesByIndex(0)!
        let data = series.getData()

        let target = data.getItemGraphicEl(0)
        let other = data.getItemGraphicEl(1)
        XCTAssertNotNil(target, "bar render must have populated the data element for index 0")
        XCTAssertNotNil(other, "bar render must have populated the data element for index 1")

        // Mark ONLY index 0 a highDown dispatcher (what BarView.updateStyle's deferred states-block does).
        states.setAsHighDownDispatcher(target!, true)
        XCTAssertTrue(states.isHighDownDispatcher(target!))
        XCTAssertFalse(states.isHighDownDispatcher(other!))

        XCTAssertTrue(target!.currentStates.isEmpty, "no emphasis before highlight")

        // dispatchAction(highlight) targeting series 0, data index 0.
        var hp = Payload(type: "highlight")
        hp.other["seriesIndex"] = 0.0       // finder → mainType 'series', component index 0
        hp.other["dataIndexInside"] = 0     // queryDataIndex → element index 0
        ec.dispatchAction(hp)

        XCTAssertTrue(target!.currentStates.contains("emphasis"),
                      "dispatch highlight must enter the emphasis state on the targeted dispatcher element")
        XCTAssertTrue(target!.hasState())
        // A non-dispatcher sibling is untouched by elSetState (isHighDownDispatcher gate).
        XCTAssertTrue(other!.currentStates.isEmpty,
                      "non-dispatcher sibling must NOT enter emphasis")

        // dispatchAction(downplay) returns it to normal.
        var dp = Payload(type: "downplay")
        dp.other["seriesIndex"] = 0.0
        dp.other["dataIndexInside"] = 0
        ec.dispatchAction(dp)

        XCTAssertTrue(target!.currentStates.isEmpty,
                      "dispatch downplay must clear the emphasis state")
        XCTAssertFalse(target!.hasState())
    }

    // ---- (3) the SlimExtensionAPI emphasis seam forwards to the engine, and allLeaveBlur (called by
    //          doDispatchAction on every high-down dispatch) is no longer an abstract fatalError. ----
    func testExtensionApiEmphasisSeamAndAllLeaveBlurAreLive() {
        let ec = makeBarChart()
        let series = ec.getModel()!.getSeriesByIndex(0)!
        let el = series.getData().getItemGraphicEl(0)!
        // The concrete slim ExtensionAPI (its emphasis seam is what views/updateDirectly reach through).
        let api = SlimExtensionAPI(ec: ec)

        api.enterEmphasis(el, nil)
        XCTAssertTrue(el.currentStates.contains("emphasis"), "api.enterEmphasis forwards to states.enterEmphasis")
        api.leaveEmphasis(el, nil)
        XCTAssertTrue(el.currentStates.isEmpty, "api.leaveEmphasis forwards to states.leaveEmphasis")

        api.enterBlur(el)
        XCTAssertTrue(el.currentStates.contains("blur"), "api.enterBlur forwards to states.enterBlur")
        api.leaveBlur(el)
        XCTAssertTrue(el.currentStates.isEmpty)

        api.enterSelect(el)
        XCTAssertTrue(el.currentStates.contains("select"), "api.enterSelect forwards to states.enterSelect")
        api.leaveSelect(el)
        XCTAssertTrue(el.currentStates.isEmpty)

        // allLeaveBlur walks every view; must not hit an abstract method (formerly fatalError).
        states.allLeaveBlur(api)
    }
}
