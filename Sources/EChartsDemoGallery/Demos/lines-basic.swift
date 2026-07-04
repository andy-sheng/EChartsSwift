// lines-basic — a single cartesian lines series (from→to segments via the `coords` data format). Renders
// on BOTH panes: native (EChartsKit's static LinesView draws one Line/BezierCurve per two-point line — the
// curveness item bends one into a quadratic curve; the moving-dot effect is a documented PORT-TODO) and
// real echarts.js.
extension EChartsDemoRegistry {
    static let demo_lines_basic = EChartsDemo(
        name: "lines-basic", category: "Lines",
        summary: "single lines series, 4 from→to segments on cartesian (one curved)",
        width: 480, height: 320,
        option: [
            "grid": ["left": 40.0, "top": 20.0, "right": 20.0, "bottom": 30.0] as [String: Any],
            "xAxis": ["type": "value", "min": 0.0, "max": 20.0] as [String: Any],
            "yAxis": ["type": "value", "min": 0.0, "max": 20.0] as [String: Any],
            "series": [[
                "type": "lines",
                "coordinateSystem": "cartesian2d",
                "lineStyle": ["width": 2.0, "opacity": 1.0] as [String: Any],
                "data": [
                    ["coords": [[2.0, 2.0], [8.0, 12.0]]] as [String: Any],
                    ["coords": [[8.0, 12.0], [14.0, 6.0]]] as [String: Any],
                    ["coords": [[14.0, 6.0], [18.0, 16.0]]] as [String: Any],
                    // A curved segment (lineStyle.curveness bends it into a quadratic curve).
                    ["coords": [[2.0, 16.0], [18.0, 16.0]],
                     "lineStyle": ["curveness": 0.3] as [String: Any]] as [String: Any]
                ]
            ] as [String: Any]]
        ])
}
