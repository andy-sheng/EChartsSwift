// Phase 33 regression test — LIVE hover→emphasis, proven HEADLESSLY through the REAL pointer stack.
//
// Unlike ZZEmphasisTests (which drives `dispatchAction` directly), this test injects a synthetic
// POINTER event and proves the whole chain fires end to end:
//
//     EChartsView._injectPointerForTest("mousemove", x, y)
//       -> zr.handler.mousemove(ZRRawEvent)          (ZRenderKit Handler)
//       -> handler.findHover(x, y)                    (hit-tests the echarts display list)
//       -> handler.dispatchToElement(hovered, .mouseover) -> zr-level "mouseover" trigger
//       -> EChartsView._initEvents' "mouseover" listener
//       -> states.enterEmphasisWhenMouseOver(dispatcher, e)
//       -> the bar Rect enters the "emphasis" state.
//
// It does NOT call enterEmphasis directly — the emphasis MUST be produced by the injected pointer
// travelling through the live Handler hit-test and the bound listener. A mousemove off all bars then
// drives the `mouseout` leg and proves emphasis is cleared.
import XCTest
import ZRenderKit
@testable import EChartsKit

final class ZZLiveHoverTests: XCTestCase {

    override func setUp() {
        super.setUp()
        ComponentModel.registerClass(BarSeriesModel.self)
    }

    private func makeBarView() -> EChartsView {
        let view = EChartsView(width: 400, height: 300)
        view.setOption([
            "grid": ["left": 50.0, "top": 20.0, "width": 300.0, "height": 200.0] as [String: Any],
            "xAxis": ["type": "category", "data": ["A", "B", "C"]] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [["type": "bar", "data": [10.0, 20.0, 30.0]] as [String: Any]]
        ])
        return view
    }

    func testInjectedPointerDrivesEmphasisThroughHandler() {
        let view = makeBarView()

        // Grab bar 0's rendered element from the series data.
        let series = view.ec.getModel()!.getSeriesByIndex(0)!
        let data = series.getData()
        guard let bar0El = data.getItemGraphicEl(0), let bar0 = bar0El as? Rect else {
            XCTFail("bar render must have populated a Rect element for data index 0"); return
        }

        // Phase-33 precondition: BarView.updateStyle made every bar a highDown dispatcher, and no
        // emphasis is active yet (nothing has hovered).
        XCTAssertTrue(states.isHighDownDispatcher(bar0),
                      "BarView.updateStyle must mark each bar a highDown dispatcher")
        XCTAssertTrue(bar0.currentStates.isEmpty, "bar 0 must not be in emphasis before any hover")

        // The point to hover: the center of bar 0's shape rect (shape coords are grid-global here).
        let s = bar0.shape as! RectShape
        let cx = s.x + s.width / 2
        let cy = s.y + s.height / 2

        // Force the zr storage to flatten the echarts display list so `findHover` can hit-test the bars.
        _ = view.zr.storage.getDisplayList(true)

        // ---- (1) Inject a mousemove OVER bar 0 → must enter emphasis through the real Handler. ----
        view._injectPointerForTest(type: "mousemove", zrX: cx, zrY: cy)

        XCTAssertTrue(bar0.currentStates.contains("emphasis"),
                      "an injected pointer over bar 0 must drive it into emphasis through the Handler hit-test")
        XCTAssertTrue(bar0.hasState())

        // ---- (2) Inject a mousemove OFF all bars → must leave emphasis (mouseout leg fires). ----
        // (1,1) is inside the 400×300 canvas but well outside the grid (left 50, top 20), so findHover
        // resolves no bar; the previous-hover mouseout dispatches on bar 0's dispatcher.
        view._injectPointerForTest(type: "mousemove", zrX: 1, zrY: 1)

        XCTAssertTrue(bar0.currentStates.isEmpty,
                      "moving the pointer off bar 0 must clear its emphasis via the mouseout leg")
        XCTAssertFalse(bar0.hasState())
    }

    // Retain-cycle regression: EChartsView binds zr listeners; the ctx must NOT be `self` (Eventful
    // stores ctx strongly, and zr→handler→eventful is strongly owned by the view). If the cycle
    // regresses, the view never deallocates.
    func testEChartsViewHasNoRetainCycle() {
        weak var weakView: EChartsView?
        autoreleasepool {
            let view = makeBarView()
            weakView = view
            XCTAssertNotNil(weakView)
            _ = view  // keep alive to end of scope
        }
        XCTAssertNil(weakView, "EChartsView must deallocate (no zr↔handler↔eventful↔self retain cycle)")
    }
}
