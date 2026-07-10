// Transition-fidelity tail for the MAP chart: MapView now PERSISTS its per-region GeoJSON compound paths
// and MORPHS their FILL to the new visualMap color on a same-map / same-region-set merge-mode value change
// (a color tween) instead of `group.removeAll()`-rebuilding and snapping. A map's region GEOMETRY is fixed
// (from the registered GeoJSON), so only the fill (color STRING) is `updateProps`-morphed — the shape is
// untouched. Mirrors HeatmapMorphTests. Asserts: (1) a region compound path is IDENTITY-reused across the
// value change, (2) it schedules a color-tween animator, and (3) a map/region-set change rebuilds without
// duplication. (The SVG branch is left rebuilding — not exercised here.)
import XCTest
import ZRenderKit
@testable import EChartsKit

final class MapMorphTests: XCTestCase {

    // Toy GeoJSON: N rectangular regions side by side along lng (each 10 wide). Reused from MapRenderTests.
    private func makeToyGeoJSON(_ names: [String]) -> [String: Any] {
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
        var features: [Any] = []
        for (i, name) in names.enumerated() {
            features.append(feature(name, Double(i) * 10.0, Double(i) * 10.0 + 10.0))
        }
        return ["type": "FeatureCollection", "features": features]
    }

    private func makeOption(_ mapName: String, _ data: [[String: Any]]) -> [String: Any] {
        return [
            "animation": true,
            "visualMap": [
                "type": "continuous", "min": 0.0, "max": 100.0, "calculable": true,
                "inRange": ["color": ["#e0f3f8", "#91bfdb", "#d94e5d"]] as [String: Any]
            ] as [String: Any],
            "series": [
                [
                    "type": "map", "map": mapName, "animation": true,
                    "top": 40.0, "left": 40.0, "right": 40.0, "bottom": 40.0,
                    "label": ["show": true] as [String: Any],
                    "data": data as [Any]
                ] as [String: Any]
            ]
        ]
    }

    private func mapModel(_ ec: ECharts) -> MapSeriesModel? {
        ec.getModel()?.getSeriesByType("map").first as? MapSeriesModel
    }

    // The region compound path is a CompoundPath child of the region GROUP (data.getItemGraphicEl(idx)).
    private func regionPath(_ ec: ECharts, dataIdx: Int) -> ZRenderKit.CompoundPath? {
        guard let group = mapModel(ec)?.getData().getItemGraphicEl(dataIdx) as? Group else { return nil }
        var found: ZRenderKit.CompoundPath?
        _ = group.traverse { el in
            if found == nil, let cp = el as? ZRenderKit.CompoundPath { found = cp }
            return false
        }
        return found
    }

    // Count every region compound path across the chart views' groups (duplication guard).
    private func regionPathCount(_ ec: ECharts) -> Int {
        var n = 0
        for v in ec.testChartViews {
            _ = v.group.traverse { el in if el is ZRenderKit.CompoundPath { n += 1 }; return false }
        }
        return n
    }

    private func clearAnimators(_ ec: ECharts) {
        for v in ec.testChartViews {
            _ = v.group.traverse { el in _ = el.stopAnimation(nil); return false }
        }
    }

    func testRegionFillMorphsOnValueChange() {
        ECharts.registerMap("toyMorph", makeToyGeoJSON(["West", "Central", "East"]))
        let ec = ECharts(width: 520, height: 320)
        ec.setOption(makeOption("toyMorph", [
            ["name": "West", "value": 20.0] as [String: Any],
            ["name": "Central", "value": 60.0] as [String: Any],
            ["name": "East", "value": 95.0] as [String: Any]
        ]))

        let westIdx = mapModel(ec)!.getData().indexOfName("West")
        let path1 = regionPath(ec, dataIdx: westIdx)
        XCTAssertNotNil(path1, "first render produced the West region compound path")
        let fill1: String? = { if case let .string(s)? = path1?.pathStyle?.fill { return s }; return nil }()
        XCTAssertNotNil(fill1, "region fill is a color STRING (so the Animator can tween it)")

        // Clear the first render's enter/fade-in animators.
        clearAnimators(ec)
        XCTAssertEqual(path1?.animators.count, 0, "animators cleared before the value change")

        // Merge-mode value change: SAME map + SAME regions, DIFFERENT values → the region fill morphs.
        ec.setOption(["series": [[
            "type": "map", "map": "toyMorph",
            "data": [
                ["name": "West", "value": 95.0] as [String: Any],
                ["name": "Central", "value": 20.0] as [String: Any],
                ["name": "East", "value": 60.0] as [String: Any]
            ] as [Any]
        ] as [String: Any]]])

        let path2 = regionPath(ec, dataIdx: mapModel(ec)!.getData().indexOfName("West"))

        // (1) The SAME region compound path instance is reused (not rebuilt).
        XCTAssertNotNil(path2)
        XCTAssertTrue(path1 === path2, "region compound path reused across the value change (not rebuilt)")

        // (2) It schedules a color-tween animator (fill: old visualMap color → new visualMap color).
        XCTAssertGreaterThan(path2!.animators.count, 0,
                             "region must schedule a color-morph animator on a same-region-set value change")
    }

    func testMapChangeRebuildsWithoutDuplication() {
        ECharts.registerMap("toyA", makeToyGeoJSON(["West", "Central", "East"]))
        ECharts.registerMap("toyB", makeToyGeoJSON(["Alpha", "Beta"]))

        let ec = ECharts(width: 520, height: 320)
        ec.setOption(makeOption("toyA", [
            ["name": "West", "value": 20.0] as [String: Any],
            ["name": "Central", "value": 60.0] as [String: Any],
            ["name": "East", "value": 95.0] as [String: Any]
        ]))
        XCTAssertEqual(regionPathCount(ec), 3, "3 region paths on first render (toyA)")

        // Switch to a DIFFERENT map (different region set) → rebuild fresh, no stale duplicates.
        ec.setOption(makeOption("toyB", [
            ["name": "Alpha", "value": 30.0] as [String: Any],
            ["name": "Beta", "value": 70.0] as [String: Any]
        ]))
        XCTAssertEqual(regionPathCount(ec), 2,
                       "a map / region-set change rebuilds (2 region paths), no duplication of the old 3")
    }

    func testRegionSetChangeRebuilds() {
        // Same map name is NOT reused across a differing region set: growing the region set rebuilds fresh.
        ECharts.registerMap("toyGrow", makeToyGeoJSON(["West", "East"]))
        let ec = ECharts(width: 520, height: 320)
        ec.setOption(makeOption("toyGrow", [
            ["name": "West", "value": 20.0] as [String: Any],
            ["name": "East", "value": 95.0] as [String: Any]
        ]))
        XCTAssertEqual(regionPathCount(ec), 2, "2 region paths for the 2-region map")

        // Re-register the SAME name with a THIRD region, then re-set the option (new geometry → rebuild).
        ECharts.registerMap("toyGrow", makeToyGeoJSON(["West", "Central", "East"]))
        ec.setOption(makeOption("toyGrow", [
            ["name": "West", "value": 20.0] as [String: Any],
            ["name": "Central", "value": 60.0] as [String: Any],
            ["name": "East", "value": 95.0] as [String: Any]
        ]))
        XCTAssertEqual(regionPathCount(ec), 3, "a region-set change rebuilds 3 region paths, no duplication")
    }
}
