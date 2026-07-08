// graph-force — a single graph (network) series with the default `layout:"force"` physics simulation
// (no cartesian coord system; box/view usage). The force layout settles synchronously for the static
// render (deterministic, index-seeded initial positions — no Date/random), so the native pane shows a
// spread-out force graph. Renders on BOTH panes: native (EChartsKit) and echarts.js (which runs its own
// live simulation, so exact node coordinates differ; the INTENT — a spread network — matches).
extension EChartsDemoRegistry {
    static let demo_graph_force = EChartsDemo(
        name: "graph-force", category: "Graph",
        summary: "single graph series, force layout, 8 nodes + 9 edges",
        width: 460, height: 360,
        option: [
            "series": [["type": "graph", "layout": "force",
                        "left": "10%", "right": "10%", "top": "10%", "bottom": "10%",
                        "symbolSize": 14.0, "roam": false,
                        "force": [
                            "repulsion": 120.0,
                            "edgeLength": 60.0,
                            "gravity": 0.1
                        ] as [String: Any],
                        "data": [
                            ["name": "n0"],
                            ["name": "n1"],
                            ["name": "n2"],
                            ["name": "n3"],
                            ["name": "n4"],
                            ["name": "n5"],
                            ["name": "n6"],
                            ["name": "n7"]
                        ],
                        "edges": [
                            ["source": "n0", "target": "n1"],
                            ["source": "n0", "target": "n2"],
                            ["source": "n0", "target": "n3"],
                            ["source": "n1", "target": "n4"],
                            ["source": "n2", "target": "n5"],
                            ["source": "n3", "target": "n6"],
                            ["source": "n4", "target": "n7"],
                            ["source": "n5", "target": "n7"],
                            ["source": "n6", "target": "n7"]
                        ]] as [String: Any]]
        ])
}
