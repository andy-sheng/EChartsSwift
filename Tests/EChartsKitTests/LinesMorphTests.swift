import XCTest
@testable import EChartsKit
@testable import ZRenderKit

// Transition-fidelity tail: LinesView now persists its per-item line elements (keyed by data index)
// and morphs them on a same-count value change (merge-mode setOption) instead of `group.removeAll()`-ing
// and rebuilding. This asserts the line ELEMENT itself is identity-reused and schedules a shape-morph
// animator (it slides to the new coords), and that a datum count change rebuilds without duplication.
final class LinesMorphTests: XCTestCase {

    // Find the first named "line" Path inside the lines chart view's group.
    private func firstLine(_ ec: ECharts) -> Path? {
        var found: Path?
        for v in ec.testChartViews {
            _ = v.group.traverse({ el in
                if found == nil, let p = el as? Path, p.name == "line" { found = p }
                return false
            })
        }
        return found
    }

    private func lineCount(_ ec: ECharts) -> Int {
        var n = 0
        for v in ec.testChartViews {
            _ = v.group.traverse({ el in if (el as? Path)?.name == "line" { n += 1 }; return false })
        }
        return n
    }

    private func baseOption(_ lines: [[String: Any]]) -> [String: Any] {
        return [
            "animation": true,
            "xAxis": ["type": "value"],
            "yAxis": ["type": "value"],
            "series": [[
                "type": "lines",
                "animation": true,
                "coordinateSystem": "cartesian2d",
                "data": lines
            ] as [String: Any]]
        ]
    }

    func testLineMorphsOnValueChange() {
        let ec = ECharts(width: 400, height: 300)
        ec.setOption(baseOption([["coords": [[0, 0], [10, 10]]]]))
        let line = firstLine(ec)
        XCTAssertNotNil(line, "lines render produced a named line element")

        // Clear the first render's enter animators.
        _ = ec.testChartViews.first?.group.traverse({ el in _ = el.stopAnimation(nil); return false })

        // Merge-mode value change, SAME line count, coords changed → the line morphs.
        ec.setOption(["series": [[
            "type": "lines", "animation": true, "coordinateSystem": "cartesian2d",
            "data": [["coords": [[0, 0], [20, 5]]]]
        ] as [String: Any]]])

        // 1. The SAME element instance is reused across the change (not rebuilt).
        XCTAssertTrue(line === firstLine(ec), "line element reused across the value change")
        // 2. It carries a real shape-morph animator.
        XCTAssertGreaterThan(line!.animators.count, 0,
                             "line must schedule a shape-morph animator on a same-count value change")
    }

    // A datum count change rebuilds fresh (no stale duplication) — the reuse-safety invariant holds.
    func testDatumCountChangeRebuildsWithoutDuplication() {
        let ec = ECharts(width: 400, height: 300)
        ec.setOption(baseOption([["coords": [[0, 0], [10, 10]]]]))
        XCTAssertEqual(lineCount(ec), 1)

        ec.setOption(["series": [[
            "type": "lines", "animation": true, "coordinateSystem": "cartesian2d",
            "data": [["coords": [[0, 0], [10, 10]]], ["coords": [[2, 2], [8, 6]]]]
        ] as [String: Any]]])
        XCTAssertEqual(lineCount(ec), 2, "a datum count change rebuilds without duplicating lines")

        // And back down — still no stale leftovers.
        ec.setOption(["series": [[
            "type": "lines", "animation": true, "coordinateSystem": "cartesian2d",
            "data": [["coords": [[0, 0], [10, 10]]]]
        ] as [String: Any]]])
        XCTAssertEqual(lineCount(ec), 1, "a datum count decrease drops the surplus line")
    }
}
