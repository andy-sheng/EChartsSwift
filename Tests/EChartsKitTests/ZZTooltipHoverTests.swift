// Phase 34 regression test — the tooltip CONTENT actually APPEARS on hover, proven HEADLESSLY through
// the REAL pointer stack.
//
// Unlike ZZTooltipContentTests (which drives the content model directly) and ZZLiveHoverTests (which
// proves hover→emphasis), this test injects a synthetic POINTER event and proves the whole
// hover→tooltip-appears chain fires end to end:
//
//     EChartsView._injectPointerForTest("mousemove", x, y)
//       -> zr.handler.mousemove(ZRRawEvent)          (ZRenderKit Handler)
//       -> handler.findHover(x, y) hit-tests the bar -> element "mouseover" trigger
//       -> EChartsView._initEvents' "mouseover" listener
//       -> EChartsView._showTooltipForHover(e)       (reads the bar's ECData)
//       -> TooltipView.tryShow(seriesModel, dataIndex, point)
//       -> TooltipRichContent.setContent(...) + show()  (a ZRText box added to the LIVE zr)
//
// It does NOT call tryShow directly — the tooltip MUST be produced by the injected pointer travelling
// through the live Handler hit-test and the bound listener. A mousemove off all bars then drives the
// `mouseout` leg and proves the tooltip is hidden.
import XCTest
import ZRenderKit
@testable import EChartsKit

final class ZZTooltipHoverTests: XCTestCase {

    override func setUp() {
        super.setUp()
        ComponentModel.registerClass(BarSeriesModel.self)
        ComponentModel.registerClass(TooltipModel.self)
    }

    private func makeBarView() -> EChartsView {
        let view = EChartsView(width: 400, height: 300)
        view.setOption([
            // A `tooltip: {}` option so the GLOBAL TooltipModel exists (the merge base for tryShow).
            "tooltip": [:] as [String: Any],
            "grid": ["left": 50.0, "top": 20.0, "width": 300.0, "height": 200.0] as [String: Any],
            "xAxis": ["type": "category", "data": ["A", "B", "C"]] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [["type": "bar", "data": [10.0, 20.0, 30.0]] as [String: Any]]
        ])
        return view
    }

    // Walk `view.zr` storage; return every ZRText whose style.text carries the tooltip markup (i.e. it
    // is NOT one of the chart's axis/label texts). The tooltip box is the ZRText added to the zr by
    // TooltipRichContent.setContent — it floats above `ec.getRoot()`.
    private func tooltipTexts(in view: EChartsView) -> [ZRText] {
        var out: [ZRText] = []
        for el in view.zr.storage.getDisplayList(true) {
            if let t = el as? ZRText { out.append(t) }
        }
        return out
    }

    func testHoverShowsTooltipWithRightContent() {
        let view = makeBarView()

        // Grab bar 0's rendered Rect from the series data.
        let series = view.ec.getModel()!.getSeriesByIndex(0)!
        let data = series.getData()
        guard let bar0El = data.getItemGraphicEl(0), let bar0 = bar0El as? Rect else {
            XCTFail("bar render must have populated a Rect element for data index 0"); return
        }

        // Precondition: no tooltip has been shown yet.
        XCTAssertNil(view.tooltipView, "no tooltip view should exist before any hover")

        // The point to hover: the center of bar 0's shape rect (shape coords are grid-global here).
        let s = bar0.shape as! RectShape
        let cx = s.x + s.width / 2
        let cy = s.y + s.height / 2

        // Force the zr storage to flatten the echarts display list so `findHover` can hit-test the bars.
        _ = view.zr.storage.getDisplayList(true)

        // ---- (1) Inject a mousemove OVER bar 0 → the tooltip must APPEAR through the real Handler. ----
        view._injectPointerForTest(type: "mousemove", zrX: cx, zrY: cy)

        guard let tv = view.tooltipView else {
            XCTFail("hovering bar 0 must lazily create the TooltipView"); return
        }
        XCTAssertTrue(tv.isShown(), "the tooltip must be shown after hovering bar 0")

        guard let contentEl = tv.contentEl else {
            XCTFail("the tooltip must have created its ZRText content box"); return
        }
        // The content box must be VISIBLE (Element.hide()/show() toggle `ignore`).
        XCTAssertFalse(contentEl.ignore, "the tooltip ZRText must be visible (not ignored) on hover")

        // The content ZRText must actually be hosted in the LIVE zr — i.e. it is a visible STORAGE ROOT
        // of view.zr (added by TooltipRichContent over `zr`, floating above `ec.getRoot()`). NOTE: a rich
        // ZRText is a CONTAINER — `Storage.updateDisplayList` recurses into its text tokens rather than
        // emitting the ZRText itself as a display-list leaf — so we assert on the storage roots, not the
        // flattened display list.
        XCTAssertTrue(view.zr.storage.getRoots().contains { $0 === contentEl },
                      "the tooltip ZRText must be a root of view.zr (floating above the chart)")

        // (2) Its text content must carry BOTH the category name "A" AND the value "10".
        let content = contentEl.textStyle?.text ?? ""
        XCTAssertTrue(content.contains("A"),
                      "the shown tooltip must contain the category name 'A' — got:\n\(content)")
        XCTAssertTrue(content.contains("10"),
                      "the shown tooltip must contain the value '10' — got:\n\(content)")

        // ---- (3) Inject a mousemove OFF all bars → the tooltip must HIDE (mouseout leg fires). ----
        // (1,1) is inside the 400×300 canvas but well outside the grid (left 50, top 20), so findHover
        // resolves no bar; the previous-hover mouseout dispatches on bar 0's dispatcher.
        view._injectPointerForTest(type: "mousemove", zrX: 1, zrY: 1)

        XCTAssertFalse(tv.isShown(), "moving the pointer off bar 0 must hide the tooltip via the mouseout leg")
        XCTAssertTrue(contentEl.ignore, "the hidden tooltip ZRText must be ignored (not drawn)")
    }
}
