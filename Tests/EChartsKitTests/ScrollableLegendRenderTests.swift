// END-TO-END RENDER TEST for the scrollable legend (component/legend/ScrollableLegendView.ts).
//
// A `legend: {type: 'scroll'}` with many items, laid into a narrow width, must:
//   1. lay out ALL item labels (they are clipped, not dropped),
//   2. clip the container to a single page (a Group carries a clipPath),
//   3. add the page controls: `pagePrev` / `pageNext` arrow Paths + a `pageText` "1/N" indicator
//      showing the FIRST page with N >= 2 total pages.
// A PLAIN legend (`legend: {...}`, no type) must be UNCHANGED: no page controls, no clip path.

import XCTest
import ZRenderKit
@testable import EChartsKit

// A bar series whose data is supplied via an empty DataStore, bypassing the SourceManager source
// layer (same double idiom as EChartsSmokeTests). It lets the full ECharts update cycle run
// so the legend view renders one item per named series.
private final class LegendScrollBarSeriesModel: BarSeriesModel {
    override class var type: ComponentFullType { return "series.bar" }
    override func getInitialData(_ option: ModelOption?, _ ecModel: GlobalModel?) -> SeriesData? {
        let d = SeriesData(["x", "y"], self)
        d.initData(DataStore())
        return d
    }
}

final class ScrollableLegendRenderTests: XCTestCase {

    override func setUp() {
        super.setUp()
        ComponentModel.registerClass(LegendScrollBarSeriesModel.self)
        ComponentModel.registerClass(ScrollableLegendModel.self)
    }

    // `LegendScrollBarSeriesModel` registers itself as "series.bar" with an EMPTY DataStore. Component
    // registration is process-global and one-time (ECharts does NOT re-register on each init), so
    // without restoring the real model here, EVERY later bar chart in the suite resolves to this empty
    // double and renders 0 bars (polluted ReRenderResetTests). Restore the real BarSeriesModel.
    override func tearDown() {
        ComponentModel.registerClass(BarSeriesModel.self)
        super.tearDown()
    }

    private let itemNames: [String] = (0..<12).map { "Legend Item \($0)" }

    private func baseSeries() -> [Any] {
        return itemNames.map { name in
            ["type": "bar", "name": name, "data": [1.0, 2.0, 3.0] as [Double]] as [String: Any]
        }
    }

    // Collect (by element name) the page-control elements and any clip-carrying group + item labels.
    private struct LegendScan {
        var pagePrev: Path?
        var pageNext: Path?
        var pageText: ZRText?
        var clippedGroups = 0
        var itemLabels = 0
    }

    private func scan(_ root: Group) -> LegendScan {
        var s = LegendScan()
        let nameSet = Set(itemNames)
        _ = root.traverse { el in
            if let p = el as? Path {
                if p.name == "pagePrev" { s.pagePrev = p }
                if p.name == "pageNext" { s.pageNext = p }
            }
            if let t = el as? ZRText {
                if t.name == "pageText" { s.pageText = t }
                if let text = t.textStyle?.text, nameSet.contains(text) { s.itemLabels += 1 }
            }
            if let g = el as? Group, g.getClipPath() != nil { s.clippedGroups += 1 }
            return false
        }
        return s
    }

    func testScrollLegendShowsControlsAndClipsToOnePage() {
        let ec = ECharts(width: 400, height: 300)
        ec.setOption([
            // Narrow width forces the 12 items to overflow → the controller (arrows + page text) shows.
            "legend": [
                "type": "scroll",
                "orient": "horizontal",
                "left": "center",
                "width": 120.0
            ] as [String: Any],
            "xAxis": ["type": "category", "data": ["A", "B", "C"]] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": baseSeries()
        ])

        let s = scan(ec.getRoot())

        // 1. All 12 item labels were laid out (clipping does not remove them).
        XCTAssertEqual(s.itemLabels, itemNames.count,
                       "scroll legend should lay out every item label (clipped, not dropped)")

        // 2. The container is clipped to a single page.
        XCTAssertGreaterThanOrEqual(s.clippedGroups, 1,
                                    "scroll legend should clip its container group to one page")

        // 3. The page-arrow controls exist.
        XCTAssertNotNil(s.pagePrev, "scroll legend should add a 'pagePrev' arrow control")
        XCTAssertNotNil(s.pageNext, "scroll legend should add a 'pageNext' arrow control")

        // 4. The page indicator shows the FIRST page and more than one page total ("1/N", N >= 2).
        guard let pageTextStr = s.pageText?.textStyle?.text else {
            return XCTFail("scroll legend should add a 'pageText' indicator")
        }
        let parts = pageTextStr.split(separator: "/").map(String.init)
        XCTAssertEqual(parts.count, 2, "page text should be '{current}/{total}', got '\(pageTextStr)'")
        XCTAssertEqual(parts.first, "1", "first page shown, got '\(pageTextStr)'")
        if let total = parts.count == 2 ? Int(parts[1]) : nil {
            XCTAssertGreaterThanOrEqual(total, 2, "12 items in a 120pt-wide legend should span >= 2 pages")
        }
        else {
            XCTFail("page text total should be an integer, got '\(pageTextStr)'")
        }
    }

    func testExternalVisualHarnessPagesAndClicksOnlyVisibleItems() {
        let view = EChartsView(width: 400, height: 300)
        view.setOption([
            "legend": [
                "type": "scroll",
                "orient": "horizontal",
                "left": "center",
                "width": 120.0
            ] as [String: Any],
            "xAxis": ["type": "category", "data": ["A", "B", "C"]] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": baseSeries()
        ])
        XCTAssertNotNil(view._injectScrollableLegendPageClickForTest(name: "pageNext"))
        let model = view.ec.getModel()?.getComponent("legend", 0) as? ScrollableLegendModel
        let scrollIndex = ((model?.option as? [String: Any])?["scrollDataIndex"] as? NSNumber)?
            .doubleValue
        XCTAssertGreaterThan(scrollIndex ?? 0, 0)
        XCTAssertNotNil(view._injectVisibleScrollableLegendItemClickForTest(visibleIndex: 0))
        XCTAssertNotNil(view._injectScrollableLegendPageClickForTest(name: "pagePrev"))
    }

    func testPlainLegendIsUnchangedNoControlsNoClip() {
        let ec = ECharts(width: 400, height: 300)
        ec.setOption([
            // No `type` → plain legend. Even with a narrow width it must not paginate.
            "legend": [
                "orient": "horizontal",
                "left": "center",
                "width": 120.0
            ] as [String: Any],
            "xAxis": ["type": "category", "data": ["A", "B", "C"]] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": baseSeries()
        ])

        let s = scan(ec.getRoot())

        // Plain legend still renders every item...
        XCTAssertEqual(s.itemLabels, itemNames.count, "plain legend should render every item label")
        // ...but NONE of the scrollable machinery.
        XCTAssertNil(s.pagePrev, "plain legend must not add page-arrow controls")
        XCTAssertNil(s.pageNext, "plain legend must not add page-arrow controls")
        XCTAssertNil(s.pageText, "plain legend must not add a page-text indicator")
        XCTAssertEqual(s.clippedGroups, 0, "plain legend must not clip its content")
    }
}
