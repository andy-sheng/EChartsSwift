import XCTest
@testable import EChartsKit
@testable import ZRenderKit

// L5-3 reuse-safety audit: after Task 2 a reused view re-renders onto its own prior group. A view
// that appends without clearing/diffing would DUPLICATE elements on a merge-mode setOption. This
// suite renders each chart family, then applies a merge-mode data update, and asserts the total
// element count under `root` does not grow — catching both series-view and component-view (axis,
// legend, ...) duplication. Views classified during the audit:
//   safe-clear  : LineView, LegendView, most component/simpler chart views (group.removeAll at top)
//   safe-diff   : BarView, PieView, ScatterView/EffectScatterView (SymbolDraw data.diff)
//   fixed here  : any view whose test below failed and got a group-clear guard (see commit)
final class L5ViewReuseSafetyTests: XCTestCase {

    private func rootElementCount(_ ec: ECharts) -> Int {
        var n = 0
        _ = ec.root.traverse({ _ in n += 1; return false })
        return n
    }

    // Recursive element count of the SERIES (chart-view) subtrees only. Excludes component views so a
    // legitimately-rescaled value axis (more ticks/splitLines when the data range widens) is not
    // mistaken for a leak. Series-view reuse safety is exactly what this must isolate.
    private func seriesElementCount(_ ec: ECharts) -> Int {
        var n = 0
        for v in ec.testChartViews { _ = v.group.traverse({ _ in n += 1; return false }) }
        return n
    }

    private func assertNoDuplication(_ name: String, _ option: [String: Any], update: [String: Any],
                                     file: StaticString = #filePath, line: UInt = #line) {
        let ec = ECharts(width: 480, height: 320)
        ec.setOption(option)

        // (1) Identical-data reuse must be EXACTLY stable at the whole-root level — the strongest
        //     append-leak guard (no view of any kind may accumulate elements on a no-op re-render).
        let root0 = rootElementCount(ec)
        ec.setOption(option)
        let root1 = rootElementCount(ec)
        XCTAssertEqual(root1, root0,
            "\(name): identical-data reuse grew whole-root count (\(root0) -> \(root1)) — a view appends on re-render",
            file: file, line: line)

        // (2) Changed-data reuse must not grow the SERIES subtrees (axis rescaling excluded). Catches
        //     a diff .update path that creates-and-adds instead of reusing the old element.
        let series0 = seriesElementCount(ec)
        ec.setOption(update)
        let series1 = seriesElementCount(ec)
        XCTAssertLessThanOrEqual(series1, series0,
            "\(name): series element count grew on data-change reuse (\(series0) -> \(series1)) — series view duplicates",
            file: file, line: line)
    }

    // ---- cartesian (exercises AxisView / grid reuse) ----
    func testBar() {
        assertNoDuplication("bar",
            ["xAxis": ["type": "category", "data": ["a", "b", "c"]], "yAxis": ["type": "value"],
             "series": [["type": "bar", "data": [1, 2, 3]]]],
            update: ["series": [["type": "bar", "data": [4, 5, 6]]]])
    }
    func testLine() {
        assertNoDuplication("line",
            ["xAxis": ["type": "category", "data": ["a", "b", "c"]], "yAxis": ["type": "value"],
             "series": [["type": "line", "data": [1, 2, 3]]]],
            update: ["series": [["type": "line", "data": [4, 5, 6]]]])
    }
    func testScatter() {
        assertNoDuplication("scatter",
            ["xAxis": ["type": "value"], "yAxis": ["type": "value"],
             "series": [["type": "scatter", "data": [[1, 1], [2, 2], [3, 3]]]]],
            update: ["series": [["type": "scatter", "data": [[4, 4], [5, 5]]]]])
    }
    func testEffectScatter() {
        assertNoDuplication("effectScatter",
            ["xAxis": ["type": "value"], "yAxis": ["type": "value"],
             "series": [["type": "effectScatter", "data": [[1, 1], [2, 2]]]]],
            update: ["series": [["type": "effectScatter", "data": [[3, 3], [4, 4]]]]])
    }
    func testCandlestick() {
        assertNoDuplication("candlestick",
            ["xAxis": ["type": "category", "data": ["a", "b"]], "yAxis": ["type": "value"],
             "series": [["type": "candlestick", "data": [[20, 30, 10, 35], [25, 28, 22, 40]]]]],
            update: ["series": [["type": "candlestick", "data": [[22, 33, 12, 36], [26, 29, 23, 41]]]]])
    }
    func testBoxplot() {
        assertNoDuplication("boxplot",
            ["xAxis": ["type": "category", "data": ["a", "b"]], "yAxis": ["type": "value"],
             "series": [["type": "boxplot", "data": [[1, 2, 3, 4, 5], [2, 3, 4, 5, 6]]]]],
            update: ["series": [["type": "boxplot", "data": [[2, 3, 4, 5, 6], [3, 4, 5, 6, 7]]]]])
    }
    func testPictorialBar() {
        assertNoDuplication("pictorialBar",
            ["xAxis": ["type": "category", "data": ["a", "b"]], "yAxis": ["type": "value"],
             "series": [["type": "pictorialBar", "symbol": "circle", "data": [3, 5]]]],
            update: ["series": [["type": "pictorialBar", "symbol": "circle", "data": [4, 6]]]])
    }

    // ---- polar / angle ----
    func testPie() {
        assertNoDuplication("pie",
            ["series": [["type": "pie", "data": [["value": 1, "name": "a"], ["value": 2, "name": "b"]]]]],
            update: ["series": [["type": "pie", "data": [["value": 3, "name": "a"], ["value": 4, "name": "b"]]]]])
    }
    func testFunnel() {
        assertNoDuplication("funnel",
            ["series": [["type": "funnel", "data": [["value": 60, "name": "a"], ["value": 40, "name": "b"]]]]],
            update: ["series": [["type": "funnel", "data": [["value": 55, "name": "a"], ["value": 35, "name": "b"]]]]])
    }
    func testGauge() {
        assertNoDuplication("gauge",
            ["series": [["type": "gauge", "data": [["value": 50, "name": "x"]]]]],
            update: ["series": [["type": "gauge", "data": [["value": 70, "name": "x"]]]]])
    }
    func testRadar() {
        assertNoDuplication("radar",
            ["radar": ["indicator": [["name": "a", "max": 10], ["name": "b", "max": 10], ["name": "c", "max": 10]]],
             "series": [["type": "radar", "data": [["value": [3, 4, 5]]]]]],
            update: ["series": [["type": "radar", "data": [["value": [5, 6, 7]]]]]])
    }

    // ---- hierarchy / graph ----
    func testGraph() {
        assertNoDuplication("graph",
            ["series": [["type": "graph", "layout": "none",
                         "data": [["name": "n1", "x": 10, "y": 10], ["name": "n2", "x": 50, "y": 50]],
                         "links": [["source": "n1", "target": "n2"]]]]],
            update: ["series": [["type": "graph", "layout": "none",
                                 "data": [["name": "n1", "x": 12, "y": 12], ["name": "n2", "x": 52, "y": 52]],
                                 "links": [["source": "n1", "target": "n2"]]]]])
    }
    func testTree() {
        assertNoDuplication("tree",
            ["series": [["type": "tree",
                          "data": [["name": "root", "children": [
                            ["name": "a", "value": 1], ["name": "b", "value": 2]
                          ]]]]]],
            update: ["series": [["type": "tree",
                                  "data": [["name": "root", "children": [
                                    ["name": "a", "value": 3], ["name": "b", "value": 4]
                                  ]]]]]])
    }
    func testTreemap() {
        assertNoDuplication("treemap",
            ["series": [["type": "treemap", "data": [["name": "a", "value": 10], ["name": "b", "value": 20]]]]],
            update: ["series": [["type": "treemap", "data": [["name": "a", "value": 15], ["name": "b", "value": 25]]]]])
    }
    func testSankey() {
        assertNoDuplication("sankey",
            ["series": [["type": "sankey",
                         "data": [["name": "a"], ["name": "b"], ["name": "c"]],
                         "links": [["source": "a", "target": "b", "value": 3], ["source": "b", "target": "c", "value": 2]]]]],
            update: ["series": [["type": "sankey",
                                 "data": [["name": "a"], ["name": "b"], ["name": "c"]],
                                 "links": [["source": "a", "target": "b", "value": 4], ["source": "b", "target": "c", "value": 3]]]]])
    }
    func testSunburst() {
        assertNoDuplication("sunburst",
            ["series": [["type": "sunburst", "data": [["name": "a", "value": 5, "children": [["name": "a1", "value": 3]]]]]]],
            update: ["series": [["type": "sunburst", "data": [["name": "a", "value": 6, "children": [["name": "a1", "value": 4]]]]]]])
    }

    // ---- other coord systems ----
    func testHeatmap() {
        assertNoDuplication("heatmap",
            ["xAxis": ["type": "category", "data": ["a", "b"]], "yAxis": ["type": "category", "data": ["x", "y"]],
             "visualMap": ["min": 0, "max": 10],
             "series": [["type": "heatmap", "data": [[0, 0, 3], [1, 1, 7]]]]],
            update: ["series": [["type": "heatmap", "data": [[0, 0, 5], [1, 1, 9]]]]])
    }
    func testThemeRiver() {
        assertNoDuplication("themeRiver",
            ["singleAxis": ["type": "time"],
             "series": [["type": "themeRiver",
                         "data": [["2020-01-01", 10, "a"], ["2020-01-02", 15, "a"],
                                  ["2020-01-01", 8, "b"], ["2020-01-02", 12, "b"]]]]],
            update: ["series": [["type": "themeRiver",
                                 "data": [["2020-01-01", 12, "a"], ["2020-01-02", 17, "a"],
                                          ["2020-01-01", 9, "b"], ["2020-01-02", 14, "b"]]]]])
    }
    func testLines() {
        assertNoDuplication("lines",
            ["xAxis": ["type": "value"], "yAxis": ["type": "value"],
             "series": [["type": "lines", "coordinateSystem": "cartesian2d",
                         "data": [["coords": [[0, 0], [10, 10]]]]]]],
            update: ["series": [["type": "lines", "coordinateSystem": "cartesian2d",
                                 "data": [["coords": [[0, 0], [12, 12]]]]]]])
    }
}
