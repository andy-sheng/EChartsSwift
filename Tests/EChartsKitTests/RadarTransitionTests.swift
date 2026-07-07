// Radar vertices scale in (scaleX/scaleY 0→1) when animation is on. Faithful to Symbol.ts first-create.
import XCTest
@testable import EChartsKit
@testable import ZRenderKit

final class RadarTransitionTests: XCTestCase {
    private func firstVertex(_ el: Element) -> Path? {
        if let p = el as? Path, p.name == "vertex" { return p }
        if let g = el as? Group { for c in g.children() { if let h = firstVertex(c) { return h } } }
        return nil
    }
    private func option(_ animation: Bool) -> [String: Any] {
        [
            "animation": animation,
            "radar": ["indicator": [["name": "A", "max": 100.0], ["name": "B", "max": 100.0], ["name": "C", "max": 100.0]]],
            "series": [["type": "radar", "data": [["value": [60.0, 70.0, 80.0]]]]]
        ]
    }
    func test_vertex_scales_in_when_animation_on() {
        let ec = EChartsSlim(width: 400, height: 400); ec.setOption(option(true))
        guard let v = firstVertex(ec.getRoot()) else { return XCTFail("no radar vertex (name==\"vertex\")") }
        let anim = v.animators.first { $0.getTrack("scaleX") != nil }
        XCTAssertNotNil(anim, "vertex should have a scaleX animator when animation on")
        if let track = anim?.getTrack("scaleX") {
            track.step(v, 0.0); XCTAssertEqual(v.scaleX, 0.0, accuracy: 1e-9, "track starts at 0")
            track.step(v, 1.0); XCTAssertEqual(v.scaleX, 1.0, accuracy: 1e-9, "track ends at 1")
        }
    }
    func test_vertex_full_scale_when_animation_off() {
        let ec = EChartsSlim(width: 400, height: 400); ec.setOption(option(false))
        guard let v = firstVertex(ec.getRoot()) else { return XCTFail("no radar vertex") }
        XCTAssertEqual(v.animators.count, 0, "no animator when animation off")
        XCTAssertEqual(v.scaleX, 1.0, accuracy: 1e-9, "vertex at full scale when off")
    }
}
