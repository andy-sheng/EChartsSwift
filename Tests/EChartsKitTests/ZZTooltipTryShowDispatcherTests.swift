// Regression tests for the tooltip DISPATCHER — upstream `TooltipView._tryShow` (TooltipView.ts:453-515)
// plus the `ECData` reads at the head of `_showSeriesItemTooltip` (TooltipView.ts:659-673).
//
// `_tryShow` is the single funnel every show attempt goes through. Given the hovered element it walks
// the ancestor chain with the ported `findEventDispatcher(el, det, /*returnFirstMatch*/ true)`
// (util/event.swift:32) and routes to exactly one of four outcomes:
//
//   e.dataByCoordSys non-empty ................ `_showAxisTooltip`            (covered by ZZAxisTooltipTests)
//   an ancestor has ecData.dataIndex .......... `_showSeriesItemTooltip`      (1)
//   an ancestor has ecData.tooltipConfig ...... `_showComponentItemTooltip`   (2)
//   any ancestor has tooltipDisabled .......... nothing at all                (3), (4)
//   nothing matched ........................... `_hide`                       (5)
//
// Before this port the host (`EChartsView._showTooltipForHover`) re-rolled a slimmed copy of the det
// and pre-resolved the series/dataIndex itself, which silently dropped the `tooltipDisabled` bail-out
// AND the `ssrType === 'legend'` early-out, and made an OUTER `tooltipDisabled` ancestor unable to
// cancel an inner dispatcher (the walk stopped at the first match). Each test below asserts on the
// STRING in the live `ZRText` box, so it fails if the routing regresses — not merely if it compiles.
import XCTest
import ZRenderKit
@testable import EChartsKit

final class ZZTooltipTryShowDispatcherTests: XCTestCase {

    override func setUp() {
        super.setUp()
        ComponentModel.registerClass(TooltipModel.self)
        ComponentModel.registerClass(AxisPointerModel.self)
    }

    // ------------------------------------------------------------------------
    // Fixture — one bar series + a legend, so BOTH dispatcher kinds exist in the same scene:
    //   - the bars carry `ecData.dataIndex`      → seriesDispatcher
    //   - the legend hit-rects carry `ecData.tooltipConfig` → cmptDispatcher
    // The two formatters are deliberately different strings so the assertion pins WHICH branch ran.
    // ------------------------------------------------------------------------
    private func makeView(trigger: String = "item") -> EChartsView {
        let view = EChartsView(width: 400, height: 300)
        view.setOption([
            "tooltip": ["trigger": trigger, "formatter": "SERIES:{a}"] as [String: Any],
            "legend": [
                "data": ["Alpha"],
                "tooltip": ["show": true, "formatter": "COMPONENT:{a}"] as [String: Any]
            ] as [String: Any],
            "grid": ["left": 50.0, "top": 60.0, "width": 300.0, "height": 200.0] as [String: Any],
            "xAxis": ["type": "category", "data": ["A", "B", "C"]] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [
                ["name": "Alpha", "type": "bar", "data": [1.0, 2.0, 3.0]] as [String: Any]
            ]
        ])
        _ = view.zr.storage.getDisplayList(true)
        return view
    }

    /// The first rendered element carrying `ecData.dataIndex == dataIndex` (a bar).
    private func findSeriesEl(_ view: EChartsView, dataIndex: Double) -> Element? {
        for el in view.zr.storage.getDisplayList(true) {
            let ecData = innerStore.getECData(el)
            if ecData.dataIndex == dataIndex && ecData.seriesIndex == 0 {
                return el
            }
        }
        return nil
    }

    /// The rendered element whose `ecData.tooltipConfig.name` is `name` (a legend item hit-rect).
    private func findTooltipConfigEl(_ view: EChartsView, named name: String) -> Element? {
        for el in view.zr.storage.getDisplayList(true) {
            if innerStore.getECData(el).tooltipConfig?.name == name {
                return el
            }
        }
        return nil
    }

    /// Drive the REAL pointer stack (zr Handler → mouseover → `_showTooltipForHover` → `_tryShow`)
    /// onto the centre of `el`.
    private func hover(_ view: EChartsView, _ el: Element) {
        guard let rect = el.getBoundingRect() else {
            XCTFail("the element must have a bounding rect to hover")
            return
        }
        let center = el.transformCoordToGlobal(rect.x + rect.width / 2, rect.y + rect.height / 2)
        view._injectPointerForTest(type: "mousemove", zrX: center[0], zrY: center[1])
    }

    /// The tooltip text currently in the live `ZRText` box (nil when no tooltip is up).
    private func tooltipText(_ view: EChartsView) -> String? {
        guard let tv = view.tooltipView, tv.isShown() else { return nil }
        return tv.contentEl?.textStyle?.text
    }

    // ========================================================================
    // (1) an element with `ecData.dataIndex` → the SERIES-item tooltip
    // ========================================================================
    func testDispatcherRoutesElementWithDataIndexToSeriesItemTooltip() {
        let view = makeView()
        guard let bar = findSeriesEl(view, dataIndex: 0) else {
            XCTFail("the bar series must render an element carrying ecData.dataIndex")
            return
        }
        hover(view, bar)

        XCTAssertEqual(tooltipText(view), "SERIES:Alpha",
                       "an element with ecData.dataIndex must take _tryShow's seriesDispatcher branch")
    }

    // The dispatcher walk must also RESOLVE the series off the dispatcher's own ECData — upstream
    // `_showSeriesItemTooltip`'s `ecData.seriesIndex` / `ecData.dataIndex` / `ecData.dataType` reads.
    // Driving `_tryShow` with nothing but the element pins that (the caller passes NO series at all).
    func testDispatcherResolvesSeriesAndDataIndexFromTheDispatchersECData() {
        let view = makeView()
        guard let bar2 = findSeriesEl(view, dataIndex: 2) else {
            XCTFail("the bar series must render an element for dataIndex 2")
            return
        }
        // Create the view the same way the host does, then call the dispatcher directly with ONLY the
        //   element + pointer — no seriesModel, no dataIndex.
        hover(view, bar2)
        guard let tv = view.tooltipView else {
            XCTFail("hovering must have created the TooltipView")
            return
        }
        tv.hide()
        XCTAssertNil(tooltipText(view))

        tv._tryShow(TryShowParams(target: bar2, offsetX: 100, offsetY: 100))
        XCTAssertEqual(tooltipText(view), "SERIES:Alpha",
                       "_tryShow must resolve seriesIndex/dataIndex from the dispatcher's ECData itself")
    }

    // ========================================================================
    // (2) an element with only `ecData.tooltipConfig` → the COMPONENT-item tooltip
    // ========================================================================
    func testDispatcherRoutesElementWithTooltipConfigToComponentItemTooltip() {
        let view = makeView()
        guard let hitRect = findTooltipConfigEl(view, named: "Alpha") else {
            XCTFail("LegendView must stamp an ecData.tooltipConfig on the 'Alpha' item")
            return
        }
        XCTAssertNil(innerStore.getECData(hitRect).dataIndex,
                     "fixture check: the legend hit-rect must NOT carry a dataIndex, else it would take "
                     + "the series branch")
        hover(view, hitRect)

        XCTAssertEqual(tooltipText(view), "COMPONENT:Alpha",
                       "an element with only ecData.tooltipConfig must take _tryShow's cmptDispatcher branch")
    }

    // ========================================================================
    // (3) an element under a `tooltipDisabled` ANCESTOR → no tooltip at all
    // ========================================================================
    func testTooltipDisabledAncestorSuppressesTheSeriesTooltip() {
        // --- control: without the flag the very same hover DOES show a tooltip ---------------------
        let control = makeView()
        guard let controlBar = findSeriesEl(control, dataIndex: 1) else {
            XCTFail("the bar series must render an element carrying ecData.dataIndex")
            return
        }
        hover(control, controlBar)
        XCTAssertEqual(tooltipText(control), "SERIES:Alpha", "fixture check: the hover must work at all")

        // --- the real assertion --------------------------------------------------------------------
        let view = makeView()
        guard let bar = findSeriesEl(view, dataIndex: 1) else {
            XCTFail("the bar series must render an element carrying ecData.dataIndex")
            return
        }
        guard let ancestor = bar.parent as? Element else {
            XCTFail("the bar must be parented in a group so a tooltipDisabled ANCESTOR exists")
            return
        }
        // upstream: `(el as ECElement).tooltipDisabled = true` (CustomView.ts:1052). No concrete
        //   scene-graph type conforms to `ECElement` in this port, so the flag lives in the side store.
        innerStore.getECElementProps(ancestor).tooltipDisabled = true

        hover(view, bar)
        XCTAssertNil(tooltipText(view),
                     "a tooltipDisabled ANCESTOR must cancel the tooltip even though the hovered "
                     + "element itself carries a dataIndex (upstream TooltipView.ts:483)")
    }

    // ========================================================================
    // (4) the `returnFirstMatch: true` semantics: the walk keeps going PAST a dispatcher it already
    //     found, so a tooltipDisabled ancestor further OUT still nulls it. (This is the case the
    //     pre-dispatcher host walk got wrong — it stopped at the first match.)
    // ========================================================================
    func testTooltipDisabledOnAnOuterAncestorCancelsAnAlreadyFoundInnerDispatcher() {
        let view = makeView()
        guard let bar = findSeriesEl(view, dataIndex: 0) else {
            XCTFail("the bar series must render an element carrying ecData.dataIndex")
            return
        }
        // Walk to the OUTERMOST ancestor (the zr root group), i.e. as far as possible from the
        //   dispatcher, and disable there.
        var outermost: Element = bar
        while let parent = outermost.parent as? Element {
            outermost = parent
        }
        XCTAssertFalse(outermost === bar, "the bar must have at least one ancestor")
        innerStore.getECElementProps(outermost).tooltipDisabled = true

        hover(view, bar)
        XCTAssertNil(tooltipText(view),
                     "the det must keep walking past the found seriesDispatcher so an OUTER "
                     + "tooltipDisabled ancestor can still null it")
    }

    // The component branch is gated by the same guard.
    func testTooltipDisabledAncestorSuppressesTheComponentTooltip() {
        let view = makeView()
        guard let hitRect = findTooltipConfigEl(view, named: "Alpha"),
              let ancestor = hitRect.parent as? Element else {
            XCTFail("LegendView must stamp an ecData.tooltipConfig on a parented 'Alpha' item")
            return
        }
        innerStore.getECElementProps(ancestor).tooltipDisabled = true

        hover(view, hitRect)
        XCTAssertNil(tooltipText(view),
                     "a tooltipDisabled ancestor must cancel the COMPONENT-item branch too")
    }

    // ========================================================================
    // (5) nothing matched → `_hide` (upstream TooltipView.ts:507/513)
    // ========================================================================
    func testDispatcherHidesWhenNeitherDispatcherMatches() {
        let view = makeView()
        guard let bar = findSeriesEl(view, dataIndex: 0) else {
            XCTFail("the bar series must render an element carrying ecData.dataIndex")
            return
        }
        hover(view, bar)
        XCTAssertEqual(tooltipText(view), "SERIES:Alpha")
        guard let tv = view.tooltipView else {
            XCTFail("hovering must have created the TooltipView")
            return
        }

        // A bare element with no ECData at all — upstream's `else { this._hide(dispatchAction) }`.
        let plain = Rect()
        tv._tryShow(TryShowParams(target: plain, offsetX: 10, offsetY: 10))
        XCTAssertNil(tooltipText(view),
                     "_tryShow must hide when neither a seriesDispatcher nor a cmptDispatcher is found")

        // …and the same for `e.target == nil` (upstream's outermost `else`).
        //   (Re-shown through `_tryShow` rather than `hover`: zr only fires `mouseover` when the hovered
        //    element CHANGES, so re-hovering the same bar would be a no-op.)
        tv._tryShow(TryShowParams(target: bar, offsetX: 100, offsetY: 100))
        XCTAssertEqual(tooltipText(view), "SERIES:Alpha")
        tv._tryShow(TryShowParams(target: nil, offsetX: 10, offsetY: 10))
        XCTAssertNil(tooltipText(view), "_tryShow with no target must hide too")
    }

    // ========================================================================
    // The `_hide` divergence: under `trigger:'axis'` the item leg's hide is suppressed, standing in for
    // upstream's globalListener pend/merge where the axis leg's showTip beats the item leg's hideTip
    // (see the PORT-NOTE on `TooltipView._hide`). Without it, the zr `mouseover` leg would tear down the
    // axis tooltip the same pointer move had just put up.
    // ========================================================================
    func testItemLegHideIsSuppressedUnderAxisTrigger() {
        let view = makeView(trigger: "axis")
        let tv = TooltipView(zr: view.zr, ecModel: view.ec.getModel()!)
        // Put an axis tooltip on screen the way axisTrigger does, then have the item leg fail to match.
        guard let bar = findSeriesEl(view, dataIndex: 0) else {
            XCTFail("the bar series must render an element carrying ecData.dataIndex")
            return
        }
        // The series leg self-gates on `trigger != 'item'`, so nothing is shown — but crucially the
        //   no-dispatcher arm must NOT hide either.
        tv._tryShow(TryShowParams(target: bar, offsetX: 100, offsetY: 100))
        let plain = Rect()
        tv._tryShow(TryShowParams(target: plain, offsetX: 100, offsetY: 100))
        XCTAssertFalse(tv._shownAsCmptItem)
        // The observable assertion: `_hide` did not run, so a component-item box put up by the SAME
        //   view survives a subsequent no-dispatcher `_tryShow`.
        guard let hitRect = findTooltipConfigEl(view, named: "Alpha") else {
            XCTFail("LegendView must stamp an ecData.tooltipConfig on the 'Alpha' item")
            return
        }
        tv._tryShow(TryShowParams(target: hitRect, offsetX: 100, offsetY: 100))
        XCTAssertTrue(tv.isShown(), "the component-item branch ignores `trigger` (upstream comment)")
        tv._tryShow(TryShowParams(target: plain, offsetX: 100, offsetY: 100))
        XCTAssertTrue(tv.isShown(),
                      "under trigger:'axis' the item leg's _hide must be suppressed — the axis leg owns "
                      + "the box and is the one that hides it")
    }
}
