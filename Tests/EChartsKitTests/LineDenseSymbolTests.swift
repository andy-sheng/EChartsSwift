// Density symbol thinning for the cartesian line (LineView.getIsIgnoreFunc / canShowAllSymbolForCategory,
// ported from echarts/src/chart/line/LineView.ts). `showAllSymbol: 'auto'` (the default) HIDES the
// per-point symbols when the category line is dense — so a many-point line does not materialise one
// Symbol group per datum — while a sparse line keeps every symbol. This is what saves a dense line from
// creating thousands of Symbol groups (the line-lttb perf gap).

import XCTest
import ZRenderKit
@testable import EChartsKit

final class LineDenseSymbolTests: XCTestCase {
    override func setUp() { super.setUp(); ComponentModel.registerClass(LineSeriesModel.self) }

    private func symbolCount(_ ec: ECharts) -> Int {
        var n = 0
        _ = ec.getRoot().traverse { el in
            if el is Symbol { n += 1 }
            return false
        }
        return n
    }

    // Sparse line (few, far-apart category points): every symbol is shown (none ignored).
    func testSparseLineKeepsAllSymbols() {
        let ec = ECharts(width: 400, height: 300)
        ec.setOption([
            "grid": ["left": 50.0, "top": 20.0, "width": 300.0, "height": 200.0] as [String: Any],
            "xAxis": ["type": "category", "data": ["A", "B", "C", "D", "E", "F"]] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [["type": "line", "data": [10.0, 20.0, 15.0, 40.0, 30.0, 25.0]] as [String: Any]]
        ])
        XCTAssertEqual(symbolCount(ec), 6, "a sparse line keeps a Symbol per datum")
    }

    // Dense line (many close category points): most symbols are IGNORED — only the ones whose category
    // tick survives the label-interval strategy are materialised, far fewer than the datum count.
    func testDenseLineIgnoresMostSymbols() {
        let n = 200
        let cats = (0..<n).map { "c\($0)" }
        let values = (0..<n).map { Double(($0 * 7) % 50) }
        let ec = ECharts(width: 400, height: 300)
        ec.setOption([
            "grid": ["left": 50.0, "top": 20.0, "width": 300.0, "height": 200.0] as [String: Any],
            "xAxis": ["type": "category", "data": cats] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [["type": "line", "data": values] as [String: Any]]
        ])
        let count = symbolCount(ec)
        XCTAssertGreaterThan(count, 0, "some symbols (at surviving label ticks) are still shown")
        XCTAssertLessThan(count, n / 2, "a dense line ignores most symbols (\(count) of \(n))")
    }

    // showAllSymbol: true overrides the density thinning — every datum keeps its symbol even when dense.
    func testShowAllSymbolTrueKeepsAllSymbols() {
        let n = 60
        let cats = (0..<n).map { "c\($0)" }
        let values = (0..<n).map { Double(($0 * 3) % 50) }
        let ec = ECharts(width: 400, height: 300)
        ec.setOption([
            "grid": ["left": 50.0, "top": 20.0, "width": 300.0, "height": 200.0] as [String: Any],
            "xAxis": ["type": "category", "data": cats] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [["type": "line", "showAllSymbol": true, "data": values] as [String: Any]]
        ])
        XCTAssertEqual(symbolCount(ec), n, "showAllSymbol:true keeps a Symbol per datum even when dense")
    }

    // A category axis may intentionally declare fewer categories than the series contains
    // (official-mix-line-bar does this). The polyline is clipped to the grid and its symbols must
    // obey the same clip area; otherwise the first overflow datum appears as a stray circle.
    func testCategoryOverflowSymbolsAreClipped() {
        let ec = ECharts(width: 400, height: 300)
        ec.setOption([
            "grid": ["left": 50.0, "top": 20.0, "width": 300.0, "height": 200.0] as [String: Any],
            "xAxis": ["type": "category", "data": ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]] as [String: Any],
            "yAxis": ["type": "value", "min": 0.0, "max": 25.0] as [String: Any],
            "series": [[
                "type": "line",
                "showAllSymbol": true,
                "data": [2.0, 2.2, 3.3, 4.5, 6.3, 10.2, 20.3, 23.4, 23.0, 16.5, 12.0, 6.2]
            ] as [String: Any]]
        ])
        XCTAssertEqual(symbolCount(ec), 7, "only symbols inside the seven-category grid are drawn")
    }
}
