// LABEL RETROFIT TEST for PieView. After the pie label subsystem was retrofitted onto the shared
// label core (`labelStyle.setLabelStyle` on the sector `el`), each slice's Sector must carry the label
// as its ATTACHED textContent (sector.getTextContent()) — NOT a separate ZRText added to the group.
// The default (no formatter) label text is the datum name.
//
// L1c UPDATE: `pieLabelLayout` now runs at the end of PieView.render (faithful to upstream
// chart/pie/labelLayout.ts). For outer labels it places the label at an absolute x/y and resets the
// sector's textConfig to `{ inside: false }` (position becomes nil — the label uses its own x/y), and
// attaches a non-ignored leader line (Polyline textGuideLine) with 3 points. So the position assertion
// from the pre-L1c interim ("textConfig.position == 'outer'") is superseded by the inside/guide-line
// checks below.
import XCTest
import ZRenderKit
@testable import EChartsKit

final class PieLabelStyleTests: XCTestCase {
    override func setUp() { super.setUp(); ComponentModel.registerClass(PieSeriesModel.self) }

    func testPieSectorsCarryAttachedLabelTextContent() {
        let ec = ECharts(width: 400, height: 320)
        ec.setOption([
            "series": [["type": "pie", "radius": "65%",
                        "label": ["show": true, "position": "outer"] as [String: Any],
                        "data": [["value": 40.0, "name": "A"],
                                 ["value": 30.0, "name": "B"],
                                 ["value": 20.0, "name": "C"],
                                 ["value": 10.0, "name": "D"]]] as [String: Any]]
        ])

        // Collect the sectors in scene order.
        var sectors: [Sector] = []
        _ = ec.getRoot().traverse { el in
            if let s = el as? Sector { sectors.append(s) }
            return false
        }
        XCTAssertEqual(sectors.count, 4, "a 4-slice pie should emit 4 Sectors")

        let expectedNames = ["A", "B", "C", "D"]
        for (i, s) in sectors.enumerated() {
            // The label is ATTACHED to the sector as its textContent (setLabelStyle contract),
            // not floating in the group as an independent ZRText.
            guard let label = s.getTextContent() else {
                XCTFail("sector \(i) should carry an attached label textContent"); continue
            }
            XCTAssertEqual(label.textStyle?.text, expectedNames[i],
                           "default (no formatter) pie label text should be the datum name")

            // L1c: pieLabelLayout resets textConfig for an OUTER label to `{ inside: false }`
            //   (position nil — the label is placed by its own absolute x/y).
            XCTAssertEqual(s.textConfig?.inside, false,
                           "sector \(i) textConfig.inside should be false for an outer label")
            XCTAssertNil(s.textConfig?.position,
                         "sector \(i) textConfig.position should be reset to nil by pieLabelLayout")

            // The leader line (labelLine) is attached as the sector's textGuideLine: visible (not
            //   ignored) with the 3-point [sectorEdge, elbow, textAnchor] polyline pieLabelLayout built.
            guard let guide = s.getTextGuideLine() else {
                XCTFail("sector \(i) should carry a leader-line textGuideLine"); continue
            }
            XCTAssertFalse(guide.ignore, "sector \(i) leader line should be visible")
            let pts = (guide.shape as? PolylineShape)?.points
            XCTAssertEqual(pts?.count, 3, "sector \(i) leader line should have 3 points")
        }
    }
}
