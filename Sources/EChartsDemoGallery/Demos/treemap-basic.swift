// treemap-basic — a single treemap series (no coordinate system; hierarchical tree + squarified rect
// layout, box-like usage). Renders on BOTH panes: native (EChartsKit's TreemapView draws a Rect per
// tree node) and echarts.js.
extension EChartsDemoRegistry {
    static let demo_treemap_basic = EChartsDemo(
        name: "treemap-basic", category: "Treemap",
        summary: "single treemap series, 2-level hierarchy",
        width: 460, height: 360,
        option: [
            "series": [["type": "treemap", "left": "5%", "top": 20.0, "width": "90%", "height": 320.0,
                        "data": [
                            ["name": "nodeA", "value": 10.0, "children": [
                                ["name": "nodeA1", "value": 4.0],
                                ["name": "nodeA2", "value": 6.0]
                            ]],
                            ["name": "nodeB", "value": 20.0, "children": [
                                ["name": "nodeB1", "value": 5.0],
                                ["name": "nodeB2", "value": 8.0],
                                ["name": "nodeB3", "value": 7.0]
                            ]],
                            ["name": "nodeC", "value": 12.0, "children": [
                                ["name": "nodeC1", "value": 12.0]
                            ]]
                        ]] as [String: Any]]
        ])
}
