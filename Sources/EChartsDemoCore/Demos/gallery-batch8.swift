// gallery-batch8 — an eighth batch of demos from canonical echarts `test/` scenarios (goal clause 2).
// Label / symbol / split-area / depth variations. Verified via `--render-all` (0 failed).
extension EChartsDemoRegistry {

    static let demo_bar_label_top = EChartsDemo(
        name: "bar-label-top", category: "Bar",
        summary: "bar with value labels above each bar",
        width: 460, height: 300,
        option: [
            "grid": ["left": 50.0, "top": 30.0, "width": 380.0, "height": 230.0] as [String: Any],
            "xAxis": ["type": "category", "data": ["A","B","C","D","E"]] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [["type": "bar", "label": ["show": true, "position": "top"] as [String: Any],
                        "data": [12.0,20,15,28,18]] as [String: Any]]
        ])

    static let demo_line_no_symbol = EChartsDemo(
        name: "line-no-symbol", category: "Line",
        summary: "line with showSymbol:false (bare polyline)",
        width: 460, height: 300,
        option: [
            "grid": ["left": 50.0, "top": 20.0, "width": 380.0, "height": 240.0] as [String: Any],
            "xAxis": ["type": "category", "data": (0..<12).map { "\($0)" }] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [["type": "line", "showSymbol": false,
                        "data": (0..<12).map { Double(($0 * 13 + 7) % 30 + 5) }] as [String: Any]]
        ])

    static let demo_pie_label_inside = EChartsDemo(
        name: "pie-label-inside", category: "Pie",
        summary: "pie with inside labels",
        width: 400, height: 320,
        option: [
            "series": [["type": "pie", "radius": "62%",
                        "label": ["position": "inside", "show": true] as [String: Any],
                        "data": [
                            ["value": 40.0, "name": "A"] as [String: Any],
                            ["value": 30.0, "name": "B"] as [String: Any],
                            ["value": 20.0, "name": "C"] as [String: Any],
                            ["value": 10.0, "name": "D"] as [String: Any]
                        ]] as [String: Any]]
        ])

    static let demo_scatter_dense = EChartsDemo(
        name: "scatter-dense", category: "Scatter",
        summary: "a denser 60-point scatter",
        width: 460, height: 300,
        option: [
            "grid": ["left": 50.0, "top": 20.0, "width": 380.0, "height": 240.0] as [String: Any],
            "xAxis": ["type": "value"] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [["type": "scatter", "symbolSize": 7.0, "data": {
                var d: [[Double]] = []
                for i in 0..<60 { d.append([Double((i * 17) % 50), Double((i * 29) % 40)]) }
                return d
            }()] as [String: Any]]
        ])

    static let demo_radar_split_area = EChartsDemo(
        name: "radar-split-area", category: "Radar",
        summary: "radar with alternating split areas",
        width: 420, height: 360,
        option: [
            "radar": ["indicator": [
                ["name": "A", "max": 100.0] as [String: Any], ["name": "B", "max": 100.0] as [String: Any],
                ["name": "C", "max": 100.0] as [String: Any], ["name": "D", "max": 100.0] as [String: Any],
                ["name": "E", "max": 100.0] as [String: Any]
            ], "splitArea": ["show": true] as [String: Any]] as [String: Any],
            "series": [["type": "radar", "data": [["value": [70.0,55,82,60,90], "name": "s"] as [String: Any]]] as [String: Any]]
        ])

    static let demo_graph_labeled = EChartsDemo(
        name: "graph-labeled", category: "Graph",
        summary: "graph nodes with labels shown",
        width: 420, height: 340,
        option: [
            "series": [["type": "graph", "layout": "none", "symbolSize": 26.0,
                        "label": ["show": true] as [String: Any],
                        "data": [
                            ["name": "alpha", "x": 120.0, "y": 120.0] as [String: Any],
                            ["name": "beta", "x": 260.0, "y": 110.0] as [String: Any],
                            ["name": "gamma", "x": 190.0, "y": 240.0] as [String: Any]
                        ],
                        "links": [
                            ["source": "alpha", "target": "beta"] as [String: Any],
                            ["source": "beta", "target": "gamma"] as [String: Any]
                        ]] as [String: Any]]
        ])

    static let demo_sankey_labeled = EChartsDemo(
        name: "sankey-labeled", category: "Sankey",
        summary: "sankey with node labels",
        width: 460, height: 320,
        option: [
            "series": [["type": "sankey", "left": 20.0, "top": 20.0, "right": 60.0, "bottom": 20.0,
                        "label": ["show": true] as [String: Any],
                        "data": [
                            ["name": "src"] as [String: Any], ["name": "mid"] as [String: Any],
                            ["name": "end"] as [String: Any]
                        ],
                        "links": [
                            ["source": "src", "target": "mid", "value": 8.0] as [String: Any],
                            ["source": "mid", "target": "end", "value": 5.0] as [String: Any]
                        ]] as [String: Any]]
        ])

    static let demo_tree_top_bottom = EChartsDemo(
        name: "tree-top-bottom", category: "Tree",
        summary: "tree with a top-to-bottom orient",
        width: 460, height: 360,
        option: [
            "series": [["type": "tree", "layout": "orthogonal", "orient": "TB",
                        "left": 20.0, "top": 20.0, "right": 20.0, "bottom": 40.0,
                        "data": [[
                            "name": "root",
                            "children": [
                                ["name": "A", "children": [["name": "A1"] as [String: Any]]] as [String: Any],
                                ["name": "B", "children": [["name": "B1"] as [String: Any], ["name": "B2"] as [String: Any]]] as [String: Any]
                            ]
                        ] as [String: Any]]] as [String: Any]]
        ])

    static let demo_treemap_three = EChartsDemo(
        name: "treemap-three", category: "Treemap",
        summary: "a three-branch treemap",
        width: 460, height: 320,
        option: [
            "series": [["type": "treemap", "data": [
                ["name": "P", "value": 30.0, "children": [
                    ["name": "P1", "value": 18.0] as [String: Any], ["name": "P2", "value": 12.0] as [String: Any]
                ]] as [String: Any],
                ["name": "Q", "value": 22.0, "children": [
                    ["name": "Q1", "value": 22.0] as [String: Any]
                ]] as [String: Any],
                ["name": "R", "value": 14.0] as [String: Any]
            ]] as [String: Any]]
        ])

    static let demo_sunburst_labeled = EChartsDemo(
        name: "sunburst-labeled", category: "Sunburst",
        summary: "sunburst with node labels",
        width: 400, height: 360,
        option: [
            "series": [["type": "sunburst", "radius": ["15%", "90%"],
                        "label": ["show": true] as [String: Any],
                        "data": [
                            ["name": "X", "value": 10.0, "children": [
                                ["name": "x1", "value": 6.0] as [String: Any],
                                ["name": "x2", "value": 4.0] as [String: Any]
                            ]] as [String: Any],
                            ["name": "Y", "value": 8.0] as [String: Any]
                        ]] as [String: Any]]
        ])

    static let demo_bar_min_height = EChartsDemo(
        name: "bar-min-height", category: "Bar",
        summary: "bar with a barMinHeight (tiny values still visible)",
        width: 460, height: 300,
        option: [
            "grid": ["left": 50.0, "top": 20.0, "width": 380.0, "height": 240.0] as [String: Any],
            "xAxis": ["type": "category", "data": ["A","B","C","D","E"]] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [["type": "bar", "barMinHeight": 5.0, "data": [0.5, 20, 0.2, 15, 0.8]] as [String: Any]]
        ])

    static let demo_line_two_smooth = EChartsDemo(
        name: "line-two-smooth", category: "Line",
        summary: "two smooth lines with symbols",
        width: 460, height: 300,
        option: [
            "grid": ["left": 50.0, "top": 30.0, "width": 380.0, "height": 220.0] as [String: Any],
            "legend": ["top": 4.0] as [String: Any],
            "xAxis": ["type": "category", "data": ["A","B","C","D","E","F","G"]] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [
                ["name": "hi", "type": "line", "smooth": true, "data": [20.0,32,28,40,35,48,42]] as [String: Any],
                ["name": "lo", "type": "line", "smooth": true, "data": [10.0,15,12,20,17,24,21]] as [String: Any]
            ]
        ])

    // Toolbox icon row (top-right): magicType line↔bar, restore, dataZoom box, saveAsImage. Exercises
    //   the toolbox VIEW (feature icons rendered via makePath, laid out by the box layout).
    static let demo_toolbox_basic = EChartsDemo(
        name: "toolbox-basic", category: "Component",
        summary: "toolbox icon row (magicType / restore / dataZoom / saveAsImage)",
        width: 460, height: 300,
        option: [
            "grid": ["left": 50.0, "top": 40.0, "width": 380.0, "height": 220.0] as [String: Any],
            "toolbox": [
                "feature": [
                    "magicType": ["type": ["line", "bar", "stack"]] as [String: Any],
                    "restore": [String: Any](),
                    "dataZoom": [String: Any](),
                    "saveAsImage": [String: Any]()
                ] as [String: Any]
            ] as [String: Any],
            "xAxis": ["type": "category", "data": ["A","B","C","D","E","F"]] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [["type": "bar", "data": [12.0, 20, 15, 28, 18, 24]] as [String: Any]]
        ])
}
