// Behavioral-oracle tests for the data/Tree.swift port (Phase 9: sunburst/tree vertical).
//
// Upstream echarts ships NO Jest spec for Tree/sunburst (only HTML visual tests + data
// fixtures under test/), so there is no spec to translate. Instead these tests pin the
// load-bearing Tree ALGORITHMS — hierarchy construction, depth/height, preorder/postorder
// traversal, ancestor/containment queries, and value read-back through the real SeriesData
// data pipeline (initData) — so a future refactor or upstream re-sync can regress-check
// against them. Structure mirrors CartesianCoordTests (hand-authored oracle, not a port).

import XCTest
@testable import EChartsKit

final class TreeUnitTests: XCTestCase {

    // Build the fixture hierarchy via the real `Tree.createTree` (exercises buildHierarchy,
    // updateDepthAndHeight, prepareSeriesDataSchema, SeriesData.initData, linkSeriesData):
    //
    //   root (10)
    //    ├─ A (3)
    //    │   └─ A1 (1)
    //    └─ B (6)
    private func makeFixtureTree() -> Tree {
        let dataRoot: TreeNodeOption = [
            "name": "root",
            "value": 10,
            "children": [
                [
                    "name": "A",
                    "value": 3,
                    "children": [
                        ["name": "A1", "value": 1]
                    ]
                ] as [String: Any],
                ["name": "B", "value": 6] as [String: Any]
            ]
        ]
        let hostModel = Model([:])
        return Tree.createTree(dataRoot, hostModel)
    }

    // MARK: - construction + depth/height

    func testHierarchyAndDepthHeight() {
        let tree = makeFixtureTree()

        XCTAssertEqual(tree.root.name, "root")
        XCTAssertEqual(tree.root.depth, 0)
        // upstream `updateDepthAndHeight` sets `height = maxChildHeight + 1`, so a leaf has
        // height 1. root→A→A1 (deepest) ⇒ A1=1, A=2, root=3.
        XCTAssertEqual(tree.root.height, 3)
        XCTAssertEqual(tree.root.children.count, 2)

        let a = tree.root.getNodeById("A")
        let a1 = tree.root.getNodeById("A1")
        let b = tree.root.getNodeById("B")
        XCTAssertNotNil(a); XCTAssertNotNil(a1); XCTAssertNotNil(b)
        XCTAssertEqual(a?.depth, 1)
        XCTAssertEqual(a1?.depth, 2)
        XCTAssertEqual(b?.depth, 1)
        // A subtree (A→A1): A1 leaf = 1, A = 2. Leaf B = 1.
        XCTAssertEqual(a?.height, 2)
        XCTAssertEqual(b?.height, 1)
    }

    // MARK: - traversal order

    func testPreorderTraversal() {
        let tree = makeFixtureTree()
        var visited: [String] = []
        // single closure arg → dispatched as the callback (preorder is the default order).
        tree.eachNode({ (n: TreeNode) -> Any? in
            visited.append(n.name)
            return nil
        })
        XCTAssertEqual(visited, ["root", "A", "A1", "B"])
    }

    func testPostorderTraversal() {
        let tree = makeFixtureTree()
        var visited: [String] = []
        tree.eachNode(["order": "postorder"], { (n: TreeNode) -> Any? in
            visited.append(n.name)
            return nil
        })
        XCTAssertEqual(visited, ["A1", "A", "B", "root"])
    }

    // Returning a truthy value from a preorder callback suppresses descent into that
    // node's children (upstream: `suppressVisitSub = cb.call(...)`).
    func testPreorderSuppressChildren() {
        let tree = makeFixtureTree()
        var visited: [String] = []
        tree.eachNode({ (n: TreeNode) -> Any? in
            visited.append(n.name)
            return n.name == "A" ? true : nil   // suppress A's subtree (A1)
        })
        XCTAssertEqual(visited, ["root", "A", "B"])   // A1 skipped
    }

    // MARK: - ancestor / containment queries

    func testAncestorsAndContains() {
        let tree = makeFixtureTree()
        let a1 = tree.root.getNodeById("A1")!
        let b = tree.root.getNodeById("B")!

        // getAncestors order is [root, child, grandchild, ...].
        XCTAssertEqual(tree.root.getNodeById("A1").map { $0.getAncestors(true).map { $0.name } }!,
                       ["root", "A", "A1"])
        XCTAssertEqual(a1.getAncestors(false).map { $0.name }, ["root", "A"])

        XCTAssertTrue(tree.root.contains(a1))
        XCTAssertFalse(b.contains(a1))
        XCTAssertTrue(tree.root.isAncestorOf(a1))
        XCTAssertFalse(b.isAncestorOf(a1))
    }

    // MARK: - value read-back through the data pipeline

    func testGetValueThroughDataStore() {
        let tree = makeFixtureTree()
        let a = tree.root.getNodeById("A")!
        let b = tree.root.getNodeById("B")!
        // getValue() reads the 'value' dimension from the SeriesData store wired by createTree.
        XCTAssertEqual(a.getValue() as? Double, 3)
        XCTAssertEqual(b.getValue() as? Double, 6)
    }
}
