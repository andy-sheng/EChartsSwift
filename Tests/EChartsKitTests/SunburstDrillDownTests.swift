// Verifies the sunburst drill-down interaction (chart/sunburst/sunburstAction.ts + SunburstView
// _initEvents/_rootToNode + treeHelper.retrieveTargetInfo):
//
//   - dispatching `sunburstRootToNode` with a child node RE-ROOTS the series (getViewRoot() becomes the
//     clicked node) and the layout re-lays-out around it (the clicked node's children now span a wider
//     ring — the "clicked node spans the full ring" invariant), and
//   - dispatching `sunburstRootToNode` back to the tree's virtual root (what a centre click does — roots
//     UP to viewRoot.parentNode) restores the original view root and layout.
import XCTest
@testable import EChartsKit
@testable import ZRenderKit

final class SunburstDrillDownTests: XCTestCase {

    private func option() -> [String: Any] {
        [
            "animation": false,
            "series": [["type": "sunburst", "radius": ["0%", "90%"],
                        "data": [
                            ["name": "Grandpa", "children": [
                                ["name": "Uncle Leo", "value": 15.0, "children": [
                                    ["name": "Cousin Jack", "value": 2.0],
                                    ["name": "Cousin Mary", "value": 5.0]
                                ]],
                                ["name": "Father", "value": 10.0, "children": [
                                    ["name": "Me", "value": 5.0],
                                    ["name": "Brother Peter", "value": 1.0]
                                ]]
                            ]],
                            ["name": "Nancy", "children": [
                                ["name": "Uncle Nike", "value": 10.0, "children": [
                                    ["name": "Cousin Betty", "value": 1.0],
                                    ["name": "Cousin Jenny", "value": 2.0]
                                ]]
                            ]]
                        ]] as [String: Any]]
        ]
    }

    private func angleSpan(_ node: TreeNode) -> Double {
        guard let layout = node.getLayout() as? [String: Any] else { return .nan }
        let s = (layout["startAngle"] as? Double) ?? 0
        let e = (layout["endAngle"] as? Double) ?? 0
        return abs(e - s)
    }

    func test_root_to_node_drills_down_and_center_rolls_up() {
        let ec = EChartsSlim(width: 400, height: 400)
        ec.setOption(option())

        guard let model = ec.getModel()?.getSeriesByType("sunburst").first as? SunburstSeriesModel else {
            return XCTFail("no sunburst series model")
        }
        guard let tree = model.getData().tree else { return XCTFail("no tree") }
        let virtualRoot = tree.root!
        // virtualRoot.children[0] == "Grandpa"; its child[0] == "Uncle Leo".
        let grandpa = virtualRoot.children[0]
        XCTAssertEqual(grandpa.name, "Grandpa")
        let uncleLeo = grandpa.children[0]
        XCTAssertEqual(uncleLeo.name, "Uncle Leo")

        // Baseline: the whole tree is shown, view root is the virtual root.
        XCTAssertTrue(model.getViewRoot() === virtualRoot, "initial view root should be the tree root")
        let spanBefore = angleSpan(uncleLeo)
        XCTAssertGreaterThan(spanBefore, 0, "Uncle Leo should have a non-zero arc before drilling")

        // Drill down: click "Grandpa" → dispatch sunburstRootToNode with that node.
        var drill = Payload(type: "sunburstRootToNode")
        drill.other["seriesId"] = model.id
        drill.other["targetNode"] = grandpa
        ec.dispatchAction(drill)

        // View root re-rooted to Grandpa, and its subtree re-laid-out: Uncle Leo now spans a WIDER arc
        // (15/25 of the ring vs 15/35 nested under the full tree).
        XCTAssertTrue(model.getViewRoot() === grandpa, "view root should be the drilled-to node")
        let spanAfter = angleSpan(uncleLeo)
        XCTAssertGreaterThan(spanAfter, spanBefore + 1e-6,
                             "drilled node's child should span a wider ring after re-root")

        // Centre click rolls UP to viewRoot.parentNode == virtualRoot: dispatch with the virtual root.
        var rollUp = Payload(type: "sunburstRootToNode")
        rollUp.other["seriesId"] = model.id
        rollUp.other["targetNode"] = virtualRoot
        ec.dispatchAction(rollUp)

        XCTAssertTrue(model.getViewRoot() === virtualRoot, "centre click should root back up to the parent")
        XCTAssertEqual(angleSpan(uncleLeo), spanBefore, accuracy: 1e-6,
                       "layout should restore to the original arc after rolling back up")
    }
}
