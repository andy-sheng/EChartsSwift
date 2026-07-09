// Faithful port of upstream RadarView.ts `getInitialPoints`: the radar area polygon (and its outline
// polyline) enter by GROWING their `points` from a ring collapsed at the radar center [cx, cy] to the
// real vertex ring, via initProps(el, ["shape": ["points": finalPoints]]) — the Animator's 2D-array
// interpolation — NOT a transform scale-in. When animation is off the shape sits at its final points.
import XCTest
@testable import EChartsKit
@testable import ZRenderKit

final class RadarPolygonGrowTests: XCTestCase {

    private func firstNamed(_ el: Element, _ name: String) -> Path? {
        if let p = el as? Path, p.name == name { return p }
        if let g = el as? Group { for c in g.children() { if let h = firstNamed(c, name) { return h } } }
        return nil
    }

    private func points(_ p: Path) -> [VectorArray] {
        return (p.shape as? PolygonShape)?.points ?? (p.shape as? PolylineShape)?.points ?? []
    }

    private func option(_ animation: Bool) -> [String: Any] {
        [
            "animation": animation,
            "radar": ["indicator": [["name": "A", "max": 100.0], ["name": "B", "max": 100.0], ["name": "C", "max": 100.0]]],
            "series": [["type": "radar", "data": [["value": [60.0, 70.0, 80.0], "areaStyle": ["opacity": 0.7]]]]]
        ]
    }

    // ON: the polygon carries a `shape` (points) animator whose clip at t=0 collapses every point onto
    //   the radar center, and at t=1 lands on the real vertex ring.
    func test_polygon_points_grow_from_center_when_animation_on() {
        let ec = ECharts(width: 400, height: 400); ec.setOption(option(true))
        guard let poly = firstNamed(ec.getRoot(), "radarPolygon") else {
            return XCTFail("no radar polygon (name==\"radarPolygon\")")
        }
        let radar = (ec.getModel()?.getSeriesByType(SERIES_TYPE_RADAR).first as? RadarSeriesModel)?.radarCoordinateSystem
        let cx = radar?.cx ?? 0
        let cy = radar?.cy ?? 0

        // The shape sub-bag animator carries a track named "points" (targetName == "shape").
        let anim = poly.animators.first { $0.targetName == "shape" && $0.getTrack("points") != nil }
        XCTAssertNotNil(anim, "polygon should have a shape(points) animator when animation on")
        guard let clip = anim?.getClip() else { return XCTFail("no clip — points track inert") }

        _ = clip.step(0, 0)
        let start = points(poly)
        XCTAssertGreaterThan(start.count, 0, "collapsed ring has points")
        for pt in start {
            XCTAssertEqual(pt.x, cx, accuracy: 1e-6, "t=0 point collapsed onto center x")
            XCTAssertEqual(pt.y, cy, accuracy: 1e-6, "t=0 point collapsed onto center y")
        }

        _ = clip.step(1_000_000, 1_000_000)
        let end = points(poly)
        XCTAssertEqual(end.count, start.count, "point count preserved across the grow")
        // At least one vertex must be off-center (a real pentagon vertex).
        let offCenter = end.contains { abs($0.x - cx) > 1e-3 || abs($0.y - cy) > 1e-3 }
        XCTAssertTrue(offCenter, "t=1 lands on the real vertex ring (a vertex != center)")
    }

    // OFF: no animator; the polygon points sit at their final vertex ring (a vertex != center).
    func test_polygon_points_final_when_animation_off() {
        let ec = ECharts(width: 400, height: 400); ec.setOption(option(false))
        guard let poly = firstNamed(ec.getRoot(), "radarPolygon") else {
            return XCTFail("no radar polygon")
        }
        let radar = (ec.getModel()?.getSeriesByType(SERIES_TYPE_RADAR).first as? RadarSeriesModel)?.radarCoordinateSystem
        let cx = radar?.cx ?? 0
        let cy = radar?.cy ?? 0

        XCTAssertEqual(poly.animators.count, 0, "no animator when animation off")
        let pts = points(poly)
        XCTAssertGreaterThan(pts.count, 0, "polygon has points")
        let offCenter = pts.contains { abs($0.x - cx) > 1e-3 || abs($0.y - cy) > 1e-3 }
        XCTAssertTrue(offCenter, "polygon at final vertex ring when off (a vertex != center)")
    }
}
