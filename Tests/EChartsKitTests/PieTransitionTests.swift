// Entering pie sectors sweep open: endAngle animates from startAngle to the final angle when animation
// is on; sectors are at final angle with no animator when off. Faithful to PieView.ts PiePiece expansion.
import XCTest
@testable import EChartsKit
@testable import ZRenderKit

final class PieTransitionTests: XCTestCase {

    private func firstSector(_ el: Element) -> Sector? {
        if let s = el as? Sector { return s }
        if let g = el as? Group { for c in g.children() { if let hit = firstSector(c) { return hit } } }
        return nil
    }

    private func option(_ animation: Bool) -> [String: Any] {
        [
            "animation": animation,
            "series": [["type": "pie", "radius": "60%",
                        "data": [["value": 40.0, "name": "a"], ["value": 60.0, "name": "b"]]]]
        ]
    }

    func test_sector_sweeps_open_when_animation_on() {
        let ec = ECharts(width: 400, height: 400)
        ec.setOption(option(true))
        guard let sec = firstSector(ec.getRoot()) else { return XCTFail("no pie sector") }
        XCTAssertGreaterThan(sec.animators.count, 0, "sector should have an expansion animator when animation on")
        // NOTE: we do NOT assert the live shape is synchronously collapsed here — initProps'
        //   `setToFinal: true` (basicTransition.swift) jumps the live shape to its FINAL value
        //   immediately (the same behavior observed for scatter's scaleX in Task 1), so a synchronous
        //   read of sec.shape is already the final angle by the time setOption returns. The genuine
        //   proof of a collapsed->final sweep is the track-step assertion below.

        // Strengthen: find the "shape" animator and step its "endAngle" track directly on the
        // animator's real target (the Path's internal shape-accessor CLASS — a value-type SectorShape
        // struct copy would NOT observe the mutation, since Track.step's `animationSet` call only
        // mutates whatever it's handed; the accessor writes back into `path.shape` for us). This proves
        // a genuine sweep-open delta (collapsed at t=0, final at t=1), not just animator presence.
        guard let animator = sec.animators.first(where: { $0.targetName == "shape" }) else {
            return XCTFail("no shape-targeted animator on sector")
        }
        guard let track = animator.getTrack("endAngle") else {
            return XCTFail("no endAngle track on the shape animator")
        }
        let target = animator.getTarget()
        track.step(target, 0.0)
        let startAngle = (sec.shape as? SectorShape)?.startAngle ?? .infinity
        XCTAssertEqual((sec.shape as? SectorShape)?.endAngle ?? .nan, startAngle, accuracy: 1e-6,
                       "endAngle track at t=0 should be collapsed (== startAngle)")
        track.step(target, 1.0)
        XCTAssertNotEqual((sec.shape as? SectorShape)?.endAngle ?? 0, startAngle,
                          "endAngle track at t=1 should be swept open")
    }

    func test_sector_final_angle_when_animation_off() {
        let ec = ECharts(width: 400, height: 400)
        ec.setOption(option(false))
        guard let sec = firstSector(ec.getRoot()) else { return XCTFail("no pie sector") }
        XCTAssertEqual(sec.animators.count, 0, "no animator when animation off")
        let sh = sec.shape as? SectorShape
        XCTAssertNotEqual(sh?.endAngle ?? 0, sh?.startAngle ?? 0, "sector at final (non-collapsed) angle when off")
    }
}
