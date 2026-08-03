// Function-valued `symbolSize` (upstream `SymbolSizeCallback`) must reach the per-item symbol
// visual: `symbolVisual.seriesSymbolTask` evaluates the closure per datum and each drawn symbol
// scales accordingly. This is the punch-card idiom (`symbolSize: val => val[2] * 2`) — see
// official-scatter-punchCard.
import XCTest
import ZRenderKit
@testable import EChartsKit

final class ScatterSymbolSizeCallbackTests: XCTestCase {
    override func setUp() { super.setUp(); ComponentModel.registerClass(ScatterSeriesModel.self) }

    func testSymbolSizeCallbackSizesEachSymbolFromItsDatum() {
        let sizeCb: SymbolSizeCallback<CallbackDataParams> = { rawValue, _ in
            let row = rawValue as? [Any] ?? []
            let count = (row.count > 2 ? row[2] : nil).flatMap { ($0 as? Double) ?? ($0 as? Int).map(Double.init) } ?? 0
            return count * 2
        }
        let ec = ECharts(width: 400, height: 300)
        ec.setOption([
            "grid": ["left": 50.0, "top": 20.0, "width": 300.0, "height": 200.0] as [String: Any],
            "xAxis": ["type": "category", "data": ["a", "b", "c"]] as [String: Any],
            "yAxis": ["type": "category", "data": ["r"]] as [String: Any],
            "series": [["type": "scatter",
                        "symbolSize": sizeCb,
                        "data": [[0.0, 0.0, 5.0], [1.0, 0.0, 12.0], [2.0, 0.0, 0.0]]] as [String: Any]]
        ])

        // The per-item visual carries the evaluated callback result (count * 2).
        var itemSizes: [Double] = []
        ec.getModel()?.eachSeries { s, _ in
            let data = s.getData()
            for idx in 0..<data.count() {
                let v = data.getItemVisual(idx, "symbolSize")
                itemSizes.append((v as? Double) ?? (v as? Int).map(Double.init) ?? .nan)
            }
        }
        XCTAssertEqual(itemSizes, [10.0, 24.0, 0.0],
                       "symbolSize callback should size each item as count * 2")

        // And the rendered symbols reflect it: symbol width == the evaluated size.
        var drawnWidths: [Double] = []
        _ = ec.getRoot().traverse { el in
            if let path = el as? Path, path.name == "item", let br = path.getBoundingRect() {
                drawnWidths.append(Double(br.width) * path.scaleX)
            }
            return false
        }
        drawnWidths.sort()
        XCTAssertEqual(drawnWidths.count, 3, "scatter should emit one symbol per datum")
        XCTAssertEqual(drawnWidths[2], 24.0, accuracy: 0.5, "largest bubble should be 24px wide")
        XCTAssertEqual(drawnWidths[1], 10.0, accuracy: 0.5, "mid bubble should be 10px wide")
        XCTAssertEqual(drawnWidths[0], 0.0, accuracy: 0.5, "zero-count bubble should collapse to 0")
    }
}
