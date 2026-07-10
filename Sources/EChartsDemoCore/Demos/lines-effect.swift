// lines-effect — a lines series with the flying-trail `effect` on. Renders on BOTH panes: native
// (EChartsKit's LinesView draws the static Line/BezierCurve PLUS a moving `createSymbol` trail symbol
// animated along each line via a looping animator — chart/lines/EffectLine.swift) and real echarts.js.
// The headless native PNG advances every animator to a fixed frame, so the trail symbols appear
// partway along each line rather than frozen at the start.
extension EChartsDemoRegistry {
    static let demo_lines_effect = EChartsDemo(
        name: "lines-effect", category: "Lines",
        summary: "lines series with the flying-trail effect (moving symbol animated along each line)",
        width: 480, height: 320,
        option: [
            "grid": ["left": 40.0, "top": 20.0, "right": 20.0, "bottom": 30.0] as [String: Any],
            "xAxis": ["type": "value", "min": 0.0, "max": 20.0] as [String: Any],
            "yAxis": ["type": "value", "min": 0.0, "max": 20.0] as [String: Any],
            "series": [[
                "type": "lines",
                "coordinateSystem": "cartesian2d",
                // A distinct zlevel puts the lines + flying dots on their OWN painter layer, so the effect's
                //   motion-blur trail (configLayer(zlevel, {motionBlur})) fades on that layer only while the
                //   axes/grid (zlevel 0) stay crisp — the live host shows the fading trail behind each dot.
                "zlevel": 1.0,
                "lineStyle": ["width": 2.0, "opacity": 0.6, "color": "#409eff"] as [String: Any],
                "effect": [
                    "show": true,
                    "period": 4.0,
                    "trailLength": 0.6,
                    "symbol": "circle",
                    "symbolSize": 8.0,
                    "color": "#ff7043"
                ] as [String: Any],
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
