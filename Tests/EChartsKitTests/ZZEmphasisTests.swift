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
// highDown DISPATCHER (`states.isHighDownDispatcher(el)`). As of Phase 33, `BarView.updateStyle` marks
// EVERY bar slice a dispatcher via `toggleHoverEmphasis` (the previously-deferred states-block is now
// wired), so both `target` and `other` come out of the bar render already dispatchers. What isolates
// the highlight to index 0 is the dispatch's data-index finder, not the dispatcher flag — the round-trip
// below drives that end to end.
import XCTest
import ZRenderKit
@testable import EChartsKit

final class ZZEmphasisTests: XCTestCase {

    override func setUp() {
        super.setUp()
        ComponentModel.registerClass(BarSeriesModel.self)
    }

    private func makeBarChart() -> ECharts {
        let ec = ECharts(width: 400, height: 300)
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

        // As of Phase 33, BarView.updateStyle marks every bar a highDown dispatcher via toggleHoverEmphasis,
        // so both index 0 and index 1 are already dispatchers straight out of the render.
        XCTAssertTrue(states.isHighDownDispatcher(target!))
        XCTAssertTrue(states.isHighDownDispatcher(other!))

        XCTAssertTrue(target!.currentStates.isEmpty, "no emphasis before highlight")

        // dispatchAction(highlight) targeting series 0, data index 0.
        var hp = Payload(type: "highlight")
        hp.other["seriesIndex"] = 0.0       // finder → mainType 'series', component index 0
        hp.other["dataIndexInside"] = 0     // queryDataIndex → element index 0
        ec.dispatchAction(hp)

        XCTAssertTrue(target!.currentStates.contains("emphasis"),
                      "dispatch highlight must enter the emphasis state on the targeted dispatcher element")
        XCTAssertTrue(target!.hasState())
        // The sibling (index 1) is a dispatcher too, but the highlight's data-index finder targets only
        // index 0, so index 1 is never reached by elSetState.
        XCTAssertTrue(other!.currentStates.isEmpty,
                      "sibling at a different dataIndex must NOT enter emphasis")

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

    // ---- (4) the state-textStyle READBACK seam: dispatch highlight on a labeled datum whose series
    //          has `emphasis.label.color` set makes the ATTACHED label element report the emphasis
    //          color, and downplay restores it. This proves the Element→textContent state propagation
    //          plus ZRText's per-state textStyle readback (label restyles on hover/emphasis). ----
    func testHighlightRestylesAttachedLabelPerEmphasis() {
        let ec = ECharts(width: 400, height: 300)
        ec.setOption([
            "grid": ["left": 50.0, "top": 20.0, "width": 300.0, "height": 200.0] as [String: Any],
            "xAxis": ["type": "category", "data": ["A", "B", "C"]] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [[
                "type": "bar",
                "data": [10.0, 20.0, 30.0],
                // Normal label shown; emphasis recolors it red.
                "label": ["show": true, "color": "#111111"] as [String: Any],
                "emphasis": ["label": ["color": "#ff0000"] as [String: Any]] as [String: Any]
            ] as [String: Any]]
        ])

        let series = ec.getModel()!.getSeriesByIndex(0)!
        let el = series.getData().getItemGraphicEl(0)!
        let label = el.getTextContent()
        XCTAssertNotNil(label, "the bar render must attach a label textContent (label.show == true)")
        XCTAssertEqual(label!.textStyle.fill, "#111111", "normal label uses the normal label color")

        // dispatchAction(highlight) on series 0 / data index 0.
        var hp = Payload(type: "highlight")
        hp.other["seriesIndex"] = 0.0
        hp.other["dataIndexInside"] = 0
        ec.dispatchAction(hp)

        XCTAssertTrue(el.currentStates.contains("emphasis"), "host bar entered emphasis")
        XCTAssertTrue(label!.currentStates.contains("emphasis"),
                      "the attached label must have the emphasis state propagated to it")
        XCTAssertEqual(label!.textStyle.fill, "#ff0000",
                       "the attached label must report the emphasis.label color after highlight")

        // dispatchAction(downplay) restores the normal label color.
        var dp = Payload(type: "downplay")
        dp.other["seriesIndex"] = 0.0
        dp.other["dataIndexInside"] = 0
        ec.dispatchAction(dp)

        XCTAssertTrue(label!.currentStates.isEmpty, "downplay clears the label's emphasis state")
        XCTAssertEqual(label!.textStyle.fill, "#111111",
                       "the attached label must restore its normal color after downplay")
    }
}
