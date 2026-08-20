// Legend show/hide: dispatching legendToggleSelect (what a legend item click dispatches) must toggle
// LegendModel.selected and, via the legendFilter processor, hide/show the corresponding series on the
// next update. Regression for the "legend click does nothing" gap (legendAction + legendFilter +
// the LegendView item-click dispatch are now wired).
import XCTest
@testable import EChartsKit
@testable import ZRenderKit

final class LegendToggleSelectTests: XCTestCase {
    private func makeTwoSeriesWithLegend() -> ECharts {
        let ec = ECharts(width: 400, height: 300)
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

    private func renderedSeriesNames(_ ec: ECharts) -> [String] {
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

    // Regression: after a series is toggled OFF (legend-filtered → no view), a subsequent
    // highlight/downplay must NOT crash. doDispatchAction runs allLeaveBlur, which walks every series
    // and looked up its view with a force-unwrap — nil for the filtered series → crash on legend hover.
    func testDispatchAfterLegendHideDoesNotCrash() {
        let ec = makeTwoSeriesWithLegend()
        var off = Payload(type: "legendToggleSelect"); off.other["name"] = "Beta"
        ec.dispatchAction(off)   // Beta now filtered out (no view)

        // A legend hover on the still-visible item dispatches highlight then downplay — both run
        // allLeaveBlur / blurSeries over ALL series including the view-less Beta.
        var hi = Payload(type: "highlight"); hi.other["seriesName"] = "Alpha"
        ec.dispatchAction(hi)
        var lo = Payload(type: "downplay"); lo.other["seriesName"] = "Alpha"
        ec.dispatchAction(lo)
        // Reaching here without a trap is the assertion.
        XCTAssertEqual(renderedSeriesNames(ec), ["Alpha"], "Beta stays hidden; no crash on blur over a view-less series")
    }

    // An UNSELECTED (toggled-off) scatter legend item must GREY OUT its icon, not make it vanish. The
    // icon color must come from the legend-computed itemStyle (grey inactiveColor), NOT the series data
    // visual (which is empty for a legend-filtered series → previously nil fill → invisible icon).
    func testScatterLegendIconGreysOutWhenUnselected() {
        let ec = ECharts(width: 400, height: 300)
        ec.setOption([
            "legend": ["data": ["S"]] as [String: Any],
            "xAxis": ["type": "value"] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [["name": "S", "type": "scatter",
                        "itemStyle": ["color": "#ff0000"] as [String: Any],
                        "data": [[1.0, 2.0], [3.0, 4.0]] as [Any]] as [String: Any]]
        ])
        let series = ec.getModel()!.getSeriesByIndex(0)!

        // What LegendView passes for an UNSELECTED item: itemStyle.fill forced to the grey inactiveColor.
        let grey = "#cfd2d7"
        let params = LegendIconParams(itemWidth: 25, itemHeight: 14, icon: "circle",
                                      iconRotate: 0, itemStyle: ["fill": grey], lineStyle: [:],
                                      symbolKeepAspect: nil)
        guard let icon = series.getLegendIcon(params) else { XCTFail("scatter getLegendIcon returned nil"); return }

        // Find the symbol path and assert it is filled with the grey (not nil → not invisible).
        var iconFill: ZRenderKit.ZRColor?
        _ = (icon as? Group)?.traverse { el in
            if let p = el as? Path, iconFill == nil { iconFill = p.pathStyle.fill }
            return false
        }
        guard case let .string(hex)? = iconFill else {
            XCTFail("unselected scatter legend icon has no fill (vanished) — got \(String(describing: iconFill))"); return
        }
        XCTAssertEqual(hex.lowercased(), grey, "unselected scatter legend icon must be the grey inactiveColor")
    }

    func testLineLegendIconHonorsZeroLineWidth() {
        let ec = ECharts(width: 400, height: 300)
        ec.setOption([
            "legend": ["data": ["Area"]] as [String: Any],
            "xAxis": ["type": "category", "data": ["A", "B"]] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [[
                "name": "Area", "type": "line", "data": [1.0, 2.0],
                "lineStyle": ["width": 0.0] as [String: Any],
                "areaStyle": [:] as [String: Any]
            ] as [String: Any]]
        ])
        guard let series = ec.getModel()?.getSeriesByIndex(0) as? LineSeriesModel else {
            return XCTFail("expected a line series")
        }
        let params = LegendIconParams(
            itemWidth: 25, itemHeight: 14, icon: "emptyCircle", iconRotate: 0,
            itemStyle: ["fill": "#5470c6"],
            lineStyle: ["stroke": "#5470c6", "lineWidth": 0.0],
            symbolKeepAspect: nil
        )
        guard let group = series.getLegendIcon(params) as? Group,
              let line = group.childAt(0) as? Path else {
            return XCTFail("line legend icon must contain its line path")
        }
        XCTAssertEqual(line.pathStyle.lineWidth, 0,
                       "an area-only line series with lineStyle.width:0 must not show legend side bars")
    }

    func testLineLegendIconRecoversAutoWidthForVisibleSeriesLine() {
        let ec = makeTwoSeriesWithLegend()
        guard let series = ec.getModel()?.getSeriesByIndex(0) as? LineSeriesModel else {
            return XCTFail("expected a line series")
        }
        // LegendView currently receives no `legendLineStyle` visual and therefore resolves the
        // default auto width to zero. A normal positive-width series must still draw the side bars.
        let params = LegendIconParams(
            itemWidth: 25, itemHeight: 14, icon: "emptyCircle", iconRotate: 0,
            itemStyle: ["fill": "#5470c6"],
            lineStyle: ["stroke": "#5470c6", "lineWidth": 0.0],
            symbolKeepAspect: nil
        )
        guard let group = series.getLegendIcon(params) as? Group,
              let line = group.childAt(0) as? Path else {
            return XCTFail("line legend icon must contain its line path")
        }
        XCTAssertEqual(line.pathStyle.lineWidth, 2,
                       "auto legend width for a visible line series must render the normal side bars")
    }
}
