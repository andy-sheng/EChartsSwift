// Sankey node rects fade in (style.opacity 0→final) when animation on, and are at final opacity with no
// animator when off (the invisible-node guard). Faithful to the FunnelView initProps({style:{opacity}})
// entrance pattern applied to the sankey node Rects.
import XCTest
@testable import EChartsKit
@testable import ZRenderKit

final class SankeyTransitionTests: XCTestCase {
    private func firstNode(_ el: Element) -> ZRenderKit.Rect? {
        if el.name == "node", let r = el as? ZRenderKit.Rect { return r }
        if let g = el as? Group { for c in g.children() { if let h = firstNode(c) { return h } } }
        return nil
    }
    private func option(_ animation: Bool) -> [String: Any] {
        ["animation": animation,
         "series": [["type": "sankey",
                     "left": "5%", "right": "20%", "top": "5%", "bottom": "5%",
                     "nodeWidth": 20.0, "nodeGap": 8.0,
                     "data": [["name": "a"], ["name": "b"], ["name": "c"], ["name": "d"]],
                     "links": [["source": "a", "target": "b", "value": 5.0],
                               ["source": "a", "target": "c", "value": 3.0],
                               ["source": "b", "target": "d", "value": 4.0],
                               ["source": "c", "target": "d", "value": 2.0]]] as [String: Any]]]
    }
    func test_node_fades_in_when_animation_on() {
        let ec = EChartsSlim(width: 460, height: 360); ec.setOption(option(true))
        guard let rect = firstNode(ec.getRoot()) else { return XCTFail("no sankey node rect") }
        // The fade-in animates a partial "style" dict ({opacity}); the resulting sub-animator is
        // targeted at "style" and carries an "opacity" leaf track.
        let anim = rect.animators.first { $0.targetName == "style" }
        XCTAssertNotNil(anim, "sankey node should have a style (opacity) animator when animation on")
    }
    func test_node_final_opacity_when_animation_off() {
        let ec = EChartsSlim(width: 460, height: 360); ec.setOption(option(false))
        guard let rect = firstNode(ec.getRoot()) else { return XCTFail("no sankey node rect") }
        XCTAssertEqual(rect.animators.count, 0, "no animator when animation off")
        XCTAssertGreaterThan(rect.pathStyle.opacity ?? 0, 0.0, "node must be at final (visible) opacity when off — not invisible")
    }
}
