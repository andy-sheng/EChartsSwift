// Boxplot box Polygons fade in (style.opacity 0→final) when animation on, and are at final opacity with
// no animator when off (the invisible-box guard). Port deviation: upstream grows the box points-array
// shape via initProps({shape:{points}}); points-array shape animation is shared-file work, so the port
// applies the closest existing-infra pattern — the opacity fade (see FunnelTransitionTests).
import XCTest
@testable import EChartsKit
@testable import ZRenderKit

final class BoxplotTransitionTests: XCTestCase {
    private func firstBox(_ el: Element) -> BoxPath? {
        if let p = el as? BoxPath { return p }
        if let g = el as? Group { for c in g.children() { if let h = firstBox(c) { return h } } }
        return nil
    }
    private func option(_ animation: Bool) -> [String: Any] {
        ["animation": animation,
         "grid": ["left": 50.0, "top": 20.0, "width": 440.0, "height": 260.0] as [String: Any],
         "xAxis": ["type": "category", "data": ["G1", "G2", "G3"]] as [String: Any],
         "yAxis": ["type": "value"] as [String: Any],
         "series": [["type": "boxplot",
                     "data": [[10.0, 22.0, 28.0, 35.0, 50.0],
                              [15.0, 25.0, 33.0, 40.0, 55.0],
                              [8.0, 18.0, 24.0, 30.0, 44.0]]] as [String: Any]]]
    }
    func test_box_fades_in_when_animation_on() {
        let ec = EChartsSlim(width: 520, height: 340); ec.setOption(option(true))
        guard let box = firstBox(ec.getRoot()) else { return XCTFail("no boxplot BoxPath") }
        let anim = box.animators.first { $0.targetName == "style" }
        XCTAssertNotNil(anim, "boxplot box should have a style (opacity) animator when animation on")
    }
    func test_box_final_opacity_when_animation_off() {
        let ec = EChartsSlim(width: 520, height: 340); ec.setOption(option(false))
        guard let box = firstBox(ec.getRoot()) else { return XCTFail("no boxplot BoxPath") }
        XCTAssertEqual(box.animators.count, 0, "no animator when animation off")
        XCTAssertGreaterThan(box.pathStyle?.opacity ?? 0, 0.0, "box must be at final (visible) opacity when off — not invisible")
    }
}
