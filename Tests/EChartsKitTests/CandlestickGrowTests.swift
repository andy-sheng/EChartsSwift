// Proves the candlestick ENTRANCE is a FAITHFUL points-array GROW (not a snap). Drives a real
// candlestick through ECharts (the NewChartsRenderTests pattern) and inspects the first
// NormalBoxPath candle:
//
//   ON  — the view builds the box with COLLAPSED points (every end flattened to itemLayout.initBaseline
//         along the const dim by transInit), then initProps animates `points` toward the final
//         itemLayout.ends via the keyed animation seam (NormalBoxPathShape.animationGet/animationSet
//         + the Animator's 2D-array interpolation). setToFinal jumps the LIVE shape to final, so we
//         assert on the ANIMATOR TRACK: step the "shape" clip -> t=0 collapsed (all ends share one
//         coordinate = the baseline), t=1 == final ends. (The old struct-snap entrance fails this.)
//   OFF — animation disabled: no animator; the box sits at its final, visible ends.
//
// Headless: no zr tick, the clip is stepped at synthetic times (the AnimationSmokeTests pattern).
import XCTest
import ZRenderKit
@testable import EChartsKit

final class CandlestickGrowTests: XCTestCase {

    override func setUp() {
        super.setUp()
        ComponentModel.registerClass(CandlestickSeriesModel.self)
    }

    private func makeChart(animation: Bool) -> ECharts {
        let ec = ECharts(width: 520, height: 340)
        ec.setOption([
            "animation": animation,
            "animationDuration": 1000,
            "animationEasing": "linear",
            "grid": ["left": 50.0, "top": 20.0, "width": 440.0, "height": 260.0] as [String: Any],
            "xAxis": ["type": "category", "data": ["A", "B", "C", "D", "E", "F"]] as [String: Any],
            "yAxis": ["type": "value", "scale": true] as [String: Any],
            "series": [["type": "candlestick",
                        "data": [[20.0, 34.0, 18.0, 38.0], [34.0, 28.0, 25.0, 40.0],
                                 [28.0, 42.0, 26.0, 45.0], [42.0, 38.0, 35.0, 48.0],
                                 [38.0, 50.0, 36.0, 55.0], [50.0, 46.0, 44.0, 58.0]]] as [String: Any]]
        ])
        return ec
    }

    private func firstBox(_ ec: ECharts) -> NormalBoxPath? {
        var found: NormalBoxPath?
        _ = ec.getRoot().traverse { el in
            if found == nil, let b = el as? NormalBoxPath { found = b }
            return false
        }
        return found
    }

    private func points(_ box: NormalBoxPath) -> [[Double]] {
        return (box.shape as? NormalBoxPathShape)?.points ?? []
    }

    /// True when every point shares the same value along dimension `d` (the collapsed baseline state).
    private func allEqual(_ pts: [[Double]], _ d: Int) -> Bool {
        guard let first = pts.first?[d] else { return false }
        return pts.allSatisfy { abs($0[d] - first) < 1e-6 }
    }

    // ON: the entrance grows the points from a collapsed baseline to the final ends.
    func test_entrance_grows_points_from_collapsed_baseline_to_final_ends() {
        let ec = makeChart(animation: true)
        guard let box = firstBox(ec) else { return XCTFail("no NormalBoxPath candle rendered") }

        // setToFinal already jumped the LIVE shape to the final ends — capture them first.
        let final = points(box)
        XCTAssertEqual(final.count, 8, "candle has 8 ends (body quad + 4 whisker points)")
        // A real candle spans multiple values along BOTH dims (body width + high/low span), so no
        //   dimension is degenerate at the final state.
        XCTAssertFalse(allEqual(final, 0), "final ends span the category (x) dim")
        XCTAssertFalse(allEqual(final, 1), "final ends span the value (y) dim")

        // The GROW lives on the animator track. Find the shape (points) animator.
        guard let shapeAnim = box.animators.first(where: { $0.targetName == "shape" }) else {
            return XCTFail("no shape animator — entrance is snapping, not growing")
        }
        guard let clip = shapeAnim.getClip() else { return XCTFail("no clip — points track inert") }

        // t = 0: COLLAPSED start — every end flattened onto the initBaseline along the const dim, so all
        //   8 points share one coordinate (a degenerate line = invisible seed), unlike the final box.
        _ = clip.step(0, 0)
        let start = points(box)
        XCTAssertEqual(start.count, 8, "point count preserved at t=0")
        let collapsedX = allEqual(start, 0)
        let collapsedY = allEqual(start, 1)
        XCTAssertTrue(collapsedX || collapsedY,
                      "t=0 must be collapsed onto the baseline (all ends equal along the const dim)")
        XCTAssertNotEqual(start, final, "collapsed start must differ from final (would-be snap)")

        // t = 1: the animator reaches the final ends exactly.
        _ = clip.step(1000, 1000)
        let end = points(box)
        XCTAssertEqual(end.count, final.count, "point count preserved at t=1")
        for i in 0..<final.count {
            XCTAssertEqual(end[i][0], final[i][0], accuracy: 1e-6, "reaches final x (pt \(i))")
            XCTAssertEqual(end[i][1], final[i][1], accuracy: 1e-6, "reaches final y (pt \(i))")
        }
    }

    // OFF: animation disabled -> no entrance animator; the box is drawn at its final, visible ends.
    func test_entrance_off_no_animator_box_at_final_ends() {
        let ec = makeChart(animation: false)
        guard let box = firstBox(ec) else { return XCTFail("no NormalBoxPath candle rendered") }

        XCTAssertTrue(box.animators.isEmpty, "animation off -> no entrance animator")
        let pts = points(box)
        XCTAssertEqual(pts.count, 8, "candle has 8 ends")
        // Not collapsed: a real, visible box spans both dims.
        XCTAssertFalse(allEqual(pts, 0), "box at final: spans the category (x) dim")
        XCTAssertFalse(allEqual(pts, 1), "box at final: spans the value (y) dim")
    }

    // UPDATE: upstream `CandlestickView._renderNormal` reuses the existing box and calls
    // `graphic.updateProps(el, {shape: {points: itemLayout.ends}}, seriesModel, newIdx)`, so a value
    // update must morph the 8-point geometry through the keyed shape animator rather than replace the
    // whole Swift shape value synchronously.
    func test_update_morphs_reused_box_points() {
        let ec = makeChart(animation: true)
        guard let boxBefore = firstBox(ec) else { return XCTFail("no NormalBoxPath candle rendered") }

        _ = ec.getRoot().traverse { el in
            _ = el.stopAnimation(nil)
            return false
        }

        ec.setOption([
            "series": [[
                "type": "candlestick",
                "data": [[24.0, 40.0, 20.0, 44.0], [40.0, 30.0, 27.0, 46.0],
                         [30.0, 48.0, 28.0, 52.0], [48.0, 41.0, 38.0, 54.0],
                         [41.0, 56.0, 39.0, 61.0], [56.0, 49.0, 46.0, 64.0]]
            ] as [String: Any]]
        ])

        guard let boxAfter = firstBox(ec) else { return XCTFail("updated candle disappeared") }
        XCTAssertTrue(boxBefore === boxAfter, "same-index candle must reuse its upstream graphic element")
        XCTAssertNotNil(
            boxAfter.animators.first { $0.targetName == "shape" && $0.getTrack("points") != nil },
            "upstream updateProps({shape:{points}}) must morph the reused candle geometry"
        )
    }
}
