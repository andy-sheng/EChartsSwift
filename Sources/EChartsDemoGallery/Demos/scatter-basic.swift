// scatter-basic — a single cartesian scatter series (value×value). Renders on BOTH panes: native
// (EChartsKit's minimal ScatterView draws a symbol path per datum) and real echarts.js.
extension EChartsDemoRegistry {
    static let demo_scatter_basic = EChartsDemo(
        name: "scatter-basic", category: "Scatter",
        summary: "single scatter series, 8 value×value points",
        width: 480, height: 320,
        option: [
            "grid": ["left": 40.0, "top": 20.0, "right": 20.0, "bottom": 30.0] as [String: Any],
            "xAxis": ["type": "value"] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [["type": "scatter", "symbolSize": 14.0,
                        "data": [[10.0, 8.04], [8.0, 6.95], [13.0, 7.58], [9.0, 8.81],
                                 [11.0, 8.33], [14.0, 9.96], [6.0, 7.24], [4.0, 4.26]]] as [String: Any]]
        ])
}
