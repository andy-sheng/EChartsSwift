// Gauge progress arc sweeps open: the progress Sector's shape.endAngle animates from startAngle
// (collapsed) to the value angle when animation on; at the final angle with no animator when off.
// Faithful to GaugeView.ts createProgress(idx, startAngle) + graphic.initProps({shape:{endAngle}}).
import XCTest
@testable import EChartsKit
@testable import ZRenderKit

final class GaugeProgressTransitionTests: XCTestCase {

    // Collect every Sector in the tree. The axisLine band sectors are `silent: true`; the progress
    // Sector is created without `silent` (== false), so it is the only non-silent Sector — that is how
    // we match the progress arc DISTINCTLY from the axis-line band sectors.
    private func allSectors(_ el: Element, _ out: inout [Sector]) {
        if let s = el as? Sector { out.append(s) }
        if let g = el as? Group { for c in g.children() { allSectors(c, &out) } }
    }
    private func progressSector(_ el: Element) -> Sector? {
        var all: [Sector] = []
        allSectors(el, &all)
        return all.first { !$0.silent }
    }

    private func option(_ animation: Bool) -> [String: Any] {
        ["animation": animation,
         "series": [["type": "gauge", "min": 0.0, "max": 100.0,
                     "progress": ["show": true],
                     "data": [["value": 50.0]]]]]
    }

    func test_progress_sweeps_open_when_animation_on() {
        let ec = ECharts(width: 400, height: 400)
        ec.setOption(option(true))
        guard let sec = progressSector(ec.getRoot()) else { return XCTFail("no gauge progress Sector") }
        XCTAssertGreaterThan(sec.animators.count, 0, "progress should have an expansion animator when animation on")

        guard let animator = sec.animators.first(where: { $0.targetName == "shape" }) else {
            return XCTFail("no shape-targeted animator on progress Sector")
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
                          "endAngle track at t=1 should be swept open to the value angle")
    }

    func test_progress_final_angle_when_animation_off() {
        let ec = ECharts(width: 400, height: 400)
        ec.setOption(option(false))
        guard let sec = progressSector(ec.getRoot()) else { return XCTFail("no gauge progress Sector") }
        XCTAssertEqual(sec.animators.count, 0, "no animator when animation off")
        let sh = sec.shape as? SectorShape
        XCTAssertNotEqual(sh?.endAngle ?? 0, sh?.startAngle ?? 0, "progress at final (non-collapsed) angle when off")
    }
}
