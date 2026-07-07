// visualmap-basic — a cartesian scatter series colored BY VALUE through a continuous visualMap. The
// visualMap VISUAL stage runs after the series' own visual stage and overwrites each datum's palette color
// with the value->color gradient sample (low → #50a3ba, high → #d94e5d). Renders on BOTH panes: native
// (EChartsKit's ScatterView draws a symbol path per datum, each carrying the encoded fill) and real
// echarts.js. The control widget (gradient bar) is a secondary deliverable; the per-datum ENCODING is the
// point of this demo.
extension EChartsDemoRegistry {
    static let demo_visualmap_basic = EChartsDemo(
        name: "visualmap-basic", category: "VisualMap",
        summary: "scatter colored by value via a continuous visualMap gradient",
        width: 480, height: 320,
        option: [
            "grid": ["left": 40.0, "top": 20.0, "right": 20.0, "bottom": 30.0] as [String: Any],
            "xAxis": ["type": "value"] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "visualMap": [
                "type": "continuous",
                "min": 0.0,
                "max": 100.0,
                "calculable": true,
                "dimension": 1.0,
                "inRange": ["color": ["#50a3ba", "#eac736", "#d94e5d"]] as [String: Any]
            ] as [String: Any],
            "series": [["type": "scatter", "symbolSize": 16.0,
                        "data": [[10.0, 5.0], [20.0, 22.0], [30.0, 40.0], [40.0, 55.0],
                                 [50.0, 70.0], [60.0, 85.0], [70.0, 95.0], [80.0, 100.0]]] as [String: Any]]
        ])
}
