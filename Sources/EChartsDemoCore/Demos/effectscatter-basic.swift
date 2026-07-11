// effectscatter-basic — a single cartesian effectScatter series (value×value). Renders on BOTH panes:
// native (EChartsKit's EffectScatterView draws a symbol path per datum plus the animated expanding-ring
// ripple via EffectSymbol.startEffectAnimation) and real echarts.js.
extension EChartsDemoRegistry {
    static let demo_effectscatter_basic = EChartsDemo(
        name: "effectscatter-basic", category: "EffectScatter",
        summary: "single effectScatter series, 6 value×value points",
        width: 480, height: 320,
        option: [
            "grid": ["left": 40.0, "top": 20.0, "right": 20.0, "bottom": 30.0] as [String: Any],
            "xAxis": ["type": "value"] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [["type": "effectScatter", "symbolSize": 16.0,
                        "data": [[10.0, 8.04], [8.0, 6.95], [13.0, 7.58],
                                 [11.0, 8.33], [14.0, 9.96], [6.0, 7.24]]] as [String: Any]]
        ])
}
