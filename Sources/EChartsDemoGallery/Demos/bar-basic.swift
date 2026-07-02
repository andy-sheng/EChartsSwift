// bar-basic — the canonical cartesian bar chart (matches BarChartRenderTests).
// Both panes render: native (EChartsKit) and real echarts.js.
extension EChartsDemoRegistry {
    static let demo_bar_basic = EChartsDemo(
        name: "bar-basic", category: "Bar",
        summary: "4 categories, single bar series (10/20/30/40)",
        width: 400, height: 300,
        option: [
            "grid": ["left": 50.0, "top": 20.0, "width": 300.0, "height": 200.0] as [String: Any],
            "xAxis": ["type": "category", "data": ["A", "B", "C", "D"]] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [["type": "bar", "data": [10.0, 20.0, 30.0, 40.0]] as [String: Any]]
        ])
}
