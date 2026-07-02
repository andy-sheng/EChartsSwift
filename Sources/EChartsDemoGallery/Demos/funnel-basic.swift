// funnel-basic — a single funnel series (no coordinate system; box + funnel layout). Renders on BOTH
// panes: native (EChartsKit's FunnelView draws a Polygon trapezoid per datum) and echarts.js.
extension EChartsDemoRegistry {
    static let demo_funnel_basic = EChartsDemo(
        name: "funnel-basic", category: "Funnel",
        summary: "single funnel series, 5 stages",
        width: 460, height: 340,
        option: [
            "series": [["type": "funnel", "left": "10%", "top": 20.0, "width": "80%", "height": 300.0,
                        "data": [["value": 100.0, "name": "Show"],
                                 ["value": 80.0, "name": "Click"],
                                 ["value": 60.0, "name": "Visit"],
                                 ["value": 40.0, "name": "Inquiry"],
                                 ["value": 20.0, "name": "Order"]]] as [String: Any]]
        ])
}
