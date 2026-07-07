// LABEL RETROFIT TEST for PieView. After the pie label subsystem was retrofitted onto the shared
// label core (`labelStyle.setLabelStyle` on the sector `el`), each slice's Sector must carry the label
// as its ATTACHED textContent (sector.getTextContent()) — NOT a separate ZRText added to the group.
// The default (no formatter) label text is the datum name, and the sector's textConfig.position must
// reflect the pie label model position ("outer").
import XCTest
import ZRenderKit
@testable import EChartsKit

final class PieLabelStyleTests: XCTestCase {
    override func setUp() { super.setUp(); ComponentModel.registerClass(PieSeriesModel.self) }

    func testPieSectorsCarryAttachedLabelTextContent() {
        let ec = EChartsSlim(width: 400, height: 320)
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
            // textConfig position reflects the label model position.
            XCTAssertEqual(s.textConfig?.position as? String, "outer",
                           "sector \(i) textConfig.position should reflect label.position 'outer'")
        }
    }
}
