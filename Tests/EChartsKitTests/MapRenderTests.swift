// END-TO-END RENDER TEST for the Phase-24 MAP chart (a `series.map` on the geo coordinate system).
// Registers a SMALL toy GeoJSON (three side-by-side rectangular regions) under map name "toy", drives
// ECharts with a `series:[{type:"map", map:"toy", data:[{name,value}...]}]` (+ a continuous visualMap),
// and asserts the choropleth reaches the ZRenderKit scene graph:
//   (1) one region-polygon CompoundPath per feature (MapView wraps each region's Polygon subpaths in a
//       CompoundPath, same as GeoView), and
//   (2) the region FILLS VARY with the datum value — proving the visualMap encoding stage ran and MapView
//       read the encoded `getItemVisual(dataIdx,'style').fill` back (not the flat itemStyle backdrop).
// This also guards the full wiring: geoCreator's map-series-group path builds an exclusive Geo for the
// series and injects it as `coordinateSystem`; mapDataStatistic stamps `originalData`; MapView projects the
// region rings through the Geo. Without any of these the map renders empty / flat.
import XCTest
import ZRenderKit
@testable import EChartsKit

final class MapRenderTests: XCTestCase {

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

    private func makeOption() -> [String: Any] {
        return [
            "visualMap": [
                "type": "continuous",
                "min": 0.0,
                "max": 100.0,
                "calculable": true,
                "inRange": ["color": ["#e0f3f8", "#91bfdb", "#d94e5d"]] as [String: Any]
            ] as [String: Any],
            "series": [
                [
                    "type": "map",
                    "map": "toy",
                    "top": 40.0, "left": 40.0, "right": 40.0, "bottom": 40.0,
                    "label": ["show": true] as [String: Any],
                    "data": [
                        ["name": "West", "value": 20.0] as [String: Any],
                        ["name": "Central", "value": 60.0] as [String: Any],
                        ["name": "East", "value": 95.0] as [String: Any]
                    ] as [Any]
                ] as [String: Any]
            ]
        ]
    }

    func testMapRendersOneRegionPolygonPerRegion() {
        ECharts.registerMap("toy", makeToyGeoJSON())

        let ec = ECharts(width: 520, height: 320)
        ec.setOption(makeOption())

        // The map series must be wired onto a Geo coordinate system (geoCreator map-series-group path).
        guard let mapModel = ec.getModel()?.getSeriesByType("map").first as? MapSeriesModel else {
            return XCTFail("map series model not loaded")
        }
        XCTAssertTrue(mapModel.coordinateSystem is Geo, "map series should be injected with a Geo coord")

        // Each region's polygon subpaths are wrapped in ONE CompoundPath (MapView.createCompoundPath).
        var compoundPaths: [ZRenderKit.CompoundPath] = []
        _ = ec.getRoot().traverse { el in
            if let cp = el as? ZRenderKit.CompoundPath { compoundPaths.append(cp) }
            return false
        }
        XCTAssertGreaterThan(compoundPaths.count, 0, "map → at least one region-polygon CompoundPath")
        // Three regions → three polygon compound paths (no interiors / linestrings in the toy map).
        XCTAssertEqual(compoundPaths.count, 3, "one polygon CompoundPath per toy region")
    }

    func testMapRegionFillsVaryWithValue() {
        ECharts.registerMap("toy", makeToyGeoJSON())

        let ec = ECharts(width: 520, height: 320)
        ec.setOption(makeOption())

        var fills: [String] = []
        _ = ec.getRoot().traverse { el in
            if let cp = el as? ZRenderKit.CompoundPath, let fill = cp.pathStyle?.fill {
                if case let .string(s) = fill, !s.isEmpty {
                    fills.append(s)
                }
            }
            return false
        }

        XCTAssertEqual(fills.count, 3, "every region CompoundPath should carry a solid fill")
        // The visualMap encoding maps West(20)/Central(60)/East(95) to three distinct gradient samples,
        //   which MapView writes onto each region. Flat itemStyle would give one repeated color.
        XCTAssertGreaterThanOrEqual(Set(fills).count, 2,
            "region fills should vary with the datum value (visualMap encoding), got \(fills)")
    }
}
