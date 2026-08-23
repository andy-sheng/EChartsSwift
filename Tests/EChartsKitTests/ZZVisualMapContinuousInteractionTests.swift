// Regression test — the interactive handles of the CONTINUOUS visualMap (ContinuousView).
//
// Proves, HEADLESSLY through the REAL pointer stack (like ZZInsidePanTests / ZZSliderZoomTests):
//   (1) a `calculable` continuous visualMap renders its two draggable handle thumbs at the selected-range
//       ends, and
//   (2) DRAGGING a handle changes the model's selected range. The drag is injected through the live zr
//       Handler (mousedown → mousemove → mouseup); the Handler's Draggable mixin finds the draggable
//       handle thumb under the pointer, calls its `drift` (→ ContinuousView._dragHandle), which updates
//       the interval and dispatches `selectDataRange` → the ported action handler mutates the model.
//
// It does NOT call dispatchAction('selectDataRange') directly — the new range MUST be produced by the
// injected drag travelling through the live Handler + the element `draggable`/`drift` wiring.
import XCTest
import ZRenderKit
@testable import EChartsKit

final class ZZVisualMapContinuousInteractionTests: XCTestCase {

    override func setUp() {
        super.setUp()
        ComponentModel.registerClass(ScatterSeriesModel.self)
    }

    /// A cartesian scatter colored by a continuous, calculable visualMap over [0,100] with a SUB-window
    /// range [20,80] (room to move either handle). The visualMap sits at a known top-left corner.
    private func makeView() -> EChartsView {
        let view = EChartsView(width: 480, height: 360)
        view.setOption([
            "grid": ["left": 120.0, "top": 20.0, "width": 300.0, "height": 260.0] as [String: Any],
            "xAxis": ["type": "value"] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "visualMap": [
                "type": "continuous",
                "min": 0.0, "max": 100.0,
                "range": [20.0, 80.0],
                "calculable": true,
                "left": 10.0, "top": 40.0,
                "dimension": 1.0,
                "inRange": ["color": ["#50a3ba", "#eac736", "#d94e5d"]] as [String: Any]
            ] as [String: Any],
            "series": [["type": "scatter", "symbolSize": 14.0,
                        "data": [[10.0, 5.0], [30.0, 40.0], [50.0, 70.0], [70.0, 95.0]]] as [String: Any]]
        ])
        // Flatten the display list so the Handler can hit-test + the element transforms are current.
        _ = view.zr.storage.getDisplayList(true)
        return view
    }

    private func continuousView(_ view: EChartsView) -> ContinuousView? {
        for cv in view.ec._componentsViews {
            if let c = cv as? ContinuousView { return c }
        }
        return nil
    }

    private func model(_ view: EChartsView) -> ContinuousModel? {
        return view.ec.getModel()?.getComponent("visualMap", 0) as? ContinuousModel
    }

    // ---- (1) the two handle thumbs render at the range ends ----
    func testHandlesRenderForCalculableVisualMap() {
        let view = makeView()
        guard let cv = continuousView(view) else {
            XCTFail("a calculable continuous visualMap must produce a ContinuousView"); return
        }
        XCTAssertNotNil(cv._handleThumbForTest(0), "the low-value handle thumb must be rendered")
        XCTAssertNotNil(cv._handleThumbForTest(1), "the high-value handle thumb must be rendered")

        let selected = (model(view)?.getSelected() as? [Double]) ?? []
        XCTAssertEqual(selected.count, 2)
        XCTAssertEqual(selected[0], 20, accuracy: 1e-6, "initial selected low must be 20")
        XCTAssertEqual(selected[1], 80, accuracy: 1e-6, "initial selected high must be 80")
    }

    // ---- (2) dragging a handle changes the selected range (through the live Handler / Draggable) ----
    func testDraggingHandleChangesSelectedRange() {
        let view = makeView()
        guard let cv = continuousView(view), let handle = cv._handleThumbForTest(1) else {
            XCTFail("no ContinuousView / handle"); return
        }

        let before = (model(view)?.getSelected() as? [Double]) ?? []
        XCTAssertEqual(before[1], 80, accuracy: 1e-6)

        // The handle thumb's GLOBAL pixel centre (its local origin (0,0) run through the full transform
        // chain — the bar group's orient/scale transform + the positioned visualMap group).
        let center = handle.transformCoordToGlobal(0, 0)
        let cx = center[0]
        let cy = center[1]

        // Inject a drag of the high handle. A vertical bar maps a y-drag to a range change; drag far
        // enough (60px) that the clamped interval definitely moves off 80.
        view._injectPointerForTest(type: "mousedown", zrX: cx, zrY: cy)
        view._injectPointerForTest(type: "mousemove", zrX: cx, zrY: cy + 60)
        view._injectPointerForTest(type: "mouseup", zrX: cx, zrY: cy + 60)

        let after = (model(view)?.getSelected() as? [Double]) ?? []
        print("VISUALMAP handle drag: \(before) -> \(after)")
        XCTAssertEqual(after.count, 2, "the model must still hold a 2-element range")
        XCTAssertTrue(
            abs(after[0] - before[0]) > 1e-6 || abs(after[1] - before[1]) > 1e-6,
            "dragging a handle must change the selected range — got \(before) -> \(after)"
        )
        // The range stays clamped within the data extent [0,100].
        XCTAssertGreaterThanOrEqual(after[0], 0)
        XCTAssertLessThanOrEqual(after[1], 100)
    }

    func testExternalVisualHarnessTargetsOwnedHandle() {
        let view = makeView()
        let before = (model(view)?.getSelected() as? [Double]) ?? []

        let point = view._injectVisualMapHandleDragForTest(
            componentIndex: 0, handleIndex: 1, deltaX: 0, deltaY: 60
        )

        XCTAssertNotNil(point)
        let after = (model(view)?.getSelected() as? [Double]) ?? []
        XCTAssertNotEqual(after, before)
    }

    func testNullEndTextRendersAsEmptyString() {
        let view = EChartsView(width: 480, height: 360)
        view.setOption([
            "xAxis": ["type": "value"] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "visualMap": [
                "type": "continuous", "min": 0.0, "max": 100.0,
                "text": [NSNull(), "FG:   "] as [Any],
                "dimension": 1.0,
                "inRange": ["color": ["green", "yellow"]] as [String: Any]
            ] as [String: Any],
            "series": [["type": "scatter", "data": [[0.0, 50.0]]] as [String: Any]]
        ])

        guard let cv = continuousView(view) else {
            return XCTFail("continuous visualMap view must render")
        }
        var texts: [String] = []
        _ = cv.group.traverse { el in
            if let text = (el as? ZRText)?.textStyle?.text { texts.append(text) }
            return false
        }
        XCTAssertFalse(texts.contains("<null>"), "JSON null end text must stay visually empty")
        XCTAssertTrue(texts.contains("FG:   "))
    }
}
