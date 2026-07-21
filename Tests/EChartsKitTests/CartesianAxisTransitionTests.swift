// CartesianAxisView.render calls `groupTransition(oldAxisGroup, this._axisGroup, axisModel)`:
// elements of the previous render are matched to the fresh ones by `anid`, snapped back to the old
// pose and then animated to the new one. This guards the wiring (a refactor of the `_axisGroup`
// capture order or of the `anid` prefixes would silently turn it back into a no-op).
//
// NOTE: only x/y/rotation interpolate today (axis labels); the `shape` leg is discrete — see the
// PORT-TODO on the `groupTransition` call in CartesianAxisView.render.
import XCTest
@testable import EChartsKit
@testable import ZRenderKit

final class CartesianAxisTransitionTests: XCTestCase {

    /// Collect every element (recursively) whose `anid` starts with `prefix`.
    private func collect(_ el: Element, prefix: String, into out: inout [Element]) {
        if let anid = el.anid, anid.hasPrefix(prefix) { out.append(el) }
        if let g = el as? Group { for c in g.children() { collect(c, prefix: prefix, into: &out) } }
    }

    private func option(_ cats: [String], _ data: [Double]) -> [String: Any] {
        [
            "animation": true,
            "animationDurationUpdate": 300,
            "xAxis": ["type": "category", "data": cats],
            "yAxis": ["type": "value"],
            "series": [["type": "bar", "data": data]]
        ]
    }

    func test_axis_labels_animate_across_renders() {
        let ec = ECharts(width: 400, height: 300)
        ec.setOption(option(["a", "b", "c"], [10.0, 20.0, 30.0]))

        var before: [Element] = []
        collect(ec.getRoot(), prefix: "label_", into: &before)
        XCTAssertGreaterThan(before.count, 0, "axis labels should carry an `anid`")
        // First render has no old group -> groupTransition is a no-op (upstream `if (!g1 || !g2)`).
        XCTAssertEqual(before.reduce(0) { $0 + $1.animators.count }, 0,
                       "no axis-label animator on the first render")

        // Re-render with more categories and a wider value range: the category labels `label_0/1/2`
        // and the value labels `label_10/20/30` keep their `anid` but land at a new x/y.
        ec.setOption(option(["a", "b", "c", "d", "e"], [10.0, 20.0, 30.0, 40.0, 50.0]))

        var after: [Element] = []
        collect(ec.getRoot(), prefix: "label_", into: &after)
        XCTAssertGreaterThan(after.count, 0, "axis labels should still be built on re-render")

        let matched = after.filter { el in
            guard let anid = el.anid else { return false }
            return before.contains { $0.anid == anid }
        }
        XCTAssertGreaterThan(matched.count, 0, "some labels should carry an `anid` seen in the old group")
        XCTAssertGreaterThan(matched.reduce(0) { $0 + $1.animators.count }, 0,
                             "groupTransition should animate re-rendered axis labels matched by `anid`")
    }
}
