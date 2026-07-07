// Proves the FULL live-host animation chain works end-to-end for a SHAPE animation (pie sector
// expansion) — not just the headless animator-creation that PieTransitionTests covers. This is the
// regression guard for the 2026-07-07 "pie-basic has no animation" investigation, whose conclusion was
// that the mechanism is correct and any missing motion is environmental (stale binary / one-shot timing),
// not a code defect.
//
// The chain verified here:
//   EChartsView.setOption → EChartsSlim render (collapsed sector + initProps animator)
//     → _syncRoot (zr.add(root) → Group.addSelfToZr registers the animator with the LIVE zr.animation)
//     → zr.animation.update() steps the clip → ShapeAnimationAccessor writes endAngle + dirtyShape
//     → (in the app: stage.update → _flush → painter.refresh repaints).
import XCTest
import Foundation
@testable import EChartsKit
@testable import ZRenderKit

final class LiveAnimationTickTests: XCTestCase {

    private func firstSector(_ el: Element) -> Sector? {
        if let s = el as? Sector { return s }
        if let g = el as? Group { for c in g.children() { if let h = firstSector(c) { return h } } }
        return nil
    }

    private func pieView() -> (EChartsView, Sector) {
        let opt: [String: Any] = [
            "animation": true,
            "series": [["type": "pie", "radius": "60%",
                        "data": [["value": 40.0, "name": "a"], ["value": 60.0, "name": "b"]]]]
        ]
        let view = EChartsView(width: 400, height: 400)   // a REAL zr + _syncRoot, unlike the zr-less EChartsSlim
        view.setOption(opt)
        let sec = firstSector(view.ec.getRoot())!
        return (view, sec)
    }

    /// The pie sector's expansion animator must be registered with the live zr.animation (via _syncRoot's
    /// zr.add → addSelfToZr), else the app's AnimationLoop would tick an empty clock and nothing animates.
    func test_pie_animator_is_registered_with_live_zr() {
        let (view, sec) = pieView()
        XCTAssertTrue(sec.__zr === view.zr, "sector not added to the live zr — animator never registered")
        XCTAssertEqual(sec.animators.count, 1, "expected one expansion animator")
        XCTAssertNotNil(view.zr.animation, "live zr must own an animation clock")
    }

    /// Driving the LIVE zr.animation.update() over real elapsed time must advance the sector's endAngle
    /// from its collapsed start toward the final angle — the definitive proof the shape animation ticks
    /// through the real host clock (not just via a hand-stepped clip). Integration smoke test.
    func test_live_tick_advances_sector_endAngle() {
        let (view, sec) = pieView()
        let startAngle = (sec.shape as! SectorShape).startAngle
        let finalAngle = (sec.shape as! SectorShape).endAngle
        XCTAssertGreaterThan(finalAngle, startAngle, "sanity: final angle is beyond the start")

        // First tick pins the clip's t=0 baseline: endAngle snaps back to the collapsed start.
        view.zr.animation.update()
        let afterFirst = (sec.shape as! SectorShape).endAngle
        XCTAssertEqual(afterFirst, startAngle, accuracy: 1e-4,
                       "first live tick should collapse endAngle to the start (clip t=0)")

        // Let ~150ms of the 1000ms enter elapse, then tick again — endAngle must have moved toward final.
        Thread.sleep(forTimeInterval: 0.15)
        view.zr.animation.update()
        let afterElapse = (sec.shape as! SectorShape).endAngle
        XCTAssertGreaterThan(afterElapse, afterFirst + 1e-4,
                             "live tick over real time must advance endAngle toward the final angle")
        XCTAssertLessThanOrEqual(afterElapse, finalAngle + 1e-6, "should not overshoot the final angle")
    }
}
