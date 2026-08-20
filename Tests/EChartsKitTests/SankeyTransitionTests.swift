// Sankey uses the upstream first-render clip reveal. Nodes stay at final opacity while a clip rect grows
// across the entire diagram; with animation off no clip animation is installed.
import XCTest
@testable import EChartsKit
@testable import ZRenderKit

final class SankeyTransitionTests: XCTestCase {
    private func firstClipRect(_ el: Element) -> Rect? {
        if let clip = el.getClipPath() as? Rect { return clip }
        if let group = el as? Group {
            for child in group.children() {
                if let clip = firstClipRect(child) { return clip }
            }
        }
        return nil
    }

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
    func test_diagram_clip_reveals_when_animation_on() {
        let ec = ECharts(width: 460, height: 360); ec.setOption(option(true))
        guard let clip = firstClipRect(ec.getRoot()) else { return XCTFail("no sankey clip rect") }
        guard let animator = clip.animators.first(where: { $0.targetName == "shape" }) else {
            return XCTFail("sankey clip should have a shape animator when animation is on")
        }
        XCTAssertNotNil(animator.getTrack("width"), "sankey clip should reveal from left to right")
    }
    func test_node_final_opacity_when_animation_off() {
        let ec = ECharts(width: 460, height: 360); ec.setOption(option(false))
        guard let rect = firstNode(ec.getRoot()) else { return XCTFail("no sankey node rect") }
        XCTAssertEqual(rect.animators.count, 0, "no animator when animation off")
        XCTAssertGreaterThan(rect.pathStyle.opacity ?? 0, 0.0, "node must be at final (visible) opacity when off — not invisible")
    }
}
