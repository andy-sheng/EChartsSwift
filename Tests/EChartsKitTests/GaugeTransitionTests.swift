// Gauge pointer sweeps from startAngle to the value angle (rotation transform) when animation on.
// Faithful to GaugeView.ts pointer initProps({rotation}).
import XCTest
@testable import EChartsKit
@testable import ZRenderKit

final class GaugeTransitionTests: XCTestCase {
    private func firstPointer(_ el: Element) -> Path? {
        if let p = el as? PointerPath { return p }
        if let g = el as? Group { for c in g.children() { if let h = firstPointer(c) { return h } } }
        return nil
    }
    private func option(_ animation: Bool) -> [String: Any] {
        ["animation": animation,
         "series": [["type": "gauge", "min": 0.0, "max": 100.0, "data": [["value": 50.0]]]]]
    }
    func test_pointer_sweeps_when_animation_on() {
        let ec = ECharts(width: 400, height: 400); ec.setOption(option(true))
        guard let p = firstPointer(ec.getRoot()) else { return XCTFail("no gauge pointer (PointerPath)") }
        let anim = p.animators.first { $0.getTrack("rotation") != nil }
        XCTAssertNotNil(anim, "pointer should have a rotation animator when animation on")
        if let track = anim?.getTrack("rotation") {
            track.step(p, 0.0); let atStart = p.rotation
            track.step(p, 1.0); let atEnd = p.rotation
            XCTAssertNotEqual(atStart, atEnd, accuracy: 1e-9, "rotation track must carry a real start→value delta")
        }
    }
    func test_pointer_final_rotation_when_animation_off() {
        let ec = ECharts(width: 400, height: 400); ec.setOption(option(false))
        guard let p = firstPointer(ec.getRoot()) else { return XCTFail("no gauge pointer") }
        XCTAssertEqual(p.animators.count, 0, "no animator when animation off")
    }
}
