// sankey-basic — a single sankey (flow) series (no cartesian coord system; box usage). Renders on
// BOTH panes: native (EChartsKit's SankeyView draws a Rect per node + a filled ribbon SankeyPath per
// edge, positions coming from the sankey box-layout stage) and echarts.js. Four nodes a/b/c/d laid
// out left→right by depth, links carrying flow values.
extension EChartsDemoRegistry {
    static let demo_sankey_basic = EChartsDemo(
        name: "sankey-basic", category: "Sankey",
        summary: "single sankey series, 4 nodes a/b/c/d + weighted links",
        width: 460, height: 360,
        option: [
            "series": [["type": "sankey",
                        "left": "5%", "right": "20%", "top": "5%", "bottom": "5%",
                        "nodeWidth": 20.0, "nodeGap": 8.0,
                        "data": [
                            ["name": "a"],
                            ["name": "b"],
                            ["name": "c"],
                            ["name": "d"]
                        ],
                        "links": [
                            ["source": "a", "target": "b", "value": 5.0],
                            ["source": "a", "target": "c", "value": 3.0],
                            ["source": "b", "target": "d", "value": 4.0],
                            ["source": "c", "target": "d", "value": 2.0]
                        ]] as [String: Any]]
        ])
}
