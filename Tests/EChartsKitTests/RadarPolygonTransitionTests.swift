// Radar area polygon scales in from the radar center (scaleX/scaleY 0→1) when animation is on.
// Port stand-in for upstream's collapse-to-center points enter (points animation not ported).
import XCTest
@testable import EChartsKit
@testable import ZRenderKit

final class RadarPolygonTransitionTests: XCTestCase {
    // Match the area polygon distinctly from the vertex symbols (named "vertex") and the outline.
    private func firstPolygon(_ el: Element) -> Path? {
        if let p = el as? Path, p.name == "radarPolygon" { return p }
        if let g = el as? Group { for c in g.children() { if let h = firstPolygon(c) { return h } } }
        return nil
    }
    private func option(_ animation: Bool) -> [String: Any] {
        [
            "animation": animation,
            "radar": ["indicator": [["name": "A", "max": 100.0], ["name": "B", "max": 100.0], ["name": "C", "max": 100.0]]],
            "series": [["type": "radar", "data": [["value": [60.0, 70.0, 80.0], "areaStyle": ["opacity": 0.7]]]]]
        ]
    }
    func test_polygon_scales_in_when_animation_on() {
        let ec = EChartsSlim(width: 400, height: 400); ec.setOption(option(true))
        guard let p = firstPolygon(ec.getRoot()) else { return XCTFail("no radar polygon (name==\"radarPolygon\")") }
        let anim = p.animators.first { $0.getTrack("scaleX") != nil }
        XCTAssertNotNil(anim, "polygon should have a scaleX animator when animation on")
        if let track = anim?.getTrack("scaleX") {
            track.step(p, 0.0); XCTAssertEqual(p.scaleX, 0.0, accuracy: 1e-9, "track starts at 0")
            track.step(p, 1.0); XCTAssertEqual(p.scaleX, 1.0, accuracy: 1e-9, "track ends at 1")
        }
    }
    func test_polygon_full_scale_when_animation_off() {
        let ec = EChartsSlim(width: 400, height: 400); ec.setOption(option(false))
        guard let p = firstPolygon(ec.getRoot()) else { return XCTFail("no radar polygon") }
        XCTAssertEqual(p.animators.count, 0, "no animator when animation off")
        XCTAssertEqual(p.scaleX, 1.0, accuracy: 1e-9, "polygon at full scale when off")
        XCTAssertEqual(p.scaleY, 1.0, accuracy: 1e-9, "polygon at full scale when off")
    }
}
