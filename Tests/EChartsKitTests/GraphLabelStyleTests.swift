// Graph node labels route through the shared label core (labelStyle.setLabelStyle), so the label is
// attached as the node symbol's textContent, its text runs through the series label FORMATTER, and the
// textConfig position reflects the label model. Faithful to Symbol.ts._updateLabel (useNameLabel off →
// getDefaultLabel), which the old hand-rolled ZRText block did NOT do (it ignored the formatter).
import XCTest
@testable import EChartsKit
@testable import ZRenderKit

final class GraphLabelStyleTests: XCTestCase {
    private func firstNode(_ el: Element) -> Path? {
        if let p = el as? Path, p.name == "item" { return p }
        if let g = el as? Group { for c in g.children() { if let h = firstNode(c) { return h } } }
        return nil
    }

    private func option(showLabel: Bool, formatter: String?) -> [String: Any] {
        var label: [String: Any] = ["show": showLabel]
        if let f = formatter { label["formatter"] = f }
        return [
            "animation": false,
            "series": [[
                "type": "graph", "layout": "none",
                "label": label,
                "data": [["name": "n1", "x": 100.0, "y": 100.0], ["name": "n2", "x": 200.0, "y": 200.0]],
                "links": [["source": "n1", "target": "n2"]]
            ]]
        ]
    }

    // The label text is produced by the series formatter ('node-{b}' → 'node-<name>'), which only the
    // shared core applies — the old inline block used the raw name and would fail this assertion.
    func test_node_label_uses_formatter_via_setLabelStyle() {
        let ec = EChartsSlim(width: 400, height: 400)
        ec.setOption(option(showLabel: true, formatter: "node-{b}"))
        guard let node = firstNode(ec.getRoot()) else { return XCTFail("no graph node (name==\"item\")") }
        guard let label = node.getTextContent() else {
            return XCTFail("node should have an attached label textContent when label.show==true")
        }
        XCTAssertEqual(label.textStyle?.text, "node-n1", "label text should run through the series formatter")
        // No explicit position → createTextConfig defaults the normal-state label position to 'inside'.
        XCTAssertEqual(node.textConfig?.position as? String, "inside",
                       "textConfig.position should reflect the (defaulted) label model position")
    }

    // Default label (no formatter) resolves to the node's name via getDefaultLabel.
    func test_node_label_default_text_is_name() {
        let ec = EChartsSlim(width: 400, height: 400)
        ec.setOption(option(showLabel: true, formatter: nil))
        guard let node = firstNode(ec.getRoot()) else { return XCTFail("no graph node") }
        // graph label default formatter is '{b}', so text is the name.
        XCTAssertEqual(node.getTextContent()?.textStyle?.text, "n1")
    }

    // The node symbol path carries z2:100 (Symbol._createSymbol's retrieve2(z2, 100)); its label defaults
    // to z2:0, so WITHOUT the doUpdateZ lift it sorts BEHIND the opaque node and is invisible (the bug).
    // EChartsSlim.updateZ lifts the graph node label to z2 = subtreeMaxZ2 + 2, so it paints over the node
    // — matching real echarts (whose default 'inside' node labels render on top of the node symbol).
    func test_node_label_z2_lifted_above_symbol() {
        let ec = EChartsSlim(width: 400, height: 400)
        ec.setOption(option(showLabel: true, formatter: nil))
        guard let node = firstNode(ec.getRoot()) else { return XCTFail("no graph node") }
        XCTAssertEqual(node.z2, 100, "graph node symbol path z2 is retrieve2(z2, 100)")
        guard let label = node.getTextContent() else { return XCTFail("no node label") }
        XCTAssertGreaterThan(label.z2, node.z2,
                             "node label must sort ABOVE its symbol so it is not hidden behind the node")
        XCTAssertEqual(label.z2, node.z2 + 2, "doUpdateZ lifts the label to subtreeMaxZ2 + 2")
    }

    // label.show:false → setLabelStyle hides the label (no visible textContent).
    func test_node_label_hidden_when_show_false() {
        let ec = EChartsSlim(width: 400, height: 400)
        ec.setOption(option(showLabel: false, formatter: nil))
        guard let node = firstNode(ec.getRoot()) else { return XCTFail("no graph node") }
        // Either no textContent is created, or it is ignored.
        if let label = node.getTextContent() {
            XCTAssertTrue(label.ignore, "label textContent should be ignored when label.show==false")
        }
    }
}
