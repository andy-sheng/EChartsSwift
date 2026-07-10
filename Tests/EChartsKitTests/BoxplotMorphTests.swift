// Transition-fidelity tail: BoxplotView now persists its SeriesData and diffs (add/update/remove)
// on a merge-mode setOption value change, morphing each box's `points`-array shape to its new
// whisker/box geometry instead of clearing the group and rebuilding-and-snapping. This asserts the
// box ELEMENT itself is identity-reused across a same-count value change and schedules a real
// shape-morph animator, and that a count change rebuilds without stale duplication.
import XCTest
@testable import EChartsKit
@testable import ZRenderKit

final class BoxplotMorphTests: XCTestCase {

    // Depth-first find the i-th BoxPath across all chart views' groups (index 0 = first box).
    private func box(_ ec: ECharts, _ index: Int) -> BoxPath? {
        var found: [BoxPath] = []
        for v in ec.testChartViews {
            _ = v.group.traverse({ el in
                if let p = el as? BoxPath { found.append(p) }
                return false
            })
        }
        return index < found.count ? found[index] : nil
    }

    private func boxCount(_ ec: ECharts) -> Int {
        var n = 0
        for v in ec.testChartViews {
            _ = v.group.traverse({ el in if el is BoxPath { n += 1 }; return false })
        }
        return n
    }

    private func baseOption(_ data: [[Double]]) -> [String: Any] {
        ["animation": true,
         "grid": ["left": 50.0, "top": 20.0, "width": 440.0, "height": 260.0] as [String: Any],
         "xAxis": ["type": "category", "data": ["G1", "G2"]] as [String: Any],
         "yAxis": ["type": "value"] as [String: Any],
         "series": [["type": "boxplot", "animation": true, "data": data] as [String: Any]]]
    }

    // Same item count value change → each box element is IDENTITY-reused and morphs (real animator).
    func testBoxMorphsOnValueChange() {
        let ec = ECharts(width: 520, height: 340)
        ec.setOption(baseOption([[1, 2, 3, 4, 5], [2, 3, 4, 5, 6]]))

        let box0Before = box(ec, 0)
        let box1Before = box(ec, 1)
        XCTAssertNotNil(box0Before, "first render produced a boxplot BoxPath")
        XCTAssertNotNil(box1Before, "first render produced a second BoxPath")

        // Clear the first render's entrance/grow animators.
        for v in ec.testChartViews { _ = v.group.traverse({ el in _ = el.stopAnimation(nil); return false }) }

        // Merge-mode value change, same item count → the boxes morph.
        ec.setOption(["series": [["type": "boxplot", "data": [[2, 4, 6, 8, 10], [1, 2, 3, 4, 5]]] as [String: Any]]])

        let box0After = box(ec, 0)
        // 1. Element IDENTITY reused across the change (not rebuilt).
        XCTAssertTrue(box0Before === box0After, "box 0 reused across the value change (not rebuilt)")
        XCTAssertTrue(box1Before === box(ec, 1), "box 1 reused across the value change (not rebuilt)")

        // 2. The reused box schedules a REAL shape-morph animator.
        XCTAssertGreaterThan(box0After!.animators.count, 0,
                             "reused box must schedule a shape-morph animator on a same-count value change")
        XCTAssertNotNil(box0After!.animators.first { $0.targetName == "shape" },
                        "the morph animator targets the `shape` (points) — real geometry tween")
    }

    // An item add/remove rebuilds fresh (no stale duplication) — the reuse-safety invariant holds.
    func testItemCountChangeRebuildsWithoutDuplication() {
        let ec = ECharts(width: 520, height: 340)
        ec.setOption(baseOption([[1, 2, 3, 4, 5], [2, 3, 4, 5, 6]]))
        XCTAssertEqual(boxCount(ec), 2, "two boxes for two data items")

        // Grow to three items → three boxes, no duplicate leftover.
        ec.setOption(["xAxis": ["type": "category", "data": ["G1", "G2", "G3"]] as [String: Any],
                      "series": [["type": "boxplot",
                                  "data": [[1, 2, 3, 4, 5], [2, 3, 4, 5, 6], [3, 4, 5, 6, 7]]] as [String: Any]]])
        XCTAssertEqual(boxCount(ec), 3, "item-count grow adds one box, no duplicate")

        // Shrink to one item → one box, the removed boxes are gone.
        ec.setOption(["xAxis": ["type": "category", "data": ["G1"]] as [String: Any],
                      "series": [["type": "boxplot", "data": [[1, 2, 3, 4, 5]]] as [String: Any]]])
        XCTAssertEqual(boxCount(ec), 1, "item-count shrink removes boxes, no stale duplication")
    }
}
