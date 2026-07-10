import XCTest
@testable import EChartsKit
@testable import ZRenderKit

// Transition-fidelity tail: RadarView now persists its per-item Polygon/Polyline (+ vertex symbols) and
// morphs on a same-count value change (merge-mode setOption) instead of rebuilding-and-snapping. This
// asserts the polygon ELEMENT itself is identity-reused across a value change and schedules a shape-morph
// animator (the data ring slides to its new vertices), and that a count change rebuilds without leaking
// duplicate elements.
final class RadarMorphTests: XCTestCase {

    // Find the first named Path (e.g. "radarPolygon") anywhere under the radar chart view's group.
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

    // Count every named Path across the radar chart views.
    private func countNamed(_ ec: ECharts, _ name: String) -> Int {
        var n = 0
        for v in ec.testChartViews {
            _ = v.group.traverse({ el in if (el as? Path)?.name == name { n += 1 }; return false })
        }
        return n
    }

    private func baseIndicatorOption(_ dataItems: [[String: Any]]) -> [String: Any] {
        return [
            "animation": true,
            "radar": [
                "indicator": [
                    ["name": "A", "max": 10],
                    ["name": "B", "max": 10],
                    ["name": "C", "max": 10]
                ]
            ],
            "series": [[
                "type": "radar",
                "animation": true,
                "data": dataItems
            ]]
        ]
    }

    func testPolygonMorphsOnValueChange() {
        let ec = ECharts(width: 400, height: 400)
        ec.setOption(baseIndicatorOption([["value": [3, 4, 5]]]))

        let poly = namedPath(ec, "radarPolygon")
        XCTAssertNotNil(poly, "radar render produced a named polygon")
        // Clear the first render's collapse-to-center / scale-in entrance animators.
        _ = ec.testChartViews.first?.group.traverse({ el in _ = el.stopAnimation(nil); return false })

        // Merge-mode value change, same indicator + item count → the polygon morphs (real animator).
        ec.setOption(["series": [["type": "radar", "animation": true, "data": [["value": [8, 2, 9]]]]]])

        let after = namedPath(ec, "radarPolygon")
        XCTAssertTrue(poly === after, "polygon reused across the value change (not rebuilt)")
        XCTAssertGreaterThan(poly!.animators.count, 0,
                             "polygon must schedule a shape-morph animator on a same-count value change")
    }

    func testPolylineMorphsOnValueChange() {
        let ec = ECharts(width: 400, height: 400)
        ec.setOption(baseIndicatorOption([["value": [3, 4, 5]]]))

        let line = namedPath(ec, "radarPolyline")
        XCTAssertNotNil(line, "radar render produced a named polyline")
        _ = ec.testChartViews.first?.group.traverse({ el in _ = el.stopAnimation(nil); return false })

        ec.setOption(["series": [["type": "radar", "animation": true, "data": [["value": [8, 2, 9]]]]]])

        XCTAssertTrue(line === namedPath(ec, "radarPolyline"), "polyline reused across the value change")
        XCTAssertGreaterThan(line!.animators.count, 0,
                             "polyline must schedule a shape-morph animator on a same-count value change")
    }

    // An item-count change rebuilds fresh — a single polygon per item, no stale duplication.
    func testItemCountChangeRebuildsWithoutDuplication() {
        let ec = ECharts(width: 400, height: 400)
        ec.setOption(baseIndicatorOption([["value": [3, 4, 5]]]))
        XCTAssertEqual(countNamed(ec, "radarPolygon"), 1)

        // Add a second data item → the item count changed, so it rebuilds.
        ec.setOption(["series": [["type": "radar", "animation": true,
                                  "data": [["value": [3, 4, 5]], ["value": [6, 1, 8]]]]]])
        XCTAssertEqual(countNamed(ec, "radarPolygon"), 2, "an item-count change rebuilds, no duplicate")
    }

    // An indicator (vertex) count change rebuilds fresh — no stale duplication.
    func testIndicatorCountChangeRebuildsWithoutDuplication() {
        let ec = ECharts(width: 400, height: 400)
        ec.setOption(baseIndicatorOption([["value": [3, 4, 5]]]))
        XCTAssertEqual(countNamed(ec, "radarPolygon"), 1)

        // Four indicators now (was three) → the vertex count changed, so it rebuilds fresh.
        ec.setOption([
            "radar": ["indicator": [
                ["name": "A", "max": 10], ["name": "B", "max": 10],
                ["name": "C", "max": 10], ["name": "D", "max": 10]
            ]],
            "series": [["type": "radar", "animation": true, "data": [["value": [3, 4, 5, 6]]]]]
        ])
        XCTAssertEqual(countNamed(ec, "radarPolygon"), 1,
                       "an indicator-count change rebuilds a single polygon, no duplicate")
    }
}
