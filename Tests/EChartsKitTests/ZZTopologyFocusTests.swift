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
        //   `indexOfRawIndex` mapping is a pre-existing note stub); with no data filtering the inside
        //   index equals the raw index.
        p.other["dataIndexInside"] = dataIndex
        view.ec.dispatchAction(p)
    }

    private func isBlurred(_ el: Element?) -> Bool {
        guard let el else { return false }
        var found = el.currentStates.contains("blur")
        el.traverse { child in found = found || child.currentStates.contains("blur") }
        return found
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

        // Phase 48: the edge blur-propagation hook. Tree edges (BezierCurve/TreePath — NOT "item"-named
        //   node symbols) are blurred by the group traverse; the in-lineage ones un-blur with their node.
        //   Without the hook every edge would stay blurred; with it, some are bright and some blurred.
        _ = view.zr.storage.getDisplayList(true)
        var edgesBlurred = 0, edgesBright = 0
        for el in view.zr.storage.getDisplayList(false) {
            if el.name == "item" { continue }                 // node symbol, not an edge
            if el is BezierCurve || el is TreePath {
                if el.currentStates.contains("blur") { edgesBlurred += 1 } else { edgesBright += 1 }
            }
        }
        XCTAssertGreaterThan(edgesBright, 0, "at least one in-lineage tree edge must un-blur with its node")
        XCTAssertGreaterThan(edgesBlurred, 0, "at least one out-of-lineage tree edge must stay blurred")
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

        // Ribbons (edges): the adjacency `{node:[a,b], edge:[0]}` set keeps the a→b ribbon (edge 0)
        //   BRIGHT and blurs the unrelated c→d ribbon (edge 1) — the chord analogue of the graph edge
        //   fan-out (ChordEdge.updateData → toggleHoverEmphasis → states.blurSeries object-focus branch,
        //   which resolves the `edge` key through ChordSeriesModel.getData(.edge)).
        let edgeData = (series as! ChordSeriesModel).getEdgeData()
        XCTAssertTrue(edgeData.count() >= 2, "chord must build one ribbon per link")
        XCTAssertFalse(isBlurred(edgeData.getItemGraphicEl(0)), "adjacent ribbon a-b must stay bright")
        XCTAssertTrue(isBlurred(edgeData.getItemGraphicEl(1)), "unrelated ribbon c-d must be blurred")
    }

    // MARK: - Chord LIVE hover → the hovered sector enters the "emphasis" ZR state (the mouse-over leg,
    //   not the dispatch). Mirrors MapTreemapHoverTests: inject a synthetic pointer over the sector's
    //   global center through the real Handler hit-test → EChartsView "mouseover" → enterEmphasisWhenMouseOver.
    func testChordSectorHoverEntersEmphasis() {
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
        var aIdx = -1
        for i in 0..<data.count() where (data.getName(i) == "a") { aIdx = i }
        XCTAssertTrue(aIdx >= 0, "chord must build a node named 'a'")
        guard let el = data.getItemGraphicEl(aIdx) else {
            XCTFail("chord render must populate a sector for 'a'"); return
        }
        // The sector is a highDown dispatcher (ChordPiece.updateData → toggleHoverEmphasis).
        XCTAssertTrue(states.isHighDownDispatcher(el),
                      "ChordPiece must be marked a highDown dispatcher")

        // The bounding-box center of an annular sector lies OUTSIDE the ring, so hit-test a point that is
        //   genuinely inside the arc: mid-angle at mid-radius (local sector coords → global).
        guard let sector = el as? Path, let shape = sector.shape as? SectorShape else {
            XCTFail("ChordPiece must carry a SectorShape"); return
        }
        let midAngle = (shape.startAngle + shape.endAngle) / 2
        let rMid = (shape.r0 + shape.r) / 2
        let lx = shape.cx + rMid * cos(midAngle)
        let ly = shape.cy + rMid * sin(midAngle)
        let g = el.transformCoordToGlobal(lx, ly)
        view._injectPointerForTest(type: "mousemove", zrX: g[0], zrY: g[1])
        XCTAssertTrue(el.currentStates.contains("emphasis"),
                      "hovering the chord sector must enter the emphasis state")

        // Move off the sector → emphasis clears (the mouseout leg).
        view._injectPointerForTest(type: "mousemove", zrX: 1, zrY: 1)
        XCTAssertFalse(el.currentStates.contains("emphasis"),
                       "moving off the sector must clear the emphasis state")
    }

    // MARK: - Chord LIVE hover → the adjacency focus FAN-OUT (the reported bug: hover only emphasized
    //   the sector; the unrelated nodes/ribbons never faded). Mouse-over a node must blur every
    //   non-adjacent node + ribbon with a RENDERED opacity drop, and mouse-out must restore them.
    func testChordLiveHoverBlursNonAdjacent() {
        let view = EChartsView(width: 460, height: 380)
        view.setOption([
            "series": [["type": "chord",
                        // No explicit emphasis: exercise the DEFAULT chord focus:'adjacency'.
                        "data": [
                            ["name": "a"] as [String: Any], ["name": "b"] as [String: Any],
                            ["name": "c"] as [String: Any], ["name": "d"] as [String: Any]
                        ],
                        "links": [
                            ["source": "a", "target": "b", "value": 5.0] as [String: Any],
                            ["source": "c", "target": "d", "value": 3.0] as [String: Any]
                        ]] as [String: Any]]
        ])
        _ = view.zr.storage.getDisplayList(true)
        let series = view.ec.getModel()!.getSeriesByIndex(0)!
        let data = series.getData()
        func idx(of name: String) -> Int? {
            for i in 0..<data.count() where (data.getName(i) == name) { return i }
            return nil
        }
        guard let a = idx(of: "a"), let b = idx(of: "b"), let c = idx(of: "c"),
              let sector = data.getItemGraphicEl(a) as? Path,
              let shape = sector.shape as? SectorShape else {
            XCTFail("chord must build named node sectors"); return
        }
        let edgeData = (series as! ChordSeriesModel).getEdgeData()
        let unrelatedNode = data.getItemGraphicEl(c) as? Path
        let unrelatedRibbon = edgeData.getItemGraphicEl(1) as? Path
        let normalNodeOpacity = unrelatedNode?.pathStyle?.opacity ?? 1
        let normalRibbonOpacity = unrelatedRibbon?.pathStyle?.opacity ?? 1
        XCTAssertEqual(unrelatedNode?.stateTransition?.duration ?? -1, 300, accuracy: 1e-9,
                       "chord data elements inherit the global stateAnimation duration")
        XCTAssertEqual(unrelatedRibbon?.stateTransition?.duration ?? -1, 300, accuracy: 1e-9,
                       "chord ribbons inherit the global stateAnimation duration")

        // Hover node a (mid-angle / mid-radius, local → global).
        let midAngle = (shape.startAngle + shape.endAngle) / 2
        let rMid = (shape.r0 + shape.r) / 2
        let g = sector.transformCoordToGlobal(shape.cx + rMid * cos(midAngle),
                                              shape.cy + rMid * sin(midAngle))
        view._injectPointerForTest(type: "mousemove", zrX: g[0], zrY: g[1])

        XCTAssertFalse(isBlurred(data.getItemGraphicEl(a)), "hovered node a must not be blurred")
        XCTAssertFalse(isBlurred(data.getItemGraphicEl(b)), "adjacent target b must stay bright")
        XCTAssertTrue(isBlurred(data.getItemGraphicEl(c)),
                      "live hover must blur the unrelated node c (was the reported no-op)")
        XCTAssertTrue(isBlurred(edgeData.getItemGraphicEl(1)), "unrelated ribbon c-d must blur")
        XCTAssertFalse(isBlurred(edgeData.getItemGraphicEl(0)), "adjacent ribbon a-b must stay bright")
        XCTAssertTrue(unrelatedNode?.animators.contains(where: {
            $0.__fromStateTransition != nil && $0.targetName == "style" && $0.getTrack("opacity") != nil
        }) == true, "hover blur must interpolate node opacity through a state-transition animator")
        XCTAssertTrue(unrelatedRibbon?.animators.contains(where: {
            $0.__fromStateTransition != nil && $0.targetName == "style" && $0.getTrack("opacity") != nil
        }) == true, "hover blur must interpolate ribbon opacity through a state-transition animator")

        // State transitions deliberately leave the live style at its normal value until the first
        // animation frame (matching zrender). Prime and sample the two opacity clips halfway through
        // the global 300 ms cubicOut transition instead of expecting the old instantaneous jump.
        for element in [unrelatedNode, unrelatedRibbon] {
            guard let clip = element?.animators.first(where: {
                $0.__fromStateTransition != nil && $0.targetName == "style" && $0.getTrack("opacity") != nil
            })?.getClip() else {
                XCTFail("hover blur is missing its opacity clip"); return
            }
            _ = clip.step(0, 0)
            _ = clip.step(150, 150)
        }
        XCTAssertLessThan(unrelatedNode?.pathStyle?.opacity ?? 1, normalNodeOpacity,
                          "the blur must visibly interpolate the unrelated node opacity")
        XCTAssertLessThan(unrelatedRibbon?.pathStyle?.opacity ?? 1, normalRibbonOpacity,
                          "the blur must visibly interpolate the unrelated ribbon opacity")

        // Mouse-out → everything restores.
        view._injectPointerForTest(type: "mousemove", zrX: 1, zrY: 1)
        XCTAssertFalse(isBlurred(data.getItemGraphicEl(c)), "mouseout must clear the node blur")
        XCTAssertFalse(isBlurred(edgeData.getItemGraphicEl(1)), "mouseout must clear the ribbon blur")
        for element in [unrelatedNode, unrelatedRibbon] {
            guard let clip = element?.animators.first(where: {
                $0.__fromStateTransition != nil && $0.targetName == "style" && $0.getTrack("opacity") != nil
            })?.getClip() else {
                XCTFail("mouseout restore is missing its opacity clip"); return
            }
            _ = clip.step(0, 0)
            _ = clip.step(300, 300)
        }
        XCTAssertEqual(unrelatedNode?.pathStyle?.opacity ?? -1, normalNodeOpacity, accuracy: 1e-6,
                       "node opacity restored after mouseout")
        XCTAssertEqual(unrelatedRibbon?.pathStyle?.opacity ?? -1, normalRibbonOpacity, accuracy: 1e-6,
                       "ribbon opacity restored after mouseout")
    }
}
