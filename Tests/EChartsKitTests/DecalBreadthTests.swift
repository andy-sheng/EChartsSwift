// Verifies the DECAL BREADTH port (extending decal beyond BarView):
//   (a) the itemStyle.decal → pathStyle.decal bridge in the other decal-capable series views —
//       pie (Sector), funnel (Polygon), map (region CompoundPath) — each synthesizes a `_decalEl`
//       (Path.getDecalElement()) filled with the generated tiling Pattern; and the FAITHFUL scatter
//       case where the symbol path intentionally clears decal (upstream Symbol.ts:296-297).
//   (b) SeriesModel.enableAriaDecal (chart/helper/enableAriaDecalForTree) — aria.decal.show assigns a
//       per-node decal visual to a tree-structured series (treemap).
//
// ECharts registers all built-in series in its init, so no manual registerClass is needed here
// (avoids the process-global registry-pollution trap).

import XCTest
import ZRenderKit
@testable import EChartsKit

final class DecalBreadthTests: XCTestCase {

    // A rect-symbol itemStyle.decal (any decal produces a Pattern with a non-empty tile on Darwin).
    private func itemDecal() -> [String: Any] {
        return [
            "symbol": "rect",
            "color": "#ffffff",
            "dashArrayX": [2, 2],
            "dashArrayY": [2, 2],
            "symbolSize": 1
        ]
    }

    // ---- (a) pie ------------------------------------------------------------------------------

    func testPieItemStyleDecalSynthesizesDecalElement() {
        let ec = ECharts(width: 400, height: 320)
        ec.setOption([
            "series": [["type": "pie", "radius": "65%",
                        "data": [
                            ["value": 40.0, "name": "A", "itemStyle": ["decal": itemDecal()] as [String: Any]],
                            ["value": 30.0, "name": "B"],
                            ["value": 20.0, "name": "C"],
                            ["value": 10.0, "name": "D"]
                        ]] as [String: Any]]
        ])

        var sectors: [Sector] = []
        _ = ec.getRoot().traverse { el in
            if let s = el as? Sector { sectors.append(s) }
            return false
        }
        guard let decaled = sectors.first else { return XCTFail("pie should emit Sectors") }

        guard let pattern = decaled.pathStyle.decal else {
            return XCTFail("pie sector with itemStyle.decal should carry pathStyle.decal (via barStyleFromDict)")
        }
        XCTAssertFalse(decalImageURI(pattern)?.isEmpty ?? true, "the decal Pattern must carry a tile image")

        decaled.update()
        guard let decalEl = decaled.getDecalElement() else {
            return XCTFail("Path.update() should synthesize a decal element for the decal-textured slice")
        }
        XCTAssertTrue(decalEl.silent)
        guard case .some(.pattern) = decalEl.pathStyle.fill else {
            return XCTFail("decal element fill should be the decal Pattern")
        }

        // A plain (no-decal) slice does NOT synthesize a decal element.
        let plain = sectors[1]
        XCTAssertNil(plain.pathStyle.decal, "the non-decal slice keeps a nil decal")
        plain.update()
        XCTAssertNil(plain.getDecalElement(), "no decal element for the plain slice")
    }

    // ---- (a) funnel ---------------------------------------------------------------------------

    func testFunnelItemStyleDecalSynthesizesDecalElement() {
        let ec = ECharts(width: 400, height: 400)
        ec.setOption([
            "animation": false,
            "series": [["type": "funnel",
                        "data": [
                            ["value": 60.0, "name": "a", "itemStyle": ["decal": itemDecal()] as [String: Any]],
                            ["value": 40.0, "name": "b"]
                        ]] as [String: Any]]
        ])

        var pieces: [ZRenderKit.Polygon] = []
        _ = ec.getRoot().traverse { el in
            if let p = el as? ZRenderKit.Polygon, p.name == "item" { pieces.append(p) }
            return false
        }
        guard let decaled = pieces.first else { return XCTFail("funnel should emit piece Polygons") }

        guard let pattern = decaled.pathStyle.decal else {
            return XCTFail("funnel piece with itemStyle.decal should carry pathStyle.decal (via barStyleFromDict)")
        }
        XCTAssertFalse(decalImageURI(pattern)?.isEmpty ?? true)

        decaled.update()
        guard let decalEl = decaled.getDecalElement() else {
            return XCTFail("Path.update() should synthesize a decal element for the decal-textured piece")
        }
        guard case .some(.pattern) = decalEl.pathStyle.fill else {
            return XCTFail("decal element fill should be the decal Pattern")
        }
    }

    // ---- (a) scatter (FAITHFUL: decal intentionally disabled on symbols) -----------------------

    func testScatterSymbolDecalIsDisabledFaithfully() {
        // Series-level itemStyle.decal — every symbol would receive it via barStyleFromDict, but the
        // Symbol path clears it (faithful to upstream).
        let ec = ECharts(width: 400, height: 300)
        ec.setOption([
            "grid": ["left": 40.0, "top": 20.0, "width": 320.0, "height": 220.0] as [String: Any],
            "xAxis": ["type": "value"] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [["type": "scatter", "symbolSize": 20.0,
                        "itemStyle": ["decal": itemDecal()] as [String: Any],
                        "data": [[10.0, 20.0], [20.0, 30.0], [30.0, 15.0]]] as [String: Any]]
        ])

        var symbols: [Path] = []
        _ = ec.getRoot().traverse { el in
            if let p = el as? Path, p.name == "item" { symbols.append(p) }
            return false
        }
        XCTAssertFalse(symbols.isEmpty, "scatter should emit symbol paths")
        for p in symbols {
            XCTAssertNil(p.pathStyle.decal,
                         "scatter/symbol path faithfully clears decal (upstream Symbol.ts:296-297)")
            p.update()
            XCTAssertNil(p.getDecalElement(),
                         "no decal element is synthesized for a symbol (decal disabled)")
        }
    }

    // ---- (a) map region -----------------------------------------------------------------------

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

    func testMapRegionItemStyleDecalSynthesizesDecalElement() {
        ECharts.registerMap("toyDecal", makeToyGeoJSON())
        let ec = ECharts(width: 520, height: 320)
        ec.setOption([
            "series": [[
                "type": "map",
                "map": "toyDecal",
                "top": 40.0, "left": 40.0, "right": 40.0, "bottom": 40.0,
                "data": [
                    ["name": "West", "value": 20.0, "itemStyle": ["decal": itemDecal()] as [String: Any]] as [String: Any],
                    ["name": "Central", "value": 60.0] as [String: Any],
                    ["name": "East", "value": 95.0] as [String: Any]
                ] as [Any]
            ] as [String: Any]]
        ])

        // The region CompoundPath carrying a decal is the "West" region.
        var decaledRegion: CompoundPath?
        _ = ec.getRoot().traverse { el in
            if let cp = el as? CompoundPath, cp.pathStyle.decal != nil { decaledRegion = cp }
            return false
        }
        guard let region = decaledRegion else {
            return XCTFail("the West region should carry a decal Pattern on its CompoundPath")
        }
        XCTAssertFalse(decalImageURI(region.pathStyle.decal!)?.isEmpty ?? true)

        region.update()
        guard let decalEl = region.getDecalElement() else {
            return XCTFail("Path.update() should synthesize a decal element for the decal-textured region")
        }
        guard case .some(.pattern) = decalEl.pathStyle.fill else {
            return XCTFail("decal element fill should be the decal Pattern")
        }
    }

    // ---- (b) enableAriaDecal for tree-structured series (treemap) ------------------------------

    func testAriaDecalAssignsDecalsToTreemapNodes() {
        let ec = ECharts(width: 400, height: 400)
        ec.setOption([
            "aria": ["decal": ["show": true] as [String: Any]] as [String: Any],
            "series": [[
                "type": "treemap",
                "animation": false,
                "left": 0.0, "top": 0.0, "width": 400.0, "height": 400.0,
                "data": [
                    ["name": "nodeA", "value": 10.0, "children": [
                        ["name": "nodeA1", "value": 4.0],
                        ["name": "nodeA2", "value": 6.0]
                    ]],
                    ["name": "nodeB", "value": 20.0, "children": [
                        ["name": "nodeB1", "value": 5.0],
                        ["name": "nodeB2", "value": 8.0]
                    ]]
                ]
            ] as [String: Any]]
        ])

        guard let model = ec.getModel(),
              let series = model.getSeriesByIndex(0) else { return XCTFail("model") }
        XCTAssertTrue(series.hasEnableAriaDecal, "treemap defines enableAriaDecal")

        let data = series.getData()
        // enableAriaDecalForTree walked the tree and assigned a per-node decal visual; nodes under the
        // SAME depth-1 branch share one decal, nodes under DIFFERENT branches get DISTINCT decals.
        // Collect the decal visual for each named node.
        func decalFor(_ name: String) -> [String: Any]? {
            let idx = data.indexOfName(name)
            guard idx >= 0 else { return nil }
            return data.getItemVisual(idx, "decal") as? [String: Any]
        }

        guard let dA1 = decalFor("nodeA1"), let dA2 = decalFor("nodeA2"),
              let dB1 = decalFor("nodeB1") else {
            return XCTFail("every treemap node should receive an aria palette decal visual")
        }

        // Same branch (A) → same decal texture.
        func sig(_ d: [String: Any]) -> String {
            let sym = (d["symbol"] as? String) ?? ""
            let dy = d["dashArrayY"].map { "\($0)" } ?? ""
            return sym + "|" + dy
        }
        XCTAssertEqual(sig(dA1), sig(dA2), "nodes under the same depth-1 branch share the branch decal")
        // Different branch (B) → distinct decal.
        XCTAssertNotEqual(sig(dA1), sig(dB1), "different depth-1 branches get distinct palette decals")

        // decalVisual then converted the assigned decal visual into a paintable Pattern on the item style.
        let idxA1 = data.indexOfName("nodeA1")
        if let styleA1 = data.getItemVisual(idxA1, "style") as? [String: Any] {
            XCTAssertTrue(styleA1["decal"] is ZRenderKit.Pattern,
                          "decalVisual should store a Pattern on the node's style visual")
        }
        else {
            XCTFail("nodeA1 should have a style visual")
        }
    }

    func testAriaDecalDisabledLeavesTreemapNodesWithoutDecal() {
        let ec = ECharts(width: 400, height: 400)
        ec.setOption([
            "series": [[
                "type": "treemap",
                "animation": false,
                "left": 0.0, "top": 0.0, "width": 400.0, "height": 400.0,
                "data": [
                    ["name": "nodeA", "value": 10.0, "children": [
                        ["name": "nodeA1", "value": 4.0]
                    ]]
                ]
            ] as [String: Any]]
        ])
        guard let data = ec.getModel()?.getSeriesByIndex(0)?.getData() else { return XCTFail("model") }
        let idx = data.indexOfName("nodeA1")
        XCTAssertNil(data.getItemVisual(idx, "decal"),
                     "without aria.decal.show no node decal is assigned")
    }
}


// `Pattern.image` is an `ImageSource` enum (`.url(String)` / `.image(ImageLike)`) since the
//   Pattern retype; decal tiles are always produced as `.url(dataURI)`.
private func decalImageURI(_ pattern: ZRenderKit.Pattern) -> String? {
    if case let .url(uri) = pattern.image { return uri }
    return nil
}
