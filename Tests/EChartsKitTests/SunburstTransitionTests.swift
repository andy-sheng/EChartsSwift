// Entering sunburst sectors expand radially: the angular partition is established immediately and
// the outer radius animates from the inner radius to its final value. This follows upstream
// SunburstPiece.ts firstCreate behavior (sunburst entrance is not PieView's angular sweep).
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

    func test_sector_expands_outward_when_animation_on() {
        let ec = ECharts(width: 400, height: 400)
        ec.setOption(option(true))
        guard let sec = firstSector(ec.getRoot()) else { return XCTFail("no sunburst sector") }
        XCTAssertGreaterThan(sec.animators.count, 0, "sector should have an expansion animator when animation on")

        // Step the "shape" animator's radius track directly on its real target. This proves a genuine
        // inner-radius -> outer-radius expansion, not merely the presence of an animator.
        guard let animator = sec.animators.first(where: { $0.targetName == "shape" }) else {
            return XCTFail("no shape-targeted animator on sector")
        }
        guard let track = animator.getTrack("r") else {
            return XCTFail("no radius track on the shape animator")
        }
        let target = animator.getTarget()
        track.step(target, 0.0)
        let innerRadius = (sec.shape as? SectorShape)?.r0 ?? .infinity
        XCTAssertEqual((sec.shape as? SectorShape)?.r ?? .nan, innerRadius, accuracy: 1e-6,
                       "radius track at t=0 should be collapsed to the inner radius")
        track.step(target, 1.0)
        XCTAssertGreaterThan((sec.shape as? SectorShape)?.r ?? 0, innerRadius,
                             "radius track at t=1 should be expanded to the outer radius")
    }

    func test_sector_final_angle_when_animation_off() {
        let ec = ECharts(width: 400, height: 400)
        ec.setOption(option(false))
        guard let sec = firstSector(ec.getRoot()) else { return XCTFail("no sunburst sector") }
        XCTAssertEqual(sec.animators.count, 0, "no animator when animation off")
        let sh = sec.shape as? SectorShape
        XCTAssertNotEqual(sh?.endAngle ?? 0, sh?.startAngle ?? 0, "sector at final (non-collapsed) angle when off")
    }
}
