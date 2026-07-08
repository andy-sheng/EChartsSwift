// L3 Roam — GRAPH pan/zoom end-to-end. Builds a `roam:true` graph through EChartsView, injects a real
// drag / wheel through the live Handler, and asserts the graph node graphic elements actually SHIFT (pan)
// and SCALE (zoom).
//
//     _injectPointerForTest("mousedown"/"mousemove"/"mouseup", ...)   (drag)
//       -> zr Handler -> RoamController uniform fan-out -> 'pan' -> updateGraphRoamControllerSimply
//       -> ec.dispatchAction({type:'graphRoam', dx, dy}) -> graphRoam action applies pan to the graph
//          view coord sys -> full update() re-renders -> node graphic els shifted by (dx, dy)
import XCTest
import ZRenderKit
@testable import EChartsKit

final class ZZGraphRoamTests: XCTestCase {

    override func setUp() {
        super.setUp()
        ComponentModel.registerClass(GraphSeriesModel.self)
    }

    /// A 2-node `layout:'none'` graph with `roam:true`. Nodes at data (10,10) and (90,90); one link.
    private func makeGraphView() -> EChartsView {
        let view = EChartsView(width: 400, height: 300)
        view.setOption([
            "series": [[
                "type": "graph",
                "layout": "none",
                "roam": true,
                "data": [
                    ["name": "a", "x": 10.0, "y": 10.0] as [String: Any],
                    ["name": "b", "x": 90.0, "y": 90.0] as [String: Any]
                ],
                "links": [["source": "a", "target": "b"] as [String: Any]]
            ] as [String: Any]]
        ])
        _ = view.zr.storage.getDisplayList(true)
        return view
    }

    private func graphSeries(_ view: EChartsView) -> GraphSeriesModel? {
        return view.ec.getModel()?.getSeriesByIndex(0) as? GraphSeriesModel
    }

    private func nodePos(_ view: EChartsView, _ i: Int) -> (x: Double, y: Double)? {
        guard let sm = graphSeries(view), let el = sm.getData().getItemGraphicEl(i) else { return nil }
        return (el.x, el.y)
    }

    /// The center of the graph's view rect — a point guaranteed inside the roam pointer-check area.
    private func viewCenter(_ view: EChartsView) -> (x: Double, y: Double) {
        guard let sm = graphSeries(view),
              let vc = sm.coordinateSystem as? GraphViewCoordSys,
              let r = vc.getViewRect() else { return (200, 150) }
        return (r.x + r.width / 2, r.y + r.height / 2)
    }

    // A drag over the graph must shift EVERY node graphic element by the drag delta (pan).
    func testDragPansNodes() {
        let view = makeGraphView()
        guard let before0 = nodePos(view, 0), let before1 = nodePos(view, 1) else {
            return XCTFail("nodes must have graphic elements after render")
        }
        let c = viewCenter(view)
        let dx = 40.0, dy = 30.0
        view._injectPointerForTest(type: "mousedown", zrX: c.x, zrY: c.y)
        view._injectPointerForTest(type: "mousemove", zrX: c.x + dx, zrY: c.y + dy)
        view._injectPointerForTest(type: "mouseup", zrX: c.x + dx, zrY: c.y + dy)

        guard let after0 = nodePos(view, 0), let after1 = nodePos(view, 1) else {
            return XCTFail("nodes must still exist after the pan re-render")
        }
        print("GRAPH-ROAM pan: node0 (\(before0.x),\(before0.y)) -> (\(after0.x),\(after0.y))")
        XCTAssertEqual(after0.x - before0.x, dx, accuracy: 0.5, "node0 must shift right by dx")
        XCTAssertEqual(after0.y - before0.y, dy, accuracy: 0.5, "node0 must shift down by dy")
        XCTAssertEqual(after1.x - before1.x, dx, accuracy: 0.5, "node1 must shift right by dx")
        XCTAssertEqual(after1.y - before1.y, dy, accuracy: 0.5, "node1 must shift down by dy")
    }

    // A wheel over the graph must SCALE the layout: the distance between the two nodes grows by the zoom
    // factor (a positive wheel delta zooms in; factor 1.2 for |delta| in (1,3]).
    func testWheelZoomsNodes() {
        let view = makeGraphView()
        guard let before0 = nodePos(view, 0), let before1 = nodePos(view, 1) else {
            return XCTFail("nodes must have graphic elements after render")
        }
        let beforeDist = hypot(before1.x - before0.x, before1.y - before0.y)
        XCTAssertGreaterThan(beforeDist, 1, "the two nodes must be laid out apart")

        let c = viewCenter(view)
        view._injectWheelForTest(zrDelta: 3, zrX: c.x, zrY: c.y)

        guard let after0 = nodePos(view, 0), let after1 = nodePos(view, 1) else {
            return XCTFail("nodes must still exist after the zoom re-render")
        }
        let afterDist = hypot(after1.x - after0.x, after1.y - after0.y)
        print("GRAPH-ROAM zoom: dist \(beforeDist) -> \(afterDist) (ratio \(afterDist / beforeDist))")
        XCTAssertEqual(afterDist / beforeDist, 1.2, accuracy: 0.05, "wheel-in scales the layout by ~1.2x")
    }

    // A graph WITHOUT roam must be inert to a drag (nodes do not move).
    func testNoRoamOptionIsInert() {
        let view = EChartsView(width: 400, height: 300)
        view.setOption([
            "series": [[
                "type": "graph", "layout": "none",
                "data": [
                    ["name": "a", "x": 10.0, "y": 10.0] as [String: Any],
                    ["name": "b", "x": 90.0, "y": 90.0] as [String: Any]
                ]
            ] as [String: Any]]
        ])
        _ = view.zr.storage.getDisplayList(true)
        guard let before = nodePos(view, 0) else { return XCTFail("node must render") }
        let c = viewCenter(view)
        view._injectPointerForTest(type: "mousedown", zrX: c.x, zrY: c.y)
        view._injectPointerForTest(type: "mousemove", zrX: c.x + 50, zrY: c.y + 50)
        view._injectPointerForTest(type: "mouseup", zrX: c.x + 50, zrY: c.y + 50)
        guard let after = nodePos(view, 0) else { return XCTFail("node must still render") }
        XCTAssertEqual(after.x, before.x, accuracy: 1e-6, "roam:off graph must not pan")
        XCTAssertEqual(after.y, before.y, accuracy: 1e-6, "roam:off graph must not pan")
    }
}
