// Regression tests for the PORT-NOTE audit "tooltip stale-cluster": per-series `formatTooltip`
// overrides that used to `return nil` behind a stale "tooltipMarkup.ts NOT ported" comment, even
// though `createTooltipMarkup` / `defaultSeriesFormatTooltip` are ported and live. Each test drives
// the full headless content pipeline (formatTooltip -> normalizeTooltipFormatResult ->
// buildTooltipMarkup) and asserts the rendered markup carries the datum name AND value.
import XCTest
import ZRenderKit
@testable import EChartsKit

final class ZZTooltipClusterTests: XCTestCase {

    private func htmlTooltip(_ series: SeriesModel, _ dataIndex: Double,
                             _ dataType: SeriesDataType? = nil) -> String {
        let result = series.formatTooltip(dataIndex, nil, dataType)
        XCTAssertNotNil(result, "formatTooltip must produce content, not the old nil PORT-NOTE stub")
        let frag = normalizeTooltipFormatResult(result).frag
        XCTAssertNotNil(frag, "result must normalize to a fragment")
        let html = buildTooltipMarkup(frag, TooltipMarkupStyleCreator(), .html, nil, false, [:])
        return html ?? ""
    }

    // themeRiver: `data.getName(i)` + `data.get(mapDimension('value'), i)` -> nameValue block.
    func testThemeRiverTooltipHasNameAndValue() {
        let ec = ECharts(width: 520, height: 380)
        ec.setOption([
            "singleAxis": ["type": "value"] as [String: Any],
            "series": [["type": "themeRiver",
                        "data": [
                            [0.0, 10.0, "Alpha"], [1.0, 15.0, "Alpha"],
                            [0.0,  8.0, "Beta"],  [1.0,  6.0, "Beta"]
                        ]] as [String: Any]]
        ])
        let series = ec.getModel()!.getSeriesByIndex(0)!
        let text = htmlTooltip(series, 0)
        XCTAssertTrue(text.contains("Alpha"), "themeRiver tooltip must carry the layer name — got:\n\(text)")
        XCTAssertTrue(text.contains("10"), "themeRiver tooltip must carry the datum value — got:\n\(text)")
    }

    // lines: itemName from name/fromName>toName walk + `getRawValue` value.
    func testLinesTooltipHasNameAndValue() {
        let ec = ECharts(width: 400, height: 300)
        ec.setOption([
            "xAxis": ["type": "value"] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [["type": "lines", "coordinateSystem": "cartesian2d",
                        "data": [["coords": [[0.0, 0.0], [1.0, 1.0]], "fromName": "Src", "toName": "Dst"]]
                       ] as [String: Any]]
        ])
        let series = ec.getModel()!.getSeriesByIndex(0)!
        let text = htmlTooltip(series, 0)
        XCTAssertTrue(text.contains("Src") && text.contains("Dst"),
                      "lines tooltip must carry the from>to name walk — got:\n\(text)")
    }

    // sankey: edge branch -> "source -- target" name; node branch -> node name + layout value.
    func testSankeyEdgeTooltipHasSourceTargetName() {
        let ec = ECharts(width: 500, height: 400)
        ec.setOption([
            "series": [["type": "sankey",
                        "data": [["name": "a"], ["name": "b"], ["name": "c"]],
                        "links": [["source": "a", "target": "b", "value": 5.0],
                                  ["source": "b", "target": "c", "value": 3.0]]
                       ] as [String: Any]]
        ])
        let series = ec.getModel()!.getSeriesByIndex(0)!
        let text = htmlTooltip(series, 0, .edge)
        XCTAssertTrue(text.contains("a -- b"), "sankey edge tooltip must carry 'source -- target' — got:\n\(text)")
    }

    // chord: node branch fills name/value from the circular-layout node value.
    func testChordNodeTooltipHasName() {
        let ec = ECharts(width: 500, height: 500)
        ec.setOption([
            "series": [["type": "chord",
                        "data": [["name": "alpha"], ["name": "beta"], ["name": "gamma"]],
                        "links": [["source": "alpha", "target": "beta", "value": 4.0],
                                  ["source": "beta", "target": "gamma", "value": 2.0]]
                       ] as [String: Any]]
        ])
        let series = ec.getModel()!.getSeriesByIndex(0)!
        let text = htmlTooltip(series, 0, .node)
        XCTAssertTrue(text.contains("alpha"), "chord node tooltip must carry the node name — got:\n\(text)")
    }
}
