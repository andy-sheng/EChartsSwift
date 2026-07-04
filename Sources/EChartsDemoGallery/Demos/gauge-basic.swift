// gauge-basic — a single gauge series (coordless; GaugeView computes all geometry in render). Renders on
// BOTH panes: native (EChartsKit's GaugeView draws the axis arc bands, split lines + ticks, tick labels,
// the pointer needle and the title/detail text) and echarts.js. Uses the default 225° -> -45° angle span.
extension EChartsDemoRegistry {
    static let demo_gauge_basic = EChartsDemo(
        name: "gauge-basic", category: "Gauge",
        summary: "single gauge, value 70, default 225°->-45° span",
        width: 460, height: 340,
        option: [
            "series": [["type": "gauge",
                        "data": [["value": 70.0, "name": "SCORE"]]] as [String: Any]]
        ])
}
