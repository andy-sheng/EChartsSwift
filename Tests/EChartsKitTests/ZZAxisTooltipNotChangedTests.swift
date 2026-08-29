// Regression test for `TooltipView._updateContentNotChangedOnAxis` (upstream TooltipView.ts:983) — the
// NO-CHANGE, position-only update path of the trigger:"axis" tooltip.
//
// Upstream, `_showAxisTooltip`'s `_showOrMove` callback compares the freshly built `dataByCoordSys` +
// `cbParamsList` against the ones the box on screen was built from (`_lastDataByCoordSys` /
// `_cbParamsList`); when they are equivalent it SKIPS rebuilding the content and only calls
// `_updatePosition`. `TooltipRichContent.setContent` constructs a BRAND NEW `ZRText` every time it runs
// (and re-adds it to the zr), so "the content was not rebuilt" is directly observable as ZRText IDENTITY:
//
//     same axis value hovered twice  -> `tooltipView.contentEl` is the SAME ZRText instance (only moved)
//     a different axis value hovered -> `tooltipView.contentEl` is a NEW ZRText instance
//
// Test 1 drives the REAL chain (injected pointer -> globalListener axisPointer + itemTooltip fan-out).
// Upstream TooltipView._tryShow runs on every mousemove; over empty grid it clears the axis memo before
// the pending axis showTip is delivered, so even the same category rebuilds while still following the
// pointer. Test 2 calls `_showAxisTooltip` directly with hand-built payload trees, which isolates the
// recursive comparison itself when no competing itemTooltip listener invalidates it.
import XCTest
import ZRenderKit
@testable import EChartsKit

final class ZZAxisTooltipNotChangedTests: XCTestCase {

    override func setUp() {
        super.setUp()
        ComponentModel.registerClass(BarSeriesModel.self)
        ComponentModel.registerClass(TooltipModel.self)
        ComponentModel.registerClass(AxisPointerModel.self)
    }

    private func makeAxisBarView() -> EChartsView {
        let view = EChartsView(width: 400, height: 300)
        view.setOption([
            "tooltip": ["trigger": "axis", "hideDelay": 0.0] as [String: Any],
            "grid": ["left": 50.0, "top": 20.0, "width": 300.0, "height": 200.0] as [String: Any],
            "xAxis": ["type": "category", "data": ["A", "B", "C"]] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [["type": "bar", "data": [10.0, 20.0, 30.0]] as [String: Any]]
        ])
        return view
    }

    /// Bar `idx`'s rendered Rect centre x.
    private func barCenterX(_ view: EChartsView, _ idx: Int) -> Double {
        let series = view.ec.getModel()!.getSeriesByIndex(0)!
        guard let el = series.getData().getItemGraphicEl(idx), let rect = el as? Rect else {
            XCTFail("bar render must have populated a Rect for data index \(idx)"); return 0
        }
        let s = rect.shape as! RectShape
        return s.x + s.width / 2
    }

    // ------------------------------------------------------------------------
    // 1) Through the live pointer chain: upstream itemTooltip invalidates the memo on every mousemove.
    // ------------------------------------------------------------------------
    func testHoveringTheSameAxisValueTwiceFollowsUpstreamGlobalListenerInvalidation() {
        let view = makeAxisBarView()
        _ = view.zr.storage.getDisplayList(true)

        let bx = barCenterX(view, 1)     // category "B"
        let cx = barCenterX(view, 2)     // category "C"
        // Inside the grid but ABOVE bar B's top, i.e. over NO series element. This matters: a series
        // element `mouseover` runs the ITEM path (`TooltipView.tryShow`), which — faithfully to upstream
        // `_tryShow`'s `else if (el)` branch — CLEARS `_lastDataByCoordSys`/`_cbParamsList` before bailing
        // on the trigger:'axis' guard. So the no-change branch is reachable exactly while the pointer is
        // not ENTERING a dispatcher (upstream, whose item leg is itself a mousemove handler, clears even
        // more often). Hovering the empty grid area is the plain real-world case for it.
        let gy: Double = 45.0

        // ---- first hover on "B": the box is BUILT ----
        view._injectPointerForTest(type: "mousemove", zrX: bx, zrY: gy)
        guard let tv = view.tooltipView, let firstEl = tv.contentEl else {
            XCTFail("hovering an axis chart must create the TooltipView and its ZRText box"); return
        }
        XCTAssertTrue(tv.isShown())
        let firstText = firstEl.textStyle?.text ?? ""
        XCTAssertTrue(firstText.contains("B"), "sanity: the box must show category B — got:\n\(firstText)")
        let firstX = firstEl.x

        // ---- second hover, SAME category "B" (a few px right, still inside the same band) ----
        // Upstream's itemTooltip record runs in the same globalListener fan-out and `_tryShow` clears
        // `_lastDataByCoordSys` when there is no target. The subsequently delivered axis showTip must
        // therefore rebuild the content, while using the new pointer position.
        view._injectPointerForTest(type: "mousemove", zrX: bx + 3, zrY: gy)

        guard let secondEl = tv.contentEl else {
            XCTFail("the tooltip must remain present after the second mousemove"); return
        }
        XCTAssertFalse(secondEl === firstEl,
                       "upstream itemTooltip _tryShow invalidates the axis memo on every empty-grid move")
        XCTAssertTrue(tv.isShown(), "the tooltip must still be shown after the repeated mousemove")
        XCTAssertNotEqual(secondEl.x, firstX,
                          "the rebuilt box must still follow the new pointer position")

        // ---- third hover on a DIFFERENT category "C": the content MUST be rebuilt ----
        view._injectPointerForTest(type: "mousemove", zrX: cx, zrY: gy)

        guard let newEl = tv.contentEl else {
            XCTFail("the tooltip box must exist after hovering category C"); return
        }
        XCTAssertFalse(newEl === firstEl,
                       "hovering a DIFFERENT axis value must rebuild the tooltip content")
        let newText = newEl.textStyle?.text ?? ""
        XCTAssertTrue(newText.contains("C") && newText.contains("30"),
                      "the rebuilt box must show category C's value — got:\n\(newText)")
    }

    // ------------------------------------------------------------------------
    // 2) The comparison itself, isolated: an EQUIVALENT-but-distinct payload tree is "not changed";
    //    a tree differing in exactly one compared field is "changed".
    // ------------------------------------------------------------------------
    func testUpdateContentNotChangedOnAxisComparesTheTreeStructurally() {
        let view = makeAxisBarView()
        _ = view.zr.storage.getDisplayList(true)
        let ecModel = view.ec.getModel()!

        // A private TooltipView over the same live zr (upstream's is owned by the ComponentView).
        let tv = TooltipView(zr: view.zr, ecModel: ecModel)

        func tree(value: Double, dataIndex: Double) -> [DataByCoordSys] {
            [DataByCoordSys(
                coordSysId: "grid_0", coordSysIndex: 0,
                coordSysType: "cartesian2d", coordSysMainType: "grid",
                dataByAxis: [DataByAxis(
                    value: value, axisIndex: 0, axisDim: "x", axisType: "xAxis", axisId: "x_0",
                    seriesDataIndices: [AxisTriggerDataIndex(
                        seriesIndex: 0, dataIndexInside: dataIndex, dataIndex: dataIndex
                    )],
                    valueLabelPrecision: nil, valueLabelFormatter: nil
                )]
            )]
        }

        // (a) first show → built.
        tv._showAxisTooltip(tree(value: 1, dataIndex: 1), x: 100, y: 100)
        guard let firstEl = tv.contentEl else {
            XCTFail("_showAxisTooltip must build the ZRText box on the first call"); return
        }
        XCTAssertTrue((firstEl.textStyle?.text ?? "").contains("B"),
                      "sanity: axis value 1 is category B")

        // (b) an EQUIVALENT but freshly allocated tree at a new pointer position → NOT rebuilt, MOVED.
        let movedFromX = firstEl.x
        tv._showAxisTooltip(tree(value: 1, dataIndex: 1), x: 160, y: 140)
        XCTAssertTrue(tv.contentEl === firstEl,
                      "an equivalent dataByCoordSys must take the position-only branch (same ZRText)")
        XCTAssertNotEqual(firstEl.x, movedFromX,
                          "the position-only branch must move the existing box")

        // (c) a tree whose axis VALUE differs → rebuilt.
        tv._showAxisTooltip(tree(value: 2, dataIndex: 2), x: 160, y: 140)
        guard let secondEl = tv.contentEl else {
            XCTFail("the box must exist after the rebuild"); return
        }
        XCTAssertFalse(secondEl === firstEl,
                       "a different axis value must rebuild the content (new ZRText)")
        XCTAssertTrue((secondEl.textStyle?.text ?? "").contains("C"),
                      "sanity: axis value 2 is category C")

        // (d) same value again but a different seriesDataIndices dataIndex → rebuilt.
        tv._showAxisTooltip(tree(value: 2, dataIndex: 2), x: 160, y: 140)
        XCTAssertTrue(tv.contentEl === secondEl, "sanity: the repeat must NOT rebuild")
        tv._showAxisTooltip(tree(value: 2, dataIndex: 1), x: 160, y: 140)
        XCTAssertFalse(tv.contentEl === secondEl,
                       "a different seriesDataIndices dataIndex must rebuild the content")

        // (e) hide() clears the memo, so the next identical show must rebuild again.
        guard let thirdEl = tv.contentEl else { XCTFail("box must exist"); return }
        tv.hide()
        tv._showAxisTooltip(tree(value: 2, dataIndex: 1), x: 160, y: 140)
        XCTAssertFalse(tv.contentEl === thirdEl,
                       "hide() must clear _lastDataByCoordSys so the content is rebuilt on the next show")
    }

    // ------------------------------------------------------------------------
    // 3) The RENDER-side invalidation (`TooltipView.clearAxisTooltipMemo`, called from
    //    `EChartsView._afterSetOption`). Upstream never needs it: its item leg is a per-mousemove
    //    `globalListener('itemTooltip')` that nulls `_lastDataByCoordSys` on every pointer move, so a
    //    re-render can never be masked by the memo. This port only runs `tryShow` on element ENTER, so a
    //    `setOption` that changes something the memo does NOT compare (here: the `formatter`) would
    //    otherwise leave STALE content on screen while the pointer stays in the same axis band.
    // ------------------------------------------------------------------------
    func testSetOptionInvalidatesTheAxisNoChangeMemo() {
        let view = makeAxisBarView()
        _ = view.zr.storage.getDisplayList(true)
        let bx = barCenterX(view, 1)     // category "B"
        let gy: Double = 45.0

        view._injectPointerForTest(type: "mousemove", zrX: bx, zrY: gy)
        guard let tv = view.tooltipView, let firstEl = tv.contentEl else {
            XCTFail("hovering an axis chart must create the TooltipView and its ZRText box"); return
        }

        // Change ONLY the formatter — the dataByCoordSys tree and every `cbParams.data` the memo compares
        // stay byte-identical, so without the invalidation the next hover takes the no-change branch.
        view.setOption(["tooltip": [
            "trigger": "axis", "hideDelay": 0.0, "formatter": "CUSTOM-AXIS-FORMATTER"
        ] as [String: Any]])
        _ = view.zr.storage.getDisplayList(true)

        view._injectPointerForTest(type: "mousemove", zrX: bx + 3, zrY: gy)
        guard let newEl = tv.contentEl else {
            XCTFail("the tooltip box must exist after the re-hover"); return
        }
        XCTAssertFalse(newEl === firstEl,
                       "a setOption must invalidate the axis no-change memo, so the next hover REBUILDS "
                       + "the content instead of only moving the stale box")
        XCTAssertTrue((newEl.textStyle?.text ?? "").contains("CUSTOM-AXIS-FORMATTER"),
                      "the rebuilt box must use the NEW formatter — got:\n\(newEl.textStyle?.text ?? "")")
    }
}
