// RETROFIT TEST for the map chart's region LABEL onto the SHARED LABEL CORE (label/labelStyle.swift).
//
// Before the retrofit, `MapView._resetLabelForRegion` drew each region label as a STANDALONE `ZRText`
// added to the region group — the region compound-path element had NO `textContent`. After the retrofit
// the label is attached to the region compound-path el via `labelStyle.setLabelStyle`, so the el exposes
// a `getTextContent()` whose `style.text` is the region name. Since MapView switched over to the shared
// `MapDraw`, `el.textConfig.position` is the upstream `labelXY` percent-offset ARRAY (the region centroid
// expressed relative to the el bounding rect) rather than a named position keyword — see
// MapDraw.resetLabelForRegion / MapDraw.ts:742 and the switchover note in MapView.swift. These tests
// assert that end-to-end (drive ECharts → walk the scene graph → inspect the CompoundPath's label).
import XCTest
import ZRenderKit
@testable import EChartsKit

final class MapLabelTests: XCTestCase {

    // Toy GeoJSON: three rectangular regions side by side along lng.
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

    private func makeOption(labelExtra: [String: Any] = [:]) -> [String: Any] {
        var label: [String: Any] = ["show": true]
        for (k, v) in labelExtra { label[k] = v }
        return [
            "series": [
                [
                    "type": "map",
                    "map": "toy",
                    "top": 40.0, "left": 40.0, "right": 40.0, "bottom": 40.0,
                    "label": label,
                    "data": [
                        ["name": "West", "value": 20.0] as [String: Any],
                        ["name": "Central", "value": 60.0] as [String: Any],
                        ["name": "East", "value": 95.0] as [String: Any]
                    ] as [Any]
                ] as [String: Any]
            ]
        ]
    }

    // Collect every region CompoundPath in render order.
    private func compoundPaths(_ ec: ECharts) -> [ZRenderKit.CompoundPath] {
        var out: [ZRenderKit.CompoundPath] = []
        _ = ec.getRoot().traverse { el in
            if let cp = el as? ZRenderKit.CompoundPath { out.append(cp) }
            return false
        }
        return out
    }

    // ---- (1) after render, each region compound-path el carries the label as textContent ----
    func testRegionLabelAttachedAsTextContent() {
        ECharts.registerMap("toy", makeToyGeoJSON())
        let ec = ECharts(width: 520, height: 320)
        ec.setOption(makeOption())

        let paths = compoundPaths(ec)
        XCTAssertEqual(paths.count, 3, "one polygon CompoundPath per toy region")

        // Every region compound-path must own a ZRText textContent whose text is the region name.
        var texts: [String] = []
        for cp in paths {
            guard let label = cp.getTextContent() else {
                return XCTFail("region CompoundPath must own a label textContent (setLabelStyle)")
            }
            XCTAssertFalse(label.ignore, "label.show:true → attached label must not be ignored")
            if let t = label.textStyle.text { texts.append(t) }
        }
        XCTAssertEqual(Set(texts), ["West", "Central", "East"],
                       "each region label text is the region (datum) name, got \(texts)")
    }

    // ---- (2) textConfig.position is the labelXY percent-offset ARRAY for a geoJSON region ----
    //   `MapDraw._buildGeoJSON` always passes the region `centerPt` as `labelXY` (MapDraw.ts:368), and
    //   `resetLabelForRegion` then OVERWRITES `el.textConfig.position` with a two-element percent STRING
    //   array relative to the el bounding rect, plus a `layoutRect` (MapDraw.ts:742). So the region label
    //   is positioned at the region centroid, NOT by a named position keyword.
    func testRegionLabelPositionIsCenterPercentArray() {
        ECharts.registerMap("toy", makeToyGeoJSON())
        let ec = ECharts(width: 520, height: 320)
        ec.setOption(makeOption())

        for cp in compoundPaths(ec) {
            guard let cfg = cp.textConfig else {
                return XCTFail("region CompoundPath must have a textConfig after setLabelStyle")
            }
            guard let pos = cfg.position as? [String] else {
                return XCTFail("region label position must be the labelXY percent array, got \(String(describing: cfg.position))")
            }
            XCTAssertEqual(pos.count, 2, "percent position is [x%, y%]")
            for p in pos {
                XCTAssertTrue(p.hasSuffix("%"), "each component is a percent string, got \(p)")
            }
            XCTAssertNotNil(cfg.layoutRect,
                            "the percent position is resolved against textConfig.layoutRect (the el rect)")
        }
    }

    // ---- (3) an explicit label.position is IGNORED for a geoJSON region (labelXY wins) ----
    //   before the MapDraw switchover the inlined `_resetLabelForRegion` let `label.position`
    //   reach `textConfig.position`. Upstream does not: the `labelXY` percent array unconditionally
    //   replaces whatever `createTextConfig` derived from the label model. (SVG regions pass
    //   `labelXY == nil` and therefore DO keep the named position.)
    func testRegionLabelExplicitPositionOverriddenByLabelXY() {
        ECharts.registerMap("toy", makeToyGeoJSON())
        let ec = ECharts(width: 520, height: 320)
        ec.setOption(makeOption(labelExtra: ["position": "top"]))

        for cp in compoundPaths(ec) {
            XCTAssertNil(cp.textConfig?.position as? String,
                         "label.position must NOT survive as a string — labelXY overwrites it upstream")
            XCTAssertEqual((cp.textConfig?.position as? [String])?.count, 2,
                           "region label position stays the labelXY percent array")
        }
    }

    // ---- (4) normal label.show:false → the normal-state label is hidden (ignored) ----
    //   NOTE: the map series default sets emphasis/select label.show:true, so setLabelStyle still
    //   creates a textContent (needed for those states) but marks the NORMAL render as ignored — matching
    //   upstream. So the assertion is "normal label is not shown", i.e. textContent.ignore == true.
    func testRegionLabelHiddenWhenShowFalse() {
        ECharts.registerMap("toy", makeToyGeoJSON())
        let ec = ECharts(width: 520, height: 320)
        var opt = makeOption()
        // Override the series label to show:false.
        var series = (opt["series"] as! [[String: Any]])
        series[0]["label"] = ["show": false] as [String: Any]
        opt["series"] = series
        ec.setOption(opt)

        for cp in compoundPaths(ec) {
            if let label = cp.getTextContent() {
                XCTAssertTrue(label.ignore,
                              "normal label.show:false → the normal-state label must be ignored (hidden)")
            }
        }
    }
}
