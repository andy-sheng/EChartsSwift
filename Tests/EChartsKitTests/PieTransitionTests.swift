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

    // Collect sectors in scene-graph (data) order.
    private func allSectors(_ el: Element, into out: inout [Sector]) {
        if let s = el as? Sector { out.append(s) }
        if let g = el as? Group { for c in g.children() { allSectors(c, into: &out) } }
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

    // The clockwise-sweep fix: on the FIRST render of the whole pie, every sector is seeded collapsed
    // onto the pie's shared GLOBAL start angle (the first sector's startAngle) and BOTH its startAngle
    // and endAngle animate out — so the pie draws on like a sweeping clock hand (upstream PieView.ts
    // `startAngle != null` branch). The bug was that non-first sectors opened in place from their OWN
    // final start (only endAngle animated), so this test targets the SECOND sector, whose global start
    // differs from its own start. Regression guard: the buggy code has no `startAngle` track here at all.
    func test_nonfirst_sector_sweeps_from_global_start() {
        let ec = ECharts(width: 400, height: 400)
        ec.setOption(option(true))
        var sectors: [Sector] = []
        allSectors(ec.getRoot(), into: &sectors)
        guard sectors.count >= 2 else { return XCTFail("expected >= 2 pie sectors, got \(sectors.count)") }

        // Live shapes have already jumped to FINAL (initProps setToFinal) by the time setOption returns.
        let globalStart = (sectors[0].shape as? SectorShape)?.startAngle ?? .nan   // first sector's own start
        let second = sectors[1]
        let ownStart = (second.shape as? SectorShape)?.startAngle ?? .nan          // second sector's own start
        XCTAssertFalse(globalStart.isNaN || ownStart.isNaN, "sector shapes must be sectors")
        XCTAssertNotEqual(globalStart, ownStart, accuracy: 1e-6,
                          "precondition: the second sector's own start must differ from the global start")

        guard let animator = second.animators.first(where: { $0.targetName == "shape" }) else {
            return XCTFail("no shape-targeted animator on the second sector")
        }
        // The fix REQUIRES a startAngle track here (the buggy in-place open animated only endAngle).
        guard let startTrack = animator.getTrack("startAngle") else {
            return XCTFail("second sector has no startAngle track — it opened in place, not a global sweep")
        }
        let target = animator.getTarget()
        startTrack.step(target, 0.0)
        XCTAssertEqual((second.shape as? SectorShape)?.startAngle ?? .nan, globalStart, accuracy: 1e-6,
                       "at t=0 the second sector's startAngle should be collapsed onto the GLOBAL start")
        startTrack.step(target, 1.0)
        XCTAssertEqual((second.shape as? SectorShape)?.startAngle ?? .nan, ownStart, accuracy: 1e-6,
                       "at t=1 the second sector's startAngle should reach its own final start")
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
