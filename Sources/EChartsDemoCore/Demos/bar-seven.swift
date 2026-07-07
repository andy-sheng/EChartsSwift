// bar-seven — a wider bar series (7 categories, non-monotonic) to exercise band-width layout
// with more columns. Both panes render.
extension EChartsDemoRegistry {
    static let demo_bar_seven = EChartsDemo(
        name: "bar-seven", category: "Bar",
        summary: "7 categories, non-monotonic values (weekday-style)",
        width: 480, height: 320,
        option: [
            "grid": ["left": 40.0, "top": 20.0, "right": 20.0, "bottom": 30.0] as [String: Any],
            "xAxis": ["type": "category",
                      "data": ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [["type": "bar",
                        "data": [120.0, 200.0, 150.0, 80.0, 70.0, 110.0, 130.0]] as [String: Any]]
        ])
}
