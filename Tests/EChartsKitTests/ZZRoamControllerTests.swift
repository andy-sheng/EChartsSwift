// L3 Roam — RoamController unit test. Drives synthetic mousedown/mousemove/mouseup + wheel through the
// REAL zr Handler (EChartsView._injectPointerForTest / _injectWheelForTest) and asserts the ported
// `RoamController` emits 'pan' (with the exact dx/dy) and 'zoom' (with a scale > 1).
//
//     _injectPointerForTest("mousedown"/"mousemove", x, y)
//       -> zr.handler.mousedown/mousemove(ZRRawEvent)
//       -> zr "mousedown"/"mousemove" trigger
//       -> RoamController's addRoamZrListener uniform fan-out -> _mousedownHandler / _mousemoveHandler
//       -> controller.trigger('pan', {dx, dy, ...})  -> the .on('pan') listener
import XCTest
import ZRenderKit
@testable import EChartsKit

final class ZZRoamControllerTests: XCTestCase {

    /// A controller enabled over a live (headless) zr, with an isInSelf that accepts any point so the
    /// gesture always passes `_checkPointer`. Returns (view, controller) — the view owns the zr.
    private func makeController(_ controlType: Any?) -> (EChartsView, RoamController) {
        let view = EChartsView(width: 400, height: 300)
        let controller = RoamController(view.zr)
        let comp = ComponentModel(nil, nil, nil)
        let opt = RoamOption(
            component: comp,
            api: view.ec.api,
            isInSelf: { _, _, _ in true }
        )
        controller.enable(controlType, opt)
        return (view, controller)
    }

    // A drag mousedown(100,100) -> mousemove(130,120) must emit ONE 'pan' with dx=30, dy=20.
    func testDragEmitsPanWithDxDy() {
        let (view, controller) = makeController(true)
        var captured: RoamEventParams?
        var panCount = 0
        controller.on("pan") { p in captured = p; panCount += 1 }

        view._injectPointerForTest(type: "mousedown", zrX: 100, zrY: 100)
        view._injectPointerForTest(type: "mousemove", zrX: 130, zrY: 120)
        view._injectPointerForTest(type: "mouseup", zrX: 130, zrY: 120)

        XCTAssertNotNil(captured, "a drag must emit a 'pan' event")
        XCTAssertEqual(panCount, 1, "one mousemove during a drag emits exactly one 'pan'")
        XCTAssertEqual(captured?.dx ?? .nan, 30, accuracy: 1e-6, "dx = newX - oldX = 130 - 100")
        XCTAssertEqual(captured?.dy ?? .nan, 20, accuracy: 1e-6, "dy = newY - oldY = 120 - 100")
        XCTAssertEqual(captured?.oldX ?? .nan, 100, accuracy: 1e-6)
        XCTAssertEqual(captured?.newX ?? .nan, 130, accuracy: 1e-6)
        _ = controller // keep alive
    }

    // A mousemove WITHOUT a preceding mousedown (no drag) must NOT emit 'pan'.
    func testMoveWithoutDownDoesNotPan() {
        let (view, controller) = makeController(true)
        var panCount = 0
        controller.on("pan") { _ in panCount += 1 }
        view._injectPointerForTest(type: "mousemove", zrX: 130, zrY: 120)
        XCTAssertEqual(panCount, 0, "a hover move (no drag) must not emit 'pan'")
        _ = controller
    }

    // A mouse wheel over the controller area must emit 'zoom' with scale > 1 for a positive wheel delta.
    func testWheelEmitsZoom() {
        let (view, controller) = makeController(true)
        var captured: RoamEventParams?
        controller.on("zoom") { p in captured = p }

        view._injectWheelForTest(zrDelta: 3, zrX: 100, zrY: 100)

        XCTAssertNotNil(captured, "a wheel must emit a 'zoom' event")
        XCTAssertGreaterThan(captured?.scale ?? 0, 1.0, "a positive wheel delta zooms IN (scale > 1)")
        XCTAssertEqual(captured?.originX ?? .nan, 100, accuracy: 1e-6, "zoom origin = pointer x")
        XCTAssertEqual(captured?.originY ?? .nan, 100, accuracy: 1e-6, "zoom origin = pointer y")
        _ = controller
    }

    // A disabled controller must not emit anything.
    func testDisableStopsEvents() {
        let (view, controller) = makeController(true)
        controller.disable()
        var count = 0
        controller.on("pan") { _ in count += 1 }
        controller.on("zoom") { _ in count += 1 }
        view._injectPointerForTest(type: "mousedown", zrX: 100, zrY: 100)
        view._injectPointerForTest(type: "mousemove", zrX: 130, zrY: 120)
        view._injectWheelForTest(zrDelta: 3, zrX: 100, zrY: 100)
        XCTAssertEqual(count, 0, "a disabled controller emits nothing")
        _ = controller
    }
}
