// Regression test for the ported `tooltip.showDelay` / `tooltip.hideDelay` scheduling —
// upstream `TooltipView._showOrMove` (TooltipView.ts:517) + `TooltipRichContent.hideLater`.
//
// The assertions are all about TIMING, not compilation: a delayed show must NOT have touched the
// content when the show path returns, must land after the delay, must be cancelled by a newer show
// (upstream `clearTimeout(this._showTimout)`) and by `dispose()` — but NOT by a hide, which upstream
// leaves running (see test 3).
//
// The `setTimeout` analogue is `DispatchQueue.main.asyncAfter` (see util/throttle.swift), so every
// wait here is a main-queue block enqueued AFTER the tooltip's own — FIFO on the main queue makes
// the ordering deterministic, not a race.
import XCTest
import ZRenderKit
@testable import EChartsKit

final class ZZTooltipDelayTests: XCTestCase {

    override func setUp() {
        super.setUp()
        ComponentModel.registerClass(BarSeriesModel.self)
        ComponentModel.registerClass(TooltipModel.self)
    }

    /// A 400x300 bar chart whose global `tooltip` carries the given extra options.
    private func makeBarView(_ tooltipOption: [String: Any]) -> EChartsView {
        let view = EChartsView(width: 400, height: 300)
        view.setOption([
            "tooltip": tooltipOption,
            "grid": ["left": 50.0, "top": 20.0, "width": 300.0, "height": 200.0] as [String: Any],
            "xAxis": ["type": "category", "data": ["A", "B", "C"]] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [["type": "bar", "data": [10.0, 20.0, 30.0]] as [String: Any]]
        ])
        _ = view.zr.storage.getDisplayList(true)
        return view
    }

    /// Drain the main queue for `seconds` (lets a pending asyncAfter tooltip timer fire).
    private func pump(_ seconds: Double) {
        let exp = expectation(description: "pump \(seconds)s")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { exp.fulfill() }
        wait(for: [exp], timeout: seconds + 5)
    }

    /// The tooltip box's rich markup with the GENERATED style names removed.
    ///
    /// A richText tooltip is a string of `{styleName|content}` tokens whose style names are
    /// `'__EC_aUTo_' + n` — and `n` starts at `number.getRandomIdBase()` (`round(random()*9)`, faithful
    /// to upstream `tooltipMarkup.ts`), so a name like `__EC_aUTo_10` appears in roughly one run in five.
    /// Asserting on the raw markup therefore makes any digit test (`contains("10")`) a coin flip. Strip
    /// the names so every assertion below is about the tooltip's CONTENT only.
    private func tooltipContent(_ el: ZRText) -> String {
        return (el.textStyle?.text ?? "")
            .replacingOccurrences(of: "__EC_aUTo_[0-9]+", with: "", options: .regularExpression)
    }

    /// The centre of bar `i`'s rendered Rect (grid-global coords, hit-testable by the live Handler).
    private func barCenter(_ view: EChartsView, _ i: Int) -> (Double, Double)? {
        guard let el = view.ec.getModel()?.getSeriesByIndex(0)?.getData().getItemGraphicEl(i),
              let rect = el as? Rect, let s = rect.shape as? RectShape else { return nil }
        return (s.x + s.width / 2, s.y + s.height / 2)
    }

    // ------------------------------------------------------------------------
    // (1) showDelay > 0 => the hover show is DEFERRED, then lands.
    //     Note the option is an Int literal (`200`) on purpose: `showDelay` must survive the
    //     Int-vs-Double option-read trap (`get(...) as? Double` would return nil and silently
    //     degrade to "no delay").
    // ------------------------------------------------------------------------
    func testShowDelayDefersTheHoverTooltipThenShowsIt() {
        let view = makeBarView(["showDelay": 200])
        guard let (cx, cy) = barCenter(view, 0) else { XCTFail("bar 0 must render"); return }

        view._injectPointerForTest(type: "mousemove", zrX: cx, zrY: cy)

        guard let tv = view.tooltipView else {
            XCTFail("hovering bar 0 must lazily create the TooltipView"); return
        }
        // The show path ran, but `_showOrMove` parked the content step on a timer.
        XCTAssertNil(tv.contentEl,
                     "with showDelay:200 the hover must NOT have built the content box yet")
        XCTAssertFalse(tv.isShown(), "with showDelay:200 the tooltip must not be shown synchronously")

        // Still parked well before the delay elapses.
        pump(0.08)
        XCTAssertNil(tv.contentEl, "the tooltip must still be parked 80ms into a 200ms showDelay")

        // ... and lands once it does.
        pump(0.25)
        XCTAssertTrue(tv.isShown(), "the deferred show must land after tooltip.showDelay")
        guard let el = tv.contentEl else {
            XCTFail("the deferred show must have built the ZRText content box"); return
        }
        XCTAssertFalse(el.ignore, "the deferred tooltip box must be visible")
        let text = tooltipContent(el)
        XCTAssertTrue(text.contains("A") && text.contains("10"),
                      "the deferred tooltip must carry bar 0's content — got:\n\(text)")
    }

    // ------------------------------------------------------------------------
    // (2) A NEWER show cancels the pending one — upstream `clearTimeout(this._showTimout)`.
    //     Timeline (showDelay 200ms), driven through the showTip ACTION so no mouseout/hide
    //     intervenes and the only cancel possible is `_showOrMove`'s own:
    //       t=0    showTip dataIndex 0   -> would fire at t=200
    //       t=100  showTip dataIndex 2   -> would fire at t=300, and must CANCEL the t=200 one
    //       t=250  nothing shown yet     <- the load-bearing assertion (a live t=200 timer would
    //                                       already have painted "A"/10 here)
    //       t=400  shown, and it is C/30
    // ------------------------------------------------------------------------
    func testANewShowCancelsThePendingDelayedShow() {
        let view = makeBarView(["showDelay": 200.0])

        func showTip(_ dataIndex: Int) {
            var payload = Payload(type: "showTip")
            payload.other["seriesIndex"] = 0
            payload.other["dataIndex"] = dataIndex
            view.ec.dispatchAction(payload)
        }

        showTip(0)
        pump(0.1)
        showTip(2)

        pump(0.15)   // t ~= 250ms
        XCTAssertNil(view.tooltipView?.contentEl,
                     "the second show must have cancelled the first pending timer (nothing may be "
                     + "painted at t=250ms when the cancelled timer was due at t=200ms)")

        pump(0.15)   // t ~= 400ms
        guard let el = view.tooltipView?.contentEl else {
            XCTFail("the surviving deferred show must land"); return
        }
        let text = tooltipContent(el)
        XCTAssertTrue(text.contains("C") && text.contains("30"),
                      "only the LAST requested tooltip may be shown — got:\n\(text)")
        XCTAssertFalse(text.contains("10"),
                       "the cancelled tooltip's content must never appear — got:\n\(text)")
    }

    // ------------------------------------------------------------------------
    // (3) A hide does NOT cancel a pending delayed show — pinning UPSTREAM semantics.
    //     `_showTimout` is touched ONLY by `_showOrMove`'s own `clearTimeout` (TooltipView.ts:527);
    //     neither `_hide` (TooltipView.ts:1034, which just dispatches `hideTip`) nor `manuallyHideTip`
    //     (TooltipView.ts:389, which only calls `hideLater`) clears it. So a `showDelay` timer armed
    //     before the pointer left still fires — and the show must not be swallowed, otherwise a
    //     PROGRAMMATIC `showTip` would be lost to any stray `mouseout` inside the delay window.
    // ------------------------------------------------------------------------
    func testHideDoesNotCancelThePendingDelayedShow() {
        let view = makeBarView(["showDelay": 200.0])
        guard let (cx, cy) = barCenter(view, 0) else { XCTFail("bar 0 must render"); return }

        view._injectPointerForTest(type: "mousemove", zrX: cx, zrY: cy)
        XCTAssertNotNil(view.tooltipView, "the hover must create the TooltipView")
        // Leave the bar immediately (mouseout leg -> TooltipView.hide()).
        view._injectPointerForTest(type: "mousemove", zrX: 1, zrY: 1)

        pump(0.35)
        guard let el = view.tooltipView?.contentEl else {
            XCTFail("upstream leaves `_showTimout` running on hide — the parked show must still land")
            return
        }
        XCTAssertEqual(view.tooltipView?.isShown(), true, "and the landed show must report itself shown")
        let text = tooltipContent(el)
        XCTAssertTrue(text.contains("A") && text.contains("10"),
                      "the landed tooltip must carry bar 0's content — got:\n\(text)")
    }

    // ------------------------------------------------------------------------
    // (4) dispose() cancels a pending delayed show — a fired timer must not resurrect the box
    //     (it would `setContent` + `zr.add` an element into a zr the view has already left).
    // ------------------------------------------------------------------------
    func testDisposeCancelsThePendingDelayedShow() {
        let view = makeBarView(["showDelay": 200.0])
        guard let (cx, cy) = barCenter(view, 0) else { XCTFail("bar 0 must render"); return }

        view._injectPointerForTest(type: "mousemove", zrX: cx, zrY: cy)
        guard let tv = view.tooltipView else { XCTFail("the hover must create the TooltipView"); return }
        let rootsBefore = view.zr.storage.getRoots().count
        tv.dispose()

        pump(0.35)
        XCTAssertNil(tv.contentEl, "dispose() must cancel the pending show — no box may be built")
        XCTAssertEqual(view.zr.storage.getRoots().count, rootsBefore,
                       "no resurrected tooltip element may be added to the zr after dispose()")
    }

    // ------------------------------------------------------------------------
    // (5) hideDelay defers the actual teardown — upstream `manuallyHideTip` ->
    //     `tooltipContent.hideLater(hideDelay)`. `isShow()` flips false immediately (upstream sets
    //     `_show = false` up front "to avoid invoke hideLater multiple times") while the ZRText stays
    //     DRAWN for the delay, so the user can move the pointer into an `enterable` tooltip.
    // ------------------------------------------------------------------------
    func testHideDelayKeepsTheBoxDrawnForTheDelay() {
        let view = makeBarView(["hideDelay": 250.0])
        guard let (cx, cy) = barCenter(view, 0) else { XCTFail("bar 0 must render"); return }

        view._injectPointerForTest(type: "mousemove", zrX: cx, zrY: cy)
        guard let tv = view.tooltipView, let el = tv.contentEl else {
            XCTFail("hovering bar 0 (showDelay 0) must show the tooltip synchronously"); return
        }
        XCTAssertFalse(el.ignore, "precondition: the tooltip box is drawn on hover")

        // Leave the bar -> hide() -> hideLater(250).
        view._injectPointerForTest(type: "mousemove", zrX: 1, zrY: 1)
        XCTAssertFalse(tv.isShown(), "isShow() must flip false as soon as the hide is requested")
        XCTAssertFalse(el.ignore, "but the box must still be DRAWN during tooltip.hideDelay")

        pump(0.1)
        XCTAssertFalse(el.ignore, "still drawn 100ms into a 250ms hideDelay")

        pump(0.3)
        XCTAssertTrue(el.ignore, "after tooltip.hideDelay the box must actually be hidden")
    }

    // ------------------------------------------------------------------------
    // (6) A show during the hideDelay window CANCELS the pending hide (upstream
    //     `TooltipRichContent.show()` -> `clearTimeout(this._hideTimeout)`), so the re-hovered
    //     tooltip must not blink out when the stale timer would have fired.
    // ------------------------------------------------------------------------
    func testShowCancelsThePendingDelayedHide() {
        let view = makeBarView(["hideDelay": 250.0])
        guard let (cx, cy) = barCenter(view, 0) else { XCTFail("bar 0 must render"); return }

        view._injectPointerForTest(type: "mousemove", zrX: cx, zrY: cy)
        guard let tv = view.tooltipView, tv.contentEl != nil else {
            XCTFail("hovering bar 0 must show the tooltip"); return
        }

        view._injectPointerForTest(type: "mousemove", zrX: 1, zrY: 1)   // schedules hide at t~250
        pump(0.05)
        view._injectPointerForTest(type: "mousemove", zrX: cx, zrY: cy) // re-hover -> show() cancels it

        XCTAssertTrue(tv.isShown(), "the re-hover must show the tooltip again")
        pump(0.35)   // well past when the cancelled hide was due
        XCTAssertTrue(tv.isShown(), "the pending hide must have been cancelled by the new show")
        // `setContent` REBUILDS the ZRText, so the box to inspect is the CURRENT `contentEl`, not the
        //   one captured before the re-hover (that one was discarded and would pass vacuously).
        guard let el2 = tv.contentEl else {
            XCTFail("the re-shown tooltip must still have a content box"); return
        }
        XCTAssertFalse(el2.ignore, "the re-shown tooltip must still be drawn")
    }
}
