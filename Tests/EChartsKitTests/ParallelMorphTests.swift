import XCTest
@testable import EChartsKit
@testable import ZRenderKit

// Transition-fidelity tail: ParallelView now persists its per-item polylines and MORPHS them on a
// same-item-count merge-mode setOption value change (each line's shape.points slide to the new
// geometry) instead of rebuilding the whole data group and snapping. This asserts the polyline
// ELEMENT itself is reused and schedules a shape-morph animator; and that an item-count change
// rebuilds a single set of lines with no stale duplication.
final class ParallelMorphTests: XCTestCase {

    // Collect every Polyline in the chart views' groups.
    private func polylines(_ ec: ECharts) -> [ZRenderKit.Polyline] {
        var out: [ZRenderKit.Polyline] = []
        for v in ec.testChartViews {
            _ = v.group.traverse({ el in
                if let p = el as? ZRenderKit.Polyline { out.append(p) }
                return false
            })
        }
        return out
    }

    private func baseOption(_ data: [[Double]]) -> [String: Any] {
        [
            "animation": true,
            "parallelAxis": [
                ["dim": 0, "name": "Price"]  as [String: Any],
                ["dim": 1, "name": "Amount"] as [String: Any],
                ["dim": 2, "name": "Volume"] as [String: Any]
            ],
            "parallel": ["left": "10%", "right": "12%", "top": "10%", "bottom": "10%"] as [String: Any],
            "series": [["type": "parallel",
                        "animation": true,
                        "lineStyle": ["width": 2] as [String: Any],
                        "data": data] as [String: Any]]
        ]
    }

    func testPolylineMorphsOnValueChange() {
        let ec = ECharts(width: 520, height: 380)
        ec.setOption(baseOption([[12, 230, 8], [24, 140, 15]]))
        let before = polylines(ec)
        XCTAssertEqual(before.count, 2, "two parallel rows → two polylines")
        // Clear the first render's enter/fade animators.
        for v in ec.testChartViews { _ = v.group.traverse({ el in _ = el.stopAnimation(nil); return false }) }

        // Merge-mode value change, SAME item count → the polylines morph in place.
        ec.setOption(["series": [["type": "parallel", "data": [[40, 90, 20], [8, 200, 5]]] as [String: Any]]])

        let after = polylines(ec)
        XCTAssertEqual(after.count, 2, "still two polylines after the value change (no duplication)")
        // (1) polyline identity reused (not rebuilt).
        XCTAssertTrue(before[0] === after[0] && before[1] === after[1],
                      "polylines reused across the value change (not rebuilt)")
        // (2) each reused polyline schedules a shape-morph animator.
        XCTAssertGreaterThan(after[0].animators.count, 0,
                             "polyline must schedule a shape-morph animator on a same-count value change")
        XCTAssertGreaterThan(after[1].animators.count, 0,
                             "second polyline must also schedule a shape-morph animator")
    }

    func testItemCountChangeRebuildsWithoutDuplication() {
        let ec = ECharts(width: 520, height: 380)
        ec.setOption(baseOption([[12, 230, 8], [24, 140, 15]]))
        XCTAssertEqual(polylines(ec).count, 2)

        // (3) item-count change → rebuild fresh; exactly the new count, no leftover lines.
        ec.setOption(["series": [["type": "parallel",
                                  "data": [[1, 2, 3], [4, 5, 6], [7, 8, 9]]] as [String: Any]]])
        XCTAssertEqual(polylines(ec).count, 3,
                       "an item-count change rebuilds one polyline per row, no stale duplicates")
    }
}
