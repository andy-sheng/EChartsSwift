// gallery-batch5 — a fifth batch of demos from canonical echarts `test/` scenarios (goal clause 2).
// More configuration variations across the ported chart types. Verified via `--render-all` (0 failed).
extension EChartsDemoRegistry {

    static let demo_bar_horizontal_stack = EChartsDemo(
        name: "bar-horizontal-stack", category: "Bar",
        summary: "horizontal stacked bars (yAxis category)",
        width: 480, height: 300,
        option: [
            "grid": ["left": 60.0, "top": 30.0, "width": 380.0, "height": 220.0] as [String: Any],
            "legend": ["top": 4.0] as [String: Any],
            "xAxis": ["type": "value"] as [String: Any],
            "yAxis": ["type": "category", "data": ["A","B","C","D"]] as [String: Any],
            "series": [
                ["name": "x", "type": "bar", "stack": "s", "data": [12.0,18,9,15]] as [String: Any],
                ["name": "y", "type": "bar", "stack": "s", "data": [8.0,6,11,7]] as [String: Any]
            ]
        ])

    static let demo_line_multi_axis = EChartsDemo(
        name: "line-multi-axis", category: "Line",
        summary: "two lines on two independent y-axes",
        width: 500, height: 300,
        option: [
            "grid": ["left": 50.0, "top": 30.0, "width": 400.0, "height": 220.0] as [String: Any],
            "legend": ["top": 4.0] as [String: Any],
            "xAxis": ["type": "category", "data": ["A","B","C","D","E"]] as [String: Any],
            "yAxis": [["type": "value"] as [String: Any], ["type": "value"] as [String: Any]],
            "series": [
                ["name": "a", "type": "line", "data": [120.0,132,101,134,90]] as [String: Any],
                ["name": "b", "type": "line", "yAxisIndex": 1, "data": [2.2,4.9,7.0,2.3,2.5]] as [String: Any]
            ]
        ])

    static let demo_scatter_two_axis = EChartsDemo(
        name: "scatter-two-axis", category: "Scatter",
        summary: "scatter with axis min/max set",
        width: 460, height: 300,
        option: [
            "grid": ["left": 50.0, "top": 20.0, "width": 380.0, "height": 240.0] as [String: Any],
            "xAxis": ["type": "value", "min": 0.0, "max": 30.0] as [String: Any],
            "yAxis": ["type": "value", "min": 0.0, "max": 30.0] as [String: Any],
            "series": [["type": "scatter", "symbolSize": 12.0,
                        "data": [[5.0,6],[12.0,18],[22.0,9],[27.0,24],[15.0,15]]] as [String: Any]]
        ])

    static let demo_pie_ring_label = EChartsDemo(
        name: "pie-ring-label", category: "Pie",
        summary: "ring pie with centered label position",
        width: 420, height: 320,
        option: [
            "series": [["type": "pie", "radius": ["35%", "65%"],
                        "label": ["position": "outside"] as [String: Any],
                        "data": [
                            ["value": 22.0, "name": "one"] as [String: Any],
                            ["value": 33.0, "name": "two"] as [String: Any],
                            ["value": 11.0, "name": "three"] as [String: Any],
                            ["value": 34.0, "name": "four"] as [String: Any]
                        ]] as [String: Any]]
        ])

    static let demo_radar_two = EChartsDemo(
        name: "radar-two", category: "Radar",
        summary: "two radar series, one filled",
        width: 440, height: 360,
        option: [
            "legend": ["top": 4.0] as [String: Any],
            "radar": ["indicator": [
                ["name": "A", "max": 100.0] as [String: Any], ["name": "B", "max": 100.0] as [String: Any],
                ["name": "C", "max": 100.0] as [String: Any], ["name": "D", "max": 100.0] as [String: Any],
                ["name": "E", "max": 100.0] as [String: Any], ["name": "F", "max": 100.0] as [String: Any]
            ]] as [String: Any],
            "series": [["type": "radar", "data": [
                ["value": [72.0,58,80,63,90,55], "name": "budget"] as [String: Any],
                ["value": [50.0,74,60,82,45,70], "name": "actual"] as [String: Any]
            ]] as [String: Any]]
        ])

    static let demo_graph_symbol = EChartsDemo(
        name: "graph-symbol", category: "Graph",
        summary: "graph with per-node symbol sizes",
        width: 420, height: 340,
        option: [
            "series": [["type": "graph", "layout": "none",
                        "data": [
                            ["name": "n0", "x": 120.0, "y": 120.0, "symbolSize": 30.0] as [String: Any],
                            ["name": "n1", "x": 260.0, "y": 110.0, "symbolSize": 18.0] as [String: Any],
                            ["name": "n2", "x": 190.0, "y": 240.0, "symbolSize": 24.0] as [String: Any]
                        ],
                        "links": [
                            ["source": "n0", "target": "n1"] as [String: Any],
                            ["source": "n1", "target": "n2"] as [String: Any],
                            ["source": "n2", "target": "n0"] as [String: Any]
                        ]] as [String: Any]]
        ])

    static let demo_sankey_multi = EChartsDemo(
        name: "sankey-multi", category: "Sankey",
        summary: "a three-column sankey",
        width: 480, height: 320,
        option: [
            "series": [["type": "sankey", "left": 20.0, "top": 20.0, "right": 40.0, "bottom": 20.0,
                        "data": [
                            ["name": "a"] as [String: Any], ["name": "b"] as [String: Any],
                            ["name": "c"] as [String: Any], ["name": "d"] as [String: Any],
                            ["name": "e"] as [String: Any]
                        ],
                        "links": [
                            ["source": "a", "target": "c", "value": 5.0] as [String: Any],
                            ["source": "b", "target": "c", "value": 3.0] as [String: Any],
                            ["source": "c", "target": "d", "value": 6.0] as [String: Any],
                            ["source": "c", "target": "e", "value": 2.0] as [String: Any]
                        ]] as [String: Any]]
        ])

    static let demo_tree_deep = EChartsDemo(
        name: "tree-deep", category: "Tree",
        summary: "a deeper orthogonal tree",
        width: 500, height: 360,
        option: [
            "series": [["type": "tree", "layout": "orthogonal", "orient": "LR",
                        "left": 20.0, "top": 20.0, "right": 100.0, "bottom": 20.0,
                        "data": [[
                            "name": "r",
                            "children": [
                                ["name": "a", "children": [
                                    ["name": "a1", "children": [["name": "a1x"] as [String: Any]]] as [String: Any],
                                    ["name": "a2"] as [String: Any]
                                ]] as [String: Any],
                                ["name": "b", "children": [["name": "b1"] as [String: Any]]] as [String: Any]
                            ]
                        ] as [String: Any]]] as [String: Any]]
        ])

    static let demo_treemap_flat = EChartsDemo(
        name: "treemap-flat", category: "Treemap",
        summary: "a flat treemap of six values",
        width: 460, height: 320,
        option: [
            "series": [["type": "treemap", "data": [
                ["name": "A", "value": 40.0] as [String: Any],
                ["name": "B", "value": 30.0] as [String: Any],
                ["name": "C", "value": 20.0] as [String: Any],
                ["name": "D", "value": 15.0] as [String: Any],
                ["name": "E", "value": 10.0] as [String: Any],
                ["name": "F", "value": 8.0] as [String: Any]
            ]] as [String: Any]]
        ])

    static let demo_sunburst_ring = EChartsDemo(
        name: "sunburst-ring", category: "Sunburst",
        summary: "a sunburst with an inner hole",
        width: 400, height: 360,
        option: [
            "series": [["type": "sunburst", "radius": ["20%", "95%"],
                        "data": [
                            ["name": "G1", "value": 12.0, "children": [
                                ["name": "g1a", "value": 5.0] as [String: Any],
                                ["name": "g1b", "value": 7.0] as [String: Any]
                            ]] as [String: Any],
                            ["name": "G2", "value": 10.0, "children": [
                                ["name": "g2a", "value": 6.0] as [String: Any],
                                ["name": "g2b", "value": 4.0] as [String: Any]
                            ]] as [String: Any],
                            ["name": "G3", "value": 6.0] as [String: Any]
                        ]] as [String: Any]]
        ])

    static let demo_boxplot_wide = EChartsDemo(
        name: "boxplot-wide", category: "Boxplot",
        summary: "seven boxplot categories",
        width: 520, height: 300,
        option: [
            "grid": ["left": 50.0, "top": 20.0, "width": 450.0, "height": 240.0] as [String: Any],
            "xAxis": ["type": "category", "data": (0..<7).map { "g\($0)" }] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [["type": "boxplot", "data": (0..<7).map { i -> [Double] in
                let b = 20.0 + Double((i * 9) % 20)
                return [b, b + 10, b + 20, b + 30, b + 42]
            }] as [String: Any]]
        ])

    static let demo_funnel_wide = EChartsDemo(
        name: "funnel-wide", category: "Funnel",
        summary: "a descending funnel with six stages",
        width: 440, height: 340,
        option: [
            "series": [["type": "funnel", "left": "10%", "top": 20.0, "width": "80%", "height": 280.0,
                        "data": [
                            ["value": 100.0, "name": "S1"] as [String: Any],
                            ["value": 80.0, "name": "S2"] as [String: Any],
                            ["value": 60.0, "name": "S3"] as [String: Any],
                            ["value": 40.0, "name": "S4"] as [String: Any],
                            ["value": 25.0, "name": "S5"] as [String: Any],
                            ["value": 12.0, "name": "S6"] as [String: Any]
                        ]] as [String: Any]]
        ])
}
