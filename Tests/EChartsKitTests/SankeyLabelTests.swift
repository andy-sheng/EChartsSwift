// LABEL-CORE RETROFIT TEST for the sankey node label. After the retrofit, each node Rect must own its
// label as a ZRText `textContent` produced by the SHARED `labelStyle.setLabelStyle` core (not the old
// inline `sankeySetLabel` reproduction). We assert:
//   1. the node Rect has a getTextContent() whose style text == the default label (the node name/id),
//   2. el.textConfig.position reflects the sankey node label model position ('right'),
//   3. the attached ZRText carries the per-state (emphasis/blur/select) states that ONLY the shared
//      core creates — this is the discriminator that fails against the old inline label drawing, which
//      never populated any ZRText states.
import XCTest
import ZRenderKit
@testable import EChartsKit

final class SankeyLabelTests: XCTestCase {
    func testSankeyNodeLabelUsesSharedLabelCore() {
        let ec = ECharts(width: 460, height: 360)
        ec.setOption([
            "series": [["type": "sankey",
                        "left": "5%", "right": "20%", "top": "5%", "bottom": "5%",
                        "nodeWidth": 20.0, "nodeGap": 8.0,
                        "data": [["name": "a"], ["name": "b"], ["name": "c"], ["name": "d"]],
                        "links": [["source": "a", "target": "b", "value": 5.0],
                                  ["source": "a", "target": "c", "value": 3.0],
                                  ["source": "b", "target": "d", "value": 4.0],
                                  ["source": "c", "target": "d", "value": 2.0]]] as [String: Any]]
        ])

        // Locate the node Rect labeled 'a'.
        var targetRect: ZRenderKit.Rect?
        _ = ec.getRoot().traverse { el in
            if el.name == "node", let rect = el as? ZRenderKit.Rect,
               rect.getTextContent()?.textStyle?.text == "a" {
                targetRect = rect
            }
            return false
        }

        guard let rect = targetRect else {
            return XCTFail("expected a node Rect whose label text == 'a'")
        }

        // 1. textContent produced by setLabelStyle carries the default label text.
        let label = rect.getTextContent()
        XCTAssertNotNil(label, "node Rect must have a ZRText textContent")
        XCTAssertEqual(label?.textStyle?.text, "a", "label text == node name/id (default label)")

        // 2. textConfig.position mirrors the sankey node label model default ('right').
        XCTAssertEqual(rect.textConfig?.position as? String, "right",
                       "node label position must reflect the label model position 'right'")

        // 3. DISCRIMINATOR: only the shared core populates the ZRText's emphasis/blur/select states.
        XCTAssertNotNil(label?.states["emphasis"],
                        "setLabelStyle must attach an emphasis state to the label ZRText")
    }
}
