// Upstream chord entrance scales the complete chord group about its center. Individual node sectors are
// installed at their final angles immediately: adding an endAngle tween creates a spurious outline/sweep
// animation that is not present in echarts.js.
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

    func test_group_scales_in_without_node_arc_sweep_when_animation_on() {
        let ec = ECharts(width: 460, height: 360)
        ec.setOption(option(true))
        guard let sec = firstChordPiece(ec.getRoot()) else { return XCTFail("no chord node arc") }
        XCTAssertNil(sec.animators.first(where: { $0.targetName == "shape" }),
                     "node sectors must not carry a per-arc sweep animator")
        let shape = sec.shape as? SectorShape
        XCTAssertNotEqual(shape?.endAngle ?? 0, shape?.startAngle ?? 0,
                          "node sector is installed at its final sweep")

        guard let chordGroup = sec.parent as? Group else { return XCTFail("no chord view group") }
        guard let animator = chordGroup.animators.first(where: {
            $0.getTrack("scaleX") != nil && $0.getTrack("scaleY") != nil
        }) else {
            return XCTFail("chord group must carry the entrance scale animator")
        }
        let target = animator.getTarget()
        animator.getTrack("scaleX")?.step(target, 0)
        animator.getTrack("scaleY")?.step(target, 0)
        XCTAssertEqual(chordGroup.scaleX, 0.01, accuracy: 1e-9)
        XCTAssertEqual(chordGroup.scaleY, 0.01, accuracy: 1e-9)
        animator.getTrack("scaleX")?.step(target, 1)
        animator.getTrack("scaleY")?.step(target, 1)
        XCTAssertEqual(chordGroup.scaleX, 1, accuracy: 1e-9)
        XCTAssertEqual(chordGroup.scaleY, 1, accuracy: 1e-9)
    }

    func test_node_arc_final_angle_when_animation_off() {
        let ec = ECharts(width: 460, height: 360)
        ec.setOption(option(false))
        guard let sec = firstChordPiece(ec.getRoot()) else { return XCTFail("no chord node arc") }
        XCTAssertEqual(sec.animators.count, 0, "no animator when animation off")
        let sh = sec.shape as? SectorShape
        XCTAssertNotEqual(sh?.endAngle ?? 0, sh?.startAngle ?? 0, "node arc at final (non-collapsed) angle when off")
    }
}
