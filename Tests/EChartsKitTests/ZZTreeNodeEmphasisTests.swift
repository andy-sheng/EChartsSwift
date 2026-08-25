// Tree NODE hover EMPHASIS — the self-emphasis + label-restyle + focus 'ancestor'/'relative' legs that
// complement ZZTopologyFocusTests (which covers focus:'descendant' node/edge blur). Tree nodes route
// through the shared SymbolDraw/Symbol, so `data.getItemGraphicEl(i)` is the node's Symbol (a Group); its
// child "item"-named Path carries the label and is the emphasis carrier (Symbol.updateData →
// toggleHoverEmphasis(self, focus, ...)). Highlighting a node must:
//   - enter the "emphasis" ZR state on the node symbol AND restyle its label (the setLabelStyle emphasis
//     state on the label textContent), and
//   - resolve `emphasis.focus` = 'ancestor'/'relative' onto the topology index set so the lineage stays
//     bright and the rest blurs (TreeView.decorateNode → treeResolveFocus → ecData.focus), and
//   - fully clear on `downplay` (allLeaveBlur on every high-down dispatch + leaveEmphasis).
//
// Drives the blur via dispatchAction(highlight/downplay, seriesIndex, dataIndex) → blurSeriesFromHighlight
// Payload (the live mouseover fan-out is deferred). A blurred element carries the "blur" ZR state; a
// focused/emphasized one carries "emphasis" (or neither, when merely un-blurred).
import XCTest
import ZRenderKit
@testable import EChartsKit

final class ZZTreeNodeEmphasisTests: XCTestCase {

    override func setUp() {
        super.setUp()
        ComponentModel.registerClass(TreeSeriesModel.self)
    }

    // root → A(→A1,A2), B(→B1). focus set by the caller via the series `emphasis.focus`.
    private func makeTree(focus: String) -> EChartsView {
        let view = EChartsView(width: 420, height: 340)
        view.setOption([
            "series": [["type": "tree", "layout": "orthogonal", "orient": "LR",
                        "symbolSize": 10.0,
                        // an explicit, distinct emphasis label colour so the label carries a real
                        // emphasis state (proves the restyle rather than a no-op default).
                        "label": ["show": true, "color": "#111111"] as [String: Any],
                        "emphasis": ["focus": focus,
                                     "label": ["color": "#ff0000"] as [String: Any]] as [String: Any],
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
        _ = view.zr.storage.getDisplayList(true)
        return view
    }

    private func highlight(_ view: EChartsView, dataIndex: Int) {
        var p = Payload(type: "highlight")
        p.other["seriesIndex"] = 0.0
        p.other["dataIndexInside"] = dataIndex
        view.ec.dispatchAction(p)
    }
    private func downplay(_ view: EChartsView, dataIndex: Int) {
        var p = Payload(type: "downplay")
        p.other["seriesIndex"] = 0.0
        p.other["dataIndexInside"] = dataIndex
        view.ec.dispatchAction(p)
    }
    private func containsState(_ el: Element?, _ state: String) -> Bool {
        guard let el else { return false }
        var found = el.currentStates.contains(state)
        el.traverse { child in found = found || child.currentStates.contains(state) }
        return found
    }
    private func isBlurred(_ el: Element?) -> Bool { containsState(el, "blur") }
    private func isEmphasized(_ el: Element?) -> Bool { containsState(el, "emphasis") }

    private func idx(_ view: EChartsView, _ name: String) -> Int? {
        let data = view.ec.getModel()!.getSeriesByIndex(0)!.getData()
        for i in 0..<data.count() where data.getName(i) == name { return i }
        return nil
    }
    private func symbolPath(_ view: EChartsView, _ i: Int) -> ZRenderKit.Path? {
        let data = view.ec.getModel()!.getSeriesByIndex(0)!.getData()
        return (data.getItemGraphicEl(i) as? Symbol)?.getSymbolPath()
    }

    // MARK: self-emphasis + label restyle — highlighting a node enters emphasis on the node symbol AND
    //   its label textContent (the setLabelStyle emphasis state on the label).
    func testHoverNodeEntersEmphasisAndRestylesLabel() {
        let view = makeTree(focus: "descendant")
        guard let a = idx(view, "A") else { return XCTFail("node A must exist") }
        let data = view.ec.getModel()!.getSeriesByIndex(0)!.getData()

        // The node symbol (Group) is a high-down dispatcher (Symbol.updateData → toggleHoverEmphasis).
        XCTAssertTrue(states.isHighDownDispatcher(data.getItemGraphicEl(a)!),
                      "tree node Symbol must be marked a highDown dispatcher")

        highlight(view, dataIndex: a)

        // The node's symbol Path entered the emphasis state (traverseUpdateState reached the child).
        XCTAssertTrue(isEmphasized(symbolPath(view, a)),
                      "highlighting a tree node must enter the emphasis state on its symbol")
        // Its label textContent restyles to the emphasis label state.
        let label = symbolPath(view, a)?.getTextContent()
        XCTAssertNotNil(label, "node A must carry a label textContent")
        XCTAssertTrue(label!.currentStates.contains("emphasis"),
                      "the node label must restyle (enter emphasis) when its node is highlighted")

        // downplay clears the emphasis on the node + its label.
        downplay(view, dataIndex: a)
        XCTAssertFalse(isEmphasized(symbolPath(view, a)),
                       "downplay must clear the node emphasis state")
        XCTAssertFalse(symbolPath(view, a)!.getTextContent()!.currentStates.contains("emphasis"),
                       "downplay must clear the label emphasis state")
    }

    // MARK: focus:'ancestor' — highlighting a leaf keeps its ancestor chain bright, blurs the rest.
    func testAncestorFocusKeepsLineageBright() {
        let view = makeTree(focus: "ancestor")
        guard let a1 = idx(view, "A1"), let a = idx(view, "A"), let root = idx(view, "root"),
              let a2 = idx(view, "A2"), let b = idx(view, "B") else { return XCTFail("nodes") }
        let data = view.ec.getModel()!.getSeriesByIndex(0)!.getData()

        highlight(view, dataIndex: a1)   // ancestors of A1 = root, A, A1

        XCTAssertFalse(isBlurred(data.getItemGraphicEl(a1)), "highlighted A1 must not blur")
        XCTAssertFalse(isBlurred(data.getItemGraphicEl(a)), "ancestor A must stay bright")
        XCTAssertFalse(isBlurred(data.getItemGraphicEl(root)), "ancestor root must stay bright")
        XCTAssertTrue(isBlurred(data.getItemGraphicEl(a2)), "sibling A2 (not an ancestor) must blur")
        XCTAssertTrue(isBlurred(data.getItemGraphicEl(b)), "unrelated B must blur")

        downplay(view, dataIndex: a1)
        for n in [a1, a, root, a2, b] {
            XCTAssertFalse(isBlurred(data.getItemGraphicEl(n)), "downplay must clear all blur")
        }
    }

    // MARK: focus:'relative' — highlighting a mid node keeps BOTH its ancestors and its descendants bright.
    func testRelativeFocusKeepsAncestorsAndDescendantsBright() {
        let view = makeTree(focus: "relative")
        guard let a = idx(view, "A"), let root = idx(view, "root"), let a1 = idx(view, "A1"),
              let a2 = idx(view, "A2"), let b = idx(view, "B"), let b1 = idx(view, "B1") else {
            return XCTFail("nodes")
        }
        let data = view.ec.getModel()!.getSeriesByIndex(0)!.getData()

        highlight(view, dataIndex: a)   // relative(A) = ancestors(root,A) ∪ descendants(A,A1,A2)

        XCTAssertFalse(isBlurred(data.getItemGraphicEl(root)), "ancestor root must stay bright")
        XCTAssertFalse(isBlurred(data.getItemGraphicEl(a)), "highlighted A must stay bright")
        XCTAssertFalse(isBlurred(data.getItemGraphicEl(a1)), "descendant A1 must stay bright")
        XCTAssertFalse(isBlurred(data.getItemGraphicEl(a2)), "descendant A2 must stay bright")
        XCTAssertTrue(isBlurred(data.getItemGraphicEl(b)), "off-lineage B must blur")
        XCTAssertTrue(isBlurred(data.getItemGraphicEl(b1)), "off-lineage B1 must blur")
    }
}
