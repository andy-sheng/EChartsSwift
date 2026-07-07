// Graph nodes scale in (scaleX/scaleY 0→1) when animation is on. Faithful to Symbol.ts first-create.
import XCTest
@testable import EChartsKit
@testable import ZRenderKit

final class GraphTransitionTests: XCTestCase {
    private func firstNode(_ el: Element) -> Path? {
        if let p = el as? Path, p.name == "node" { return p }
        if let g = el as? Group { for c in g.children() { if let h = firstNode(c) { return h } } }
        return nil
    }
    private func option(_ animation: Bool) -> [String: Any] {
        [
            "animation": animation,
            "series": [[
                "type": "graph", "layout": "none",
                "data": [["name": "n1", "x": 100.0, "y": 100.0], ["name": "n2", "x": 200.0, "y": 200.0]],
                "links": [["source": "n1", "target": "n2"]]
            ]]
        ]
    }
    func test_node_scales_in_when_animation_on() {
        let ec = EChartsSlim(width: 400, height: 400); ec.setOption(option(true))
        guard let node = firstNode(ec.getRoot()) else { return XCTFail("no graph node (name==\"node\")") }
        let anim = node.animators.first { $0.getTrack("scaleX") != nil }
        XCTAssertNotNil(anim, "node should have a scaleX animator when animation on")
        if let track = anim?.getTrack("scaleX") {
            track.step(node, 0.0); XCTAssertEqual(node.scaleX, 0.0, accuracy: 1e-9, "track starts at 0")
            track.step(node, 1.0); XCTAssertEqual(node.scaleX, 1.0, accuracy: 1e-9, "track ends at 1")
        }
    }
    func test_node_full_scale_when_animation_off() {
        let ec = EChartsSlim(width: 400, height: 400); ec.setOption(option(false))
        guard let node = firstNode(ec.getRoot()) else { return XCTFail("no graph node") }
        XCTAssertEqual(node.animators.count, 0, "no animator when animation off")
        XCTAssertEqual(node.scaleX, 1.0, accuracy: 1e-9, "node at full scale when off")
    }
}
