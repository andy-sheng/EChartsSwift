// Proves the Phase-3 deferred gap (PORT_STATUS §10 #8 / §11a) is CLOSED: `animateTo({shape:{…}})`
// now drives the value-type RectShape's fields in place through ShapeAnimationAccessor, instead of
// being inert. The Phase-3 ElementAnimation port had to skip exactly this (shape sub-bag not wired,
// animators.count == 0); here we assert a real shape animator is created AND that stepping its Clip
// interpolates `rect.shape.height` end-to-end (Animator + Track + Clip + linear easing → the live
// value-type struct).

import XCTest
@testable import ZRenderKit

final class ShapeAnimationWiringTests: XCTestCase {

    func test_shape_height_animates_through_path_animateTo() throws {
        let rect = Rect()
        var s = RectShape()
        s.x = 0; s.y = 0; s.width = 10; s.height = 0
        rect.shape = s

        var cfg = ElementAnimateConfig()
        cfg.duration = 1000
        cfg.easing = .named("linear")
        rect.animateTo(["shape": ["height": 100.0]], cfg)

        // The key win vs Phase 3: a shape animator now exists (was 0 — the deferred surface).
        XCTAssertEqual(rect.animators.count, 1, "expected one shape animator from animateTo({shape:{height}})")

        guard let clip = rect.animators.first?.getClip() else {
            return XCTFail("no clip — shape track was inert")
        }

        // The Clip records its _startTime on the first step (that frame is the t=0 baseline),
        // exactly as Animation.update drives it from wall-clock — so prime at 0 first.
        _ = clip.step(0, 0)
        XCTAssertEqual((rect.shape as? RectShape)?.height ?? -1, 0.0, accuracy: 1e-9, "baseline at t=0")

        // 50% of a linear tween 0→100 → 50, written back into the live value-type shape.
        _ = clip.step(500, 500)
        XCTAssertEqual((rect.shape as? RectShape)?.height ?? -1, 50.0, accuracy: 1e-6)

        // End → exactly 100 (and width/x untouched).
        _ = clip.step(1000, 500)
        XCTAssertEqual((rect.shape as? RectShape)?.height ?? -1, 100.0, accuracy: 1e-9)
        XCTAssertEqual((rect.shape as? RectShape)?.width ?? -1, 10.0, accuracy: 1e-9)
    }
}
