// Region-rebuild fidelity for the MAP chart.
//
// HISTORY: this file used to assert a port-INVENTED L5 feature — MapView kept a name-keyed cache of the
// per-region GeoJSON compound paths and `updateProps`-tweened their visualMap FILL across a merge-mode
// value change (`_morphGeoJSON`). When MapView switched over to the shared `MapDraw` (the real upstream
// owner of the region backdrop), that invention was retired: upstream `MapDraw._buildGeoJSON`
// (MapDraw.ts:297) does `regionsGroup.removeAll()` and rebuilds EVERY region path on every draw, so the
// paths are neither identity-reused nor colour-tweened. See the switchover PORT-NOTE at the top of
// MapView.swift.
//
// These tests now assert the upstream semantics: (1) a same-region-set value change REBUILDS the region
// paths (fresh instances, new fill, no colour-tween animator), and (2)/(3) a map / region-set change
// rebuilds without duplication. (The SVG branch is left rebuilding — not exercised here.)
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

    // Upstream MapDraw rebuilds the whole regions group on every draw — a value change therefore produces
    // FRESH region paths carrying the new visualMap fill, with no identity reuse and no colour tween.
    func testRegionRebuildsOnValueChange() {
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

        // Merge-mode value change: SAME map + SAME regions, DIFFERENT values → upstream rebuilds them.
        ec.setOption(["series": [[
            "type": "map", "map": "toyMorph",
            "data": [
                ["name": "West", "value": 95.0] as [String: Any],
                ["name": "Central", "value": 20.0] as [String: Any],
                ["name": "East", "value": 60.0] as [String: Any]
            ] as [Any]
        ] as [String: Any]]])

        let path2 = regionPath(ec, dataIdx: mapModel(ec)!.getData().indexOfName("West"))

        // (1) Upstream `regionsGroup.removeAll()` + rebuild ⇒ a FRESH path instance, no identity reuse.
        XCTAssertNotNil(path2, "the value change re-rendered the West region")
        XCTAssertFalse(path1 === path2,
                       "upstream MapDraw._buildGeoJSON rebuilds the regions group — no identity reuse")

        // (2) The rebuilt path carries the NEW visualMap color, applied directly (no colour tween).
        let fill2: String? = { if case let .string(s)? = path2?.pathStyle?.fill { return s }; return nil }()
        XCTAssertNotNil(fill2, "rebuilt region fill is a color STRING")
        XCTAssertNotEqual(fill1, fill2, "West 20 → 95 must land on a different visualMap color")
        XCTAssertEqual(path2!.animators.count, 0,
                       "upstream MapDraw schedules no fill-morph animator (the L5 colour tween was retired)")

        // (3) No duplication: still exactly one path per region after the rebuild.
        XCTAssertEqual(regionPathCount(ec), 3, "rebuild leaves 3 region paths, no stale duplicates")
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
