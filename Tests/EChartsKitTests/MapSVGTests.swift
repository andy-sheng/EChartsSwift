// SVG-BACKED MAP completion tests (echarts/src/component/helper/MapDraw.ts `_buildSVG`).
//
// Proves the geoSVG interactivity that landed on top of the parseSVG + GeoSVGResource core:
//   (a) a NAMED SVG region is a highDown dispatcher → enters "emphasis" on a highlight (GeoView._buildSVG's
//       resetStateTriggerForRegion → toggleHoverEmphasis + setStatesStylesFromModel);
//   (b) named SVG regions get a NAME LABEL via the shared label core (setLabelStyle → el.textContent);
//   (c) geo ROAM shifts the SVG root group (the OVERALL view transform, WITH roam, is copied onto the svg
//       wrapper group; a drag re-seeds it through the full update());
//   (d) a series:"map" on an SVG map binds each datum to its named region and colours it by value
//       (MapView._buildSVG: applyOptionStyleForRegion visualMap fill + data.setItemGraphicEl).
import XCTest
import ZRenderKit
@testable import EChartsKit

final class MapSVGTests: XCTestCase {

    // A toy SVG map: three named shapes (a <rect>, a <circle> and a <path>) → three geo REGIONS.
    private let toySVG = """
    <svg width="200" height="120" viewBox="0 0 200 120">
      <rect name="alpha" x="10" y="10" width="60" height="90" fill="#4e79a7"/>
      <circle name="beta" cx="120" cy="55" r="40" fill="#e15759"/>
      <path name="gamma" d="M150 100 L190 100 L170 20 Z" fill="#59a14f"/>
    </svg>
    """

    // MARK: (a) emphasis on a named region

    func test_geoSVG_namedRegion_entersEmphasisOnHighlight() {
        ECharts.registerMap("emphSVG", ["svg": toySVG] as [String: Any])

        let ec = ECharts(width: 520, height: 320)
        ec.setOption([
            "geo": [
                "map": "emphSVG",
                "top": 20.0, "left": 20.0, "right": 20.0, "bottom": 20.0
            ] as [String: Any]
        ])

        guard let geoModel = ec.getModel()?.getComponent("geo", 0) as? GeoModel,
              let geoView = ec._componentsViews.compactMap({ $0 as? GeoView }).first else {
            return XCTFail("geo component / GeoView not wired for an SVG map")
        }

        // The named <rect> region is registered as a highDown dispatcher.
        let dispatchers = geoView.findHighDownDispatchers("alpha") ?? []
        XCTAssertEqual(dispatchers.count, 1, "one dispatcher element registered for the named region 'alpha'")
        guard let el = dispatchers.first else { return XCTFail("no dispatcher for 'alpha'") }

        XCTAssertTrue(states.isHighDownDispatcher(el),
                      "GeoView._buildSVG must mark the named SVG region a highDown dispatcher")
        XCTAssertNotNil(el.getState("emphasis"),
                        "applyOptionStyleForRegion must stamp the emphasis itemStyle state")
        XCTAssertTrue(el.currentStates.isEmpty, "region must not be in emphasis before a highlight")

        // A highlight lands the "emphasis" state on the region (the same call a highlight dispatch makes).
        states.enterEmphasis(el)
        XCTAssertTrue(el.currentStates.contains("emphasis"),
                      "highlighting a named SVG region must drive it into emphasis")

        states.leaveEmphasis(el)
        XCTAssertTrue(el.currentStates.isEmpty, "downplay must clear the region emphasis")
    }

    // MARK: (b) region name labels

    func test_geoSVG_namedRegions_getNameLabels() {
        ECharts.registerMap("labelSVG", ["svg": toySVG] as [String: Any])

        let ec = ECharts(width: 520, height: 320)
        ec.setOption([
            "geo": [
                "map": "labelSVG",
                "top": 20.0, "left": 20.0, "right": 20.0, "bottom": 20.0,
                "label": ["show": true] as [String: Any]
            ] as [String: Any]
        ])

        guard let geoModel = ec.getModel()?.getComponent("geo", 0) as? GeoModel,
              let geoView = ec._componentsViews.compactMap({ $0 as? GeoView }).first else {
            return XCTFail("geo component / GeoView not wired for an SVG map")
        }

        for name in ["alpha", "beta", "gamma"] {
            guard let el = geoView.findHighDownDispatchers(name)?.first else {
                XCTFail("no region element for '\(name)'"); continue
            }
            guard let text = el.getTextContent() else {
                XCTFail("named region '\(name)' must get a name label (setLabelStyle → textContent)"); continue
            }
            XCTAssertEqual(text.textStyle?.text, name, "the region label text defaults to the region name")
        }
    }

    // MARK: (c) roam shifts the SVG root group

    // The component view is recreated on the full update() a geoRoam triggers, so re-fetch it each read.
    private func svgWrapperX(_ view: EChartsView) -> Double? {
        let geoView = view.ec._componentsViews.compactMap { $0 as? GeoView }.first
        // GeoView delegates to MapDraw: view group → `mapDraw.group` → `_transformGroup`, which is the
        // element the ROAM transform is applied to (the svg root below it carries only the RAW trans).
        let mapDrawGroup = geoView?.group.childAt(0) as? Group
        return (mapDrawGroup?.childAt(0) as? Group)?.x
    }

    func test_geoSVG_roamShiftsSvgRootGroup() {
        ECharts.registerMap("roamSVG", ["svg": toySVG] as [String: Any])

        let view = EChartsView(width: 520, height: 320)
        view.setOption([
            "geo": [
                "map": "roamSVG",
                "roam": true,
                "top": 40.0, "left": 40.0, "right": 40.0, "bottom": 40.0
            ] as [String: Any]
        ])
        _ = view.zr.storage.getDisplayList(true)

        guard let geoModel = view.ec.getModel()?.getComponent("geo", 0) as? GeoModel,
              let geo = geoModel.coordinateSystem as? Geo else {
            return XCTFail("geo SVG not wired")
        }

        // The svg wrapper group is the geo view group's child; its transform x is the OVERALL trans x.
        guard let beforeX = svgWrapperX(view) else { return XCTFail("no svg wrapper group after render") }

        // A drag over the map center pans the geo, which re-copies the shifted OVERALL trans onto the group.
        let r = geo.getViewRect()
        let cx = r.x + r.width / 2, cy = r.y + r.height / 2
        let dx = 40.0, dy = 30.0
        view._injectPointerForTest(type: "mousedown", zrX: cx, zrY: cy)
        view._injectPointerForTest(type: "mousemove", zrX: cx + dx, zrY: cy + dy)
        view._injectPointerForTest(type: "mouseup", zrX: cx + dx, zrY: cy + dy)
        _ = view.zr.storage.getDisplayList(true)

        guard let afterX = svgWrapperX(view) else { return XCTFail("no svg wrapper group after the pan re-render") }
        print("SVG-ROAM pan: svgGroup.x \(beforeX) -> \(afterX)")
        XCTAssertEqual(afterX - beforeX, dx, accuracy: 0.5, "geo roam must shift the SVG root group by dx")
    }

    // A geo SVG WITHOUT roam is inert to a drag.
    func test_geoSVG_noRoamIsInert() {
        ECharts.registerMap("inertSVG", ["svg": toySVG] as [String: Any])

        let view = EChartsView(width: 520, height: 320)
        view.setOption([
            "geo": ["map": "inertSVG", "top": 40.0, "left": 40.0, "right": 40.0, "bottom": 40.0] as [String: Any]
        ])
        _ = view.zr.storage.getDisplayList(true)

        guard let geoModel = view.ec.getModel()?.getComponent("geo", 0) as? GeoModel,
              let geo = geoModel.coordinateSystem as? Geo else {
            return XCTFail("geo SVG not wired")
        }
        guard let beforeX = svgWrapperX(view) else { return XCTFail("no svg wrapper group") }

        let r = geo.getViewRect()
        let cx = r.x + r.width / 2, cy = r.y + r.height / 2
        view._injectPointerForTest(type: "mousedown", zrX: cx, zrY: cy)
        view._injectPointerForTest(type: "mousemove", zrX: cx + 50, zrY: cy + 50)
        view._injectPointerForTest(type: "mouseup", zrX: cx + 50, zrY: cy + 50)
        _ = view.zr.storage.getDisplayList(true)

        guard let afterX = svgWrapperX(view) else { return XCTFail("no svg wrapper group") }
        XCTAssertEqual(afterX, beforeX, accuracy: 1e-6, "roam:off geo SVG must not pan")
    }

    // MARK: (d) series:"map" on an SVG map colours regions by value

    func test_mapSeriesSVG_bindsValueToNamedRegion_colorsByValue() {
        ECharts.registerMap("seriesSVG", ["svg": toySVG] as [String: Any])

        let ec = ECharts(width: 520, height: 320)
        ec.setOption([
            "visualMap": [
                "type": "continuous",
                "min": 0.0, "max": 100.0,
                "inRange": ["color": ["#e0f3f8", "#91bfdb", "#d94e5d"]] as [String: Any]
            ] as [String: Any],
            "series": [
                [
                    "type": "map",
                    "map": "seriesSVG",
                    "top": 40.0, "left": 40.0, "right": 40.0, "bottom": 40.0,
                    "data": [
                        ["name": "alpha", "value": 20.0] as [String: Any],
                        ["name": "beta", "value": 60.0] as [String: Any],
                        ["name": "gamma", "value": 95.0] as [String: Any]
                    ] as [Any]
                ] as [String: Any]
            ]
        ])

        guard let mapModel = ec.getModel()?.getSeriesByType("map").first as? MapSeriesModel else {
            return XCTFail("map series model not loaded")
        }
        XCTAssertTrue(mapModel.coordinateSystem is Geo, "map series should be injected with a Geo coord")
        XCTAssertEqual((mapModel.coordinateSystem as? Geo)?.resourceType, "geoSVG",
                       "the map series must render on a geoSVG coord system")

        let data = mapModel.getData()
        var fills: [String] = []
        for name in ["alpha", "beta", "gamma"] {
            let idx = data.indexOfName(name)
            XCTAssertTrue(idx >= 0, "map data binds a datum to region '\(name)'")
            // The named SVG element is bound as the datum's graphic el (resetEventTriggerForRegion).
            guard let el = data.getItemGraphicEl(idx) else {
                XCTFail("map series must bind region '\(name)' to its named SVG element"); continue
            }
            if let path = el as? Path, let fill = path.pathStyle?.fill, case let .string(s) = fill, !s.isEmpty {
                fills.append(s)
            }
        }

        XCTAssertEqual(fills.count, 3, "every bound region should carry a solid fill")
        // The visualMap maps 20 / 60 / 95 to three distinct colours the map series writes onto each region.
        XCTAssertGreaterThanOrEqual(Set(fills).count, 2,
            "region fills should vary with the datum value (visualMap encoding), got \(fills)")
    }
}
