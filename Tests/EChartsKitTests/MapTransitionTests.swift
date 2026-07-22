// Map regions are rendered at their FINAL (visible) opacity with no entrance animator, whether animation
// is on or off.
//
// HISTORY: MapView's inlined `createCompoundPath` used to do an `initProps({ style: { opacity: 0 } })`
// fade-in, and this file asserted it. That was a port INVENTION — upstream `component/helper/MapDraw.ts`
// contains no `initProps` / `updateProps` call at all, so map regions never fade in. The switchover of
// MapView onto the shared `MapDraw` retired it (see the PORT-NOTE at the top of MapView.swift); the
// "fades in" case below is inverted to lock the upstream behaviour in.
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

    func test_region_does_not_fade_in_when_animation_on() {
        ECharts.registerMap("toy", makeToyGeoJSON())
        let ec = ECharts(width: 520, height: 320)
        ec.setOption(option(true))
        guard let cp = firstRegion(ec.getRoot()) else { return XCTFail("no map region CompoundPath") }

        // Upstream MapDraw has NO initProps: even with animation on, the region is created at its final
        // opacity and schedules no style (opacity) entrance animator.
        XCTAssertNil(cp.animators.first(where: { $0.targetName == "style" }),
                     "upstream map regions have no entrance fade — the initProps fade was a port invention")
        XCTAssertGreaterThan(cp.pathStyle?.opacity ?? 0.0, 0.0,
                             "region must be at final (visible) opacity immediately, not invisible at t=0")
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
