// Phase 34+ regression test — LIVE hover→emphasis breadth across the NODE-structured charts
// GRAPH, TREE, and SANKEY.
//
// Modeled on ZZHoverBreadthTests / ZZHoverBreadth2Tests (scatter/pie/line, candlestick/…): each test
// builds an EChartsView, grabs a per-NODE element from the series data (`data.getItemGraphicEl(idx)`),
// injects a synthetic POINTER over its bounding-rect center (mapped to GLOBAL coords via
// `transformCoordToGlobal`, since graph/tree/sankey node elements sit under a translated series group)
// through `_injectPointerForTest`, and asserts the node enters the "emphasis" state through the REAL
// Handler hit-test + the EChartsView "mouseover" listener → states.enterEmphasisWhenMouseOver. A second
// mousemove off the node proves the "mouseout" leg clears emphasis.
//
// This proves GraphView / TreeView / SankeyView now mark each per-node graphic element a highDown
// dispatcher (mirroring ScatterView / SankeyView.ts's own emphasis call sites), so hover-to-highlight
// works for node/edge structures, not only cartesian/pie series.
import XCTest
import ZRenderKit
@testable import EChartsKit

final class ZZHoverBreadth3Tests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Series model classes are auto-registered by EChartsSlim; re-registering is idempotent/harmless.
        ComponentModel.registerClass(GraphSeriesModel.self)
        ComponentModel.registerClass(TreeSeriesModel.self)
        ComponentModel.registerClass(SankeySeriesModel.self)
    }

    // Node elements sit under a series group that is translated to the layout origin (graph: origin;
    // tree/sankey: layoutInfo.x/y). The element's world `transform` (composed after getDisplayList(true))
    // maps its local bounding-rect center to the GLOBAL pixel the Handler hit-tests against.
    private func globalCenter(_ el: Element) -> (Double, Double)? {
        guard let r = el.getBoundingRect() else { return nil }
        let lx = r.x + r.width / 2
        let ly = r.y + r.height / 2
        let g = el.transformCoordToGlobal(lx, ly)
        return (g[0], g[1])
    }

    // MARK: - Graph (node symbols; layout 'none')

    func testGraphNodeHoverEntersEmphasis() {
        let view = EChartsView(width: 400, height: 300)
        // layout 'none' → each node's [x, y] comes straight from its data item. n3 is ISOLATED (no link),
        // so its center is not shared with any edge endpoint (edges run node-center to node-center since
        // adjustEdge is DEFERRED) → the hit-test resolves the node symbol cleanly.
        view.setOption([
            "series": [["type": "graph", "layout": "none", "symbolSize": 30.0,
                        "data": [
                            ["name": "n0", "x": 100.0, "y": 100.0] as [String: Any],
                            ["name": "n1", "x": 200.0, "y": 100.0] as [String: Any],
                            ["name": "n2", "x": 150.0, "y": 200.0] as [String: Any],
                            ["name": "n3", "x": 320.0, "y": 240.0] as [String: Any]
                        ],
                        "links": [
                            ["source": "n0", "target": "n1"] as [String: Any],
                            ["source": "n1", "target": "n2"] as [String: Any]
                        ]] as [String: Any]]
        ])

        let series = view.ec.getModel()!.getSeriesByIndex(0)!
        let data = series.getData()
        guard let el = data.getItemGraphicEl(3) else {
            XCTFail("graph render must populate a node symbol for data index 3"); return
        }
        XCTAssertTrue(states.isHighDownDispatcher(el),
                      "GraphView must mark each node symbol a highDown dispatcher")
        XCTAssertTrue(el.currentStates.isEmpty, "graph node 3 must not be in emphasis before any hover")

        _ = view.zr.storage.getDisplayList(true)
        guard let (cx, cy) = globalCenter(el) else { XCTFail("no bounding rect"); return }

        view._injectPointerForTest(type: "mousemove", zrX: cx, zrY: cy)
        XCTAssertTrue(el.currentStates.contains("emphasis"),
                      "an injected pointer over graph node 3 must drive it into emphasis")

        view._injectPointerForTest(type: "mousemove", zrX: 1, zrY: 1)
        XCTAssertTrue(el.currentStates.isEmpty,
                      "moving off graph node 3 must clear its emphasis via the mouseout leg")
    }

    // MARK: - Tree (node symbols)

    func testTreeNodeHoverEntersEmphasis() {
        let view = EChartsView(width: 500, height: 360)
        view.setOption([
            "series": [["type": "tree", "left": 40.0, "top": 20.0, "right": 40.0, "bottom": 20.0,
                        "symbol": "circle", "symbolSize": 18.0,
                        "data": [
                            ["name": "root", "children": [
                                ["name": "c1", "children": [
                                    ["name": "g1"] as [String: Any],
                                    ["name": "g2"] as [String: Any]
                                ]] as [String: Any],
                                ["name": "c2"] as [String: Any]
                            ]] as [String: Any]
                        ]] as [String: Any]]
        ])

        let series = view.ec.getModel()!.getSeriesByIndex(0)!
        let data = series.getData()
        // Data index 0 is the VIRTUAL root (no layout, no symbol); real nodes start at index 1. Index 3
        // is a LEAF ('g1') — a leaf has exactly one incident curve, approaching from its parent (left),
        // so its right half is curve-free (see hover offset below).
        let leafIdx = 3
        guard let el = data.getItemGraphicEl(leafIdx) else {
            XCTFail("tree render must populate a node symbol for leaf data index \(leafIdx)"); return
        }
        XCTAssertTrue(states.isHighDownDispatcher(el),
                      "TreeView must mark each node symbol a highDown dispatcher")
        XCTAssertTrue(el.currentStates.isEmpty, "tree leaf node must not be in emphasis before any hover")

        _ = view.zr.storage.getDisplayList(true)
        guard let (cx, cy) = globalCenter(el) else { XCTFail("no bounding rect"); return }

        // Leaf/interior nodes share their center with a parent→child curve endpoint (curves run
        // center-to-center; adjustEdge/trim DEFERRED). In the default 'LR' orient the curve approaches a
        // node from the LEFT, so a point just RIGHT of center is inside the symbol but off the curve —
        // the hit-test then resolves the node symbol rather than the thin curve drawn atop it.
        guard let r = el.getBoundingRect() else { XCTFail("no bounding rect"); return }
        let offX = cx + r.width * 0.30

        view._injectPointerForTest(type: "mousemove", zrX: offX, zrY: cy)
        XCTAssertTrue(el.currentStates.contains("emphasis"),
                      "an injected pointer over the tree leaf node must drive it into emphasis")

        view._injectPointerForTest(type: "mousemove", zrX: 1, zrY: 1)
        XCTAssertTrue(el.currentStates.isEmpty,
                      "moving off the tree leaf node must clear its emphasis via the mouseout leg")
    }

    // MARK: - Sankey (node rects)

    func testSankeyNodeHoverEntersEmphasis() {
        let view = EChartsView(width: 460, height: 360)
        view.setOption([
            "series": [["type": "sankey",
                        "left": "5%", "right": "20%", "top": "5%", "bottom": "5%",
                        "nodeWidth": 20.0, "nodeGap": 8.0,
                        "data": [["name": "a"] as [String: Any], ["name": "b"] as [String: Any],
                                 ["name": "c"] as [String: Any], ["name": "d"] as [String: Any]],
                        "links": [["source": "a", "target": "b", "value": 5.0] as [String: Any],
                                  ["source": "a", "target": "c", "value": 3.0] as [String: Any],
                                  ["source": "b", "target": "d", "value": 4.0] as [String: Any],
                                  ["source": "c", "target": "d", "value": 2.0] as [String: Any]]] as [String: Any]]
        ])

        let series = view.ec.getModel()!.getSeriesByIndex(0)!
        let data = series.getData()
        guard let el = data.getItemGraphicEl(0), el is ZRenderKit.Rect else {
            XCTFail("sankey render must populate a node Rect for data index 0"); return
        }
        XCTAssertTrue(states.isHighDownDispatcher(el),
                      "SankeyView must mark each node rect a highDown dispatcher")
        XCTAssertTrue(el.currentStates.isEmpty, "sankey node 0 must not be in emphasis before any hover")

        // Node rects carry z2:10 (above the edge ribbons), so the bounding-center hit resolves the node.
        _ = view.zr.storage.getDisplayList(true)
        guard let (cx, cy) = globalCenter(el) else { XCTFail("no bounding rect"); return }

        view._injectPointerForTest(type: "mousemove", zrX: cx, zrY: cy)
        XCTAssertTrue(el.currentStates.contains("emphasis"),
                      "an injected pointer over sankey node 0 must drive it into emphasis")

        view._injectPointerForTest(type: "mousemove", zrX: 1, zrY: 1)
        XCTAssertTrue(el.currentStates.isEmpty,
                      "moving off sankey node 0 must clear its emphasis via the mouseout leg")
    }
}
