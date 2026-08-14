// Verifies SunburstPiece routes its sector labels through the shared label core
// (`labelStyle.setLabelStyle`) instead of the former hand-rolled normal-only text style.
//
// After render, each drawn sector's attached label (its ZRText textContent) must carry:
//   - style.text == the node's default label (the datum name — upstream `text || node.name`), and
//   - no forced sector-color fill when label.color is unspecified (upstream attached-text behavior),
//   - the host `textConfig.inside == true` reflecting the default 'inside' label position.
import XCTest
import ZRenderKit
@testable import EChartsKit

final class SunburstLabelTests: XCTestCase {

    private func option() -> [String: Any] {
        [
            "animation": false,
            "series": [["type": "sunburst", "radius": ["0%", "90%"],
                        "data": [
                            ["name": "Grandpa", "children": [
                                ["name": "Uncle Leo", "value": 15.0, "children": [
                                    ["name": "Cousin Jack", "value": 2.0],
                                    ["name": "Cousin Mary", "value": 5.0]
                                ]],
                                ["name": "Father", "value": 10.0, "children": [
                                    ["name": "Me", "value": 5.0],
                                    ["name": "Brother Peter", "value": 1.0]
                                ]]
                            ]],
                            ["name": "Nancy", "children": [
                                ["name": "Uncle Nike", "value": 10.0, "children": [
                                    ["name": "Cousin Betty", "value": 1.0],
                                    ["name": "Cousin Jenny", "value": 2.0]
                                ]]
                            ]]
                        ]] as [String: Any]]
        ]
    }

    func test_sector_labels_go_through_shared_label_core() {
        let ec = ECharts(width: 400, height: 400)
        ec.setOption(option())

        var labelTexts: [String] = []
        var piecesWithLabel = 0
        var piecesWithForcedFill = 0
        var piecesInside = 0

        _ = ec.getRoot().traverse { el in
            guard let piece = el as? SunburstPiece, piece.node != nil,
                  let label = piece.getTextContent() else { return false }
            // Only count nodes that actually draw a label (the virtualRoot / value-0 nodes bail).
            guard let text = label.textStyle?.text, !text.isEmpty else { return false }

            piecesWithLabel += 1
            labelTexts.append(text)

            if label.textStyle?.fill != nil { piecesWithForcedFill += 1 }

            // Default sunburst label position is 'inside' → host textConfig.inside == true.
            if piece.textConfig?.inside == true { piecesInside += 1 }
            return false
        }

        XCTAssertGreaterThan(piecesWithLabel, 0, "at least one sunburst sector must carry a label")

        // Text == default label (the node name), for named leaf/branch nodes.
        for expected in ["Uncle Leo", "Father", "Nancy", "Cousin Jack", "Me"] {
            XCTAssertTrue(labelTexts.contains(expected),
                          "expected a sector label with text == \(expected); got \(labelTexts)")
        }

        // Default labels use the global text color. Only an explicit label.color='inherit' should
        // receive the sector fill; forcing it here makes labels blend into their sectors.
        XCTAssertEqual(piecesWithForcedFill, 0,
                       "unspecified sunburst label color must not inherit the sector fill")
        XCTAssertEqual(piecesInside, piecesWithLabel,
                       "every sector's textConfig.inside must reflect the default 'inside' label position")
    }
}
