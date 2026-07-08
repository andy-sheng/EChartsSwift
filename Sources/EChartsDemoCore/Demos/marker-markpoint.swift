// marker-markpoint — bar chart with markPoint max + min (statistic markers).
// Both panes render: native (EChartsKit) and real echarts.js.
extension EChartsDemoRegistry {
    static let demo_marker_markpoint = EChartsDemo(
        name: "marker-markpoint", category: "Marker",
        summary: "Bar with markPoint max + min pins",
        width: 400, height: 300,
        option: [
            "grid": ["left": 50.0, "top": 20.0, "width": 300.0, "height": 200.0] as [String: Any],
            "xAxis": ["type": "category", "data": ["A", "B", "C", "D", "E"]] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [[
                "type": "bar",
                "data": [10.0, 40.0, 25.0, 15.0, 30.0],
                "markPoint": [
                    "data": [
                        ["type": "max", "name": "Max"] as [String: Any],
                        ["type": "min", "name": "Min"] as [String: Any]
                    ]
                ] as [String: Any]
            ] as [String: Any]]
        ])
}
