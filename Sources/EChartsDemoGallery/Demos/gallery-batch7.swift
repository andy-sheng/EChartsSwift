// gallery-batch7 — a seventh batch of demos from canonical echarts `test/` scenarios (goal clause 2).
// Item-style + edge-shape + per-indicator variations. Verified via `--render-all` (0 failed).
extension EChartsDemoRegistry {

    static let demo_bar_item_color = EChartsDemo(
        name: "bar-item-color", category: "Bar",
        summary: "bar with an explicit itemStyle color",
        width: 460, height: 300,
        option: [
            "grid": ["left": 50.0, "top": 20.0, "width": 380.0, "height": 240.0] as [String: Any],
            "xAxis": ["type": "category", "data": ["A","B","C","D","E"]] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [["type": "bar", "itemStyle": ["color": "#c23531"] as [String: Any],
                        "data": [14.0,22,18,27,20]] as [String: Any]]
        ])

    static let demo_line_item_color = EChartsDemo(
        name: "line-item-color", category: "Line",
        summary: "line with an explicit lineStyle color + wide width",
        width: 460, height: 300,
        option: [
            "grid": ["left": 50.0, "top": 20.0, "width": 380.0, "height": 240.0] as [String: Any],
            "xAxis": ["type": "category", "data": ["A","B","C","D","E","F"]] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [["type": "line", "lineStyle": ["color": "#2f4554", "width": 3.0] as [String: Any],
                        "data": [12.0,20,15,24,19,28]] as [String: Any]]
        ])

    static let demo_scatter_series_color = EChartsDemo(
        name: "scatter-series-color", category: "Scatter",
        summary: "two scatter series with explicit colors",
        width: 460, height: 300,
        option: [
            "grid": ["left": 50.0, "top": 30.0, "width": 380.0, "height": 220.0] as [String: Any],
            "legend": ["top": 4.0] as [String: Any],
            "xAxis": ["type": "value"] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [
                ["name": "p", "type": "scatter", "itemStyle": ["color": "#61a0a8"] as [String: Any],
                 "symbolSize": 12.0, "data": [[10.0,8],[15.0,14],[8.0,11]]] as [String: Any],
                ["name": "q", "type": "scatter", "itemStyle": ["color": "#d48265"] as [String: Any],
                 "symbolSize": 12.0, "data": [[12.0,18],[20.0,7],[16.0,15]]] as [String: Any]
            ]
        ])

    static let demo_pie_colored = EChartsDemo(
        name: "pie-colored", category: "Pie",
        summary: "pie with per-slice itemStyle colors",
        width: 400, height: 320,
        option: [
            "series": [["type": "pie", "radius": "62%",
                        "data": [
                            ["value": 30.0, "name": "r", "itemStyle": ["color": "#c23531"] as [String: Any]] as [String: Any],
                            ["value": 25.0, "name": "g", "itemStyle": ["color": "#2f8f4e"] as [String: Any]] as [String: Any],
                            ["value": 20.0, "name": "b", "itemStyle": ["color": "#3a6ea5"] as [String: Any]] as [String: Any],
                            ["value": 25.0, "name": "y", "itemStyle": ["color": "#d4a017"] as [String: Any]] as [String: Any]
                        ]] as [String: Any]]
        ])

    static let demo_tree_polyline = EChartsDemo(
        name: "tree-polyline", category: "Tree",
        summary: "tree with polyline edgeShape",
        width: 500, height: 340,
        option: [
            "series": [["type": "tree", "layout": "orthogonal", "orient": "LR",
                        "edgeShape": "polyline",
                        "left": 20.0, "top": 20.0, "right": 100.0, "bottom": 20.0,
                        "data": [[
                            "name": "root",
                            "children": [
                                ["name": "A", "children": [
                                    ["name": "A1"] as [String: Any], ["name": "A2"] as [String: Any]
                                ]] as [String: Any],
                                ["name": "B", "children": [["name": "B1"] as [String: Any]]] as [String: Any]
                            ]
                        ] as [String: Any]]] as [String: Any]]
        ])

    static let demo_graph_grid = EChartsDemo(
        name: "graph-grid", category: "Graph",
        summary: "a 3×3 grid graph (layout none)",
        width: 420, height: 380,
        option: [
            "series": [["type": "graph", "layout": "none", "symbolSize": 18.0,
                        "data": {
                            var d: [[String: Any]] = []
                            for r in 0..<3 { for c in 0..<3 {
                                d.append(["name": "n\(r)\(c)", "x": Double(80 + c * 120), "y": Double(60 + r * 120)])
                            } }
                            return d
                        }(),
                        "links": {
                            var l: [[String: Any]] = []
                            for r in 0..<3 { for c in 0..<3 {
                                if c < 2 { l.append(["source": "n\(r)\(c)", "target": "n\(r)\(c + 1)"]) }
                                if r < 2 { l.append(["source": "n\(r)\(c)", "target": "n\(r + 1)\(c)"]) }
                            } }
                            return l
                        }()] as [String: Any]]
        ])

    static let demo_sankey_branch = EChartsDemo(
        name: "sankey-branch", category: "Sankey",
        summary: "a branching sankey (one source → three targets)",
        width: 480, height: 320,
        option: [
            "series": [["type": "sankey", "left": 20.0, "top": 20.0, "right": 40.0, "bottom": 20.0,
                        "data": [
                            ["name": "root"] as [String: Any], ["name": "t1"] as [String: Any],
                            ["name": "t2"] as [String: Any], ["name": "t3"] as [String: Any]
                        ],
                        "links": [
                            ["source": "root", "target": "t1", "value": 4.0] as [String: Any],
                            ["source": "root", "target": "t2", "value": 6.0] as [String: Any],
                            ["source": "root", "target": "t3", "value": 3.0] as [String: Any]
                        ]] as [String: Any]]
        ])

    static let demo_radar_varied_max = EChartsDemo(
        name: "radar-varied-max", category: "Radar",
        summary: "radar with a different max per indicator",
        width: 440, height: 360,
        option: [
            "radar": ["indicator": [
                ["name": "Sales", "max": 6500.0] as [String: Any],
                ["name": "Admin", "max": 16000.0] as [String: Any],
                ["name": "Tech", "max": 30000.0] as [String: Any],
                ["name": "Support", "max": 38000.0] as [String: Any],
                ["name": "Dev", "max": 52000.0] as [String: Any],
                ["name": "Market", "max": 25000.0] as [String: Any]
            ]] as [String: Any],
            "series": [["type": "radar", "data": [
                ["value": [4300.0, 10000, 28000, 35000, 50000, 19000], "name": "budget"] as [String: Any]
            ]] as [String: Any]]
        ])

    static let demo_heatmap_piecewise = EChartsDemo(
        name: "heatmap-piecewise", category: "Heatmap",
        summary: "heatmap with a piecewise visualMap",
        width: 480, height: 320,
        option: [
            "grid": ["left": 50.0, "top": 20.0, "width": 380.0, "height": 200.0] as [String: Any],
            "xAxis": ["type": "category", "data": (0..<8).map { "c\($0)" }] as [String: Any],
            "yAxis": ["type": "category", "data": (0..<5).map { "r\($0)" }] as [String: Any],
            "visualMap": ["type": "piecewise", "min": 0.0, "max": 10.0, "splitNumber": 5,
                          "orient": "horizontal", "left": "center", "bottom": 0.0] as [String: Any],
            "series": [["type": "heatmap", "data": {
                var d: [[Double]] = []
                for x in 0..<8 { for y in 0..<5 { d.append([Double(x), Double(y), Double((x * 3 + y * 2) % 11)]) } }
                return d
            }()] as [String: Any]]
        ])

    static let demo_line_boundary_gap = EChartsDemo(
        name: "line-boundary-gap", category: "Line",
        summary: "line with boundaryGap:false (starts at the axis edge)",
        width: 460, height: 300,
        option: [
            "grid": ["left": 50.0, "top": 20.0, "width": 380.0, "height": 240.0] as [String: Any],
            "xAxis": ["type": "category", "boundaryGap": false,
                      "data": ["A","B","C","D","E","F","G"]] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [["type": "line", "data": [8.0,15,10,22,17,26,20]] as [String: Any]]
        ])

    static let demo_themeriver_three = EChartsDemo(
        name: "themeriver-three", category: "ThemeRiver",
        summary: "a three-series themeRiver",
        width: 520, height: 300,
        option: [
            "singleAxis": ["type": "time", "top": 30.0, "bottom": 30.0] as [String: Any],
            "series": [["type": "themeRiver", "data": [
                ["2015/11/08", 10.0, "A"], ["2015/11/09", 15.0, "A"], ["2015/11/10", 12.0, "A"],
                ["2015/11/08", 8.0, "B"],  ["2015/11/09", 11.0, "B"], ["2015/11/10", 14.0, "B"],
                ["2015/11/08", 5.0, "C"],  ["2015/11/09", 7.0, "C"],  ["2015/11/10", 9.0, "C"]
            ]] as [String: Any]]
        ])

    static let demo_boxplot_single = EChartsDemo(
        name: "boxplot-single", category: "Boxplot",
        summary: "a single boxplot category",
        width: 360, height: 300,
        option: [
            "grid": ["left": 50.0, "top": 20.0, "width": 280.0, "height": 240.0] as [String: Any],
            "xAxis": ["type": "category", "data": ["only"]] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [["type": "boxplot", "data": [[18.0, 30, 42, 55, 68]]] as [String: Any]]
        ])
}
