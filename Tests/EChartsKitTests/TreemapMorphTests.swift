import XCTest
@testable import EChartsKit
@testable import ZRenderKit

// Transition-fidelity tail (batch-A morph idiom): TreemapView now persists its per-node graphic
// elements and MORPHS on a same-node-count merge-mode value change instead of rebuild-and-snap. A
// value change re-lays-out the squarify rects, so each node group slides and its bg/content rect
// resizes (updateProps shape) to the new slot. This asserts a node rect is identity-reused across the
// change and carries a shape-morph animator, and that a node-COUNT change rebuilds cleanly (no
// duplicated tiles).
final class TreemapMorphTests: XCTestCase {

    // All treemap tile rects across the chart views, in a stable pre-order.
    private func allRects(_ ec: ECharts) -> [ZRenderKit.Rect] {
        var out: [ZRenderKit.Rect] = []
        for v in ec.testChartViews {
            _ = v.group.traverse({ el in
                if let r = el as? ZRenderKit.Rect { out.append(r) }
                return false
            })
        }
        return out
    }

    private func stopAllAnimation(_ ec: ECharts) {
        for v in ec.testChartViews {
            _ = v.group.traverse({ el in _ = el.stopAnimation(nil); return false })
        }
    }

    private func series(_ data: [[String: Any]]) -> [String: Any] {
        [
            "animation": true,
            "series": [[
                "type": "treemap",
                "animation": true,
                "left": 0.0, "top": 0.0, "width": 400.0, "height": 400.0,
                "roam": false, "nodeClick": false, "breadcrumb": ["show": false],
                "data": data
            ] as [String: Any]]
        ]
    }

    func testTileMorphsOnValueChange() {
        let ec = ECharts(width: 400, height: 400)
        ec.setOption(series([
            ["name": "a", "value": 10.0],
            ["name": "b", "value": 20.0],
            ["name": "c", "value": 30.0]
        ]))
        let before = allRects(ec)
        XCTAssertGreaterThan(before.count, 0, "treemap produced node rects")
        // Clear the first render's enter/opacity animators so we measure only the morph.
        stopAllAnimation(ec)

        // Merge-mode value change, SAME node count → the tiles morph (re-laid-out to new sizes).
        ec.setOption(["series": [[
            "type": "treemap",
            "data": [
                ["name": "a", "value": 30.0],
                ["name": "b", "value": 5.0],
                ["name": "c", "value": 15.0]
            ]
        ] as [String: Any]]])

        let after = allRects(ec)
        // (1) A node rect is identity-reused across the value change (not rebuilt).
        let beforeSet = Set(before.map { ObjectIdentifier($0) })
        let reused = after.filter { beforeSet.contains(ObjectIdentifier($0)) }
        XCTAssertGreaterThan(reused.count, 0, "at least one node rect reused across the value change")

        // (2) A reused rect carries a shape-morph animator (the tile slides/resizes).
        let morphing = reused.contains { rect in
            rect.animators.contains { $0.targetName == "shape" }
        }
        XCTAssertTrue(morphing, "a reused node rect must schedule a shape-morph animator on a same-count value change")
    }

    func testNodeCountChangeRebuildsWithoutDuplication() {
        let ec = ECharts(width: 400, height: 400)
        ec.setOption(series([
            ["name": "a", "value": 10.0],
            ["name": "b", "value": 20.0],
            ["name": "c", "value": 30.0]
        ]))
        let firstCount = allRects(ec).count
        XCTAssertGreaterThan(firstCount, 0)

        // Two fewer nodes → node-count change → rebuild fresh (storage reset, container wiped).
        ec.setOption(["series": [[
            "type": "treemap",
            "data": [
                ["name": "a", "value": 10.0]
            ]
        ] as [String: Any]]])

        let afterCount = allRects(ec).count
        // A single node → strictly fewer rects than the 3-node render, proving no stale duplication.
        XCTAssertLessThan(afterCount, firstCount, "a node-count shrink rebuilds without leaving stale tiles")
        XCTAssertGreaterThan(afterCount, 0, "the surviving node still renders")
    }
}
