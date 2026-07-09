// INTERACTION — SANKEY node dragging. Upstream lets you drag a node rect (el.draggable + el.drift) which
// dispatches the `dragNode` action; the handler persists the node's localX/localY on the series option
// (setNodePosition) and the full update() re-render moves the node and RE-ROUTES its incident edge ribbons.
//
// Two paths are exercised:
//   1. dispatch the `dragNode` action directly (the headless oracle) — asserts the node rect jumps to
//      localX*width / localY*height and the outgoing edge ribbon's start endpoint follows.
//   2. a LIVE pointer drag through the real Handler (mousedown/move/up over the node rect) — asserts the
//      node rect actually moves (el.drift → driftHandler → dragNode → re-render).
import XCTest
import ZRenderKit
@testable import EChartsKit

final class SankeyNodeDragTests: XCTestCase {

    private func makeSankeyView(draggable: Any? = nil) -> EChartsView {
        let view = EChartsView(width: 460, height: 360)
        var series: [String: Any] = [
            "type": "sankey", "left": "5%", "right": "20%", "top": "5%", "bottom": "5%",
            "nodeWidth": 20.0, "nodeGap": 8.0,
            "data": [["name": "a"], ["name": "b"], ["name": "c"], ["name": "d"]],
            "links": [["source": "a", "target": "b", "value": 5.0],
                      ["source": "a", "target": "c", "value": 3.0],
                      ["source": "b", "target": "d", "value": 4.0],
                      ["source": "c", "target": "d", "value": 2.0]]
        ]
        if let draggable = draggable { series["draggable"] = draggable }
        view.setOption(["series": [series]])
        _ = view.zr.storage.getDisplayList(true)
        return view
    }

    private func series(_ view: EChartsView) -> SankeySeriesModel? {
        return view.ec.getModel()?.getSeriesByIndex(0) as? SankeySeriesModel
    }

    // The node Rect for a data index (searches the live scene graph via ecData tag).
    private func nodeRect(_ view: EChartsView, _ dataIndex: Int) -> ZRenderKit.Rect? {
        var found: ZRenderKit.Rect?
        _ = view.ec.getRoot().traverse { el in
            if el.name == "node", let rect = el as? ZRenderKit.Rect {
                let ec = innerStore.getECData(rect)
                if ec.dataType == .node && Int(ec.dataIndex ?? -1) == dataIndex {
                    found = rect
                    return true
                }
            }
            return false
        }
        return found
    }

    private func firstRibbonShape(_ view: EChartsView) -> SankeyPathShape? {
        var shape: SankeyPathShape?
        _ = view.ec.getRoot().traverse { el in
            if shape == nil, let path = el as? SankeyPath, let s = path.shape as? SankeyPathShape {
                shape = s
                return true
            }
            return false
        }
        return shape
    }

    // ---- 1. Dispatch dragNode directly ------------------------------------------------------------
    func testDispatchDragNodeMovesNodeAndReroutesLinks() {
        let view = makeSankeyView()
        guard let sm = series(view), let layout = sm.layoutInfo else {
            return XCTFail("sankey must have layoutInfo after render")
        }
        let width = layout.width, height = layout.height

        guard let before = nodeRect(view, 0), let beforeShape = before.shape as? RectShape else {
            return XCTFail("node 0 rect must exist")
        }
        let beforeX = beforeShape.x, beforeY = beforeShape.y
        guard let beforeRibbon = firstRibbonShape(view) else {
            return XCTFail("edge ribbon must exist")
        }
        let beforeX1 = beforeRibbon.x1, beforeY1 = beforeRibbon.y1

        // Drag node 0 to a distinct fractional position.
        let localX = 0.5, localY = 0.6
        var p = Payload(type: "dragNode")
        p.other["seriesId"] = sm.id
        p.other["dataIndex"] = 0
        p.other["localX"] = localX
        p.other["localY"] = localY
        view.ec.dispatchAction(p)
        _ = view.zr.storage.getDisplayList(true)

        guard let after = nodeRect(view, 0), let afterShape = after.shape as? RectShape else {
            return XCTFail("node 0 rect must still exist after drag")
        }
        print("SANKEY-DRAG node0 x \(beforeX)->\(afterShape.x) (expect \(localX * width)); y \(beforeY)->\(afterShape.y) (expect \(localY * height))")
        XCTAssertEqual(afterShape.x, localX * width, accuracy: 0.5, "node x must jump to localX*width")
        XCTAssertEqual(afterShape.y, localY * height, accuracy: 0.5, "node y must jump to localY*height")
        XCTAssertNotEqual(afterShape.x, beforeX, accuracy: 1e-6, "node must actually move in x")

        // The outgoing edge ribbon must re-route: its start endpoint follows the dragged source node.
        guard let afterRibbon = firstRibbonShape(view) else {
            return XCTFail("edge ribbon must still exist after drag")
        }
        print("SANKEY-DRAG ribbon start (\(beforeX1),\(beforeY1)) -> (\(afterRibbon.x1),\(afterRibbon.y1))")
        let ribbonMoved = abs(afterRibbon.x1 - beforeX1) > 1 || abs(afterRibbon.y1 - beforeY1) > 1
        XCTAssertTrue(ribbonMoved, "the incident edge ribbon must re-route to the dragged node")
    }

    // ---- 2. Live pointer drag through the real Handler --------------------------------------------
    func testLivePointerDragMovesNode() {
        let view = makeSankeyView()   // draggable defaults to true.
        guard let before = nodeRect(view, 0), let beforeShape = before.shape as? RectShape else {
            return XCTFail("node 0 rect must exist")
        }
        // The node rect is draggable + carries a driftHandler.
        XCTAssertEqual(before.draggable, .true, "node rect must be draggable")
        XCTAssertNotNil(before.driftHandler, "node rect must carry a drift handler")

        // Aim the pointer at the node rect center (mainGroup is placed at layoutInfo.x/y, so add the group offset).
        guard let sm = series(view),
              let v = view.ec.api.getViewOfSeriesModel(sm) as? SankeyView else {
            return XCTFail("sankey view must exist")
        }
        let g = v._mainGroupForTest
        let cx = g.x + beforeShape.x + beforeShape.width / 2
        let cy = g.y + beforeShape.y + beforeShape.height / 2
        let dx = 25.0, dy = 35.0

        view._injectPointerForTest(type: "mousedown", zrX: cx, zrY: cy)
        view._injectPointerForTest(type: "mousemove", zrX: cx + dx, zrY: cy + dy)
        view._injectPointerForTest(type: "mouseup", zrX: cx + dx, zrY: cy + dy)
        _ = view.zr.storage.getDisplayList(true)

        guard let after = nodeRect(view, 0), let afterShape = after.shape as? RectShape else {
            return XCTFail("node 0 rect must still exist after live drag")
        }
        print("SANKEY-DRAG live node0 x \(beforeShape.x)->\(afterShape.x); y \(beforeShape.y)->\(afterShape.y)")
        let moved = abs(afterShape.x - beforeShape.x) > 1 || abs(afterShape.y - beforeShape.y) > 1
        XCTAssertTrue(moved, "a live pointer drag over the node must move it")
    }

    // ---- 3. draggable:false is inert --------------------------------------------------------------
    func testDraggableFalseLeavesNodeStatic() {
        let view = makeSankeyView(draggable: false)
        guard let rect = nodeRect(view, 0) else { return XCTFail("node 0 rect must exist") }
        XCTAssertEqual(rect.draggable, .false, "draggable:false node must not be draggable")
        XCTAssertNil(rect.driftHandler, "draggable:false node must have no drift handler")
    }
}
