// Map regions fade in (style.opacity 0→final) when animation is on, and are at final (visible) opacity
// with no animator when off (the invisible-region guard). Faithful to MapView.createCompoundPath's
// initProps({style:{opacity}}) fade — the same idiom as FunnelView's piece fade-in.
import XCTest
@testable import EChartsKit
@testable import ZRenderKit

final class MapTransitionTests: XCTestCase {

    // Toy GeoJSON: three side-by-side rectangular regions (same as MapRenderTests).
    private func makeToyGeoJSON() -> [String: Any] {
        func feature(_ name: String, _ lng0: Double, _ lng1: Double) -> [String: Any] {
            return [
                "type": "Feature",
                "properties": ["name": name] as [String: Any],
                "geometry": [
                    "type": "Polygon",
                    "coordinates": [[[lng0, 0.0], [lng1, 0.0], [lng1, 10.0], [lng0, 10.0], [lng0, 0.0]]]
                ] as [String: Any]
            ]
        }
        return [
            "type": "FeatureCollection",
            "features": [
                feature("West", 0.0, 10.0),
                feature("Central", 10.0, 20.0),
                feature("East", 20.0, 30.0)
            ] as [Any]
        ]
    }

    private func option(_ animation: Bool) -> [String: Any] {
        return [
            "animation": animation,
            "series": [
                [
                    "type": "map",
                    "map": "toy",
                    "top": 40.0, "left": 40.0, "right": 40.0, "bottom": 40.0,
                    "data": [
                        ["name": "West", "value": 20.0] as [String: Any],
                        ["name": "Central", "value": 60.0] as [String: Any],
                        ["name": "East", "value": 95.0] as [String: Any]
                    ] as [Any]
                ] as [String: Any]
            ]
        ]
    }

    private func firstRegion(_ el: Element) -> ZRenderKit.CompoundPath? {
        if let cp = el as? ZRenderKit.CompoundPath { return cp }
        if let g = el as? Group { for c in g.children() { if let hit = firstRegion(c) { return hit } } }
        return nil
    }

    func test_region_fades_in_when_animation_on() {
        ECharts.registerMap("toy", makeToyGeoJSON())
        let ec = ECharts(width: 520, height: 320)
        ec.setOption(option(true))
        guard let cp = firstRegion(ec.getRoot()) else { return XCTFail("no map region CompoundPath") }

        // The fade-in animates a partial "style" dict ({opacity}); the resulting sub-animator is
        // targeted at "style" and carries an "opacity" leaf track (same idiom as FunnelTransitionTests).
        guard let animator = cp.animators.first(where: { $0.targetName == "style" }) else {
            return XCTFail("map region should have a style (opacity) animator when animation on")
        }
        guard let track = animator.getTrack("opacity") else {
            return XCTFail("no opacity track on the style animator")
        }
        // Strengthen: step the opacity track directly to prove a real fade delta (invisible at t=0,
        //   visible at t=1), not merely animator presence.
        let target = animator.getTarget()
        track.step(target, 0.0)
        XCTAssertEqual(cp.pathStyle?.opacity ?? .nan, 0.0, accuracy: 1e-6,
                       "opacity track at t=0 should be collapsed to 0 (invisible)")
        track.step(target, 1.0)
        XCTAssertGreaterThan(cp.pathStyle?.opacity ?? 0.0, 0.0,
                             "opacity track at t=1 should have faded in to a visible opacity")
    }

    func test_region_final_opacity_when_animation_off() {
        ECharts.registerMap("toy", makeToyGeoJSON())
        let ec = ECharts(width: 520, height: 320)
        ec.setOption(option(false))
        guard let cp = firstRegion(ec.getRoot()) else { return XCTFail("no map region CompoundPath") }
        XCTAssertEqual(cp.animators.count, 0, "no animator when animation off")
        XCTAssertGreaterThan(cp.pathStyle?.opacity ?? 0.0, 0.0,
                             "region must be at final (visible) opacity when off — not invisible")
    }
}
