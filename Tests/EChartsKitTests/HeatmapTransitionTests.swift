// Upstream heatmap cells do not add a per-cell entrance fade. They are painted at final opacity on
// the initial render regardless of the global animation switch (updates may still morph).
import XCTest
@testable import EChartsKit
@testable import ZRenderKit

final class HeatmapTransitionTests: XCTestCase {
    // The grid/coordinate-system background is also a Rect, so match the per-datum cell by its "item"
    // name (set by HeatmapView, mirroring FunnelPiece/PieView) — not just the first Rect in the tree.
    private func firstCell(_ el: Element) -> ZRenderKit.Rect? {
        if let r = el as? ZRenderKit.Rect, r.name == "item" { return r }
        if let g = el as? Group { for c in g.children() { if let h = firstCell(c) { return h } } }
        return nil
    }
    private func option(_ animation: Bool) -> [String: Any] {
        ["animation": animation,
         "grid": ["left": 50.0, "top": 20.0, "right": 20.0, "bottom": 40.0] as [String: Any],
         "xAxis": ["type": "category", "data": ["Mon", "Tue", "Wed", "Thu", "Fri"]] as [String: Any],
         "yAxis": ["type": "category", "data": ["AM", "PM", "Eve"]] as [String: Any],
         "visualMap": [
            "type": "continuous",
            "min": 0.0,
            "max": 10.0,
            "calculable": true,
            "inRange": ["color": ["#313695", "#74add1", "#fee090", "#f46d43", "#a50026"]] as [String: Any]
         ] as [String: Any],
         "series": [[
            "type": "heatmap",
            "data": [
                [0.0, 0.0, 1.0], [1.0, 0.0, 3.0], [2.0, 0.0, 5.0], [3.0, 0.0, 7.0], [4.0, 0.0, 9.0],
                [0.0, 1.0, 2.0], [1.0, 1.0, 4.0], [2.0, 1.0, 6.0], [3.0, 1.0, 8.0], [4.0, 1.0, 10.0],
                [0.0, 2.0, 0.0], [1.0, 2.0, 2.0], [2.0, 2.0, 4.0], [3.0, 2.0, 6.0], [4.0, 2.0, 8.0]
            ]
         ] as [String: Any]]]
    }
    func test_cell_has_no_extra_entrance_fade_when_animation_on() {
        let ec = ECharts(width: 480, height: 320); ec.setOption(option(true))
        guard let rect = firstCell(ec.getRoot()) else { return XCTFail("no heatmap cell rect") }
        XCTAssertTrue(rect.animators.isEmpty, "heatmap must not invent a per-cell entrance fade")
        XCTAssertGreaterThan(rect.pathStyle.opacity ?? 0, 0.0)
    }
    func test_cell_final_opacity_when_animation_off() {
        let ec = ECharts(width: 480, height: 320); ec.setOption(option(false))
        guard let rect = firstCell(ec.getRoot()) else { return XCTFail("no heatmap cell rect") }
        XCTAssertEqual(rect.animators.count, 0, "no animator when animation off")
        XCTAssertGreaterThan(rect.pathStyle.opacity ?? 0, 0.0, "cell must be at final (visible) opacity when off — not invisible")
    }
}
