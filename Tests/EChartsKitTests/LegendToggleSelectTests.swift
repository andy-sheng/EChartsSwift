// Legend show/hide: dispatching legendToggleSelect (what a legend item click dispatches) must toggle
// LegendModel.selected and, via the legendFilter processor, hide/show the corresponding series on the
// next update. Regression for the "legend click does nothing" gap (legendAction + legendFilter were
// unported; LegendView item click was a PORT-TODO).
import XCTest
@testable import EChartsKit

final class LegendToggleSelectTests: XCTestCase {
    private func makeTwoSeriesWithLegend() -> EChartsSlim {
        let ec = EChartsSlim(width: 400, height: 300)
        ec.setOption([
            "legend": ["data": ["Alpha", "Beta"]] as [String: Any],
            "xAxis": ["type": "category", "data": ["A", "B", "C"]] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [
                ["name": "Alpha", "type": "line", "data": [1.0, 2.0, 3.0]] as [String: Any],
                ["name": "Beta", "type": "line", "data": [3.0, 2.0, 1.0]] as [String: Any]
            ]
        ])
        return ec
    }

    private func renderedSeriesNames(_ ec: EChartsSlim) -> [String] {
        var names: [String] = []
        ec.getModel()!.eachSeries { s, _ in names.append(s.name) }
        return names
    }

    func testLegendToggleHidesAndRestoresSeries() {
        let ec = makeTwoSeriesWithLegend()
        XCTAssertEqual(renderedSeriesNames(ec).sorted(), ["Alpha", "Beta"], "both series render initially")

        // Legend item click on "Beta" → dispatchAction(legendToggleSelect, name:Beta).
        var off = Payload(type: "legendToggleSelect"); off.other["name"] = "Beta"
        ec.dispatchAction(off)
        XCTAssertEqual(renderedSeriesNames(ec), ["Alpha"], "toggling Beta off must filter it out of the render set")

        // The legend model records the unselected state.
        let legend = ec.getModel()!.getComponent("legend") as? LegendModel
        XCTAssertEqual(legend?.isSelected("Beta"), false)
        XCTAssertEqual(legend?.isSelected("Alpha"), true)

        // Click again → restored.
        var on = Payload(type: "legendToggleSelect"); on.other["name"] = "Beta"
        ec.dispatchAction(on)
        XCTAssertEqual(renderedSeriesNames(ec).sorted(), ["Alpha", "Beta"], "toggling Beta back on restores it")
        XCTAssertEqual(legend?.isSelected("Beta"), true)
    }

    func testLegendHoverHighlightsSeriesByName() {
        // Legend item mouseover dispatches highlight(seriesName); the series' data must enter emphasis,
        // and mouseout (downplay) must clear it.
        let ec = makeTwoSeriesWithLegend()
        let betaData = ec.getModel()!.getSeriesByName("Beta").first!.getData()

        var hi = Payload(type: "highlight"); hi.other["seriesName"] = "Beta"
        ec.dispatchAction(hi)
        let anyEmphasis = (0..<betaData.count()).contains { idx in
            (betaData.getItemGraphicEl(idx)?.currentStates.contains("emphasis")) ?? false
        }
        XCTAssertTrue(anyEmphasis, "legend hover highlight(seriesName) must emphasize the series' data")

        var lo = Payload(type: "downplay"); lo.other["seriesName"] = "Beta"
        ec.dispatchAction(lo)
        let stillEmphasis = (0..<betaData.count()).contains { idx in
            (betaData.getItemGraphicEl(idx)?.currentStates.contains("emphasis")) ?? false
        }
        XCTAssertFalse(stillEmphasis, "legend mouseout (downplay) must clear the emphasis")
    }
}
