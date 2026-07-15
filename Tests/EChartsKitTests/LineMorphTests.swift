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
        guard let area = namedPath(ec, "area") as? ECPolygon else {
            return XCTFail("area render produced a named band")
        }
        let oldAreaPts = (area.shape as! ECPolygonShape).points
        _ = ec.testChartViews.first?.group.traverse({ el in _ = el.stopAnimation(nil); return false })

        ec.setOption(["series": [["type": "line", "areaStyle": [:], "data": [8, 2, 6, 3]]]])

        // Faithful upstream mechanism (LineView._doUpdateAnimation via lineAnimationDiff): the area band is
        //   REUSED (morphed), not rebuilt. Its own animator only animates `stackedOnPoints` (constant for a
        //   flat baseline), while its top edge follows the polyline's morph (the polyline schedules the
        //   shape animator; the area's points are re-synced to it — CONVENTIONS §3/§4).
        XCTAssertTrue(area === (namedPath(ec, "area") as? ECPolygon), "area band reused across the value change (not rebuilt)")
        let newAreaPts = (area.shape as! ECPolygonShape).points
        XCTAssertNotEqual(oldAreaPts, newAreaPts, "the area's top edge updates to the new data (morph, not stale)")
        // The polyline (the morph driver) is reused and schedules a shape-morph animator — the marker that
        //   this went through the morph path (lineAnimationDiff), NOT a fresh rebuild + clip-reveal replay.
        guard let line = namedPath(ec, "line") as? ECPolyline else { return XCTFail("no reused polyline") }
        XCTAssertNotNil(line.animators.first(where: { $0.getTrack("points") != nil }),
                        "polyline must schedule a shape-morph animator on a same-shape value change")
        // The area's top edge tracks the polyline's points (shared-geometry sync).
        XCTAssertEqual(newAreaPts, (line.shape as! ECPolylineShape).points,
                       "the area's top edge follows the polyline's morphed points")
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
