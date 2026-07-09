// Treemap tile labels route through the shared label core (labelStyle.setLabelStyle) instead of the
// old manual ZRText building. After render, each leaf content tile (a Rect `el`) must carry the label
// as its textContent (el.getTextContent()) with:
//   - textStyle.text == the node's default label (the datum name), and
//   - el.textConfig.position reflecting the label model position ("inside", the treemap default).
//
// The `position` assertion is the discriminator vs the old manual path: the old prepareText set only
// textConfig.inside = true and NEVER a position, so the old code has textContent but no position.
import XCTest
@testable import EChartsKit
@testable import ZRenderKit

final class TreemapLabelStyleTests: XCTestCase {

    // Collect every Rect in the scene graph that carries a text content.
    private func labeledTiles(_ el: Element, _ out: inout [ZRenderKit.Rect]) {
        if let r = el as? ZRenderKit.Rect, r.getTextContent() != nil {
            out.append(r)
        }
        if let g = el as? Group {
            for c in g.children() { labeledTiles(c, &out) }
        }
    }

    private func option() -> [String: Any] {
        [
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
        ]
    }

    func test_leaf_tile_label_routes_through_setLabelStyle() {
        let ec = ECharts(width: 400, height: 400)
        ec.setOption(option())

        var tiles: [ZRenderKit.Rect] = []
        labeledTiles(ec.getRoot(), &tiles)

        XCTAssertFalse(tiles.isEmpty, "at least one treemap leaf tile should carry a label textContent")

        let leafNames: Set<String> = ["nodeA1", "nodeA2", "nodeB1", "nodeB2"]

        // Find a leaf-labelled tile and verify BOTH the default-label text and the label position.
        var matched = false
        for tile in tiles {
            guard let text = tile.getTextContent()?.textStyle?.text, leafNames.contains(text) else {
                continue
            }
            matched = true
            // Default position for a treemap label is "inside" — setLabelStyle writes it to the host
            // element's textConfig (createTextConfig). The old manual path left position nil.
            XCTAssertEqual(tile.textConfig?.position as? String, "inside",
                           "label position ('inside') must be written to the tile textConfig by setLabelStyle")
        }
        XCTAssertTrue(matched, "a leaf tile label text should equal its datum name (default label)")
    }
}
