// Legend SELECTOR buttons ("All"/"Inv"): with `legend.selector` set, LegendView._createSelector renders
// a clickable label per selector item. A click dispatches `legendAllSelect` (type "all") or
// `legendInverseSelect` (type "inverse"), scoped to the legend by `legendId`. Those actions mutate
// LegendModel.selected (all-true / inverted) and, via legendFilter, show/hide the matching series on the
// next update. Regression for the "selector button does nothing" gap (the onclick is now wired in
// LegendView._createSelector — dispatches legendAllSelect / legendInverseSelect).
import XCTest
import ZRenderKit
@testable import EChartsKit

final class LegendSelectorButtonTests: XCTestCase {
    private func makeTwoSeriesWithSelector() -> ECharts {
        let ec = ECharts(width: 500, height: 300)
        ec.setOption([
            "legend": [
                "data": ["Alpha", "Beta"],
                "selector": [
                    ["type": "all"] as [String: Any],
                    ["type": "inverse"] as [String: Any]
                ] as [Any]
            ] as [String: Any],
            "xAxis": ["type": "category", "data": ["A", "B", "C"]] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [
                ["name": "Alpha", "type": "line", "data": [1.0, 2.0, 3.0]] as [String: Any],
                ["name": "Beta", "type": "line", "data": [3.0, 2.0, 1.0]] as [String: Any]
            ]
        ])
        return ec
    }

    private func renderedSeriesNames(_ ec: ECharts) -> [String] {
        var names: [String] = []
        ec.getModel()!.eachSeries { s, _ in names.append(s.name) }
        return names
    }

    // The selector buttons are the ZRText labels in the legend view whose text is the locale title
    // ("All"/"Inv"). Item labels are the series names, so these are unambiguous.
    private func selectorButtons(_ root: Group) -> [String: ZRText] {
        var out: [String: ZRText] = [:]
        _ = root.traverse { el in
            if let t = el as? ZRText, let text = t.textStyle?.text, text == "All" || text == "Inv" {
                out[text] = t
            }
            return false
        }
        return out
    }

    // The button carries a live click handler: TRIGGERING "click" on the button element (the same call
    // Handler.dispatchToElement makes on a real click) must run the bound onclick → dispatch the action
    // → flip the selection. Proves both "carries a click handler" and "the action flips selection".
    func testSelectorButtonClickHandlerFlipsSelection() {
        let ec = makeTwoSeriesWithSelector()
        let legend = ec.getModel()!.getComponent("legend") as? LegendModel
        let buttons = selectorButtons(ec.getRoot())
        XCTAssertEqual(buttons.count, 2, "one selector button per selector item (All + Inv)")

        XCTAssertEqual(legend?.isSelected("Alpha"), true)
        XCTAssertEqual(legend?.isSelected("Beta"), true)

        // A real click on the "Inv" button → bound handler dispatches legendInverseSelect.
        guard let invButton = buttons["Inv"] else { return XCTFail("no 'Inv' selector button") }
        _ = invButton.trigger("click", nil)

        XCTAssertEqual(legend?.isSelected("Alpha"), false, "clicking Inv must invert the selection")
        XCTAssertEqual(legend?.isSelected("Beta"), false)
        XCTAssertEqual(renderedSeriesNames(ec), [], "both series filtered out after the Inv-button click")
    }

    func testLegendInverseSelectFlipsSelectionAndHidesSeries() {
        let ec = makeTwoSeriesWithSelector()
        let legend = ec.getModel()!.getComponent("legend") as? LegendModel
        XCTAssertEqual(renderedSeriesNames(ec).sorted(), ["Alpha", "Beta"], "both series render initially")
        XCTAssertEqual(legend?.isSelected("Alpha"), true)
        XCTAssertEqual(legend?.isSelected("Beta"), true)

        // Inverse selector button → dispatchAction(legendInverseSelect, legendId). Both flip true→false.
        var inv = Payload(type: "legendInverseSelect"); inv.other["legendId"] = legend?.id
        ec.dispatchAction(inv)
        XCTAssertEqual(legend?.isSelected("Alpha"), false, "inverse flips a selected item to unselected")
        XCTAssertEqual(legend?.isSelected("Beta"), false)
        XCTAssertEqual(renderedSeriesNames(ec), [], "both series filtered out after inverse-select")
    }

    func testLegendAllSelectRestoresSelection() {
        let ec = makeTwoSeriesWithSelector()
        let legend = ec.getModel()!.getComponent("legend") as? LegendModel

        // First hide one series so "select all" has something to restore.
        var off = Payload(type: "legendToggleSelect"); off.other["name"] = "Beta"
        ec.dispatchAction(off)
        XCTAssertEqual(renderedSeriesNames(ec), ["Alpha"], "Beta hidden by toggle")

        // "All" selector button → dispatchAction(legendAllSelect, legendId). Everything selected.
        var all = Payload(type: "legendAllSelect"); all.other["legendId"] = legend?.id
        ec.dispatchAction(all)
        XCTAssertEqual(legend?.isSelected("Alpha"), true)
        XCTAssertEqual(legend?.isSelected("Beta"), true, "all-select re-selects the toggled-off item")
        XCTAssertEqual(renderedSeriesNames(ec).sorted(), ["Alpha", "Beta"], "all series shown after all-select")
    }
}
