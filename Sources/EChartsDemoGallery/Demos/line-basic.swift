// line-basic — a line series. HTML-only for now (nativeSupported:false): the native LineView is not
// yet ported (Phase 6c+). Included to show the gallery's HTML pane is fully general and that the
// structure grows — the native pane will light up when chart/line lands.
extension EChartsDemoRegistry {
    static let demo_line_basic = EChartsDemo(
        name: "line-basic", category: "Line",
        summary: "single line series (native pending — chart/line not yet ported)",
        width: 480, height: 320,
        nativeSupported: false,
        option: [
            "grid": ["left": 40.0, "top": 20.0, "right": 20.0, "bottom": 30.0] as [String: Any],
            "xAxis": ["type": "category",
                      "data": ["A", "B", "C", "D", "E", "F"]] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [["type": "line", "data": [820.0, 932.0, 901.0, 934.0, 1290.0, 1330.0]] as [String: Any]]
        ])
}
