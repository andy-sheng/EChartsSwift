// END-TO-END RENDER TESTS for the Phase-10 hierarchical chart verticals: sunburst (Sector per tree
// node), treemap (Rect per tree node), tree (Symbol + parent/child edge per node). Each drives
// EChartsSlim with a real hierarchical option and asserts elements reach the ZRenderKit scene. These
// also guard the SeriesData.cloneShallow tree re-link fix: without firing linkSeriesData's cloneShallow
// injection, `getData().tree` would be nil after dataTaskReset and every hierarchical series would
// render empty (sunburst force-unwraps `tree!` and would crash).
import XCTest
import ZRenderKit
@testable import EChartsKit

final class HierarchicalChartsRenderTests: XCTestCase {
    func testSunburstRendersSectors() {
        let ec = EChartsSlim(width: 400, height: 400)
        ec.setOption([
            "series": [["type": "sunburst", "radius": ["0%", "90%"],
                        "data": [["name": "A", "children": [["name": "A1", "value": 3.0],
                                                            ["name": "A2", "value": 5.0]]],
                                 ["name": "B", "value": 4.0]]] as [String: Any]]
        ])
        var sectors = 0
        _ = ec.getRoot().traverse { el in if el is ZRenderKit.Sector { sectors += 1 }; return false }
        XCTAssertGreaterThan(sectors, 0, "sunburst nodes → Sector wedges")
    }

    func testTreemapRendersRects() {
        let ec = EChartsSlim(width: 460, height: 360)
        ec.setOption([
            "series": [["type": "treemap", "left": "5%", "top": 20.0, "width": "90%", "height": 320.0,
                        "data": [["name": "a", "value": 10.0, "children": [["name": "a1", "value": 4.0],
                                                                          ["name": "a2", "value": 6.0]]],
                                 ["name": "b", "value": 20.0]]] as [String: Any]]
        ])
        var rects = 0
        _ = ec.getRoot().traverse { el in if el is ZRenderKit.Rect { rects += 1 }; return false }
        XCTAssertGreaterThan(rects, 0, "treemap nodes → Rects")
    }

    func testTreeRendersNodesAndEdges() {
        let ec = EChartsSlim(width: 460, height: 360)
        ec.setOption([
            "series": [["type": "tree", "left": "10%", "right": "10%", "top": "10%", "bottom": "10%",
                        "orient": "LR",
                        "data": [["name": "root", "children": [
                            ["name": "A", "children": [["name": "A1"], ["name": "A2"]]],
                            ["name": "B"]]]]] as [String: Any]]
        ])
        var paths = 0
        _ = ec.getRoot().traverse { el in if el is ZRenderKit.Path { paths += 1 }; return false }
        XCTAssertGreaterThan(paths, 0, "tree nodes → symbol + edge Paths")
    }
}
