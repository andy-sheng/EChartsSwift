// Tree expand/collapse — clicking a tree node toggles node.isExpand and the now-collapsed subtree's
// descendants stop rendering. Mirrors upstream chart/tree/treeAction.ts (`treeExpandAndCollapse`) +
// TreeView.ts's per-node `el.on('click', ...)` → api.dispatchAction. The action's update:'update' re-runs
// treeLayout, so a collapsed node's children lose their layout and the symbolNeedsDraw gate drops them.
//
//   ec.dispatchAction({type:'treeExpandAndCollapse', seriesId, dataIndex})
//     -> treeExpandAndCollapse action toggles node.isExpand
//        -> full update() re-lays-out -> TreeView drops the collapsed subtree's nodes
import XCTest
import ZRenderKit
@testable import EChartsKit

final class TreeExpandCollapseTests: XCTestCase {

    /// A small orthogonal tree (root → A,B → leaves), rendered through EChartsView.
    private func makeTreeView(edgeShape: String = "curve", layout: String = "orthogonal") -> EChartsView {
        let view = EChartsView(width: 400, height: 300)
        let series: [String: Any] = [
            "type": "tree", "left": "10%", "right": "10%", "top": "10%", "bottom": "10%",
            "symbolSize": 8.0, "orient": "LR", "edgeShape": edgeShape, "layout": layout,
            "animationDurationUpdate": 750.0, "animationEasingUpdate": "cubicOut",
            "data": [
                ["name": "root", "children": [
                    ["name": "A", "children": [["name": "A1"], ["name": "A2"]]] as [String: Any],
                    ["name": "B", "children": [["name": "B1"], ["name": "B2"]]] as [String: Any]
                ]] as [String: Any]
            ]
        ]
        view.setOption(["series": [series]])
        _ = view.zr.storage.getDisplayList(true)
        return view
    }

    private func treeSeries(_ view: EChartsView) -> TreeSeriesModel? {
        return view.ec.getModel()?.getSeriesByIndex(0) as? TreeSeriesModel
    }

    /// The dataIndex of the first node with the given name (nil if absent).
    private func dataIndex(_ series: TreeSeriesModel, name: String) -> Int? {
        let data = series.getData()
        for i in 0..<data.count() {
            if data.tree?.getNodeByDataIndex(i)?.name == name { return i }
        }
        return nil
    }

    private func node(_ series: TreeSeriesModel, name: String) -> TreeNode? {
        guard let idx = dataIndex(series, name: name) else { return nil }
        return series.getData().tree?.getNodeByDataIndex(idx)
    }

    /// Count nodes that currently render (have a valid layout — the symbolNeedsDraw gate TreeView uses).
    private func renderedNodeCount(_ series: TreeSeriesModel) -> Int {
        let data = series.getData()
        var n = 0
        for i in 0..<data.count() where symbolNeedsDraw(data, i) { n += 1 }
        return n
    }

    // Collapsing a parent flips its isExpand and hides its descendants; re-expanding restores them.
    func testClickCollapsesAndExpandsSubtree() {
        let view = makeTreeView()
        guard let series = treeSeries(view) else { return XCTFail("tree series must exist") }
        guard let aIdx = dataIndex(series, name: "A"),
              let aNode = node(series, name: "A") else { return XCTFail("node A must exist") }

        XCTAssertTrue(aNode.isExpand, "A starts expanded")
        let before = renderedNodeCount(view: view)   // root, A, B, A1, A2, B1, B2 = 7
        XCTAssertEqual(before, 7, "all 7 nodes render initially")

        // Click A → collapse.
        var collapse = Payload(type: "treeExpandAndCollapse")
        collapse.other["seriesId"] = series.id
        collapse.other["dataIndex"] = aIdx
        view.ec.dispatchAction(collapse)

        guard let seriesAfter = treeSeries(view),
              let aAfter = node(seriesAfter, name: "A") else { return XCTFail("A must persist") }
        XCTAssertFalse(aAfter.isExpand, "clicking A flips isExpand to collapsed")
        let collapsed = renderedNodeCount(view: view)
        print("TREE-EXPAND: rendered \(before) -> \(collapsed) after collapsing A")
        XCTAssertEqual(collapsed, before - 2, "A's two children (A1, A2) stop rendering")
        XCTAssertFalse(symbolNeedsDrawByName(seriesAfter, "A1"), "A1 no longer draws")

        // Click A again → expand back.
        var expand = Payload(type: "treeExpandAndCollapse")
        expand.other["seriesId"] = series.id
        expand.other["dataIndex"] = aIdx
        view.ec.dispatchAction(expand)

        guard let seriesReexp = treeSeries(view),
              let aReexp = node(seriesReexp, name: "A") else { return XCTFail("A must persist") }
        XCTAssertTrue(aReexp.isExpand, "clicking A again re-expands it")
        XCTAssertEqual(renderedNodeCount(view: view), before, "all nodes render again after re-expand")
    }

    // Web TreeView.removeNode keeps a disappearing descendant alive for the update duration, moves it
    // to the nearest laid-out ancestor, and fades its path/label. Removing it on the collapse frame is
    // the visible snap caught by the official-tree animation comparison.
    func testCollapseAnimatesDescendantAndEdgeTowardSourceNode() throws {
        let view = makeTreeView()
        settleAnimations(view.ec.getRoot())
        let series = try XCTUnwrap(treeSeries(view))
        let aIndex = try XCTUnwrap(dataIndex(series, name: "A"))
        let a1Index = try XCTUnwrap(dataIndex(series, name: "A1"))
        let a1 = try XCTUnwrap(series.getData().getItemGraphicEl(a1Index) as? Symbol)
        let oldX = a1.x
        let oldY = a1.y
        let oldEdge = try XCTUnwrap(curveEnding(atX: oldX, y: oldY, in: view.ec.getRoot()))

        var collapse = Payload(type: "treeExpandAndCollapse")
        collapse.other["seriesId"] = series.id
        collapse.other["dataIndex"] = aIndex
        view.ec.dispatchAction(collapse)

        let collapsedSeries = try XCTUnwrap(treeSeries(view))
        let sourceLayout = try XCTUnwrap(
            collapsedSeries.getData().getItemLayout(aIndex) as? [String: Any]
        )
        let sourceX = try XCTUnwrap(sourceLayout["x"] as? Double) + 1.0
        let sourceY = try XCTUnwrap(sourceLayout["y"] as? Double) + 1.0

        XCTAssertNotNil(a1.parent, "a collapsing descendant must remain in the scene during its leave tween")
        let nodeLeave = try XCTUnwrap(a1.animators.first { $0.scope == "leave" })
        XCTAssertNotNil(oldEdge.parent, "the descendant edge must remain in the scene during its leave tween")
        XCTAssertNotNil(oldEdge.animators.first { $0.scope == "leave" })

        let clip = try XCTUnwrap(nodeLeave.getClip())
        clip.resetForDeterministicSampling()
        _ = clip.sampleForDeterministicRendering(at: 375.0)
        XCTAssertLessThan(abs(a1.x - sourceX), abs(oldX - sourceX),
                          "the descendant must move toward its source node")
        XCTAssertLessThan(abs(a1.y - sourceY), abs(oldY - sourceY),
                          "the descendant must move toward its source node")
    }

    // Web creates a re-expanded descendant at sourceOldLayout and updateProps-tweens it to targetLayout.
    // Creating it directly at targetLayout reproduces the final frame but loses the outward tree motion.
    func testExpandStartsDescendantAtSourceOldLayout() throws {
        let view = makeTreeView()
        settleAnimations(view.ec.getRoot())
        var series = try XCTUnwrap(treeSeries(view))
        let aIndex = try XCTUnwrap(dataIndex(series, name: "A"))

        var action = Payload(type: "treeExpandAndCollapse")
        action.other["seriesId"] = series.id
        action.other["dataIndex"] = aIndex
        view.ec.dispatchAction(action)
        settleAnimations(view.ec.getRoot())

        series = try XCTUnwrap(treeSeries(view))
        let collapsedSource = try XCTUnwrap(series.getData().getItemGraphicEl(aIndex) as? Symbol)
        let sourceOldX = collapsedSource.x
        let sourceOldY = collapsedSource.y
        action.other["seriesId"] = series.id
        action.other["dataIndex"] = aIndex
        view.ec.dispatchAction(action)

        let expandedSeries = try XCTUnwrap(treeSeries(view))
        let a1Index = try XCTUnwrap(dataIndex(expandedSeries, name: "A1"))
        let a1 = try XCTUnwrap(expandedSeries.getData().getItemGraphicEl(a1Index) as? Symbol)
        let update = try XCTUnwrap(a1.animators.first { $0.scope == "update" })
        let clip = try XCTUnwrap(update.getClip())
        clip.resetForDeterministicSampling()
        _ = clip.sampleForDeterministicRendering(at: 0.0)
        XCTAssertEqual(a1.x, sourceOldX, accuracy: 1e-6,
                       "a re-expanded descendant starts at sourceOldLayout.x")
        XCTAssertEqual(a1.y, sourceOldY, accuracy: 1e-6,
                       "a re-expanded descendant starts at sourceOldLayout.y")
    }

    func testPolylineReexpandGrowsTheParentForkOutward() throws {
        let view = makeTreeView(edgeShape: "polyline")
        settleAnimations(view.ec.getRoot())
        var series = try XCTUnwrap(treeSeries(view))
        let aIndex = try XCTUnwrap(dataIndex(series, name: "A"))

        var action = Payload(type: "treeExpandAndCollapse")
        action.other["seriesId"] = series.id
        action.other["dataIndex"] = aIndex
        view.ec.dispatchAction(action)
        settleAnimations(view.ec.getRoot())

        series = try XCTUnwrap(treeSeries(view))
        action.other["seriesId"] = series.id
        action.other["dataIndex"] = aIndex
        view.ec.dispatchAction(action)

        _ = try XCTUnwrap(treeSeries(view))
        var fork: TreePath?
        view.ec.getRoot().traverse { element in
            guard fork == nil, let path = element as? TreePath,
                  path.animators.contains(where: { $0.scope == "update" }) else { return }
            let clips = path.animators.compactMap { $0.getClip() }
            for clip in clips {
                clip.resetForDeterministicSampling()
                _ = clip.sampleForDeterministicRendering(at: 0)
            }
            if let shape = path.shape as? TreeEdgeShape,
               !shape.childPoints.isEmpty,
               abs(shape.childPoints[0][0] - shape.parentPoint[0]) < 1e-6,
               abs(shape.childPoints[0][1] - shape.parentPoint[1]) < 1e-6 {
                fork = path
            }
        }
        let initial = try XCTUnwrap(fork?.shape as? TreeEdgeShape)
        XCTAssertEqual(initial.childPoints.first, initial.parentPoint,
                       "Web re-expands a polyline from its retained parent point")
    }

    func testInsertedNodeUsesDataDiffIdentityAndStartsAtItsParent() throws {
        let view = EChartsView(width: 400, height: 300)
        func option(_ children: [[String: Any]]) -> [String: Any] {
            ["series": [[
                "id": "tree", "type": "tree", "left": "10%", "right": "10%",
                "top": "10%", "bottom": "10%", "symbolSize": 8.0,
                "animationDurationUpdate": 750.0,
                "data": [["name": "root", "children": children] as [String: Any]]
            ] as [String: Any]]]
        }
        view.setOption(option([["name": "A"], ["name": "B"]]))
        settleAnimations(view.ec.getRoot())
        var series = try XCTUnwrap(treeSeries(view))
        let rootIndex = try XCTUnwrap(dataIndex(series, name: "root"))
        let aIndex = try XCTUnwrap(dataIndex(series, name: "A"))
        let root = try XCTUnwrap(series.getData().getItemGraphicEl(rootIndex) as? Symbol)
        let a = try XCTUnwrap(series.getData().getItemGraphicEl(aIndex) as? Symbol)
        let rootOldX = root.x
        let rootOldY = root.y

        view.setOption(option([
            ["name": "C", "children": [["name": "C1"]]],
            ["name": "A"],
            ["name": "B"]
        ]))
        series = try XCTUnwrap(treeSeries(view))
        let updatedAIndex = try XCTUnwrap(dataIndex(series, name: "A"))
        let cIndex = try XCTUnwrap(dataIndex(series, name: "C"))
        XCTAssertTrue(series.getData().getItemGraphicEl(updatedAIndex) === a,
                      "reordering must retain the symbol matched by data.diff identity")
        let c = try XCTUnwrap(series.getData().getItemGraphicEl(cIndex) as? Symbol)
        let c1Index = try XCTUnwrap(dataIndex(series, name: "C1"))
        let c1 = try XCTUnwrap(series.getData().getItemGraphicEl(c1Index) as? Symbol)
        for symbol in [c, c1] {
            let update = try XCTUnwrap(symbol.animators.first { $0.scope == "update" })
            let clip = try XCTUnwrap(update.getClip())
            clip.resetForDeterministicSampling()
            _ = clip.sampleForDeterministicRendering(at: 0)
            XCTAssertEqual(symbol.x, rootOldX, accuracy: 1e-6)
            XCTAssertEqual(symbol.y, rootOldY, accuracy: 1e-6,
                           "a wholly inserted subtree must share the retained ancestor start")
        }
    }

    func testRadialInsertedEdgeStartsAtTheParentsOldAngle() throws {
        let view = EChartsView(width: 400, height: 300)
        func option(_ children: [[String: Any]]) -> [String: Any] {
            ["series": [[
                "id": "tree", "type": "tree", "layout": "radial",
                "left": "10%", "right": "10%", "top": "10%", "bottom": "10%",
                "symbolSize": 8.0, "animationDurationUpdate": 750.0,
                "data": [["name": "root", "children": children] as [String: Any]]
            ] as [String: Any]]]
        }
        view.setOption(option([
            ["name": "A", "children": [["name": "A1"]]],
            ["name": "B"]
        ]))
        settleAnimations(view.ec.getRoot())
        var series = try XCTUnwrap(treeSeries(view))
        let aIndex = try XCTUnwrap(dataIndex(series, name: "A"))
        let a = try XCTUnwrap(series.getData().getItemGraphicEl(aIndex) as? Symbol)
        let oldAX = a.x
        let oldAY = a.y

        view.setOption(option([
            ["name": "C"],
            ["name": "A", "children": [["name": "A1"], ["name": "A2"]]],
            ["name": "B"]
        ]))
        series = try XCTUnwrap(treeSeries(view))
        let a2Index = try XCTUnwrap(dataIndex(series, name: "A2"))
        let a2 = try XCTUnwrap(series.getData().getItemGraphicEl(a2Index) as? Symbol)
        var enteringEdge: BezierCurve?
        view.ec.getRoot().traverse { element in
            guard enteringEdge == nil, let curve = element as? BezierCurve,
                  let shape = curve.shape as? BezierCurveShape,
                  abs(shape.x2 - a2.x) < 1e-6, abs(shape.y2 - a2.y) < 1e-6,
                  curve.animators.contains(where: { $0.scope == "update" }) else { return }
            enteringEdge = curve
        }
        let edge = try XCTUnwrap(enteringEdge)
        for clip in edge.animators.compactMap({ $0.getClip() }) {
            clip.resetForDeterministicSampling()
            _ = clip.sampleForDeterministicRendering(at: 0)
        }
        let initial = try XCTUnwrap(edge.shape as? BezierCurveShape)
        XCTAssertEqual(initial.x1, oldAX, accuracy: 1e-6)
        XCTAssertEqual(initial.y1, oldAY, accuracy: 1e-6)
        XCTAssertEqual(initial.x2, oldAX, accuracy: 1e-6)
        XCTAssertEqual(initial.y2, oldAY, accuracy: 1e-6)
    }

    // A wrong seriesId must not toggle the tree (the query filter rejects it).
    func testWrongSeriesIdIsInert() {
        let view = makeTreeView()
        guard let series = treeSeries(view),
              let aIdx = dataIndex(series, name: "A"),
              let aNode = node(series, name: "A") else { return XCTFail("setup") }
        XCTAssertTrue(aNode.isExpand)

        var p = Payload(type: "treeExpandAndCollapse")
        p.other["seriesId"] = "not-the-tree"
        p.other["dataIndex"] = aIdx
        view.ec.dispatchAction(p)

        guard let aAfter = treeSeries(view).flatMap({ node($0, name: "A") }) else { return XCTFail("A") }
        XCTAssertTrue(aAfter.isExpand, "a non-matching seriesId leaves the node untouched")
    }

    // ---- helpers bound to a live view (re-fetch the series each read: update() rebuilds SeriesData) ----
    private func renderedNodeCount(view: EChartsView) -> Int {
        guard let s = treeSeries(view) else { return 0 }
        return renderedNodeCount(s)
    }
    private func symbolNeedsDrawByName(_ series: TreeSeriesModel, _ name: String) -> Bool {
        guard let idx = dataIndex(series, name: name) else { return false }
        return symbolNeedsDraw(series.getData(), idx)
    }

    private func settleAnimations(_ root: Element) {
        var clips: [Clip] = []
        root.traverse { element in
            for animator in element.animators {
                if let clip = animator.getClip() { clips.append(clip) }
            }
        }
        for clip in clips {
            clip.resetForDeterministicSampling()
            if clip.sampleForDeterministicRendering(at: 1_000_000_000) { clip.ondestroy() }
        }
    }

    private func curveEnding(atX x: Double, y: Double, in root: Element) -> BezierCurve? {
        var found: BezierCurve?
        root.traverse { element in
            guard found == nil, let curve = element as? BezierCurve,
                  let shape = curve.shape as? BezierCurveShape else { return }
            if abs(shape.x2 - x) < 1e-6, abs(shape.y2 - y) < 1e-6 { found = curve }
        }
        return found
    }
}
