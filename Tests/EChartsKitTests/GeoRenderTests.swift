// END-TO-END RENDER TEST for the Phase-23 GEO coordinate system (the 7th coord system) + its component
// view. Registers a SMALL toy GeoJSON (three side-by-side rectangular regions) under map name "toy",
// drives ECharts with `geo: { map: "toy" }`, and asserts the geo BACKDROP reaches the ZRenderKit
// scene graph: one region polygon CompoundPath per feature (GeoView wraps each region's Polygon subpaths
// in a CompoundPath). Also guards the coord-sys wiring: CoordinateSystemManager.register("geo", geoCreator)
// → GeoCreator.create builds the Geo coord, geoModel.coordinateSystem is set, and Geo.dataToPoint projects
// [lng,lat] → pixel via the View transform. Without any of these the backdrop renders empty.
import XCTest
import ZRenderKit
@testable import EChartsKit

final class GeoRenderTests: XCTestCase {

    // Toy GeoJSON: three rectangular regions side by side along lng: West[0..10], Central[10..20], East[20..30],
    //   all lat 0..10.
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

    func testGeoRendersRegionBackdrop() {
        ECharts.registerMap("toy", makeToyGeoJSON())

        let ec = ECharts(width: 520, height: 300)
        ec.setOption([
            "geo": [
                "map": "toy",
                "top": 40.0, "left": 40.0, "right": 40.0, "bottom": 40.0,
                "itemStyle": ["borderColor": "#333", "borderWidth": 1.0, "areaColor": "#e0e6ef"] as [String: Any],
                "label": ["show": true] as [String: Any]
            ] as [String: Any]
        ])

        // Each region's polygon subpaths are wrapped in ONE CompoundPath (MapDraw.createCompoundPath).
        // The region-name label is the compound path's ATTACHED `textContent` (upstream
        // MapDraw.resetLabelForRegion → setLabelStyle), not a standalone scene child, and `Group.traverse`
        // does NOT descend into `textContent` — so collect the attached label hosts and assert on their
        // CONTENT (mere existence would also pass for an empty or emphasis-only label).
        var compoundPaths = 0
        var labels: [ZRenderKit.ZRText] = []
        _ = ec.getRoot().traverse { el in
            if el is ZRenderKit.CompoundPath { compoundPaths += 1 }
            if let label = el.getTextContent() { labels.append(label) }
            return false
        }
        XCTAssertGreaterThan(compoundPaths, 0, "geo backdrop → one region-polygon CompoundPath per feature")
        // Three regions → three polygon compound paths (each region has no interior/linestring here).
        XCTAssertEqual(compoundPaths, 3, "one polygon CompoundPath per toy region")
        XCTAssertEqual(labels.count, 3, "one region-name label host per toy region")
        for name in ["West", "Central", "East"] {
            XCTAssertTrue(
                labels.contains { !$0.ignore && $0.textStyle.text == name },
                "region-name label \"\(name)\" renders in the normal state (label.show = true)"
            )
        }
    }

    func testGeoDataToPointProjectsAndOrders() {
        ECharts.registerMap("toy", makeToyGeoJSON())

        let ec = ECharts(width: 520, height: 300)
        ec.setOption([
            "geo": [
                "map": "toy",
                "top": 40.0, "left": 40.0, "right": 40.0, "bottom": 40.0
            ] as [String: Any]
        ])

        // Reach the Geo coord instance via the geo component model.
        guard let geoModel = ec.getModel()?.getComponent("geo", 0) as? GeoModel,
              let geo = geoModel.coordinateSystem as? Geo else {
            return XCTFail("geo component model / coordinateSystem (Geo) not wired")
        }

        // A vertex on the LEFT of the lng range (West, lng 0) must project to a smaller x than a vertex on
        //   the RIGHT (East, lng 30). Geo.dataToPoint([lng, lat]) → pixel via the View transform.
        guard let pLeft = geo.dataToPoint([0.0, 5.0]),
              let pRight = geo.dataToPoint([30.0, 5.0]) else {
            return XCTFail("Geo.dataToPoint returned nil for toy lng/lat vertices")
        }
        XCTAssertEqual(pLeft.count, 2)
        XCTAssertEqual(pRight.count, 2)
        XCTAssertLessThan(pLeft[0], pRight[0], "west vertex (lng 0) lands left of east vertex (lng 30)")

        // Both projected points must lie within the geo view rect (the laid-out coord pixel box).
        let vr = geo.getViewRect()
        let eps = 1e-6
        for p in [pLeft, pRight] {
            XCTAssertGreaterThanOrEqual(p[0], vr.x - eps)
            XCTAssertLessThanOrEqual(p[0], vr.x + vr.width + eps)
            XCTAssertGreaterThanOrEqual(p[1], vr.y - eps)
            XCTAssertLessThanOrEqual(p[1], vr.y + vr.height + eps)
        }
    }
}
