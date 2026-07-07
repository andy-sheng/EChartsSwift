// line-basic — a single cartesian line series. Now renders on BOTH panes: native (EChartsKit's
// minimal LineView) and real echarts.js.
extension EChartsDemoRegistry {
    static let demo_line_basic = EChartsDemo(
        name: "line-basic", category: "Line",
        summary: "single line series through 6 category points",
        width: 480, height: 320,
        option: [
            "grid": ["left": 40.0, "top": 20.0, "right": 20.0, "bottom": 30.0] as [String: Any],
            "xAxis": ["type": "category",
                      "data": ["A", "B", "C", "D", "E", "F"]] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [["type": "line", "data": [820.0, 932.0, 901.0, 934.0, 1290.0, 1330.0]] as [String: Any]]
        ])
}
