// Regression tests for the tooltip `formatter` OVERRIDE — upstream TooltipView.ts:835-873 (the
// `formatter` branch of `_showTooltipContent`).
//
// The load-bearing claim is that a FUNCTION-valued `tooltip.formatter` (a Swift closure carried in the
// option bag — the same closure-in-option plumbing `label.formatter` uses, model/mixin/dataFormat.swift)
// actually REPLACES the rendered tooltip text. Before this port the function formatter was a documented
// deferral, so the closure was silently ignored and the DEFAULT markup was shown instead. Every test
// here therefore asserts on the STRING that ends up in the live `ZRText` box, not merely that the
// option round-trips.
//
// Covered:
//   (1) trigger:'item'  — 1-arg closure `(CallbackDataParams) -> String`
//   (2) trigger:'item'  — full upstream 3-arg closure `(params, asyncTicket, callback) -> String`
//   (3) the ASYNC ticket path: `callback(asyncTicket, html)` invoked LATER swaps the content in, and a
//       STALE ticket is REJECTED (upstream `if (cbTicket === this._ticket)`)
//   (4) trigger:'axis'  — array-arity closure `([CallbackDataParams]) -> String`, and the axis
//       `cbParamsList` really carries `axisValue`/`axisValueLabel`/`marker`
//   (5) the STRING formatter still works (no regression) — including that a `{marker}` token is left
//       VERBATIM, which is upstream's behaviour (`formatTpl` only substitutes the `$vars`-listed keys)
import XCTest
import ZRenderKit
@testable import EChartsKit

final class ZZTooltipFormatterTests: XCTestCase {

    override func setUp() {
        super.setUp()
        ComponentModel.registerClass(BarSeriesModel.self)
        ComponentModel.registerClass(TooltipModel.self)
        ComponentModel.registerClass(AxisPointerModel.self)
    }

    private func makeBarView(tooltip: [String: Any]) -> EChartsView {
        let view = EChartsView(width: 400, height: 300)
        view.setOption([
            "tooltip": tooltip,
            "grid": ["left": 50.0, "top": 20.0, "width": 300.0, "height": 200.0] as [String: Any],
            "xAxis": ["type": "category", "data": ["A", "B", "C"]] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [["type": "bar", "name": "S0", "data": [10.0, 20.0, 30.0]] as [String: Any]]
        ])
        return view
    }

    /// Hover the centre of bar `idx` through the REAL pointer stack and return the shown tooltip text.
    private func hoverBar(_ view: EChartsView, _ idx: Int) -> String? {
        let series = view.ec.getModel()!.getSeriesByIndex(0)!
        guard let el = series.getData().getItemGraphicEl(idx), let bar = el as? Rect else {
            XCTFail("bar render must have populated a Rect for data index \(idx)"); return nil
        }
        let s = bar.shape as! RectShape
        _ = view.zr.storage.getDisplayList(true)
        view._injectPointerForTest(type: "mousemove", zrX: s.x + s.width / 2, zrY: s.y + s.height / 2)
        guard let tv = view.tooltipView, let contentEl = tv.contentEl else {
            XCTFail("hovering bar \(idx) must create + show the TooltipView"); return nil
        }
        XCTAssertTrue(tv.isShown(), "the tooltip must be shown after hovering bar \(idx)")
        return contentEl.textStyle?.text ?? ""
    }

    // ---- (1) trigger:'item' — the 1-arg closure formatter REPLACES the default markup ----
    func testItemFunctionFormatterReplacesContent() {
        var seenName: String?
        var seenValue: Any?
        var seenSeriesName: String?
        let formatter: (CallbackDataParams) -> String = { params in
            seenName = params.name
            seenValue = params.value
            seenSeriesName = params.seriesName
            return "FN>>" + params.name + "=" + format._str(params.value)
        }
        let view = makeBarView(tooltip: ["trigger": "item", "formatter": formatter])

        guard let text = hoverBar(view, 1) else { return }

        // The closure's return value IS the tooltip content — not the default markup.
        XCTAssertEqual(text, "FN>>B=20",
                       "the function formatter's return value must BE the tooltip content — got:\n\(text)")
        // And the closure really received the hovered datum's params.
        XCTAssertEqual(seenName, "B", "the formatter must receive the hovered datum's name")
        XCTAssertEqual(format._str(seenValue), "20", "the formatter must receive the hovered datum's value")
        XCTAssertEqual(seenSeriesName, "S0", "the formatter must receive the series name")
    }

    // The pre-created `params.marker` (upstream TooltipView.ts:698) must be available to the closure —
    // it is the ONLY way a user formatter can draw the series' colour swatch.
    func testItemFunctionFormatterReceivesPreCreatedMarker() {
        var seenMarker: TooltipMarker?
        let formatter: (CallbackDataParams) -> String = { params in
            seenMarker = params.marker
            return "M"
        }
        let view = makeBarView(tooltip: ["trigger": "item", "formatter": formatter])
        _ = hoverBar(view, 0)

        guard let marker = seenMarker, case .string(let markerStr) = marker else {
            XCTFail("params.marker must be pre-created for the formatter callback (got \(String(describing: seenMarker)))")
            return
        }
        // richText markers are `{styleName|}` tokens registered on the markupStyleCreator.
        XCTAssertTrue(markerStr.contains("{") && markerStr.contains("|"),
                      "the richText marker must be a {style|} token — got '\(markerStr)'")
    }

    // ---- (2) the FULL upstream 3-arg signature `(params, asyncTicket, callback) -> String` ----
    func testItemFunctionFormatterFullSignatureSyncReturn() {
        var seenTicket: String?
        let formatter: (CallbackDataParams, String, TooltipFormatterAsyncCallback) -> String = {
            params, asyncTicket, _ in
            seenTicket = asyncTicket
            return "SYNC:" + params.name
        }
        let view = makeBarView(tooltip: ["trigger": "item", "formatter": formatter])

        guard let text = hoverBar(view, 2) else { return }
        XCTAssertEqual(text, "SYNC:C", "the 3-arg formatter's synchronous return must be the content")
        // upstream: `const asyncTicket = 'item_' + dataModel.name + '_' + dataIndex` (TooltipView.ts:719)
        XCTAssertEqual(seenTicket, "item_S0_2", "the formatter must receive upstream's item asyncTicket")
    }

    // ---- (3) the ASYNC ticket path — a LATER `callback(ticket, html)` swaps the content in ----
    func testAsyncCallbackUpdatesContentAndStaleTicketIsRejected() {
        // Capture the callback + ticket handed to the formatter; return a placeholder synchronously
        // (exactly the upstream "loading…" idiom).
        var captured: (ticket: String, callback: TooltipFormatterAsyncCallback)?
        let formatter: (CallbackDataParams, String, TooltipFormatterAsyncCallback) -> String = {
            _, asyncTicket, callback in
            captured = (asyncTicket, callback)
            return "loading..."
        }
        let view = makeBarView(tooltip: ["trigger": "item", "formatter": formatter])

        guard let initial = hoverBar(view, 0) else { return }
        XCTAssertEqual(initial, "loading...", "the synchronous return is shown first")

        guard let cap = captured else {
            XCTFail("the formatter must have been handed an asyncTicket + callback"); return
        }
        // `TooltipRichContent.setContent` builds a FRESH ZRText each time (upstream does too), so the
        // shown text must be re-read from the view rather than from a captured element.
        func shownText() -> String { view.tooltipView?.contentEl?.textStyle?.text ?? "" }

        // (a) The LIVE ticket resolves: the box content is replaced.
        cap.callback(cap.ticket, "ASYNC-CONTENT")
        XCTAssertEqual(shownText(), "ASYNC-CONTENT",
                       "invoking callback(asyncTicket, html) must swap the tooltip content in")

        // (b) A STALE ticket must be IGNORED — upstream `if (cbTicket === this._ticket)`. This is what
        //     stops a slow async formatter from overwriting the tooltip of a LATER hover.
        cap.callback("some-other-ticket", "STALE-CONTENT")
        XCTAssertEqual(shownText(), "ASYNC-CONTENT",
                       "a stale cbTicket must NOT overwrite the shown tooltip")

        // (c) Hovering a DIFFERENT datum re-tickets; the OLD hover's callback is now stale.
        _ = hoverBar(view, 2)
        XCTAssertEqual(shownText(), "loading...", "the new hover shows its own synchronous content")
        cap.callback(cap.ticket, "OLD-HOVER-CONTENT")
        XCTAssertEqual(shownText(), "loading...",
                       "the previous hover's callback must not overwrite the current tooltip")
    }

    // ---- (4) trigger:'axis' — the ARRAY-arity closure + the axis params it receives ----
    func testAxisFunctionFormatterReceivesParamsList() {
        var seenCount = 0
        var seenAxisValueLabel: String?
        var seenAxisValue: Any?
        var seenAxisDim: String?
        let formatter: ([CallbackDataParams]) -> String = { paramsList in
            seenCount = paramsList.count
            seenAxisValueLabel = paramsList.first?.axisValueLabel
            seenAxisValue = paramsList.first?.axisValue
            seenAxisDim = paramsList.first?.axisDim
            return "AXIS[" + paramsList.map { $0.name + ":" + format._str($0.value) }.joined(separator: ",") + "]"
        }
        let view = makeBarView(tooltip: ["trigger": "axis", "formatter": formatter])

        // Drive the real axisTrigger chain by hovering category "B"'s x inside the grid.
        let series = view.ec.getModel()!.getSeriesByIndex(0)!
        guard let el = series.getData().getItemGraphicEl(1), let bar = el as? Rect else {
            XCTFail("bar render must have populated a Rect for data index 1"); return
        }
        let s = bar.shape as! RectShape
        _ = view.zr.storage.getDisplayList(true)
        view._injectPointerForTest(type: "mousemove", zrX: s.x + s.width / 2, zrY: 120)

        guard let tv = view.tooltipView, let contentEl = tv.contentEl else {
            XCTFail("hovering an axis chart must create + show the TooltipView"); return
        }
        XCTAssertTrue(tv.isShown(), "the combined axis tooltip must be shown")

        XCTAssertEqual(contentEl.textStyle?.text ?? "", "AXIS[B:20]",
                       "the array-arity function formatter must replace the combined axis markup")
        XCTAssertEqual(seenCount, 1, "one series is listed at the hovered axis value")
        // The axis slots must be stamped onto cbParamsList (upstream TooltipView.ts:588-596).
        XCTAssertEqual(seenAxisValueLabel, "B", "cbParams.axisValueLabel must carry the hovered category")
        XCTAssertEqual(seenAxisValue as? String, "B", "cbParams.axisValue must carry the raw axis value")
        XCTAssertEqual(seenAxisDim, "x", "cbParams.axisDim must carry the hovered axis dimension")
    }

    // ---- (5) the STRING formatter is unaffected ----
    func testStringFormatterStillApplies() {
        let view = makeBarView(tooltip: ["trigger": "item", "formatter": "TPL {b}: {c}"])
        guard let text = hoverBar(view, 1) else { return }
        XCTAssertEqual(text, "TPL B: 20", "the string formatter must still substitute the $vars")
    }

    func testRichTextHostTranslatesHTMLBreaksFromFormatter() {
        let formatter: (CallbackDataParams) -> String = { _ in
            "first<br/>second<BR>third<br />fourth"
        }
        let view = makeBarView(tooltip: ["trigger": "item", "formatter": formatter])
        guard let text = hoverBar(view, 1) else { return }
        XCTAssertEqual(text, "first\nsecond\nthird\nfourth",
                       "the native rich-text tooltip must not paint HTML break tags literally")
    }

    // `formatTpl` only substitutes the keys listed under `$vars` (= seriesName/name/value, + percent for
    // pie/funnel), so a `{marker}` token in a STRING formatter is left VERBATIM — upstream does the same.
    // (The pre-created `params.marker` is for the FUNCTION formatter; see the test above.)
    func testStringFormatterLeavesMarkerTokenVerbatim() {
        let view = makeBarView(tooltip: ["trigger": "item", "formatter": "{marker}{b}"])
        guard let text = hoverBar(view, 1) else { return }
        XCTAssertEqual(text, "{marker}B",
                       "`{marker}` is not a $var — upstream leaves it in the template verbatim")
    }

    // ---- (6) the STRING formatter's TIME-AXIS pre-pass (upstream `timeFormat(params0.axisValue, …)`) ----
    // Upstream runs the template through `timeFormat` (this port's `time.format`) BEFORE `formatTpl`
    // when `params0.axisType` contains 'time', so `{yyyy}`/`{MM}`/`{dd}` resolve against the hovered
    // AXIS VALUE. The pre-pass is ported, and the axis path now stamps the `axisType`/`axisValue` it
    // reads — but it is DORMANT, see the PORT-TODO on `isTimeAxis` in TooltipView.swift: the axis
    // models `ECharts.setOption` instantiates report `type == "xAxis"` instead of upstream's
    // `"xAxis.time"`. This test pins BOTH halves: the gap itself (so the day `EChartsXAxisModel.type`
    // is fixed, this fails loudly and the expectation below flips) and the formatter the branch calls.
    func testStringFormatterTimeAxisPrePassIsDormantOnTheKnownAxisTypeGap() {
        // The `time.format` (upstream `timeFormat`) call the pre-pass makes, on the value the axis path
        // really stamps into `cbParams.axisValue` — i.e. what the tooltip WILL show once the model type
        // carries its subType.
        XCTAssertEqual(time.format(1546387200000.0, "D={yyyy}/{MM}/{dd}", true), "D=2019/01/02",
                       "the ported timeFormat must format the hovered axis value")

        var seenAxisType: String?
        var seenAxisValue: Any?
        let probe: ([CallbackDataParams]) -> String = { list in
            seenAxisType = list.first?.axisType
            seenAxisValue = list.first?.axisValue
            return "probe"
        }
        let probeView = makeTimeAxisView(tooltip: ["trigger": "axis", "formatter": probe])
        hoverTimeAxisDatum1(probeView)
        // The axis path DOES stamp both slots — the value is right, the type is the port's main-type-only
        // form (upstream would be "xAxis.time"). That single missing subType is the whole gap.
        XCTAssertEqual(seenAxisValue as? Double, 1546387200000.0,
                       "cbParams.axisValue must carry the hovered timestamp")
        XCTAssertEqual(seenAxisType, "xAxis",
                       "KNOWN GAP (PORT-TODO in TooltipView.swift): EChartsXAxisModel.type omits the "
                       + "subType, so `axisType.indexOf('time')` never matches. When this becomes "
                       + "'xAxis.time', flip the string-formatter expectation below to 'D=2019/01/02'.")

        // The observable consequence of the gap: the template reaches the box UNFORMATTED.
        let view = makeTimeAxisView(tooltip: ["trigger": "axis", "formatter": "D={yyyy}/{MM}/{dd}"])
        hoverTimeAxisDatum1(view)
        XCTAssertEqual(view.tooltipView?.contentEl?.textStyle?.text ?? "", "D={yyyy}/{MM}/{dd}",
                       "with the axisType gap the time template is shown verbatim (see PORT-TODO)")
    }

    private func makeTimeAxisView(tooltip: [String: Any]) -> EChartsView {
        let view = EChartsView(width: 400, height: 300)
        view.setOption([
            "useUTC": true,
            "tooltip": tooltip,
            "grid": ["left": 50.0, "top": 20.0, "width": 300.0, "height": 200.0] as [String: Any],
            "xAxis": ["type": "time"] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [[
                "type": "bar",
                "name": "S0",
                // 2019-01-01T00:00:00Z and 2019-01-02T00:00:00Z
                "data": [[1546300800000.0, 10.0], [1546387200000.0, 20.0]]
            ] as [String: Any]]
        ])
        return view
    }

    /// Hover the second (2019-01-02) datum of a `makeTimeAxisView` chart through the real pointer stack.
    private func hoverTimeAxisDatum1(_ view: EChartsView) {
        let series = view.ec.getModel()!.getSeriesByIndex(0)!
        guard let el = series.getData().getItemGraphicEl(1), let bar = el as? Rect else {
            XCTFail("bar render must have populated a Rect on the time axis"); return
        }
        let s = bar.shape as! RectShape
        _ = view.zr.storage.getDisplayList(true)
        view._injectPointerForTest(type: "mousemove", zrX: s.x + s.width / 2, zrY: 120)
        XCTAssertTrue(view.tooltipView?.isShown() ?? false,
                      "the axis tooltip must be shown on the time axis")
    }

    // A non-string / non-closure `formatter` must leave the DEFAULT markup standing (this port has no
    // `HTMLElement` arm — see the PORT-NOTE in `_showTooltipContent`).
    func testUnsupportedFormatterKeepsDefaultMarkup() {
        let view = makeBarView(tooltip: ["trigger": "item", "formatter": 42])
        guard let text = hoverBar(view, 0) else { return }
        XCTAssertTrue(text.contains("A") && text.contains("10"),
                      "an unsupported formatter value must fall back to the default markup — got:\n\(text)")
    }

    // upstream's `if (formatter)` is JS-truthy: an EMPTY-STRING formatter must NOT blank the tooltip.
    func testEmptyStringFormatterIsFalsyAndKeepsDefaultMarkup() {
        let view = makeBarView(tooltip: ["trigger": "item", "formatter": ""])
        guard let text = hoverBar(view, 0) else { return }
        XCTAssertTrue(text.contains("A") && text.contains("10"),
                      "an empty-string formatter is falsy upstream — the default markup must stand — got:\n\(text)")
    }
}
