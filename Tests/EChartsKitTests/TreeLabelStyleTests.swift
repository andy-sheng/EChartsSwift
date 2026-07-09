// TREE LABEL retrofit onto the SHARED LABEL CORE (label/labelStyle.swift).
//
// Upstream TreeView draws node labels through SymbolClz's `useNameLabel: true` +
// `setLabelStyle(symbolPath, getLabelStatesModels(itemModel), { labelFetcher: seriesModel, ... })`
// (chart/helper/Symbol.ts:315). L2 UPDATE: the ported TreeView now routes its node symbols through the
// shared SymbolDraw/Symbol, so `data.getItemGraphicEl(i)` is the node's `Symbol` (a Group) and its child
// symbol Path (name "item") carries the label. This test asserts the label reaches that item Path through
// `labelStyle.setLabelStyle` (the shared Symbol's `useNameLabel: true` core path) rather than the old
// hand-rolled ZRText:
//   - the item element carries a `getTextContent()` whose `textStyle.text` == the node NAME
//     (the useNameLabel default text), and
//   - `el.textConfig.position` reflects the tree's outward side ('left'/'right' per orientation)
//     unless the label model pins a position, and
//   - the config was produced by the core's `createTextConfig` (it stamps `outsideFill`, which the
//     old hand-rolled `ElementTextConfig()` never set) — the marker that the label went through the core.
import XCTest
import ZRenderKit
@testable import EChartsKit

final class TreeLabelStyleTests: XCTestCase {

    private func firstSeries(_ ec: ECharts) -> SeriesModel? {
        var found: SeriesModel?
        ec.getModel()?.eachSeries { s, _ in if found == nil { found = s } }
        return found
    }

    func testTreeNodeLabelRoutesThroughSetLabelStyle() {
        let ec = ECharts(width: 460, height: 360)
        ec.setOption([
            "series": [["type": "tree", "left": "10%", "right": "10%", "top": "10%", "bottom": "10%",
                        "orient": "LR",
                        "data": [["name": "root", "children": [
                            ["name": "A", "children": [["name": "A1"], ["name": "A2"]]],
                            ["name": "B"]]]]] as [String: Any]]
        ])

        guard let seriesModel = firstSeries(ec) else { return XCTFail("no tree series model") }
        let data = seriesModel.getData()
        XCTAssertGreaterThan(data.count(), 0, "tree should build data rows")

        // Collect every node item element that carries a label textContent, keyed by data index.
        var labelled: [(idx: Int, el: ZRenderKit.Path, text: String, position: String?)] = []
        for i in 0..<data.count() {
            // The node graphic el is a Symbol (Group); its "item"-named child Path carries the label.
            guard let sym = data.getItemGraphicEl(i) as? Symbol, let el = sym.getSymbolPath() else { continue }
            guard let tc = el.getTextContent() else { continue }
            let pos = el.textConfig?.position as? String
            labelled.append((i, el, tc.textStyle?.text ?? "<nil>", pos))

            // The text is the node NAME (useNameLabel default), NOT a value-derived default label.
            XCTAssertEqual(tc.textStyle?.text, data.getName(i),
                           "node label text must be the datum name (useNameLabel default)")
            // The config went through the core's createTextConfig, which stamps outsideFill.
            // The old hand-rolled ElementTextConfig() never set this → guards the retrofit.
            XCTAssertNotNil(el.textConfig?.outsideFill,
                            "textConfig.outsideFill must be set by labelStyle.createTextConfig")
        }

        XCTAssertGreaterThan(labelled.count, 0, "at least one tree node should carry a label")

        // Default (no label.position pinned): outward side per LR orientation — leaves label 'right',
        // internal nodes label 'left'. Assert both sides appear and every position is left/right.
        let positions = Set(labelled.compactMap { $0.position })
        for p in positions {
            XCTAssertTrue(p == "left" || p == "right",
                          "orthogonal LR tree label position should default to left/right, got \(p)")
        }
        // The tree has both internal nodes (root, A) and leaves (A1, A2, B), so both sides must occur.
        XCTAssertTrue(positions.contains("left"), "internal nodes label on the inner (left) side")
        XCTAssertTrue(positions.contains("right"), "leaves label on the outer (right) side")
    }
}
