// Boxplot box Polygons GROW their points-array shape on entrance: the box ends collapse to the median
// baseline (transInit collapses every point along constDim to itemLayout.initBaseline) and initProps
// tweens the [[Double]] points from that collapsed line out to the final `itemLayout.ends`. When
// animation on, the shape (points) animator carries collapsed→final; when off, no animator and the live
// box sits at its final ends (visible, has area). Faithful to upstream BoxplotView.updateNormalBoxData.
import XCTest
@testable import EChartsKit
@testable import ZRenderKit

final class BoxplotGrowTests: XCTestCase {
    private func firstBox(_ el: Element) -> BoxPath? {
        if let p = el as? BoxPath { return p }
        if let g = el as? Group { for c in g.children() { if let h = firstBox(c) { return h } } }
        return nil
    }
    private func points(_ box: BoxPath) -> [[Double]] {
        (box.shape as? BoxPathShape)?.points ?? []
    }
    /// The dim (0 or 1) along which every point shares the same coordinate (the collapsed/const dim),
    /// or nil if the point set spans both dims.
    private func collapsedDim(_ pts: [[Double]]) -> Int? {
        guard let first = pts.first else { return nil }
        for d in 0..<2 {
            if pts.allSatisfy({ abs($0[d] - first[d]) < 1e-9 }) { return d }
        }
        return nil
    }
    private func option(_ animation: Bool) -> [String: Any] {
        ["animation": animation,
         "grid": ["left": 50.0, "top": 20.0, "width": 440.0, "height": 260.0] as [String: Any],
         "xAxis": ["type": "category", "data": ["G1", "G2", "G3"]] as [String: Any],
         "yAxis": ["type": "value"] as [String: Any],
         "series": [["type": "boxplot",
                     "data": [[10.0, 22.0, 28.0, 35.0, 50.0],
                              [15.0, 25.0, 33.0, 40.0, 55.0],
                              [8.0, 18.0, 24.0, 30.0, 44.0]]] as [String: Any]]]
    }

    // ON: a points (shape) animator whose clip carries the collapsed box (all points on the median
    //     baseline along constDim) at t=0 out to the final ends at t=1.
    func test_box_points_grow_when_animation_on() {
        let ec = ECharts(width: 520, height: 340); ec.setOption(option(true))
        guard let box = firstBox(ec.getRoot()) else { return XCTFail("no boxplot BoxPath") }

        let anim = box.animators.first { $0.targetName == "shape" }
        XCTAssertNotNil(anim, "boxplot box should have a shape (points) animator when animation on")
        guard let clip = anim?.getClip() else { return XCTFail("no clip — points track inert") }

        // t=0: the animator restores the COLLAPSED start — the box is flattened onto the median baseline,
        //   i.e. every point shares one coordinate (constDim); the box still spans the other (width) dim.
        _ = clip.step(0, 0)
        let p0 = points(box)
        XCTAssertFalse(p0.isEmpty, "collapsed start has points")
        guard let cDim = collapsedDim(p0) else {
            return XCTFail("t=0 must collapse to a line (all points equal along one dim)")
        }
        let wDim = 1 - cDim
        XCTAssertFalse(p0.allSatisfy { abs($0[wDim] - p0[0][wDim]) < 1e-9 },
                       "collapsed line still spans the width dim (box is not a single point)")

        // t=1: reaches the final ends — the box now spans the const dim too (grew off the baseline),
        //   while its width (the other dim) is unchanged from the collapsed start.
        _ = clip.step(1000, 1000)
        let p1 = points(box)
        XCTAssertEqual(p1.count, p0.count, "point count preserved across the grow")
        XCTAssertNil(collapsedDim(p1), "final ends span BOTH dims (box has area — not collapsed)")
        for i in 0..<p1.count {
            XCTAssertEqual(p1[i][wDim], p0[i][wDim], accuracy: 1e-9,
                           "width dim unchanged by the grow (only the value/const dim expands)")
        }
        XCTAssertFalse(p1.allSatisfy { abs($0[cDim] - p0[0][cDim]) < 1e-9 },
                       "final ends vary along the collapsed dim — the box grew off the median baseline")
    }

    // OFF: no animator, and the live box sits at its final ends (spans both dims — visible, has area,
    //      not left collapsed on the baseline).
    func test_box_final_points_when_animation_off() {
        let ec = ECharts(width: 520, height: 340); ec.setOption(option(false))
        guard let box = firstBox(ec.getRoot()) else { return XCTFail("no boxplot BoxPath") }
        XCTAssertEqual(box.animators.count, 0, "no animator when animation off")
        let p = points(box)
        XCTAssertFalse(p.isEmpty, "box has points")
        XCTAssertNil(collapsedDim(p),
                     "box must be at final ends (spans both dims — visible) when off, not collapsed")
    }
}
