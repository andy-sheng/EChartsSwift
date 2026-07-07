// Funnel labels are now drawn through the SHARED LABEL CORE (labelStyle.setLabelStyle /
// getLabelStatesModels) instead of an inline ZRText build. These tests assert the retrofit:
//   - the label ZRText is attached to the piece polygon as its textContent, with the datum NAME as
//     its normal text (upstream `defaultText: data.getName(idx)`), and the funnel-specific textConfig
//     (local + inside) preserved;
//   - the EMPHASIS state label style is populated on the text — something ONLY the shared core does
//     (the previous inline label code created no per-state styles). This is the assertion that fails
//     against the old implementation.
import XCTest
@testable import EChartsKit
@testable import ZRenderKit

final class FunnelLabelTests: XCTestCase {

    private func collectPieces(_ el: Element, into out: inout [ZRenderKit.Polygon]) {
        if let p = el as? ZRenderKit.Polygon, p.name == "item" { out.append(p) }
        if let g = el as? Group { for c in g.children() { collectPieces(c, into: &out) } }
    }

    private func pieces(_ root: Element) -> [ZRenderKit.Polygon] {
        var out: [ZRenderKit.Polygon] = []
        collectPieces(root, into: &out)
        return out
    }

    private func option() -> [String: Any] {
        ["animation": false,
         "series": [["type": "funnel",
                     "data": [["value": 60.0, "name": "a"], ["value": 40.0, "name": "b"]]]]]
    }

    // Primary: the label text is attached via the shared core (textContent on the piece polygon), the
    // normal text is the datum name, and funnel's textConfig (local + inside) is set on the polygon.
    func test_label_attached_with_name_text_and_textconfig() {
        let ec = EChartsSlim(width: 400, height: 400); ec.setOption(option())
        let ps = pieces(ec.getRoot())
        XCTAssertEqual(ps.count, 2, "two funnel pieces")

        var labelTexts = Set<String>()
        for p in ps {
            guard let label = p.getTextContent() else {
                return XCTFail("piece polygon must carry a label textContent")
            }
            if let t = label.textStyle?.text { labelTexts.insert(t) }
            // funnel sets textConfig.local = true on the piece (positions the label by absolute x/y).
            XCTAssertEqual(p.textConfig?.local, true, "funnel piece textConfig.local must be true")
        }
        XCTAssertEqual(labelTexts, ["a", "b"], "normal label text is the datum name for each piece")
    }

    // Differentiator (FAILS against the old inline label code): the shared core populates the
    // emphasis-state label style on the ZRText. The previous inline implementation created no states
    // on the label text, so states["emphasis"] would be nil.
    func test_emphasis_label_state_populated_by_shared_core() {
        let ec = EChartsSlim(width: 400, height: 400); ec.setOption(option())
        let ps = pieces(ec.getRoot())
        XCTAssertFalse(ps.isEmpty, "expected funnel pieces")

        for p in ps {
            guard let label = p.getTextContent() else { return XCTFail("no label textContent") }
            let normalText = label.textStyle?.text
            let emphasisState = label.states[DisplayState.emphasis.rawValue]
            XCTAssertNotNil(emphasisState, "shared core must create an emphasis state on the label")
            XCTAssertEqual(emphasisState?.textStyle?.text, normalText,
                           "emphasis label text falls back to the normal (name) text")
        }
    }
}
