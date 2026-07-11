// Phase 31 regression tests — the HOST-INDEPENDENT tooltip CONTENT model.
//
// Proves, headlessly (no TooltipView / pointer host), that:
//   (1) `SeriesModel.formatTooltip(dataIndex, ...)` -> `defaultSeriesFormatTooltip` produces a real
//       `TooltipMarkupSection` fragment (NOT the old nil PORT-NOTE stub), and
//   (2) `normalizeTooltipFormatResult` unwraps it to a `TooltipMarkupBlockFragment`, and
//   (3) `buildTooltipMarkup(frag, ...)` renders that fragment to an actual content STRING that
//       carries BOTH the category name ("A") and the datum value ("10"), in BOTH `renderMode`
//       branches: 'html' (<span>/<div> markup) and 'richText' ({styleName|text} tokens).
//
// The on-screen TooltipView + the hover trigger are DEFERRED (they need the live-view host — a
// later phase). This test exercises the content model only, which is fully headless.
import XCTest
import ZRenderKit
@testable import EChartsKit

final class ZZTooltipContentTests: XCTestCase {

    override func setUp() {
        super.setUp()
        ComponentModel.registerClass(BarSeriesModel.self)
        ComponentModel.registerClass(TooltipModel.self)
    }

    private func makeBarChart() -> ECharts {
        let ec = ECharts(width: 400, height: 300)
        ec.setOption([
            "tooltip": ["trigger": "item"] as [String: Any],
            "grid": ["left": 50.0, "top": 20.0, "width": 300.0, "height": 200.0] as [String: Any],
            "xAxis": ["type": "category", "data": ["A", "B", "C"]] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [["type": "bar", "data": [10.0, 20.0, 30.0]] as [String: Any]]
        ])
        return ec
    }

    // ---- (0) the tooltip option is MODELED (registerClass wiring works, no view required) ----
    func testTooltipModelIsInstalled() {
        let ec = makeBarChart()
        let tooltip = ec.getModel()!.getComponent("tooltip", 0)
        XCTAssertNotNil(tooltip, "option.tooltip must be modeled as a TooltipModel component")
        XCTAssertTrue(tooltip is TooltipModel, "the modeled tooltip component must be a TooltipModel")
    }

    // ---- (1) formatTooltip produces a real fragment (not the nil stub) ----
    func testFormatTooltipReturnsFragment() {
        let ec = makeBarChart()
        let series = ec.getModel()!.getSeriesByIndex(0)!
        let result = series.formatTooltip(0)
        XCTAssertNotNil(result, "formatTooltip must produce content (not the old nil PORT-NOTE stub)")

        let normalized = normalizeTooltipFormatResult(result)
        XCTAssertNotNil(normalized.frag, "the result must normalize to a TooltipMarkupBlockFragment")
        XCTAssertTrue(normalized.frag is TooltipMarkupSection, "top-level fragment is a section")
    }

    // ---- (2) html renderMode content carries the category name AND the value ----
    func testFormatTooltipHtmlContainsNameAndValue() {
        let ec = makeBarChart()
        let series = ec.getModel()!.getSeriesByIndex(0)!
        let frag = normalizeTooltipFormatResult(series.formatTooltip(0)).frag
        XCTAssertNotNil(frag)

        let html = buildTooltipMarkup(
            frag,
            TooltipMarkupStyleCreator(),
            .html,
            nil,
            false,
            [:]
        )
        XCTAssertNotNil(html, "html renderMode must yield markup text")
        let text = html ?? ""
        XCTAssertTrue(text.contains("A"), "html tooltip must contain the category name 'A' — got:\n\(text)")
        XCTAssertTrue(text.contains("10"), "html tooltip must contain the value '10' — got:\n\(text)")
        // It really is HTML markup, not just the raw values.
        XCTAssertTrue(text.contains("<div") || text.contains("<span"), "html renderMode emits HTML tags")
    }

    // ---- (3) richText renderMode content carries the category name AND the value ----
    func testFormatTooltipRichTextContainsNameAndValue() {
        let ec = makeBarChart()
        let series = ec.getModel()!.getSeriesByIndex(0)!
        let frag = normalizeTooltipFormatResult(series.formatTooltip(0)).frag
        XCTAssertNotNil(frag)

        let creator = TooltipMarkupStyleCreator()
        let rich = buildTooltipMarkup(
            frag,
            creator,
            .richText,
            nil,
            false,
            [:]
        )
        XCTAssertNotNil(rich, "richText renderMode must yield markup text")
        let text = rich ?? ""
        XCTAssertTrue(text.contains("A"), "richText tooltip must contain the category name 'A' — got:\n\(text)")
        XCTAssertTrue(text.contains("10"), "richText tooltip must contain the value '10' — got:\n\(text)")
        // richText emits {styleName|content} tokens whose styles get registered on the creator.
        XCTAssertTrue(text.contains("{") && text.contains("|"), "richText renderMode emits {style|text} tokens")
        XCTAssertFalse(creator.richTextStyles.isEmpty, "richText styles must be registered on the creator")
    }

    // ---- (4) a DIFFERENT data index resolves its OWN name + value (not index 0's) ----
    func testFormatTooltipResolvesPerIndex() {
        let ec = makeBarChart()
        let series = ec.getModel()!.getSeriesByIndex(0)!
        let frag = normalizeTooltipFormatResult(series.formatTooltip(2)).frag
        let html = buildTooltipMarkup(frag, TooltipMarkupStyleCreator(), .html, nil, false, [:]) ?? ""
        XCTAssertTrue(html.contains("C"), "index 2 tooltip must contain category 'C' — got:\n\(html)")
        XCTAssertTrue(html.contains("30"), "index 2 tooltip must contain value '30' — got:\n\(html)")
    }
}
