// Funnel pieces fade in (style.opacity 0→final) when animation on, and are at final opacity with no
// animator when off (the invisible-piece guard). Faithful to FunnelView.ts initProps({style:{opacity}}).
import XCTest
@testable import EChartsKit
@testable import ZRenderKit

final class FunnelTransitionTests: XCTestCase {
    private func firstPiece(_ el: Element) -> ZRenderKit.Polygon? {
        if let p = el as? ZRenderKit.Polygon { return p }
        if let g = el as? Group { for c in g.children() { if let h = firstPiece(c) { return h } } }
        return nil
    }
    private func option(_ animation: Bool) -> [String: Any] {
        ["animation": animation,
         "series": [["type": "funnel", "data": [["value": 60.0, "name": "a"], ["value": 40.0, "name": "b"]]]]]
    }
    func test_piece_fades_in_when_animation_on() {
        let ec = ECharts(width: 400, height: 400); ec.setOption(option(true))
        guard let poly = firstPiece(ec.getRoot()) else { return XCTFail("no funnel polygon") }
        // The fade-in animates a partial "style" dict ({opacity}); the resulting sub-animator is
        // targeted at "style" and carries an "opacity" leaf track (see EffectScatterAnimationTests'
        // ripple opacity animator for the same idiom).
        let anim = poly.animators.first { $0.targetName == "style" }
        XCTAssertNotNil(anim, "funnel piece should have a style (opacity) animator when animation on")
    }
    func test_piece_final_opacity_when_animation_off() {
        let ec = ECharts(width: 400, height: 400); ec.setOption(option(false))
        guard let poly = firstPiece(ec.getRoot()) else { return XCTFail("no funnel polygon") }
        XCTAssertEqual(poly.animators.count, 0, "no animator when animation off")
        XCTAssertGreaterThan(poly.pathStyle.opacity ?? 0, 0.0, "piece must be at final (visible) opacity when off — not invisible")
    }
}
