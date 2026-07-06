// Phase 45 regression test — `emphasis.focus` TOPOLOGY for the node/edge charts: graph 'adjacency',
// tree 'ancestor'/'descendant', sankey 'adjacency'. Highlighting a node must keep its topological
// neighbourhood BRIGHT and BLUR everything else — proving the view-layer wiring that resolves the focus
// index set (getAdjacentDataIndices / getAncestorsIndices / …) onto each dispatcher's ecData.focus, which
// `states.blurSeries` then consumes (array form for tree, {node,edge} object form for graph/sankey).
//
// Drives the blur via `dispatchAction(highlight, seriesIndex, dataIndex)` → doDispatchAction →
// blurSeriesFromHighlightPayload (the live mouseover focus fan-out is deferred — Phase 33). A blurred
// element carries the "blur" ZR state (singleEnterBlur → useStates); a focused one does not.
import XCTest
import ZRenderKit
@testable import EChartsKit

final class ZZTopologyFocusTests: XCTestCase {

    override func setUp() {
        super.setUp()
        ComponentModel.registerClass(GraphSeriesModel.self)
        ComponentModel.registerClass(TreeSeriesModel.self)
        ComponentModel.registerClass(SankeySeriesModel.self)
        ComponentModel.registerClass(ChordSeriesModel.self)
    }

    private func highlightNode(_ view: EChartsView, seriesIndex: Int, dataIndex: Int) {
        var p = Payload(type: "highlight")
        p.other["seriesIndex"] = Double(seriesIndex)
        // `dataIndexInside` is the finder key `queryDataIndex` resolves directly (the `dataIndex` →
        //   `indexOfRawIndex` mapping is a pre-existing PORT-TODO stub); with no data filtering the inside
        //   index equals the raw index.
        p.other["dataIndexInside"] = dataIndex
        view.ec.dispatchAction(p)
    }

    private func isBlurred(_ el: Element?) -> Bool {
        el?.currentStates.contains("blur") ?? false
    }

    // MARK: - Graph focus:'adjacency' — highlight n0 (linked to n1) → n2/n3 blur, n1 stays bright.
    func testGraphAdjacencyFocusBlursNonNeighbours() {
        let view = EChartsView(width: 400, height: 300)
        view.setOption([
            "series": [["type": "graph", "layout": "none", "symbolSize": 24.0,
                        "emphasis": ["focus": "adjacency"] as [String: Any],
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

        highlightNode(view, seriesIndex: 0, dataIndex: 0)   // highlight n0 (adjacent: n0, n1; edge0)

        // n0's adjacency set = {node:[0,1], edge:[0]} → n0, n1 stay bright; n2, n3 blur.
        XCTAssertFalse(isBlurred(data.getItemGraphicEl(0)), "highlighted node n0 must not be blurred")
        XCTAssertFalse(isBlurred(data.getItemGraphicEl(1)), "adjacent node n1 must stay bright")
        XCTAssertTrue(isBlurred(data.getItemGraphicEl(2)), "non-adjacent node n2 must be blurred")
        XCTAssertTrue(isBlurred(data.getItemGraphicEl(3)), "isolated node n3 must be blurred")

        // Edges: edge0 (n0-n1) is in the adjacency set → bright; edge1 (n1-n2) → blurred.
        let edgeData = (series as! GraphSeriesModel).getEdgeData()
        XCTAssertFalse(isBlurred(edgeData.getItemGraphicEl(0)), "adjacent edge n0-n1 must stay bright")
        XCTAssertTrue(isBlurred(edgeData.getItemGraphicEl(1)), "non-adjacent edge n1-n2 must be blurred")
    }

    // MARK: - Tree focus:'descendant' — highlight the root → the root's subtree stays bright, and a node
    //   in a DIFFERENT subtree blurs. (Root has all nodes as descendants, so use 'descendant' on a mid node.)
    func testTreeDescendantFocusBlursOtherSubtree() {
        let view = EChartsView(width: 400, height: 320)
        view.setOption([
            "series": [["type": "tree", "layout": "orthogonal",
                        "emphasis": ["focus": "descendant"] as [String: Any],
                        "data": [[
                            "name": "root",
                            "children": [
                                ["name": "A", "children": [
                                    ["name": "A1"] as [String: Any],
                                    ["name": "A2"] as [String: Any]
                                ]] as [String: Any],
                                ["name": "B", "children": [
                                    ["name": "B1"] as [String: Any]
                                ]] as [String: Any]
                            ]
                        ] as [String: Any]]] as [String: Any]]
        ])
        let series = view.ec.getModel()!.getSeriesByIndex(0)!
        let data = series.getData()

        // Find the dataIndex of node "A" (a mid node whose descendants are A1/A2, NOT B/B1).
        func idx(of name: String) -> Int? {
            for i in 0..<data.count() where (data.getName(i) == name) { return i }
            return nil
        }
        guard let aIdx = idx(of: "A"), let a1 = idx(of: "A1"), let bIdx = idx(of: "B") else {
            XCTFail("tree must build named nodes"); return
        }

        highlightNode(view, seriesIndex: 0, dataIndex: aIdx)   // focus = A's descendants (A, A1, A2)

        XCTAssertFalse(isBlurred(data.getItemGraphicEl(aIdx)), "highlighted node A must not be blurred")
        XCTAssertFalse(isBlurred(data.getItemGraphicEl(a1)), "A's descendant A1 must stay bright")
        XCTAssertTrue(isBlurred(data.getItemGraphicEl(bIdx)), "sibling subtree node B must be blurred")
    }

    // MARK: - Sankey focus:'adjacency' — highlight a source node → its direct edge/target stay bright,
    //   an unrelated node blurs.
    func testSankeyAdjacencyFocusBlursUnrelated() {
        let view = EChartsView(width: 460, height: 320)
        view.setOption([
            "series": [["type": "sankey",
                        "emphasis": ["focus": "adjacency"] as [String: Any],
                        "data": [
                            ["name": "a"] as [String: Any], ["name": "b"] as [String: Any],
                            ["name": "c"] as [String: Any], ["name": "d"] as [String: Any]
                        ],
                        "links": [
                            ["source": "a", "target": "b", "value": 5.0] as [String: Any],
                            ["source": "c", "target": "d", "value": 3.0] as [String: Any]
                        ]] as [String: Any]]
        ])
        let series = view.ec.getModel()!.getSeriesByIndex(0)!
        let data = series.getData()
        func idx(of name: String) -> Int? {
            for i in 0..<data.count() where (data.getName(i) == name) { return i }
            return nil
        }
        guard let a = idx(of: "a"), let b = idx(of: "b"), let c = idx(of: "c") else {
            XCTFail("sankey must build named nodes"); return
        }

        highlightNode(view, seriesIndex: 0, dataIndex: a)   // a's adjacency = {a, b} + their edge

        XCTAssertFalse(isBlurred(data.getItemGraphicEl(a)), "highlighted node a must not be blurred")
        XCTAssertFalse(isBlurred(data.getItemGraphicEl(b)), "adjacent target b must stay bright")
        XCTAssertTrue(isBlurred(data.getItemGraphicEl(c)), "unrelated node c must be blurred")
    }

    // MARK: - Chord focus:'adjacency' — highlight a source node → its edge/target stay bright, an
    //   unrelated node blurs (chord reuses the shared Graph like sankey).
    func testChordAdjacencyFocusBlursUnrelated() {
        let view = EChartsView(width: 460, height: 380)
        view.setOption([
            "series": [["type": "chord",
                        "emphasis": ["focus": "adjacency"] as [String: Any],
                        "data": [
                            ["name": "a"] as [String: Any], ["name": "b"] as [String: Any],
                            ["name": "c"] as [String: Any], ["name": "d"] as [String: Any]
                        ],
                        "links": [
                            ["source": "a", "target": "b", "value": 5.0] as [String: Any],
                            ["source": "c", "target": "d", "value": 3.0] as [String: Any]
                        ]] as [String: Any]]
        ])
        let series = view.ec.getModel()!.getSeriesByIndex(0)!
        let data = series.getData()
        func idx(of name: String) -> Int? {
            for i in 0..<data.count() where (data.getName(i) == name) { return i }
            return nil
        }
        guard let a = idx(of: "a"), let b = idx(of: "b"), let c = idx(of: "c") else {
            XCTFail("chord must build named nodes"); return
        }

        highlightNode(view, seriesIndex: 0, dataIndex: a)   // a's adjacency = {a, b} + their edge

        XCTAssertFalse(isBlurred(data.getItemGraphicEl(a)), "highlighted node a must not be blurred")
        XCTAssertFalse(isBlurred(data.getItemGraphicEl(b)), "adjacent target b must stay bright")
        XCTAssertTrue(isBlurred(data.getItemGraphicEl(c)), "unrelated node c must be blurred")
    }
}
