// Proves NormalBoxPathShape now exposes its `points` (number[][]) to the keyed animation seam, so a
// candlestick box can tween its 8 points via initProps(["shape": ["points": …]]) (the Animator's
// 2D-array interpolation), instead of snapping. Guards the shape-accessor added for the points-grow.
import XCTest
@testable import EChartsKit
@testable import ZRenderKit

final class CandlestickPointsAnimTests: XCTestCase {

    func test_normalbox_points_animate_through_the_shape_accessor() {
        let box = NormalBoxPath(["shape": NormalBoxPathShape() as PathShape])
        // Collapsed start: all 4 body points at the same baseline y = 50.
        var start = NormalBoxPathShape()
        start.points = [[0, 50], [10, 50], [10, 50], [0, 50]]
        box.shape = start

        // Animate toward a real box (a 10x40 quad). animateTo drives the shape sub-bag via the accessor.
        var cfg = ElementAnimateConfig()
        cfg.duration = 1000
        cfg.easing = .named("linear")
        box.animateTo(["shape": ["points": [[0.0, 10.0], [10.0, 10.0], [10.0, 50.0], [0.0, 50.0]]]], cfg)

        XCTAssertEqual(box.animators.count, 1, "expected one points animator from animateTo({shape:{points}})")
        guard let clip = box.animators.first?.getClip() else { return XCTFail("no clip — points track inert") }

        _ = clip.step(0, 0)
        // Midpoint: the first corner's y interpolates 50 -> 10, so at 50% it is 30.
        _ = clip.step(500, 500)
        let mid = (box.shape as? NormalBoxPathShape)?.points ?? []
        XCTAssertEqual(mid.count, 4, "point count preserved")
        XCTAssertEqual(mid[0][1], 30.0, accuracy: 1e-6, "corner y tweens 50 -> 10 (mid 30)")

        _ = clip.step(1000, 500)
        let end = (box.shape as? NormalBoxPathShape)?.points ?? []
        XCTAssertEqual(end[0][1], 10.0, accuracy: 1e-9, "reaches the final points")
    }
}
