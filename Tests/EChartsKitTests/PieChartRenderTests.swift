// END-TO-END RENDER TEST for the PIE vertical (coordless box layout). Drives ECharts with a pie
// option and inspects the ZRenderKit scene: one `Sector` per datum, each carrying a DISTINCT palette
// fill (pie defaults `colorBy: 'data'`, so the per-item `dataColorPaletteTask` assigns palette[idx]).
// This locks in the Phase-6d fix for the visual-task order + `getColorFromPalette` overload trap that
// otherwise collapsed all slices to one color (or black). Phase 6d.
import XCTest
import ZRenderKit
@testable import EChartsKit

final class PieChartRenderTests: XCTestCase {
    override func setUp() { super.setUp(); ComponentModel.registerClass(PieSeriesModel.self) }

    func testPieRendersDistinctlyColoredSectors() {
        let ec = ECharts(width: 400, height: 320)
        ec.setOption([
            "series": [["type": "pie", "radius": "65%",
                        "data": [["value": 40.0, "name": "A"],
                                 ["value": 30.0, "name": "B"],
                                 ["value": 20.0, "name": "C"],
                                 ["value": 10.0, "name": "D"]]] as [String: Any]]
        ])

        // Real data pipeline built 4 rows.
        var count = -1
        ec.getModel()?.eachSeries { s, _ in count = s.getData().count() }
        XCTAssertEqual(count, 4, "pie should build 4 rows from series.data")

        // One Sector per datum.
        var sectors: [Sector] = []
        _ = ec.getRoot().traverse { el in
            if let s = el as? Sector { sectors.append(s) }
            return false
        }
        XCTAssertEqual(sectors.count, 4, "a 4-slice pie should emit 4 Sectors")

        // Each slice carries a palette fill, and — because pie is colorBy:'data' — the fills are DISTINCT
        // and drawn from the palette (NOT the #000 default, NOT all one color).
        var fills: [String] = []
        for s in sectors {
            guard let fill = s.pathStyle?.fill else { XCTFail("sector should have a fill"); continue }
            if case let .string(str) = fill {
                XCTAssertFalse(str.isEmpty, "sector fill should be non-empty")
                XCTAssertNotEqual(str, "#000", "sector fill should be a palette color, not black")
                fills.append(str)
            } else {
                XCTFail("sector fill should be a solid color string, got \(fill)")
            }
        }
        XCTAssertEqual(fills.count, 4)
        XCTAssertEqual(Set(fills).count, 4, "pie (colorBy:data) → 4 distinct palette colors")
        let palette = (ec.getModel()?.get("color", true) as? [String]) ?? []
        XCTAssertFalse(palette.isEmpty, "palette should be populated")
        for f in fills {
            XCTAssertTrue(palette.contains(f), "sector fill \(f) should come from the palette")
        }
        // The first four fills follow the palette order (dataColorPaletteTask assigns palette[0..3]).
        XCTAssertEqual(Array(fills.prefix(4)), Array(palette.prefix(4)),
                       "slices should take palette colors in order")
    }
}
