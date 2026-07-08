// L3 Roam — TREEMAP pan/zoom end-to-end. Builds a treemap through EChartsView, injects a real drag /
// wheel through the live Handler, and asserts the treemap's CONTAINER GROUP actually SHIFTS (pan) and
// SCALES (zoom). Treemap is not on a coord system, so the roam is a transform on the container group
// (DEVIATION from upstream's rootRect re-layout — see roamHelperViewGroup.swift).
//
//     _injectPointerForTest("mousedown"/"mousemove"/"mouseup", ...)   (drag)
//       -> zr Handler -> RoamController uniform fan-out -> 'pan' -> updateTreemapRoamControllerSimply
//       -> ec.dispatchAction({type:'treemapRoam', dx, dy}) -> treemapRoam action accumulates the pan
//          -> full update() re-renders -> TreemapView re-applies the state to _containerGroup (shifted).
import XCTest
import ZRenderKit
@testable import EChartsKit

final class ZZTreemapRoamTests: XCTestCase {

    /// A small 2-level treemap. `roam` defaults to `true` for treemap; the inert test overrides it false.
    private func makeTreemapView(roam: Any? = nil) -> EChartsView {
        let view = EChartsView(width: 400, height: 400)
        var series: [String: Any] = [
            "type": "treemap", "left": "5%", "top": 20.0, "width": "90%", "height": 320.0,
            "data": [
                ["name": "nodeA", "value": 10.0, "children": [
                    ["name": "nodeA1", "value": 4.0],
                    ["name": "nodeA2", "value": 6.0]
                ]] as [String: Any],
                ["name": "nodeB", "value": 20.0, "children": [
                    ["name": "nodeB1", "value": 5.0],
                    ["name": "nodeB2", "value": 8.0]
                ]] as [String: Any]
            ]
        ]
        if let roam = roam { series["roam"] = roam }
        view.setOption(["series": [series]])
        _ = view.zr.storage.getDisplayList(true)
        return view
    }

    private func treemapSeries(_ view: EChartsView) -> TreemapSeriesModel? {
        return view.ec.getModel()?.getSeriesByIndex(0) as? TreemapSeriesModel
    }

    /// The treemap's live container group (carries the roam transform: position + scale).
    private func treemapGroup(_ view: EChartsView) -> Group? {
        guard let sm = treemapSeries(view),
              let v = view.ec.api.getViewOfSeriesModel(sm) as? TreemapView else { return nil }
        return v._containerGroupForTest
    }

    // A drag over the treemap must shift its container group by exactly the drag delta (pan).
    func testDragPansGroup() {
        let view = makeTreemapView()   // roam defaults true for treemap.
        guard let g = treemapGroup(view) else { return XCTFail("treemap container group must exist after render") }
        let beforeX = g.x, beforeY = g.y, beforeScale = g.scaleX

        let cx = 200.0, cy = 200.0
        let dx = 35.0, dy = -25.0
        view._injectPointerForTest(type: "mousedown", zrX: cx, zrY: cy)
        view._injectPointerForTest(type: "mousemove", zrX: cx + dx, zrY: cy + dy)
        view._injectPointerForTest(type: "mouseup", zrX: cx + dx, zrY: cy + dy)

        guard let after = treemapGroup(view) else { return XCTFail("treemap container group must still exist after pan") }
        print("TREEMAP-ROAM pan: group (\(beforeX),\(beforeY)) -> (\(after.x),\(after.y))")
        XCTAssertEqual(after.x - beforeX, dx, accuracy: 0.5, "group must shift by dx")
        XCTAssertEqual(after.y - beforeY, dy, accuracy: 0.5, "group must shift by dy")
        XCTAssertEqual(after.scaleX, beforeScale, accuracy: 1e-6, "a pure pan must not scale")
    }

    // A wheel over the treemap must scale its container group by the zoom factor (delta 3 → factor 1.2).
    func testWheelZoomsGroup() {
        let view = makeTreemapView()
        guard let g = treemapGroup(view) else { return XCTFail("treemap container group must exist after render") }
        let beforeScale = g.scaleX
        XCTAssertEqual(beforeScale, 1, accuracy: 1e-6, "the untouched treemap group must be unscaled")

        view._injectWheelForTest(zrDelta: 3, zrX: 200, zrY: 200)

        guard let after = treemapGroup(view) else { return XCTFail("treemap container group must still exist after zoom") }
        print("TREEMAP-ROAM zoom: scale \(beforeScale) -> \(after.scaleX)")
        XCTAssertEqual(after.scaleX, 1.2, accuracy: 0.02, "wheel-in scales the group by ~1.2x")
        XCTAssertEqual(after.scaleY, 1.2, accuracy: 0.02, "scaleY must match scaleX (uniform zoom)")
    }

    // A treemap with `roam:false` must be inert to a drag (group does not move).
    func testNoRoamOptionIsInert() {
        let view = makeTreemapView(roam: false)
        guard let g = treemapGroup(view) else { return XCTFail("treemap container group must exist after render") }
        let beforeX = g.x, beforeY = g.y
        view._injectPointerForTest(type: "mousedown", zrX: 200, zrY: 200)
        view._injectPointerForTest(type: "mousemove", zrX: 260, zrY: 240)
        view._injectPointerForTest(type: "mouseup", zrX: 260, zrY: 240)
        guard let after = treemapGroup(view) else { return XCTFail("treemap container group must still exist") }
        XCTAssertEqual(after.x, beforeX, accuracy: 1e-6, "roam:false treemap must not pan (x)")
        XCTAssertEqual(after.y, beforeY, accuracy: 1e-6, "roam:false treemap must not pan (y)")
    }
}
