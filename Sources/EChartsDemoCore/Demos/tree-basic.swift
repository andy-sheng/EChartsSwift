// tree-basic — a single tree series (no coordinate system; hierarchical tidy-tree x/y layout, box-like
// usage). Renders on BOTH panes: native (EChartsKit's TreeView draws a Symbol per node + an edge per
// parent/child link) and echarts.js.
extension EChartsDemoRegistry {
    static let demo_tree_basic = EChartsDemo(
        name: "tree-basic", category: "Tree",
        summary: "single tree series, orthogonal 3-level hierarchy",
        width: 460, height: 360,
        option: [
            "series": [["type": "tree", "left": "10%", "right": "10%", "top": "10%", "bottom": "10%",
                        "symbolSize": 8.0, "orient": "LR",
                        "data": [
                            ["name": "root", "children": [
                                ["name": "A", "children": [
                                    ["name": "A1"],
                                    ["name": "A2"]
                                ]],
                                ["name": "B", "children": [
                                    ["name": "B1"],
                                    ["name": "B2"],
                                    ["name": "B3"]
                                ]]
                            ]]
                        ]] as [String: Any]]
        ])
}
