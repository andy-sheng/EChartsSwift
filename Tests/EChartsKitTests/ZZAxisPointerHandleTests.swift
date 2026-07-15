// The axisPointer draggable HANDLE, proven HEADLESSLY through the REAL pointer → Handler/Draggable →
// updateAxisPointer → axisTrigger chain.
//
// Upstream `axisPointer: { handle: { show: true } }` renders a draggable touch handle
// (BaseAxisPointer._renderHandle → graphic.createIcon) hosted on the live zr. Dragging it drives
// `_onHandleDragMove` (via the assigned `drift`) → `updateHandleTransform` (CartesianAxisPointer) →
// the throttled `_doDispatchAxisPointer` → `api.dispatchAction({type:'updateAxisPointer', x, y, ...})`
// → the registered `axisTrigger` action → `updateModelActually` writes the new value onto the
// per-axis axisPointer model.
//
// These tests do NOT call `_renderHandle` / `_onHandleDragMove` directly. The handle is created by the
// real render, and the drag is injected as a synthetic mousedown → mousemove → mouseup SEQUENCE that
// must travel:
//
//     EChartsView._injectPointerForTest("mousedown"/"mousemove"/"mouseup", x, y)
//       -> zr.handler.<name>(ZRRawEvent)                     (ZRenderKit Handler)
//       -> Handler.findHover hits the handle SVGPath
//       -> Handler.trigger(name) -> Draggable._dragStart/_drag/_dragEnd
//       -> draggingTarget.drift(dx, dy) -> BaseAxisPointer._onHandleDragMove
//       -> updateHandleTransform + api.dispatchAction('updateAxisPointer')
//       -> axisTrigger -> updateModelActually writes axisPointerModel.value
import XCTest
import ZRenderKit
@testable import EChartsKit

final class ZZAxisPointerHandleTests: XCTestCase {

    override func setUp() {
        super.setUp()
        ComponentModel.registerClass(BarSeriesModel.self)
        ComponentModel.registerClass(TooltipModel.self)
        ComponentModel.registerClass(AxisPointerModel.self)
    }

    // A category x-axis with an always-on axisPointer + draggable handle, parked at category "A".
    //   `throttle` defaults to the mobile-perf 40ms (test 1 uses that). Test 2 passes `throttle: 0` so
    //   the drag dispatch runs SYNCHRONOUSLY: the throttle's fixRate `diff = currCall - lastExec - delay`
    //   is >= 0 for delay 0 (time advances monotonically), so every call `exec`s immediately instead of
    //   being deferred onto the run loop (which a synchronous headless test would never drain).
    private func makeHandleView(throttle: Double? = nil) -> EChartsView {
        let view = EChartsView(width: 400, height: 320)
        var handle: [String: Any] = ["show": true, "color": "#7581BD"]
        if let throttle = throttle { handle["throttle"] = throttle }
        view.setOption([
            "tooltip": ["trigger": "axis"] as [String: Any],
            "grid": ["left": 50.0, "top": 20.0, "width": 300.0, "height": 200.0] as [String: Any],
            "xAxis": [
                "type": "category",
                "data": ["A", "B", "C"],
                "axisPointer": [
                    "show": true,
                    "value": "A",
                    "snap": true,
                    "handle": handle
                ] as [String: Any]
            ] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [["type": "bar", "data": [10.0, 20.0, 30.0]] as [String: Any]]
        ])
        // Flatten the display list so `findHover` can hit-test the handle.
        _ = view.zr.storage.getDisplayList(true)
        return view
    }

    // The draggable handle is the only SVGPath on the zr (crosshair is a Line, label is ZRText).
    private func handleIcon(in view: EChartsView) -> SVGPath? {
        for el in view.zr.storage.getDisplayList(true) {
            if let p = el as? SVGPath, p.draggable == .true, !p.ignore { return p }
        }
        return nil
    }

    // The x-axis axisInfo's per-axis axisPointerModel (where updateModelActually writes value/status).
    private func xAxisPointerModel(in view: EChartsView) -> Model? {
        guard let apModel = view.ec.getModel()?.getComponent("axisPointer") as? AxisPointerModel,
              let result = apModel.coordSysAxesInfo as? CollectionResult else { return nil }
        for (_, info) in result.axesInfo where (info.axis.dim as String?) == "x" {
            return info.axisPointerModel
        }
        return nil
    }

    private func axisValueAsDouble(_ v: Any?) -> Double? {
        if let d = v as? Double { return d }
        if let i = v as? Int { return Double(i) }
        return nil
    }

    // ---- (1) handle.show:true actually CREATES a draggable, interactive handle on the zr. ----
    func testHandleIsCreatedWhenHandleShow() {
        let view = makeHandleView()

        guard let handle = handleIcon(in: view) else {
            XCTFail("axisPointer.handle.show:true must create a draggable handle icon on the zr"); return
        }
        XCTAssertEqual(handle.draggable, .true, "the handle must be draggable")
        XCTAssertGreaterThan(handle.scaleX, 0, "the handle must be scaled to its `size`")
        XCTAssertGreaterThan(handle.scaleY, 0, "the handle must be scaled to its `size`")
        XCTAssertFalse(handle.silent, "the handle must be interactive (not silent) so it can be dragged")
        // It must sit below the bottom x-axis (grid bottom 220 + handle margin 50 ≈ 270).
        XCTAssertGreaterThan(handle.y, 220.0, "the handle floats below the bottom axis by `handle.margin`")
    }

    // ---- (2) DRAGGING the handle moves the axisPointer to the corresponding axis value. ----
    func testDraggingHandleMovesAxisPointerValue() {
        let view = makeHandleView(throttle: 0)

        guard let handle = handleIcon(in: view) else {
            XCTFail("the handle must exist before it can be dragged"); return
        }
        guard let apModel = xAxisPointerModel(in: view) else {
            XCTFail("the x-axis must have a per-axis axisPointerModel"); return
        }

        // Parked at category "A" (index 0 after fixValue parse).
        let v0 = axisValueAsDouble(apModel.get("value"))
        XCTAssertEqual(v0 ?? -1, 0.0, accuracy: 0.001, "handle should be parked at category A (index 0)")

        // Capture the dispatched updateAxisPointer actions (upstream action `event:'updateAxisPointer'`).
        var updates = 0
        view.on("updateAxisPointer") { _ in updates += 1 }

        let hx = handle.x
        let hy = handle.y
        // Drag one full category band (grid width 300 / 3 = 100px) to the right: A(≈100) -> B(≈200).
        let targetX = hx + 100.0
        view._injectPointerForTest(type: "mousedown", zrX: hx, zrY: hy)
        view._injectPointerForTest(type: "mousemove", zrX: targetX, zrY: hy)
        view._injectPointerForTest(type: "mouseup",   zrX: targetX, zrY: hy)

        // (a) the drag dispatched at least one updateAxisPointer action.
        XCTAssertGreaterThanOrEqual(updates, 1,
            "dragging the handle must dispatch at least one updateAxisPointer action")

        // (b) the handle element repositioned itself to the drag point (it moves on `drift`).
        XCTAssertGreaterThan(handle.x, hx + 50.0,
            "the handle must move toward the drag position (from \(hx) to ~\(targetX))")

        // (c) the axisPointer VALUE snapped to the newly-pointed category B (index 1).
        let v1 = axisValueAsDouble(apModel.get("value"))
        XCTAssertNotNil(v1, "the axisPointer must carry a numeric value after the drag")
        XCTAssertEqual(v1 ?? -1, 1.0, accuracy: 0.001,
            "dragging one band right must move the axisPointer value from A(0) to B(1); got \(String(describing: v1))")
    }

    // ---- (3) handle.show:false (the default) creates NO handle. ----
    func testNoHandleWhenShowFalse() {
        let view = EChartsView(width: 400, height: 320)
        view.setOption([
            "tooltip": ["trigger": "axis"] as [String: Any],
            "grid": ["left": 50.0, "top": 20.0, "width": 300.0, "height": 200.0] as [String: Any],
            "xAxis": ["type": "category", "data": ["A", "B", "C"]] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [["type": "bar", "data": [10.0, 20.0, 30.0]] as [String: Any]]
        ])
        _ = view.zr.storage.getDisplayList(true)
        XCTAssertNil(handleIcon(in: view),
            "without axisPointer.handle.show, no draggable handle should be created")
    }
}
