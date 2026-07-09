// L3 Roam — GEO/MAP pan/zoom end-to-end. Builds a `roam:true` map series through EChartsView, injects a
// real drag / wheel through the live Handler, and asserts the map REGIONS actually SHIFT (pan) and SCALE
// (zoom) — measured through `Geo.dataToPoint` (the projection the region rings are built from).
//
//     _injectPointerForTest("mousedown"/"mousemove"/"mouseup", ...)   (drag)
//       -> zr Handler -> RoamController uniform fan-out -> 'pan' -> updateGeoRoamControllerSimply
//       -> ec.dispatchAction({type:'geoRoam', dx, dy}) -> geoRoam action applies pan to the Geo view coord
//          sys -> full update() re-renders -> `geo.dataToPoint(coord)` shifted by (dx, dy)
// Mirrors ZZGraphRoamTests.
import XCTest
import ZRenderKit
@testable import EChartsKit

final class ZZGeoRoamTests: XCTestCase {

    // Toy GeoJSON: three rectangular regions side by side along lng: West[0..10], Central[10..20], East[20..30].
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

    private func makeMapView(roam: Bool) -> EChartsView {
        ECharts.registerMap("toyRoam", makeToyGeoJSON())
        let view = EChartsView(width: 520, height: 320)
        var series: [String: Any] = [
            "type": "map",
            "map": "toyRoam",
            "top": 40.0, "left": 40.0, "right": 40.0, "bottom": 40.0,
            "data": [
                ["name": "West", "value": 20.0] as [String: Any],
                ["name": "Central", "value": 60.0] as [String: Any],
                ["name": "East", "value": 95.0] as [String: Any]
            ] as [Any]
        ]
        if roam { series["roam"] = true }
        view.setOption(["series": [series]])
        _ = view.zr.storage.getDisplayList(true)
        return view
    }

    private func geo(_ view: EChartsView) -> Geo? {
        guard let sm = view.ec.getModel()?.getSeriesByType("map").first as? MapSeriesModel else { return nil }
        return sm.coordinateSystem as? Geo
    }

    /// Project a lng/lat data coord to a pixel point through the Geo coord sys (the same path region rings use).
    private func project(_ view: EChartsView, _ coord: [Double]) -> (x: Double, y: Double)? {
        guard let g = geo(view), let p = g.dataToPoint(coord, false), p.count >= 2 else { return nil }
        return (p[0], p[1])
    }

    /// A point guaranteed inside the roam pointer-check area (center of the Geo view rect).
    private func viewCenter(_ view: EChartsView) -> (x: Double, y: Double) {
        guard let g = geo(view) else { return (260, 160) }
        let r = g.getViewRect()
        return (r.x + r.width / 2, r.y + r.height / 2)
    }

    // A drag over the map must shift every projected region point by the drag delta (pan).
    func testDragPansRegions() {
        let view = makeMapView(roam: true)
        guard let before = project(view, [15.0, 5.0]) else {
            return XCTFail("map region coord must project after render")
        }
        let c = viewCenter(view)
        let dx = 40.0, dy = 30.0
        view._injectPointerForTest(type: "mousedown", zrX: c.x, zrY: c.y)
        view._injectPointerForTest(type: "mousemove", zrX: c.x + dx, zrY: c.y + dy)
        view._injectPointerForTest(type: "mouseup", zrX: c.x + dx, zrY: c.y + dy)

        guard let after = project(view, [15.0, 5.0]) else {
            return XCTFail("coord must still project after the pan re-render")
        }
        print("GEO-ROAM pan: (\(before.x),\(before.y)) -> (\(after.x),\(after.y))")
        XCTAssertEqual(after.x - before.x, dx, accuracy: 0.5, "region must shift right by dx")
        XCTAssertEqual(after.y - before.y, dy, accuracy: 0.5, "region must shift down by dy")
    }

    // A wheel over the map must SCALE the projection: the distance between two projected region points
    // grows by the zoom factor (positive wheel delta zooms in; factor 1.2 for |delta| in (1,3]).
    func testWheelZoomsRegions() {
        let view = makeMapView(roam: true)
        guard let a0 = project(view, [5.0, 5.0]), let b0 = project(view, [25.0, 5.0]) else {
            return XCTFail("region coords must project after render")
        }
        let beforeDist = hypot(b0.x - a0.x, b0.y - a0.y)
        XCTAssertGreaterThan(beforeDist, 1, "the two coords must project apart")

        let c = viewCenter(view)
        view._injectWheelForTest(zrDelta: 3, zrX: c.x, zrY: c.y)

        guard let a1 = project(view, [5.0, 5.0]), let b1 = project(view, [25.0, 5.0]) else {
            return XCTFail("region coords must still project after the zoom re-render")
        }
        let afterDist = hypot(b1.x - a1.x, b1.y - a1.y)
        print("GEO-ROAM zoom: dist \(beforeDist) -> \(afterDist) (ratio \(afterDist / beforeDist))")
        XCTAssertEqual(afterDist / beforeDist, 1.2, accuracy: 0.05, "wheel-in scales the projection by ~1.2x")
    }

    // A map WITHOUT roam must be inert to a drag (projection unchanged).
    func testNoRoamOptionIsInert() {
        let view = makeMapView(roam: false)
        guard let before = project(view, [15.0, 5.0]) else { return XCTFail("coord must project") }
        let c = viewCenter(view)
        view._injectPointerForTest(type: "mousedown", zrX: c.x, zrY: c.y)
        view._injectPointerForTest(type: "mousemove", zrX: c.x + 50, zrY: c.y + 50)
        view._injectPointerForTest(type: "mouseup", zrX: c.x + 50, zrY: c.y + 50)
        guard let after = project(view, [15.0, 5.0]) else { return XCTFail("coord must still project") }
        XCTAssertEqual(after.x, before.x, accuracy: 1e-6, "roam:off map must not pan")
        XCTAssertEqual(after.y, before.y, accuracy: 1e-6, "roam:off map must not pan")
    }
}
