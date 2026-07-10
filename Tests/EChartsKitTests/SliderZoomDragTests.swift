import XCTest
@testable import EChartsKit
@testable import ZRenderKit

// Regression: dragging the slider dataZoom did NOTHING — the elements were marked `draggable`
// but `_wireDrift` (the ported `drift: bind(this._onDragMove, …)` seam, SliderZoomView.ts
// _renderHandle) was never called, so the Handler's Draggable ran the default in-place translate
// and no dataZoom action was ever dispatched.
final class SliderZoomDragTests: XCTestCase {
    private func makeView() -> EChartsView {
        let v = EChartsView(width: 480, height: 360)
        v.setOption(["animation": false,
                     "xAxis": ["type": "category",
                               "data": (0..<20).map { "c\($0)" }] as [String: Any],
                     "yAxis": ["type": "value"],
                     "dataZoom": [["type": "slider", "start": 10.0, "end": 70.0] as [String: Any]],
                     "series": [["type": "bar", "data": (0..<20).map { Double($0 * 5) }] as [String: Any]]])
        _ = v.zr.storage.getDisplayList(true)
        return v
    }

    private func globalCenter(_ el: Path) -> (Double, Double) {
        let rect = el.getBoundingRect()!
        let g = el.transformCoordToGlobal(rect.x + rect.width / 2, rect.y + rect.height / 2)
        return (g[0], g[1])
    }

    func testDraggingMoveZonePansTheWindow() {
        let v = makeView()
        guard let zoomView = v.ec._componentsViews.compactMap({ $0 as? SliderZoomView }).first,
              let moveZone = zoomView._displayables.moveZone else {
            XCTFail("slider dataZoom view + moveZone must exist (brushSelect default true)"); return
        }
        let model = zoomView.dataZoomModel!
        XCTAssertEqual(model.getPercentRange() ?? [], [10, 70], "baseline window 10-70")

        // Drag the move strip 60px to the right (mousedown → mousemove → mouseup, live handler).
        let (cx, cy) = globalCenter(moveZone)
        v._injectPointerForTest(type: "mousedown", zrX: cx, zrY: cy)
        v._injectPointerForTest(type: "mousemove", zrX: cx + 30, zrY: cy)
        v._injectPointerForTest(type: "mousemove", zrX: cx + 60, zrY: cy)
        v._injectPointerForTest(type: "mouseup", zrX: cx + 60, zrY: cy)

        guard let range = model.getPercentRange() else { return XCTFail("percent range must exist") }
        XCTAssertGreaterThan(range[0], 10, "dragging the move strip right must move the window start")
        XCTAssertGreaterThan(range[1], 70, "dragging the move strip right must move the window end")
        XCTAssertEqual(range[1] - range[0], 60, accuracy: 1.0,
                       "panning keeps the window span (~60%)")
    }

    func testDraggingHandleResizesTheWindow() {
        let v = makeView()
        guard let zoomView = v.ec._componentsViews.compactMap({ $0 as? SliderZoomView }).first,
              zoomView._displayables.handles.count >= 2,
              let handle1 = zoomView._displayables.handles[1] else {
            XCTFail("slider handles must exist"); return
        }
        let model = zoomView.dataZoomModel!

        // Drag the END handle 40px to the LEFT → window end shrinks, start unchanged.
        let (cx, cy) = globalCenter(handle1)
        v._injectPointerForTest(type: "mousedown", zrX: cx, zrY: cy)
        v._injectPointerForTest(type: "mousemove", zrX: cx - 40, zrY: cy)
        v._injectPointerForTest(type: "mouseup", zrX: cx - 40, zrY: cy)

        guard let range = model.getPercentRange() else { return XCTFail("percent range must exist") }
        XCTAssertEqual(range[0], 10, accuracy: 1.0, "start handle untouched")
        XCTAssertLessThan(range[1], 70, "dragging the end handle left must shrink the window end")
    }

    // brushSelect (default true): dragging across the empty track draws a rubber band and commits
    // the brushed span as the new window (upstream _onBrushStart/_onBrush/_onBrushEnd) — the
    // "behaves differently from HTML" part of the report.
    func testBrushSelectOnTrackSetsWindow() {
        let v = makeView()
        guard let zoomView = v.ec._componentsViews.compactMap({ $0 as? SliderZoomView }).first,
              let panel = zoomView._displayables.panel,
              let sliderGroup = zoomView._displayables.sliderGroup else {
            XCTFail("slider panel must exist"); return
        }
        let model = zoomView.dataZoomModel!
        let shape = panel.shape as! RectShape

        // Brush from 80% to 95% of the track (to the right of the 10-70% filler → hits the panel).
        let y = shape.y + shape.height / 2
        let s = sliderGroup.transformCoordToGlobal(shape.x + shape.width * 0.80, y)
        let m = sliderGroup.transformCoordToGlobal(shape.x + shape.width * 0.90, y)
        let e = sliderGroup.transformCoordToGlobal(shape.x + shape.width * 0.95, y)
        v._injectPointerForTest(type: "mousedown", zrX: s[0], zrY: s[1])
        v._injectPointerForTest(type: "mousemove", zrX: m[0], zrY: m[1])
        XCTAssertTrue(zoomView._displayables.brushRect != nil
                          && zoomView._displayables.brushRect!.ignore == false,
                      "a rubber-band rect must show while brushing")
        v._injectPointerForTest(type: "mousemove", zrX: e[0], zrY: e[1])
        v._injectPointerForTest(type: "mouseup", zrX: e[0], zrY: e[1])

        guard let range = model.getPercentRange() else { return XCTFail("percent range must exist") }
        XCTAssertEqual(range[0], 80, accuracy: 2.0, "window start = brush start (~80%)")
        XCTAssertEqual(range[1], 95, accuracy: 2.0, "window end = brush end (~95%)")
        // The commit re-renders the slider (brushRect reset to nil) or leaves the rect ignored.
        let brushRect = zoomView._displayables.brushRect
        XCTAssertTrue(brushRect == nil || brushRect!.ignore,
                      "the rubber band must be hidden after the brush commits")
    }
}
