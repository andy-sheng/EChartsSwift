import XCTest
@testable import EChartsKit
@testable import ZRenderKit

// Transition-fidelity tail: LineView now persists its polyline/area/SymbolDraw and morphs on a
// same-count value change (merge-mode setOption) instead of rebuilding. This asserts the polyline
// ELEMENT itself schedules a shape-morph animator (the line slides to the new values), and that the
// area band morphs too — not just the point symbols.
final class LineMorphTests: XCTestCase {

    // Find the named Polyline / area band inside the line chart view's group.
    private func namedPath(_ ec: ECharts, _ name: String) -> Path? {
        var found: Path?
        for v in ec.testChartViews {
            _ = v.group.traverse({ el in
                if found == nil, let p = el as? Path, p.name == name { found = p }
                return false
            })
        }
        return found
    }

    func testPolylineMorphsOnValueChange() {
        let ec = ECharts(width: 400, height: 300)
        ec.setOption(["animation": true,
                      "xAxis": ["type": "category", "data": ["a", "b", "c", "d"]],
                      "yAxis": ["type": "value"],
                      "series": [["type": "line", "animation": true, "data": [1, 3, 2, 4]]]])
        let line = namedPath(ec, "line")
        XCTAssertNotNil(line, "line render produced a named polyline")
        // Clear the first render's enter/draw-on animators.
        _ = ec.testChartViews.first?.group.traverse({ el in _ = el.stopAnimation(nil); return false })

        // Merge-mode value change, same point count → the polyline morphs.
        ec.setOption(["series": [["type": "line", "data": [8, 2, 6, 3]]]])

        // The SAME polyline instance is reused and carries a shape-morph animator.
        XCTAssertTrue(line === namedPath(ec, "line"), "polyline reused across the value change (not rebuilt)")
        XCTAssertGreaterThan(line!.animators.count, 0,
                             "polyline must schedule a shape-morph animator on a same-count value change")
    }

    func testAreaBandMorphsOnValueChange() {
        let ec = ECharts(width: 400, height: 300)
        ec.setOption(["animation": true,
                      "xAxis": ["type": "category", "data": ["a", "b", "c", "d"]],
                      "yAxis": ["type": "value"],
                      "series": [["type": "line", "animation": true, "areaStyle": [:], "data": [1, 3, 2, 4]]]])
        let area = namedPath(ec, "area")
        XCTAssertNotNil(area, "area render produced a named band")
        _ = ec.testChartViews.first?.group.traverse({ el in _ = el.stopAnimation(nil); return false })

        ec.setOption(["series": [["type": "line", "areaStyle": [:], "data": [8, 2, 6, 3]]]])

        XCTAssertTrue(area === namedPath(ec, "area"), "area band reused across the value change")
        XCTAssertGreaterThan(area!.animators.count, 0, "area band must schedule a morph animator")
    }

    // A point add/remove rebuilds fresh (no stale duplication) — the reuse-safety invariant holds.
    func testPointCountChangeRebuildsWithoutDuplication() {
        let ec = ECharts(width: 400, height: 300)
        ec.setOption(["xAxis": ["type": "category", "data": ["a", "b", "c"]],
                      "yAxis": ["type": "value"],
                      "series": [["type": "line", "data": [1, 2, 3]]]])
        func lineCount() -> Int {
            var n = 0
            for v in ec.testChartViews { _ = v.group.traverse({ el in if (el as? Path)?.name == "line" { n += 1 }; return false }) }
            return n
        }
        XCTAssertEqual(lineCount(), 1)
        ec.setOption(["xAxis": ["type": "category", "data": ["a", "b", "c", "d", "e"]],
                      "series": [["type": "line", "data": [1, 2, 3, 4, 5]]]])
        XCTAssertEqual(lineCount(), 1, "a point-count change rebuilds a single polyline, no duplicate")
    }
}
