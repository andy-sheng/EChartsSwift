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
            // A `tooltip` option so the GLOBAL TooltipModel exists (the merge base for tryShow).
            //   `hideDelay: 0` pins the SYNCHRONOUS teardown this test is about: the default
            //   `hideDelay` is 100ms, which would defer the box's `ignore` flip off this run loop
            //   (that timing is proven separately in ZZTooltipDelayTests).
            "tooltip": ["hideDelay": 0.0] as [String: Any],
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

    // ------------------------------------------------------------------------
    // The ITEM-PATH `showTip` ACTION (no pointer involved):
    //
    //     ec.dispatchAction({type:'showTip', seriesIndex:0, dataIndex:i})
    //       -> ECharts.doDispatchAction emits the 'showtip' action event
    //       -> EChartsView's `ec.on("showTip")` hook (substitutes for upstream's
    //          `update:'tooltip:manuallyShowTip'` ComponentView routing)
    //       -> TooltipView.manuallyShowTip -> findPointFromSeries(finder, ecModel)
    //       -> Cartesian2D.dataToPoint  -> tryShow(point:)
    //
    // The load-bearing assertion is that the box lands on the DATUM's pixel: before findPointFromSeries
    // was wired, `manuallyShowTip` fell back to the payload x/y and then to the VIEW CENTRE, so all three
    // data indices produced the SAME box position. Distinct positions prove the point is data-driven.
    // ------------------------------------------------------------------------
    func testShowTipActionPositionsTooltipOnTheDatumPixel() {
        let view = makeBarView()
        _ = view.zr.storage.getDisplayList(true)

        var xs: [Double] = []
        var texts: [String] = []
        for i in 0..<3 {
            var payload = Payload(type: "showTip")
            payload.other["seriesIndex"] = 0
            payload.other["dataIndex"] = i
            view.ec.dispatchAction(payload)

            guard let tv = view.tooltipView, let el = tv.contentEl else {
                XCTFail("showTip {seriesIndex:0, dataIndex:\(i)} must create + show the TooltipView"); return
            }
            XCTAssertTrue(tv.isShown(), "showTip must show the tooltip for dataIndex \(i)")
            XCTAssertFalse(el.ignore, "the tooltip ZRText must be visible for dataIndex \(i)")
            xs.append(el.x)
            texts.append(el.textStyle?.text ?? "")
        }

        // (1) The three positions must be pairwise DISTINCT — the view-centre fallback would collapse them.
        XCTAssertEqual(Set(xs).count, 3,
                       "showTip must place the box at each datum's own pixel, not one fixed fallback — got \(xs)")

        // (2) The CONTENT must match the SAME datum the position was computed from (raw-vs-inside index
        //     consistency: both go through `modelUtil.queryDataIndex` now).
        XCTAssertTrue(texts[0].contains("A") && texts[0].contains("10"), "dataIndex 0 → 'A'/10, got:\n\(texts[0])")
        XCTAssertTrue(texts[1].contains("B") && texts[1].contains("20"), "dataIndex 1 → 'B'/20, got:\n\(texts[1])")
        XCTAssertTrue(texts[2].contains("C") && texts[2].contains("30"), "dataIndex 2 → 'C'/30, got:\n\(texts[2])")

        // (3) The `name` finder form (upstream: `showTip {seriesIndex, name}`) must resolve the same datum
        //     as `dataIndex` — the guard used to require a literal `dataIndex` and silently ignore this.
        var byName = Payload(type: "showTip")
        byName.other["seriesIndex"] = 0
        byName.other["name"] = "C"
        view.ec.dispatchAction(byName)
        XCTAssertEqual(view.tooltipView?.contentEl?.x, xs[2],
                       "showTip by `name` must land on the same pixel as showTip by `dataIndex`")

        // (4) hideTip hides it.
        view.ec.dispatchAction(Payload(type: "hideTip"))
        XCTAssertEqual(view.tooltipView?.isShown(), false, "hideTip must hide the tooltip")
    }
}
