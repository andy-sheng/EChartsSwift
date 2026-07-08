// L3 Roam — TREE pan/zoom end-to-end. Builds a `roam:true` tree through EChartsView, injects a real
// drag / wheel through the live Handler, and asserts the tree's VIEW GROUP actually SHIFTS (pan) and
// SCALES (zoom). Tree is not on a coord system, so the roam is a transform on the main group (unlike
// graph, whose nodes re-lay-out) — see roamHelperViewGroup.swift.
//
//     _injectPointerForTest("mousedown"/"mousemove"/"mouseup", ...)   (drag)
//       -> zr Handler -> RoamController uniform fan-out -> 'pan' -> updateTreeRoamControllerSimply
//       -> ec.dispatchAction({type:'treeRoam', dx, dy}) -> treeRoam action accumulates the pan
//          -> full update() re-renders -> TreeView re-applies the roam state to _mainGroup (shifted by dx,dy)
import XCTest
import ZRenderKit
@testable import EChartsKit

final class ZZTreeRoamTests: XCTestCase {

    /// A small `roam:true` orthogonal tree (root → A,B → leaves), rendered through EChartsView.
    private func makeTreeView(roam: Any? = true) -> EChartsView {
        let view = EChartsView(width: 400, height: 300)
        var series: [String: Any] = [
            "type": "tree", "left": "10%", "right": "10%", "top": "10%", "bottom": "10%",
            "symbolSize": 8.0, "orient": "LR",
            "data": [
                ["name": "root", "children": [
                    ["name": "A", "children": [["name": "A1"], ["name": "A2"]]] as [String: Any],
                    ["name": "B", "children": [["name": "B1"], ["name": "B2"]]] as [String: Any]
                ]] as [String: Any]
            ]
        ]
        if let roam = roam { series["roam"] = roam }
        view.setOption(["series": [series]])
        _ = view.zr.storage.getDisplayList(true)
        return view
    }

    private func treeSeries(_ view: EChartsView) -> TreeSeriesModel? {
        return view.ec.getModel()?.getSeriesByIndex(0) as? TreeSeriesModel
    }

    /// The tree's live view group (carries the roam transform: position + scale).
    private func treeGroup(_ view: EChartsView) -> Group? {
        guard let sm = treeSeries(view),
              let v = view.ec.api.getViewOfSeriesModel(sm) as? TreeView else { return nil }
        return v._mainGroupForTest
    }

    // A drag over the tree must shift its view group by exactly the drag delta (pan).
    func testDragPansGroup() {
        let view = makeTreeView()
        guard let g = treeGroup(view) else { return XCTFail("tree view group must exist after render") }
        let beforeX = g.x, beforeY = g.y, beforeScale = g.scaleX

        let cx = 200.0, cy = 150.0
        let dx = 40.0, dy = 30.0
        view._injectPointerForTest(type: "mousedown", zrX: cx, zrY: cy)
        view._injectPointerForTest(type: "mousemove", zrX: cx + dx, zrY: cy + dy)
        view._injectPointerForTest(type: "mouseup", zrX: cx + dx, zrY: cy + dy)

        guard let after = treeGroup(view) else { return XCTFail("tree view group must still exist after pan") }
        print("TREE-ROAM pan: group (\(beforeX),\(beforeY)) -> (\(after.x),\(after.y))")
        XCTAssertEqual(after.x - beforeX, dx, accuracy: 0.5, "group must shift right by dx")
        XCTAssertEqual(after.y - beforeY, dy, accuracy: 0.5, "group must shift down by dy")
        XCTAssertEqual(after.scaleX, beforeScale, accuracy: 1e-6, "a pure pan must not scale")
    }

    // A wheel over the tree must scale its view group by the zoom factor (delta 3 → factor 1.2).
    func testWheelZoomsGroup() {
        let view = makeTreeView()
        guard let g = treeGroup(view) else { return XCTFail("tree view group must exist after render") }
        let beforeScale = g.scaleX
        XCTAssertEqual(beforeScale, 1, accuracy: 1e-6, "the untouched tree group must be unscaled")

        view._injectWheelForTest(zrDelta: 3, zrX: 200, zrY: 150)

        guard let after = treeGroup(view) else { return XCTFail("tree view group must still exist after zoom") }
        print("TREE-ROAM zoom: scale \(beforeScale) -> \(after.scaleX)")
        XCTAssertEqual(after.scaleX, 1.2, accuracy: 0.02, "wheel-in scales the group by ~1.2x")
        XCTAssertEqual(after.scaleY, 1.2, accuracy: 0.02, "scaleY must match scaleX (uniform zoom)")
    }

    // A tree WITHOUT roam (default `roam:false`) must be inert to a drag (group does not move).
    func testNoRoamOptionIsInert() {
        let view = makeTreeView(roam: nil)
        guard let g = treeGroup(view) else { return XCTFail("tree view group must exist after render") }
        let beforeX = g.x, beforeY = g.y
        view._injectPointerForTest(type: "mousedown", zrX: 200, zrY: 150)
        view._injectPointerForTest(type: "mousemove", zrX: 250, zrY: 200)
        view._injectPointerForTest(type: "mouseup", zrX: 250, zrY: 200)
        guard let after = treeGroup(view) else { return XCTFail("tree view group must still exist") }
        XCTAssertEqual(after.x, beforeX, accuracy: 1e-6, "roam:off tree must not pan (x)")
        XCTAssertEqual(after.y, beforeY, accuracy: 1e-6, "roam:off tree must not pan (y)")
    }
}
