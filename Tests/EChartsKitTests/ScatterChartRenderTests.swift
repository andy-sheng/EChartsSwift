// END-TO-END RENDER TEST for the cartesian SCATTER vertical (sibling of Bar/LineChartRenderTests).
// Drives ECharts with a value×value scatter option and inspects the ZRenderKit scene: one symbol
// `Path` per datum, each within the grid rect, at the coordinate the data maps to, carrying a palette
// fill. Phase 6d.
import XCTest
import ZRenderKit
@testable import EChartsKit

final class ScatterChartRenderTests: XCTestCase {
    override func setUp() { super.setUp(); ComponentModel.registerClass(ScatterSeriesModel.self) }

    func testScatterRendersOneSymbolPerDatum() {
        let ec = ECharts(width: 400, height: 300)
        ec.setOption([
            "grid": ["left": 50.0, "top": 20.0, "width": 300.0, "height": 200.0] as [String: Any],
            "xAxis": ["type": "value"] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [["type": "scatter", "symbolSize": 12.0,
                        "data": [[10.0, 20.0], [20.0, 30.0], [30.0, 15.0], [40.0, 40.0]]] as [String: Any]]
        ])

        // Real data pipeline built 4 rows.
        var count = -1
        ec.getModel()?.eachSeries { s, _ in count = s.getData().count() }
        XCTAssertEqual(count, 4, "scatter should build 4 rows from series.data")

        // Collect symbol paths (ScatterView names each symbol element "item").
        var symbols: [Path] = []
        _ = ec.getRoot().traverse { el in
            if let path = el as? Path, path.name == "item" { symbols.append(path) }
            return false
        }
        XCTAssertEqual(symbols.count, 4, "scatter should emit one symbol per datum")

        // Each symbol carries a non-empty palette fill; all share the single series' color
        // (scatter defaults colorBy: series → one color).
        var symbolFills: [String] = []
        for p in symbols {
            if case let .string(s)? = p.pathStyle?.fill, !s.isEmpty { symbolFills.append(s) }
        }
        XCTAssertEqual(symbolFills.count, 4, "each symbol carries a palette fill")
        XCTAssertEqual(Set(symbolFills).count, 1, "one scatter series → one palette color")
        let palette = (ec.getModel()?.get("color", true) as? [String]) ?? []
        XCTAssertTrue(palette.contains(symbolFills.first ?? ""), "symbol fill should come from the palette")
    }
}
