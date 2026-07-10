// Morph-fidelity tail: SunburstView now persists its per-node SunburstPiece sectors and MORPHS them
// on a same-node-count merge-mode setOption value change (which recomputes every wedge's angular span)
// instead of rebuilding-and-snapping. This asserts a sector ELEMENT is identity-reused across the value
// change and schedules a shape-morph animator (the wedge sweeps to its new span), and that a node-count
// change rebuilds without duplication. Modelled on LineMorphTests.
import XCTest
@testable import EChartsKit
@testable import ZRenderKit

final class SunburstMorphTests: XCTestCase {

    // Collect every SunburstPiece sector in the chart views' groups, in traversal order.
    private func sectors(_ ec: ECharts) -> [SunburstPiece] {
        var out: [SunburstPiece] = []
        for v in ec.testChartViews {
            _ = v.group.traverse({ el in
                if let s = el as? SunburstPiece { out.append(s) }
                return false
            })
        }
        return out
    }

    // A 2-level tree: root ring "A"/"B", each with two leaf children → same node count when only
    //   the leaf VALUES change (angles recompute, node count unchanged → morph).
    private func option(_ values: (Double, Double, Double, Double)) -> [String: Any] {
        [
            "animation": true,
            "series": [["type": "sunburst", "radius": ["0%", "90%"],
                        "data": [
                            ["name": "A", "children": [
                                ["name": "a1", "value": values.0],
                                ["name": "a2", "value": values.1]
                            ]],
                            ["name": "B", "children": [
                                ["name": "b1", "value": values.2],
                                ["name": "b2", "value": values.3]
                            ]]
                        ]] as [String: Any]]
        ]
    }

    func test_sector_morphs_on_value_change() {
        let ec = ECharts(width: 400, height: 400)
        ec.setOption(option((3, 1, 2, 2)))

        let before = sectors(ec)
        XCTAssertGreaterThan(before.count, 0, "sunburst render produced sectors")
        let firstIdentity = before.first!

        // Clear the first render's sweep-open entrance animators.
        for v in ec.testChartViews { _ = v.group.traverse({ el in _ = el.stopAnimation(nil); return false }) }

        // Merge-mode value change, SAME node count → every wedge morphs to its new angular span.
        ec.setOption(["series": [["type": "sunburst", "data": [
            ["name": "A", "children": [
                ["name": "a1", "value": 1.0],
                ["name": "a2", "value": 3.0]
            ]],
            ["name": "B", "children": [
                ["name": "b1", "value": 4.0],
                ["name": "b2", "value": 1.0]
            ]]
        ]]]])

        let after = sectors(ec)
        // (1) A sector element is identity-reused (not rebuilt).
        XCTAssertEqual(before.count, after.count, "node count unchanged across the value change")
        XCTAssertTrue(after.contains(where: { $0 === firstIdentity }),
                      "a SunburstPiece sector is identity-reused across the value change (morph, not rebuild)")

        // (2) At least one reused sector schedules a shape-morph animator (the wedge sweeps).
        let animating = after.reduce(0) { $0 + $1.animators.count }
        XCTAssertGreaterThan(animating, 0,
                             "a same-count value change must schedule wedge-sweep animators (morph)")
    }

    func test_node_count_change_rebuilds_without_duplication() {
        let ec = ECharts(width: 400, height: 400)
        ec.setOption(option((3, 1, 2, 2)))
        let baseCount = sectors(ec).count
        XCTAssertGreaterThan(baseCount, 0)

        // Add a child to "B" → node count grows → rebuild fresh (no stale duplicate sectors).
        ec.setOption(["series": [["type": "sunburst", "data": [
            ["name": "A", "children": [
                ["name": "a1", "value": 3.0],
                ["name": "a2", "value": 1.0]
            ]],
            ["name": "B", "children": [
                ["name": "b1", "value": 2.0],
                ["name": "b2", "value": 2.0],
                ["name": "b3", "value": 2.0]
            ]]
        ]]]])

        // Exactly one more sector than before (the added leaf) — no duplicated old sectors left behind.
        XCTAssertEqual(sectors(ec).count, baseCount + 1,
                       "a node-count change rebuilds fresh, one sector per node, no duplication")
    }
}
