// Entering bars animate their rect shape when the series has animation on, and are at final geometry
// instantly when off. Uses the ec render tree (BarView.render → data.diff enter → initProps).
import XCTest
@testable import EChartsKit
@testable import ZRenderKit

final class BarTransitionTests: XCTestCase {

    private func firstBarRect(_ el: Element) -> Rect? {
        if let r = el as? Rect { return r }
        if let g = el as? Group { for c in g.children() { if let hit = firstBarRect(c) { return hit } } }
        return nil
    }

    private func option(_ animation: Bool) -> [String: Any] {
        [
            "animation": animation,
            "xAxis": ["type": "category", "data": ["a", "b", "c"]],
            "yAxis": ["type": "value"],
            "series": [["type": "bar", "data": [10.0, 20.0, 30.0]]]
        ]
    }

    func test_bar_enter_animates_when_animation_on() {
        let ec = EChartsSlim(width: 400, height: 300)
        ec.setOption(option(true))
        guard let rect = firstBarRect(ec.getRoot()) else { return XCTFail("no bar Rect") }
        XCTAssertGreaterThan(rect.animators.count, 0, "bar should have an enter animator when animation is on")
    }

    func test_bar_no_animator_when_animation_off() {
        let ec = EChartsSlim(width: 400, height: 300)
        ec.setOption(option(false))
        guard let rect = firstBarRect(ec.getRoot()) else { return XCTFail("no bar Rect") }
        XCTAssertEqual(rect.animators.count, 0, "bar should have no animator when animation is off")
        // Bar layout height is signed (negative when the value's pixel coordinate is above the
        // baseline's — matches upstream `barLayout`'s `height = coord[1] - baseCoord`; canvas Rect
        // handles negative dimensions fine). Assert non-zero rather than positive: the enter-path
        // element creator zeros width/height only when animation is enabled (elementCreatorCartesian2D),
        // so "at final geometry" here means "not the animated-from-zero placeholder".
        XCTAssertNotEqual((rect.shape as? RectShape)?.height ?? 0, 0, "bar rect should be at final (non-zero) height")
    }
}
