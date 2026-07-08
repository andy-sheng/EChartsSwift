// marker-markarea — line chart with a markArea band spanning two yAxis values.
// Both panes render: native (EChartsKit) and real echarts.js.
extension EChartsDemoRegistry {
    static let demo_marker_markarea = EChartsDemo(
        name: "marker-markarea", category: "Marker",
        summary: "Line with a markArea band (yAxis 20–35)",
        width: 400, height: 300,
        option: [
            "grid": ["left": 50.0, "top": 20.0, "width": 300.0, "height": 200.0] as [String: Any],
            "xAxis": ["type": "category", "data": ["A", "B", "C", "D", "E"]] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [[
                "type": "line",
                "data": [10.0, 40.0, 25.0, 15.0, 30.0],
                "markArea": [
                    "itemStyle": ["color": "rgba(255, 173, 177, 0.4)"] as [String: Any],
                    "data": [[
                        ["yAxis": 20.0] as [String: Any],
                        ["yAxis": 35.0] as [String: Any]
                    ] as [[String: Any]]]
                ] as [String: Any]
            ] as [String: Any]]
        ])
}
