// gallery-batch3 — a third batch of demos derived from canonical echarts `test/` scenarios (goal clause 2:
// "在demo中实现echart test中所有用例"). Names mirror the upstream test/*.html files. Each is an
// option-expressible static snapshot exercising a ported feature; verified via `--render-all` (0 failed).
extension EChartsDemoRegistry {

    // ---- bar family ----
    static let demo_bar_background = EChartsDemo(
        name: "bar-background", category: "Bar",
        summary: "bar with showBackground (track behind each bar)",
        width: 460, height: 300,
        option: [
            "grid": ["left": 50.0, "top": 20.0, "width": 380.0, "height": 240.0] as [String: Any],
            "xAxis": ["type": "category", "data": ["A","B","C","D","E","F"]] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [["type": "bar", "showBackground": true, "data": [12.0,20,15,28,18,24]] as [String: Any]]
        ])

    static let demo_bar_large = EChartsDemo(
        name: "bar-large", category: "Bar",
        summary: "a wide bar series (40 bars)",
        width: 520, height: 300,
        option: [
            "grid": ["left": 45.0, "top": 20.0, "width": 450.0, "height": 240.0] as [String: Any],
            "xAxis": ["type": "category", "data": (0..<40).map { "\($0)" }] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [["type": "bar", "data": (0..<40).map { Double(($0 * 37 + 11) % 50 + 5) }] as [String: Any]]
        ])

    static let demo_bar_width = EChartsDemo(
        name: "bar-width", category: "Bar",
        summary: "fixed barWidth",
        width: 460, height: 300,
        option: [
            "grid": ["left": 50.0, "top": 20.0, "width": 380.0, "height": 240.0] as [String: Any],
            "xAxis": ["type": "category", "data": ["Mon","Tue","Wed","Thu","Fri"]] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [["type": "bar", "barWidth": 20.0, "data": [23.0,18,29,14,26]] as [String: Any]]
        ])

    static let demo_bar_stack_reverse = EChartsDemo(
        name: "bar-stack-reverse", category: "Bar",
        summary: "two stacked bar series with a reversed yAxis feel (stack:'x')",
        width: 460, height: 300,
        option: [
            "grid": ["left": 50.0, "top": 30.0, "width": 380.0, "height": 220.0] as [String: Any],
            "legend": ["top": 4.0] as [String: Any],
            "xAxis": ["type": "category", "data": ["A","B","C","D","E"]] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [
                ["name": "p", "type": "bar", "stack": "x", "data": [8.0,12,10,14,9]] as [String: Any],
                ["name": "q", "type": "bar", "stack": "x", "data": [6.0,5,9,4,7]] as [String: Any]
            ]
        ])

    // ---- boxplot ----
    static let demo_boxplot_multi = EChartsDemo(
        name: "boxplot-multi", category: "Boxplot",
        summary: "multiple boxplot categories",
        width: 480, height: 300,
        option: [
            "grid": ["left": 50.0, "top": 20.0, "width": 400.0, "height": 240.0] as [String: Any],
            "xAxis": ["type": "category", "data": ["c1","c2","c3","c4","c5"]] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [["type": "boxplot", "data": [
                [20.0, 34, 46, 55, 70], [22.0, 40, 50, 62, 78],
                [15.0, 30, 42, 51, 66], [25.0, 38, 48, 60, 72],
                [18.0, 33, 44, 54, 69]
            ]] as [String: Any]]
        ])

    // ---- candlestick ----
    static let demo_candlestick_large = EChartsDemo(
        name: "candlestick-large", category: "Candlestick",
        summary: "a longer OHLC candlestick series",
        width: 520, height: 300,
        option: [
            "grid": ["left": 50.0, "top": 20.0, "width": 450.0, "height": 240.0] as [String: Any],
            "xAxis": ["type": "category", "data": (0..<20).map { "d\($0)" }] as [String: Any],
            "yAxis": ["type": "value", "scale": true] as [String: Any],
            "series": [["type": "candlestick", "data": (0..<20).map { i -> [Double] in
                let base = 40.0 + Double((i * 13) % 20)
                return [base, base + Double((i * 7) % 8) - 3, base - Double((i * 5) % 6), base + Double((i * 11) % 10)]
            }] as [String: Any]]
        ])

    // ---- funnel ----
    static let demo_funnel_sorted = EChartsDemo(
        name: "funnel-sorted", category: "Funnel",
        summary: "ascending-sorted funnel",
        width: 440, height: 320,
        option: [
            "series": [[
                "type": "funnel", "sort": "ascending", "left": "10%", "top": 20.0,
                "width": "80%", "height": 260.0,
                "data": [
                    ["value": 60.0, "name": "Visit"] as [String: Any],
                    ["value": 40.0, "name": "Inquiry"] as [String: Any],
                    ["value": 20.0, "name": "Order"] as [String: Any],
                    ["value": 80.0, "name": "Show"] as [String: Any],
                    ["value": 100.0, "name": "Click"] as [String: Any]
                ]
            ] as [String: Any]]
        ])

    // ---- gauge ----
    static let demo_gauge_simple = EChartsDemo(
        name: "gauge-simple", category: "Gauge",
        summary: "a single-pointer gauge at 62",
        width: 360, height: 340,
        option: [
            "series": [["type": "gauge", "data": [["value": 62.0, "name": "Score"] as [String: Any]]] as [String: Any]]
        ])

    // ---- graph ----
    static let demo_graph_circular = EChartsDemo(
        name: "graph-circular", category: "Graph",
        summary: "circular-layout graph",
        width: 420, height: 360,
        option: [
            "series": [["type": "graph", "layout": "circular", "symbolSize": 22.0,
                        "circular": ["rotateLabel": true] as [String: Any],
                        "data": (0..<8).map { ["name": "n\($0)"] as [String: Any] },
                        "links": (0..<8).map { ["source": "n\($0)", "target": "n\(($0 + 1) % 8)"] as [String: Any] }
                       ] as [String: Any]]
        ])

    // ---- heatmap ----
    static let demo_heatmap_large = EChartsDemo(
        name: "heatmap-large", category: "Heatmap",
        summary: "a 12×7 cartesian heatmap colored by visualMap",
        width: 500, height: 320,
        option: [
            "grid": ["left": 50.0, "top": 20.0, "width": 400.0, "height": 220.0] as [String: Any],
            "xAxis": ["type": "category", "data": (0..<12).map { "h\($0)" }] as [String: Any],
            "yAxis": ["type": "category", "data": ["Mon","Tue","Wed","Thu","Fri","Sat","Sun"]] as [String: Any],
            "visualMap": ["min": 0.0, "max": 10.0, "calculable": true,
                          "orient": "horizontal", "left": "center", "bottom": 0.0] as [String: Any],
            "series": [["type": "heatmap", "data": {
                var d: [[Double]] = []
                for x in 0..<12 { for y in 0..<7 { d.append([Double(x), Double(y), Double((x * 3 + y * 5) % 11)]) } }
                return d
            }()] as [String: Any]]
        ])

    // ---- parallel ----
    static let demo_parallel_multi = EChartsDemo(
        name: "parallel-multi", category: "Parallel",
        summary: "parallel coordinates, 4 dimensions × 5 lines",
        width: 500, height: 320,
        option: [
            "parallelAxis": [
                ["dim": 0, "name": "Price"] as [String: Any],
                ["dim": 1, "name": "Weight"] as [String: Any],
                ["dim": 2, "name": "Power"] as [String: Any],
                ["dim": 3, "name": "Score"] as [String: Any]
            ],
            "series": [["type": "parallel", "data": [
                [10.0, 20, 30, 85], [22.0, 14, 44, 62], [8.0, 28, 18, 74],
                [30.0, 10, 50, 55], [16.0, 24, 26, 90]
            ]] as [String: Any]]
        ])

    // ---- pie ----
    static let demo_pie_half = EChartsDemo(
        name: "pie-half", category: "Pie",
        summary: "half-doughnut (startAngle/endAngle)",
        width: 420, height: 300,
        option: [
            "series": [[
                "type": "pie", "radius": ["40%", "70%"],
                "center": ["50%", "70%"], "startAngle": 180.0, "endAngle": 360.0,
                "data": [
                    ["value": 40.0, "name": "A"] as [String: Any],
                    ["value": 30.0, "name": "B"] as [String: Any],
                    ["value": 20.0, "name": "C"] as [String: Any],
                    ["value": 10.0, "name": "D"] as [String: Any]
                ]
            ] as [String: Any]]
        ])

    // ---- radar ----
    static let demo_radar_filled = EChartsDemo(
        name: "radar-filled", category: "Radar",
        summary: "radar with an areaStyle fill",
        width: 420, height: 360,
        option: [
            "radar": ["indicator": [
                ["name": "A", "max": 100.0] as [String: Any], ["name": "B", "max": 100.0] as [String: Any],
                ["name": "C", "max": 100.0] as [String: Any], ["name": "D", "max": 100.0] as [String: Any],
                ["name": "E", "max": 100.0] as [String: Any]
            ]] as [String: Any],
            "series": [["type": "radar", "areaStyle": [String: Any](),
                        "data": [["value": [78.0,62,84,55,70], "name": "s"] as [String: Any]]] as [String: Any]]
        ])

    // ---- scatter ----
    static let demo_scatter_symbolsize = EChartsDemo(
        name: "scatter-symbolsize", category: "Scatter",
        summary: "scatter with a large fixed symbolSize",
        width: 460, height: 300,
        option: [
            "grid": ["left": 50.0, "top": 20.0, "width": 380.0, "height": 240.0] as [String: Any],
            "xAxis": ["type": "value"] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [["type": "scatter", "symbolSize": 22.0,
                        "data": [[10.0,8],[15.0,14],[8.0,11],[20.0,6],[13.0,17],[17.0,10]]] as [String: Any]]
        ])

    // ---- sankey ----
    static let demo_sankey_vertical = EChartsDemo(
        name: "sankey-vertical", category: "Sankey",
        summary: "vertical-orient sankey",
        width: 420, height: 360,
        option: [
            "series": [["type": "sankey", "orient": "vertical",
                        "left": 20.0, "top": 20.0, "right": 20.0, "bottom": 20.0,
                        "data": [
                            ["name": "a"] as [String: Any], ["name": "b"] as [String: Any],
                            ["name": "c"] as [String: Any], ["name": "d"] as [String: Any]
                        ],
                        "links": [
                            ["source": "a", "target": "b", "value": 6.0] as [String: Any],
                            ["source": "a", "target": "c", "value": 4.0] as [String: Any],
                            ["source": "b", "target": "d", "value": 3.0] as [String: Any],
                            ["source": "c", "target": "d", "value": 5.0] as [String: Any]
                        ]] as [String: Any]]
        ])

    // ---- sunburst ----
    static let demo_sunburst_multi = EChartsDemo(
        name: "sunburst-multi", category: "Sunburst",
        summary: "a two-level sunburst",
        width: 400, height: 360,
        option: [
            "series": [["type": "sunburst", "radius": ["0%", "90%"],
                        "data": [
                            ["name": "A", "value": 10.0, "children": [
                                ["name": "A1", "value": 4.0] as [String: Any],
                                ["name": "A2", "value": 6.0] as [String: Any]
                            ]] as [String: Any],
                            ["name": "B", "value": 8.0, "children": [
                                ["name": "B1", "value": 5.0] as [String: Any],
                                ["name": "B2", "value": 3.0] as [String: Any]
                            ]] as [String: Any]
                        ]] as [String: Any]]
        ])

    // ---- treemap ----
    static let demo_treemap_levels = EChartsDemo(
        name: "treemap-levels", category: "Treemap",
        summary: "a nested treemap",
        width: 460, height: 320,
        option: [
            "series": [["type": "treemap", "data": [
                ["name": "N1", "value": 20.0, "children": [
                    ["name": "N1a", "value": 12.0] as [String: Any],
                    ["name": "N1b", "value": 8.0] as [String: Any]
                ]] as [String: Any],
                ["name": "N2", "value": 16.0, "children": [
                    ["name": "N2a", "value": 9.0] as [String: Any],
                    ["name": "N2b", "value": 7.0] as [String: Any]
                ]] as [String: Any]
            ]] as [String: Any]]
        ])

    // ---- tree ----
    static let demo_tree_right = EChartsDemo(
        name: "tree-right", category: "Tree",
        summary: "orthogonal tree, left-to-right",
        width: 480, height: 340,
        option: [
            "series": [["type": "tree", "layout": "orthogonal", "orient": "LR",
                        "left": 20.0, "top": 20.0, "right": 80.0, "bottom": 20.0,
                        "data": [[
                            "name": "root",
                            "children": [
                                ["name": "X", "children": [
                                    ["name": "X1"] as [String: Any], ["name": "X2"] as [String: Any]
                                ]] as [String: Any],
                                ["name": "Y", "children": [
                                    ["name": "Y1"] as [String: Any]
                                ]] as [String: Any]
                            ]
                        ] as [String: Any]]] as [String: Any]]
        ])

    // ---- line ----
    static let demo_line_negative = EChartsDemo(
        name: "line-negative", category: "Line",
        summary: "a line crossing zero (negative values)",
        width: 460, height: 300,
        option: [
            "grid": ["left": 50.0, "top": 20.0, "width": 380.0, "height": 240.0] as [String: Any],
            "xAxis": ["type": "category", "data": ["A","B","C","D","E","F","G"]] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [["type": "line", "data": [10.0, -5, 8, -12, 3, -7, 14]] as [String: Any]]
        ])
}
