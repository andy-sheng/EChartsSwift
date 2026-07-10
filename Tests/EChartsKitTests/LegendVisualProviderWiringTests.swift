import XCTest
@testable import EChartsKit

// LegendVisualProvider (visual/LegendVisualProvider.swift) supplies the legend component with a series'
// DATA-ITEM names + per-item icon visuals, for charts whose legend entries are item names (pie slices /
// radar indicators / funnel items / themeRiver layers / chord nodes) or graph CATEGORIES. It was ported +
// wired on pie/radar; this asserts the remaining upstream consumers (funnel/chord/themeRiver/graph) are
// wired too, so their legends auto-enumerate the data-item / category names.
final class LegendVisualProviderWiringTests: XCTestCase {

    private func provider(_ opt: [String: Any]) -> LegendVisualProviderLike? {
        let ec = ECharts(width: 320, height: 220)
        ec.setOption(opt)
        return ec.getModel()?.getSeriesByIndex(0)?.legendVisualProvider as? LegendVisualProviderLike
    }

    func testFunnelExposesItemNames() {
        let p = provider(["series": [["type": "funnel",
            "data": [["name": "A", "value": 10.0], ["name": "B", "value": 20.0]]] as [String: Any]]])
        XCTAssertNotNil(p, "funnel wires a legendVisualProvider")
        XCTAssertEqual(p?.getAllNames(), ["A", "B"], "funnel legend enumerates its data-item names")
    }

    func testChordExposesNodeNames() {
        let p = provider(["series": [["type": "chord",
            "data": [["name": "n1"], ["name": "n2"]],
            "links": [["source": "n1", "target": "n2", "value": 1.0]]] as [String: Any]]])
        XCTAssertNotNil(p, "chord wires a legendVisualProvider")
        XCTAssertTrue((p?.getAllNames().contains("n1")) ?? false, "chord legend enumerates node names")
    }

    func testThemeRiverWired() {
        let p = provider(["singleAxis": ["type": "time"] as [String: Any],
            "series": [["type": "themeRiver",
                "data": [[1.0, 10.0, "x"], [2.0, 5.0, "y"]]] as [String: Any]]])
        XCTAssertNotNil(p, "themeRiver wires a legendVisualProvider")
        XCTAssertTrue((p?.getAllNames().contains("x")) ?? false, "themeRiver legend enumerates layer names")
    }

    func testGraphExposesCategoryNames() {
        let p = provider(["series": [["type": "graph",
            "categories": [["name": "cat0"], ["name": "cat1"]],
            "data": [["name": "a", "category": 0], ["name": "b", "category": 1]],
            "links": []] as [String: Any]]])
        XCTAssertNotNil(p, "graph wires a legendVisualProvider (categories)")
        XCTAssertEqual(p?.getAllNames(), ["cat0", "cat1"], "graph legend enumerates CATEGORY names, not node names")
    }
}
