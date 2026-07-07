// graph-basic — a single graph (network) series with a circular layout (no cartesian coord system;
// box/view usage). Renders on BOTH panes: native (EChartsKit's GraphView draws a Symbol per node + a
// Line per edge, positions coming from the circular-layout stage) and echarts.js.
extension EChartsDemoRegistry {
    static let demo_graph_basic = EChartsDemo(
        name: "graph-basic", category: "Graph",
        summary: "single graph series, circular layout, 5 nodes + 5 edges",
        width: 460, height: 360,
        option: [
            "series": [["type": "graph", "layout": "circular",
                        "left": "10%", "right": "10%", "top": "10%", "bottom": "10%",
                        "symbolSize": 12.0, "roam": false,
                        "data": [
                            ["name": "n0"],
                            ["name": "n1"],
                            ["name": "n2"],
                            ["name": "n3"],
                            ["name": "n4"]
                        ],
                        "edges": [
                            ["source": "n0", "target": "n1"],
                            ["source": "n1", "target": "n2"],
                            ["source": "n2", "target": "n3"],
                            ["source": "n3", "target": "n4"],
                            ["source": "n4", "target": "n0"]
                        ]] as [String: Any]]
        ])
}
