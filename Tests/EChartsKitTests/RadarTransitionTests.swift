// Radar vertices are full-size at their final coordinates from t=0. The upstream add-path calls
// initProps on the polygon first (setToFinal), then passes polyline.shape.points to updateSymbols, so
// its nominal old points already equal the final points and no symbol position track is produced.
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
    func test_vertex_is_static_at_final_position_during_polygon_entrance() {
        let ec = ECharts(width: 400, height: 400); ec.setOption(option(true))
        guard let v = firstVertex(ec.getRoot()) else { return XCTFail("no radar vertex (name==\"vertex\")") }
        let xAnim = v.animators.first { $0.getTrack("x") != nil }
        let yAnim = v.animators.first { $0.getTrack("y") != nil }
        XCTAssertNil(xAnim, "first-render vertex x is already final")
        XCTAssertNil(yAnim, "first-render vertex y is already final")
        XCTAssertNil(v.animators.first { $0.getTrack("scaleX") != nil },
                     "radar vertices keep their final size; they do not scale in")
        XCTAssertGreaterThan(v.scaleX, 0, "vertex is visible at full configured size")
    }
    func test_vertex_full_scale_when_animation_off() {
        let ec = ECharts(width: 400, height: 400); ec.setOption(option(false))
        guard let v = firstVertex(ec.getRoot()) else { return XCTFail("no radar vertex") }
        XCTAssertEqual(v.animators.count, 0, "no animator when animation off")
        XCTAssertGreaterThan(v.scaleX, 0, "vertex is at its configured full size when animation is off")
    }
}
