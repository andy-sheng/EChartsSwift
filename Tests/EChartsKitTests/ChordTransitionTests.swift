// Entering chord node arcs sweep open: endAngle animates from startAngle to the final layout angle when
// animation is on; arcs sit at their final angle with no animator when off. Mirrors PieView's PiePiece
// expansion, applied to the chord ChordPiece (a Sector subclass) — see ChordPiece.updateData(firstCreate).
import XCTest
@testable import EChartsKit
@testable import ZRenderKit

final class ChordTransitionTests: XCTestCase {

    private func firstChordPiece(_ el: Element) -> ChordPiece? {
        if let p = el as? ChordPiece { return p }
        if let g = el as? Group { for c in g.children() { if let hit = firstChordPiece(c) { return hit } } }
        return nil
    }

    private func option(_ animation: Bool) -> [String: Any] {
        [
            "animation": animation,
            "series": [["type": "chord",
                        "center": ["50%", "50%"],
                        "radius": ["60%", "70%"],
                        "padAngle": 3.0,
                        "data": [["name": "a"], ["name": "b"], ["name": "c"], ["name": "d"]],
                        "links": [["source": "a", "target": "b", "value": 5.0],
                                  ["source": "a", "target": "c", "value": 3.0],
                                  ["source": "b", "target": "c", "value": 4.0],
                                  ["source": "b", "target": "d", "value": 2.0],
                                  ["source": "c", "target": "d", "value": 6.0]]] as [String: Any]]
        ]
    }

    func test_node_arc_sweeps_open_when_animation_on() {
        let ec = EChartsSlim(width: 460, height: 360)
        ec.setOption(option(true))
        guard let sec = firstChordPiece(ec.getRoot()) else { return XCTFail("no chord node arc") }
        XCTAssertGreaterThan(sec.animators.count, 0, "node arc should have an expansion animator when animation on")

        // Strengthen: find the "shape" animator and step its "endAngle" track directly on the animator's
        // real target (the Path's internal shape-accessor, which writes back into path.shape). This proves
        // a genuine sweep-open delta (collapsed at t=0, final at t=1), not just animator presence.
        guard let animator = sec.animators.first(where: { $0.targetName == "shape" }) else {
            return XCTFail("no shape-targeted animator on node arc")
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

    func test_node_arc_final_angle_when_animation_off() {
        let ec = EChartsSlim(width: 460, height: 360)
        ec.setOption(option(false))
        guard let sec = firstChordPiece(ec.getRoot()) else { return XCTFail("no chord node arc") }
        XCTAssertEqual(sec.animators.count, 0, "no animator when animation off")
        let sh = sec.shape as? SectorShape
        XCTAssertNotEqual(sh?.endAngle ?? 0, sh?.startAngle ?? 0, "node arc at final (non-collapsed) angle when off")
    }
}
