// Entering sunburst sectors sweep open: endAngle animates from startAngle to the final angle when
// animation is on; sectors are at final angle with no animator when off. Faithful to SunburstPiece.ts
// firstCreate expansion (angle-expansion form, mirroring PieView's PiePiece sweep).
import XCTest
@testable import EChartsKit
@testable import ZRenderKit

final class SunburstTransitionTests: XCTestCase {

    private func firstSector(_ el: Element) -> Sector? {
        if let s = el as? Sector { return s }
        if let g = el as? Group { for c in g.children() { if let hit = firstSector(c) { return hit } } }
        return nil
    }

    private func option(_ animation: Bool) -> [String: Any] {
        [
            "animation": animation,
            "series": [["type": "sunburst", "radius": ["0%", "90%"],
                        "data": [
                            ["name": "Grandpa", "children": [
                                ["name": "Uncle Leo", "value": 15.0, "children": [
                                    ["name": "Cousin Jack", "value": 2.0],
                                    ["name": "Cousin Mary", "value": 5.0]
                                ]],
                                ["name": "Father", "value": 10.0, "children": [
                                    ["name": "Me", "value": 5.0],
                                    ["name": "Brother Peter", "value": 1.0]
                                ]]
                            ]],
                            ["name": "Nancy", "children": [
                                ["name": "Uncle Nike", "value": 10.0, "children": [
                                    ["name": "Cousin Betty", "value": 1.0],
                                    ["name": "Cousin Jenny", "value": 2.0]
                                ]]
                            ]]
                        ]] as [String: Any]]
        ]
    }

    func test_sector_sweeps_open_when_animation_on() {
        let ec = EChartsSlim(width: 400, height: 400)
        ec.setOption(option(true))
        guard let sec = firstSector(ec.getRoot()) else { return XCTFail("no sunburst sector") }
        XCTAssertGreaterThan(sec.animators.count, 0, "sector should have an expansion animator when animation on")

        // Step the "shape" animator's "endAngle" track directly on the animator's real target (the Path's
        // internal shape-accessor CLASS — a value-type struct copy would not observe the mutation). This
        // proves a genuine collapsed->final sweep (collapsed at t=0, final at t=1), not just presence.
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
        let ec = EChartsSlim(width: 400, height: 400)
        ec.setOption(option(false))
        guard let sec = firstSector(ec.getRoot()) else { return XCTFail("no sunburst sector") }
        XCTAssertEqual(sec.animators.count, 0, "no animator when animation off")
        let sh = sec.shape as? SectorShape
        XCTAssertNotEqual(sh?.endAngle ?? 0, sh?.startAngle ?? 0, "sector at final (non-collapsed) angle when off")
    }
}
