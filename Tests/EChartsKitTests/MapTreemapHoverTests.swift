// Phase 49 regression test — LIVE hover→emphasis for the MAP and TREEMAP charts, the two remaining
// per-item views that were not yet highDown dispatchers (chord already had it).
//
// Modeled on ZZHoverBreadth3Tests (graph/tree/sankey): build an EChartsView, grab a per-item element via
// `data.getItemGraphicEl(idx)`, inject a synthetic pointer over its bounding-rect center (mapped to GLOBAL
// coords via `transformCoordToGlobal`, since the elements sit under a translated series group) through
// `_injectPointerForTest`, and assert the item enters the "emphasis" state through the REAL Handler
// hit-test + the EChartsView "mouseover" listener → states.enterEmphasisWhenMouseOver. A second mousemove
// off the item proves the "mouseout" leg clears emphasis.
//
// This proves MapView marks each region GROUP a highDown dispatcher (mirroring MapDraw.ts's
// resetStateTriggerForRegion) and TreemapView marks each leaf tile GROUP (and each parent background) a
// dispatcher (mirroring TreemapView.ts:828-859), so hover-to-highlight now works for these too.
import XCTest
import ZRenderKit
@testable import EChartsKit

final class MapTreemapHoverTests: XCTestCase {

    private func containsState(_ el: Element, _ state: String) -> Bool {
        var found = el.currentStates.contains(state)
        el.traverse { child in
            found = found || child.currentStates.contains(state)
        }
        return found
    }

    // Elements sit under a series group translated to the layout origin. The element's world `transform`
    // (composed after getDisplayList(true)) maps its local bounding-rect center to the GLOBAL pixel the
    // Handler hit-tests against.
    private func globalCenter(_ el: Element) -> (Double, Double)? {
        guard let r = el.getBoundingRect() else { return nil }
        let lx = r.x + r.width / 2
        let ly = r.y + r.height / 2
        let g = el.transformCoordToGlobal(lx, ly)
        return (g[0], g[1])
    }

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

    // MARK: - Map (region groups)

    func testMapRegionHoverEntersEmphasis() {
        ECharts.registerMap("hoverToy", makeToyGeoJSON())

        let view = EChartsView(width: 520, height: 320)
        view.setOption([
            "series": [[
                "type": "map",
                "map": "hoverToy",
                "top": 40.0, "left": 40.0, "right": 40.0, "bottom": 40.0,
                "data": [
                    ["name": "West", "value": 20.0] as [String: Any],
                    ["name": "Central", "value": 60.0] as [String: Any],
                    ["name": "East", "value": 95.0] as [String: Any]
                ] as [Any]
            ] as [String: Any]]
        ])

        let series = view.ec.getModel()!.getSeriesByIndex(0)!
        let data = series.getData()
        let idx = data.indexOfName("Central")
        XCTAssertTrue(idx >= 0, "map data must contain a region named 'Central'")
        guard let el = data.getItemGraphicEl(idx) else {
            XCTFail("map render must populate a region group for 'Central'"); return
        }
        XCTAssertTrue(states.isHighDownDispatcher(el),
                      "MapView must mark each region group a highDown dispatcher")
        XCTAssertFalse(containsState(el, "emphasis"), "map region must not be in emphasis before any hover")

        _ = view.zr.storage.getDisplayList(true)
        guard let (cx, cy) = globalCenter(el) else { XCTFail("no bounding rect"); return }

        view._injectPointerForTest(type: "mousemove", zrX: cx, zrY: cy)
        XCTAssertTrue(containsState(el, "emphasis"),
                      "an injected pointer over the map region must drive it into emphasis")

        view._injectPointerForTest(type: "mousemove", zrX: 1, zrY: 1)
        XCTAssertFalse(containsState(el, "emphasis"),
                      "moving off the map region must clear its emphasis via the mouseout leg")
    }

    // MARK: - Treemap (leaf tile groups)

    func testTreemapTileHoverEntersEmphasis() {
        // Canvas is larger than the treemap so there is EMPTY space to move the pointer off into (the
        // treemap tiles fully cover their own 400x400 box, so an off point inside it would land on another
        // tile rather than empty space).
        let view = EChartsView(width: 500, height: 500)
        view.setOption([
            "series": [[
                "type": "treemap",
                "animation": false,
                "left": 0.0, "top": 0.0, "width": 400.0, "height": 400.0,
                "roam": false,
                "data": [
                    ["name": "nodeA", "value": 10.0, "children": [
                        ["name": "nodeA1", "value": 4.0] as [String: Any],
                        ["name": "nodeA2", "value": 6.0] as [String: Any]
                    ]] as [String: Any],
                    ["name": "nodeB", "value": 20.0, "children": [
                        ["name": "nodeB1", "value": 5.0] as [String: Any],
                        ["name": "nodeB2", "value": 8.0] as [String: Any]
                    ]] as [String: Any]
                ] as [Any]
            ] as [String: Any]]
        ])

        let series = view.ec.getModel()!.getSeriesByIndex(0)!
        let data = series.getData()
        // A LEAF tile ('nodeB2') is a node GROUP dispatcher (its background+content children are traversed
        // for the state proxy). Its rect is its own region, so the bounding-center hit resolves it cleanly.
        let idx = data.indexOfName("nodeB2")
        XCTAssertTrue(idx >= 0, "treemap data must contain a leaf named 'nodeB2'")
        guard let el = data.getItemGraphicEl(idx) else {
            XCTFail("treemap render must populate a tile group for leaf 'nodeB2'"); return
        }
        XCTAssertTrue(states.isHighDownDispatcher(el),
                      "TreemapView must mark each leaf tile group a highDown dispatcher")
        XCTAssertFalse(containsState(el, "emphasis"), "treemap tile must not be in emphasis before any hover")

        _ = view.zr.storage.getDisplayList(true)
        guard let (cx, cy) = globalCenter(el) else { XCTFail("no bounding rect"); return }

        view._injectPointerForTest(type: "mousemove", zrX: cx, zrY: cy)
        XCTAssertTrue(containsState(el, "emphasis"),
                      "an injected pointer over the treemap tile must drive it into emphasis")

        // Move into the empty margin (x > 400) — off every tile — to fire the mouseout leg.
        view._injectPointerForTest(type: "mousemove", zrX: 470, zrY: 470)
        XCTAssertFalse(containsState(el, "emphasis"),
                      "moving off the treemap tile must clear its emphasis via the mouseout leg")
    }
}
