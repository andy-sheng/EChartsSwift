// Cartesian line draws on via a growing clip rect: with animation on, the line group's clipPath is a
// Rect whose width animates from 0 to full; with animation off, the clip is at full width (no animator).
// Faithful to createGridClipPath + LineView.setClipPath.
import XCTest
@testable import EChartsKit
@testable import ZRenderKit

final class LineTransitionTests: XCTestCase {

    // Find the first Group carrying a clipPath (the lineGroup) and return that clipPath as a Rect.
    private func firstClipRect(_ el: Element) -> Rect? {
        if let cp = el.getClipPath() as? Rect { return cp }
        if let g = el as? Group { for c in g.children() { if let hit = firstClipRect(c) { return hit } } }
        return nil
    }

    private func option(_ animation: Bool) -> [String: Any] {
        [
            "animation": animation,
            "xAxis": ["type": "category", "data": ["a", "b", "c", "d"]],
            "yAxis": ["type": "value"],
            "series": [["type": "line", "data": [10.0, 20.0, 15.0, 25.0]]]
        ]
    }

    func test_line_clip_grows_when_animation_on() {
        let ec = EChartsSlim(width: 400, height: 300)
        ec.setOption(option(true))
        guard let clip = firstClipRect(ec.getRoot()) else { return XCTFail("no line clip rect") }
        // NOTE: initProps' `enter` config sets `setToFinal: true` (basicTransition.swift), which jumps
        //   the live `clip.shape` to its FINAL value synchronously (same behavior documented in
        //   PieTransitionTests/ScatterTransitionTests) — so we don't assert a synchronous collapsed
        //   read here. The shape props animate under the "shape" sub-animator (animateToShallow
        //   recurses into a dedicated Animator whose target is the shape accessor, not the Rect
        //   itself — matching PieTransitionTests' pattern), so step via `animator.getTarget()`.
        guard let animator = clip.animators.first(where: { $0.targetName == "shape" }) else {
            return XCTFail("no shape-targeted animator on the clip rect")
        }
        guard let track = animator.getTrack("width") else {
            return XCTFail("no width track on the shape animator")
        }
        let target = animator.getTarget()
        track.step(target, 0.0)
        XCTAssertEqual((clip.shape as? RectShape)?.width ?? -1, 0.0, accuracy: 1e-6, "clip starts collapsed (width 0)")
        track.step(target, 1.0)
        XCTAssertGreaterThan((clip.shape as? RectShape)?.width ?? 0, 0.0, "clip ends at full width")
    }

    func test_line_clip_full_when_animation_off() {
        let ec = EChartsSlim(width: 400, height: 300)
        ec.setOption(option(false))
        guard let clip = firstClipRect(ec.getRoot()) else { return XCTFail("no line clip rect") }
        XCTAssertEqual(clip.animators.count, 0, "no clip animator when animation off")
        XCTAssertGreaterThan((clip.shape as? RectShape)?.width ?? 0, 0.0, "clip at full width when animation off")
    }
}
