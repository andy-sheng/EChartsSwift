// Parallel polylines fade in (style.opacity 0→final) when animation on, and are at final opacity with no
// animator when off (the invisible-line guard). ParallelView's static port has no upstream line fade
// (upstream uses a clip-reveal); this reuses the shared opacity-fade infra (FunnelView/HeatmapView idiom).
import XCTest
@testable import EChartsKit
@testable import ZRenderKit

final class ParallelTransitionTests: XCTestCase {
    private func firstLine(_ el: Element) -> ZRenderKit.Polyline? {
        if let p = el as? ZRenderKit.Polyline { return p }
        if let g = el as? Group { for c in g.children() { if let h = firstLine(c) { return h } } }
        return nil
    }
    private func option(_ animation: Bool) -> [String: Any] {
        [
            "animation": animation,
            "parallelAxis": [
                ["dim": 0, "name": "Price"]  as [String: Any],
                ["dim": 1, "name": "Amount"] as [String: Any],
                ["dim": 2, "name": "Volume"] as [String: Any]
            ],
            "parallel": ["left": "10%", "right": "12%", "top": "10%", "bottom": "10%"] as [String: Any],
            "series": [["type": "parallel",
                        "lineStyle": ["width": 2] as [String: Any],
                        "data": [
                            [12.0, 230.0,  8.0],
                            [24.0, 140.0, 15.0]
                        ]] as [String: Any]]
        ]
    }
    func test_line_fades_in_when_animation_on() {
        let ec = EChartsSlim(width: 520, height: 380); ec.setOption(option(true))
        guard let line = firstLine(ec.getRoot()) else { return XCTFail("no parallel polyline") }
        // The fade-in animates a partial "style" dict ({opacity}); the resulting sub-animator is targeted
        // at "style" and carries an "opacity" leaf track (same idiom as FunnelTransitionTests).
        let anim = line.animators.first { $0.targetName == "style" }
        XCTAssertNotNil(anim, "parallel line should have a style (opacity) animator when animation on")
    }
    func test_line_final_opacity_when_animation_off() {
        let ec = EChartsSlim(width: 520, height: 380); ec.setOption(option(false))
        guard let line = firstLine(ec.getRoot()) else { return XCTFail("no parallel polyline") }
        XCTAssertEqual(line.animators.count, 0, "no animator when animation off")
        XCTAssertGreaterThan(line.pathStyle.opacity ?? 0, 0.0,
            "line must be at final (visible) opacity when off — not invisible")
    }
}
