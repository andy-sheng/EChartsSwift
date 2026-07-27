// Phase 35 regression test — the COMBINED axis tooltip (tooltip: { trigger: "axis" }) actually APPEARS
// on hover, proven HEADLESSLY through the REAL pointer → globalListener → axisTrigger → showTip chain.
//
// Unlike ZZTooltipHoverTests (trigger:"item", driven by the element `mouseover` → tryShow item path),
// this test proves the trigger:"axis" chain fires end to end:
//
//     EChartsView._injectPointerForTest("mousemove", x, y)
//       -> zr.handler.mousemove(ZRRawEvent)                 (ZRenderKit Handler)
//       -> handler bubbles a zr-level "mousemove" ElementEvent
//       -> globalListener's mousemove listener (bound by EChartsView._bindAxisPointerListeners)
//       -> axisTrigger(payload{currTrigger,x,y}, ecModel, api)  (component/axisPointer/axisTrigger)
//            -> axis.pointToData -> snap to nearest series datum -> dataByCoordSys tree
//            -> dispatch showTip{ dataByCoordSys } through the pend/merge stage
//       -> EChartsView._realDispatchAxisPointer(showTip)
//       -> TooltipView._showAxisTooltip(dataByCoordSys)     (a ZRText box on the LIVE zr)
//
// It does NOT call _showAxisTooltip directly — the combined tooltip MUST be produced by the injected
// pointer travelling through the live Handler and the axisTrigger data core. A mousemove far off the grid
// then proves the tooltip is HIDDEN (dataByCoordSys empty → hideTip).
import XCTest
import ZRenderKit
@testable import EChartsKit

final class ZZAxisTooltipTests: XCTestCase {

    override func setUp() {
        super.setUp()
        ComponentModel.registerClass(BarSeriesModel.self)
        ComponentModel.registerClass(TooltipModel.self)
        ComponentModel.registerClass(AxisPointerModel.self)
    }

    private func makeAxisBarView() -> EChartsView {
        let view = EChartsView(width: 400, height: 300)
        view.setOption([
            // trigger:"axis" — ONE combined tooltip listing every series' value at the hovered x.
            //   `hideDelay: 0` pins the SYNCHRONOUS teardown this test is about (the default is 100ms;
            //   that timing is proven separately in ZZTooltipDelayTests).
            "tooltip": ["trigger": "axis", "hideDelay": 0.0] as [String: Any],
            "grid": ["left": 50.0, "top": 20.0, "width": 300.0, "height": 200.0] as [String: Any],
            "xAxis": ["type": "category", "data": ["A", "B", "C"]] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [["type": "bar", "data": [10.0, 20.0, 30.0]] as [String: Any]]
        ])
        return view
    }

    func testAxisHoverShowsCombinedTooltip() {
        let view = makeAxisBarView()

        // Grab bar 1's ("B") rendered Rect to compute its center x (any y inside the grid works).
        let series = view.ec.getModel()!.getSeriesByIndex(0)!
        let data = series.getData()
        guard let bar1El = data.getItemGraphicEl(1), let bar1 = bar1El as? Rect else {
            XCTFail("bar render must have populated a Rect element for data index 1 ('B')"); return
        }
        let s = bar1.shape as! RectShape
        let bx = s.x + s.width / 2       // x-pixel of category "B"
        let gy: Double = 120.0           // any y inside the grid (top 20, height 200)

        // Force the zr storage to flatten the echarts display list so `findHover`/containPoint work.
        _ = view.zr.storage.getDisplayList(true)

        // Precondition: no tooltip has been shown yet.
        XCTAssertNil(view.tooltipView, "no tooltip view should exist before any hover")

        // ---- (1) Inject a mousemove at category "B" → the COMBINED axis tooltip must APPEAR. ----
        view._injectPointerForTest(type: "mousemove", zrX: bx, zrY: gy)

        guard let tv = view.tooltipView else {
            XCTFail("hovering an axis chart must lazily create the TooltipView"); return
        }
        XCTAssertTrue(tv.isShown(), "the combined axis tooltip must be shown after hovering category B")

        guard let contentEl = tv.contentEl else {
            XCTFail("the tooltip must have created its ZRText content box"); return
        }
        XCTAssertFalse(contentEl.ignore, "the tooltip ZRText must be visible (not ignored) on hover")

        // The content ZRText must be a visible STORAGE ROOT of view.zr (a rich ZRText is a CONTAINER, so
        // assert on storage ROOTS, not the flattened display list — see ZZTooltipHoverTests).
        XCTAssertTrue(view.zr.storage.getRoots().contains { $0 === contentEl },
                      "the tooltip ZRText must be a root of view.zr (floating above the chart)")

        // (2) The combined tooltip must carry BOTH the hovered category header "B" AND the series value "20".
        let content = contentEl.textStyle?.text ?? ""
        XCTAssertTrue(content.contains("B"),
                      "the axis tooltip must contain the hovered category name 'B' — got:\n\(content)")
        XCTAssertTrue(content.contains("20"),
                      "the axis tooltip must contain series B's value '20' — got:\n\(content)")

        // ---- (3) Inject a mousemove far OFF the grid → the tooltip must HIDE (hideTip). ----
        // (1,1) is inside the 400×300 canvas but outside the grid (left 50, top 20), so no coord system
        // contains the point → axisTrigger dispatches hideTip.
        view._injectPointerForTest(type: "mousemove", zrX: 1, zrY: 1)

        XCTAssertFalse(tv.isShown(), "moving the pointer off the grid must hide the axis tooltip (hideTip)")
        XCTAssertTrue(contentEl.ignore, "the hidden tooltip ZRText must be ignored (not drawn)")
    }
}
