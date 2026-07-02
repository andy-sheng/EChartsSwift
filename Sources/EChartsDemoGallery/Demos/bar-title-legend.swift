// bar-title-legend — exercises the Phase-7 static components: a `title` (main + subtext) and a
// `legend` above a cartesian bar series. Renders on BOTH panes (native EChartsKit + echarts.js).
extension EChartsDemoRegistry {
    static let demo_bar_title_legend = EChartsDemo(
        name: "bar-title-legend", category: "Component",
        summary: "title + legend over a bar series",
        width: 500, height: 360,
        option: [
            "title": ["text": "Weekly Sales", "subtext": "Phase 7 demo", "left": "center"] as [String: Any],
            "legend": ["data": ["Alpha"], "top": 30.0] as [String: Any],
            "grid": ["left": 50.0, "top": 70.0, "width": 400.0, "height": 250.0] as [String: Any],
            "xAxis": ["type": "category", "data": ["Mon", "Tue", "Wed", "Thu", "Fri"]] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [["name": "Alpha", "type": "bar",
                        "data": [120.0, 200.0, 150.0, 80.0, 170.0]] as [String: Any]]
        ])
}
