// candlestick-basic — a single cartesian candlestick (K-line) series. Renders on BOTH panes: native
// (EChartsKit's CandlestickView draws a NormalBoxPath body+whiskers per datum, bull/bear colored) and
// echarts.js. Data per item = [open, close, lowest, highest].
extension EChartsDemoRegistry {
    static let demo_candlestick_basic = EChartsDemo(
        name: "candlestick-basic", category: "Candlestick",
        summary: "single K-line series, 6 sessions",
        width: 520, height: 340,
        option: [
            "grid": ["left": 50.0, "top": 20.0, "width": 440.0, "height": 260.0] as [String: Any],
            "xAxis": ["type": "category",
                      "data": ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]] as [String: Any],
            "yAxis": ["type": "value", "scale": true] as [String: Any],
            "series": [["type": "candlestick",
                        "data": [[20.0, 34.0, 18.0, 38.0],
                                 [34.0, 28.0, 25.0, 40.0],
                                 [28.0, 42.0, 26.0, 45.0],
                                 [42.0, 38.0, 35.0, 48.0],
                                 [38.0, 50.0, 36.0, 55.0],
                                 [50.0, 46.0, 44.0, 58.0]]] as [String: Any]]
        ])
}
