// Phase 39 regression test — LIVE drag (mousedown → mousemove → mouseup) → inside-dataZoom PAN/roam,
// proven HEADLESSLY through the REAL pointer stack (modeled on ZZInsideZoomTests, the wheel-zoom test).
//
// It injects a synthetic drag and proves the whole chain fires end to end:
//
//     EChartsView._injectPointerForTest("mousedown"/"mousemove"/"mouseup", x, y)
//       -> zr.handler.mousedown/mousemove/mouseup(ZRRawEvent{zrX,zrY})   (ZRenderKit Handler)
//       -> zr-level "mousedown"/"mousemove"/"mouseup" triggers
//       -> EChartsView._bindInsidePan's listeners
//       -> _handleInsidePanDown starts the drag; _handleInsidePanMove:
//            InsideZoomView.pan (makeMover) percentDelta + sliderMove('all') window shift
//       -> ec.dispatchAction({type:'dataZoom', batch:[{dataZoomId,start,end}]})
//       -> setRawRange -> update() -> dataZoomProcessor re-filters the series data
//
// It does NOT call dispatchAction('dataZoom') directly — the new window MUST be produced by the injected
// drag travelling through the live Handler and the bound listeners.
import XCTest
import ZRenderKit
@testable import EChartsKit

final class ZZInsidePanTests: XCTestCase {

    override func setUp() {
        super.setUp()
        ComponentModel.registerClass(BarSeriesModel.self)
    }

    /// 10 categories c0..c9, series data [0..9], grid + category xAxis + value yAxis, and an INSIDE
    /// dataZoom over a SUB-window [20, 60] (span 40) so there is room to pan both left and right.
    private func makePanView() -> EChartsView {
        let cats: [Any] = (0..<10).map { "c\($0)" }
        let data: [Any] = (0..<10).map { Double($0) }
        let view = EChartsView(width: 400, height: 300)
        view.setOption([
            "grid": ["left": 50.0, "top": 20.0, "width": 300.0, "height": 200.0] as [String: Any],
            "xAxis": ["type": "category", "data": cats] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [["type": "bar", "data": data] as [String: Any]],
            "dataZoom": [["type": "inside", "start": 20, "end": 60] as [String: Any]]
        ])
        // Flatten the display list so the Handler can hit-test / dispatch over the echarts elements.
        _ = view.zr.storage.getDisplayList(true)
        return view
    }

    private func percentRange(_ view: EChartsView) -> [Double]? {
        return (view.ec.getModel()?.getComponent("dataZoom", 0) as? InsideZoomModel)?.getPercentRange()
    }

    private func drag(_ view: EChartsView, fromX: Double, fromY: Double, dx: Double, dy: Double = 0) {
        view._injectPointerForTest(type: "mousedown", zrX: fromX, zrY: fromY)
        view._injectPointerForTest(type: "mousemove", zrX: fromX + dx, zrY: fromY + dy)
        view._injectPointerForTest(type: "mouseup", zrX: fromX + dx, zrY: fromY + dy)
    }

    // Dragging LEFT (dx < 0) on a non-inverse x-axis must shift the window toward HIGHER percents (right),
    // moving BOTH handles by the same delta so the span (40) is preserved.
    func testDragShiftsWindowPreservingSpan() {
        let view = makePanView()

        let initial = percentRange(view)
        XCTAssertEqual(initial?[0] ?? -1, 20, accuracy: 1e-6, "initial window start must be 20%")
        XCTAssertEqual(initial?[1] ?? -1, 60, accuracy: 1e-6, "initial window end must be 60%")

        // Grid left:50 top:20 width:300 height:200 → center (200, 120).
        let gx = 50.0 + 300.0 / 2
        let gy = 20.0 + 200.0 / 2
        // Drag LEFT by 150px = half the grid width. signal(x, non-inverse) = -1, so
        //   percentDelta = -1 * span(40) * (-150) / 300 = +20 → window [20,60] -> [40,80].
        drag(view, fromX: gx, fromY: gy, dx: -150)

        let panned = percentRange(view)
        print("INSIDE-PAN drag-left: [\(initial![0]),\(initial![1])] -> [\(panned![0]),\(panned![1])]")
        XCTAssertNotNil(panned)
        XCTAssertNotEqual(panned![0], 20, "drag must move the window start off its initial 20%")
        XCTAssertGreaterThan(panned![0], 20, "drag-left on a non-inverse x-axis must move the window right")
        XCTAssertEqual(panned![1] - panned![0], 40, accuracy: 1e-6, "span (end-start) must be preserved at 40")
        XCTAssertLessThanOrEqual(panned![1], 100, "the window must stay clamped within [0,100]")
        XCTAssertGreaterThanOrEqual(panned![0], 0, "the window must stay clamped within [0,100]")
    }

    // Dragging the OTHER direction (dx > 0) must move the window the OTHER way (toward lower percents).
    func testDragOtherDirectionMovesBack() {
        let view = makePanView()
        let gx = 50.0 + 300.0 / 2
        let gy = 20.0 + 200.0 / 2
        // Drag RIGHT by 75px: percentDelta = -1 * 40 * 75 / 300 = -10 → window [20,60] -> [10,50].
        drag(view, fromX: gx, fromY: gy, dx: 75)

        let panned = percentRange(view)
        print("INSIDE-PAN drag-right: [20,60] -> [\(panned![0]),\(panned![1])]")
        XCTAssertLessThan(panned![0], 20, "drag-right on a non-inverse x-axis must move the window left")
        XCTAssertEqual(panned![1] - panned![0], 40, accuracy: 1e-6, "span (end-start) must be preserved at 40")
    }

    // A drag that STARTS off the grid must not start a drag → the window is untouched by the later move.
    func testDragStartingOffGridDoesNothing() {
        let view = makePanView()
        // (1, 1) is inside the 400×300 canvas but well outside the grid (left:50, top:20).
        drag(view, fromX: 1, fromY: 1, dx: 200)
        let r = percentRange(view)
        XCTAssertEqual(r?[0] ?? -1, 20, accuracy: 1e-6, "an off-grid drag must not shift the window")
        XCTAssertEqual(r?[1] ?? -1, 60, accuracy: 1e-6, "an off-grid drag must not shift the window")
    }
}
