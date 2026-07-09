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
    private func makeTreeView() -> EChartsView {
        let view = EChartsView(width: 400, height: 300)
        let series: [String: Any] = [
            "type": "tree", "left": "10%", "right": "10%", "top": "10%", "bottom": "10%",
            "symbolSize": 8.0, "orient": "LR",
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
}
