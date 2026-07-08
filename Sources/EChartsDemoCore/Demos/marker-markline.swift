// marker-markline — line chart with markLine average (statistic horizontal line).
// Both panes render: native (EChartsKit) and real echarts.js.
extension EChartsDemoRegistry {
    static let demo_marker_markline = EChartsDemo(
        name: "marker-markline", category: "Marker",
        summary: "Line with markLine average + a fixed yAxis line",
        width: 400, height: 300,
        option: [
            "grid": ["left": 50.0, "top": 20.0, "width": 300.0, "height": 200.0] as [String: Any],
            "xAxis": ["type": "category", "data": ["A", "B", "C", "D", "E"]] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [[
                "type": "line",
                "data": [10.0, 40.0, 25.0, 15.0, 30.0],
                "markLine": [
                    "data": [
                        ["type": "average", "name": "Avg"] as [String: Any],
                        ["yAxis": 35.0, "name": "Target"] as [String: Any]
                    ]
                ] as [String: Any]
            ] as [String: Any]]
        ])
}
