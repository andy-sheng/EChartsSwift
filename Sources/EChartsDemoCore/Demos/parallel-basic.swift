// parallel-basic — a single parallel-coordinates series across FOUR value axes (Price / Amount /
// Volume / Score) with THREE data lines. Parallel is the fifth coordinate system: each `parallelAxis`
// component draws one vertical axis backdrop (axisLine + ticks + labels, via AxisBuilder), laid out
// left-to-right by the Parallel coord, and the chart-side ParallelView draws one Polyline per data
// item connecting its value on each axis (points from Parallel.dataToPoint per dimension). Renders on
// BOTH panes: native (EChartsKit) and echarts.js.
extension EChartsDemoRegistry {
    static let demo_parallel_basic = EChartsDemo(
        name: "parallel-basic", category: "Parallel",
        summary: "single parallel series, 4 value axes (Price/Amount/Volume/Score) × 3 lines",
        width: 480, height: 360,
        option: [
            "parallelAxis": [
                ["dim": 0, "name": "Price"]  as [String: Any],
                ["dim": 1, "name": "Amount"] as [String: Any],
                ["dim": 2, "name": "Volume"] as [String: Any],
                ["dim": 3, "name": "Score"]  as [String: Any]
            ],
            "parallel": [
                "left": "8%", "right": "12%", "top": "12%", "bottom": "12%"
            ] as [String: Any],
            "series": [[
                "type": "parallel",
                "lineStyle": ["width": 2] as [String: Any],
                "data": [
                    [12.0, 230.0,  8.0, 90.0],
                    [24.0, 140.0, 15.0, 60.0],
                    [ 6.0, 320.0,  3.0, 75.0]
                ]
            ] as [String: Any]]
        ])
}
