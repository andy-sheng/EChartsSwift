// polar-basic — a single POLAR coordinate system (angleAxis + radiusAxis) with a scatter series drawn
// on it. Polar is a non-cartesian coordinate system (Phase 13): the `angleAxis` component draws the
// angle ring (axisLine circle + split lines + tick labels around the ring) and the `radiusAxis`
// component draws the radial axis line + ticks + split lines, forming the backdrop. ScatterView is
// polar-aware — each datum is placed via the polar `dataToPoint([radius, angle])` (radius = dim 0,
// angle = dim 1, per polarDimensions). Renders on BOTH panes: native (EChartsKit) and echarts.js.
//
// Mirrors the official "Two Value-Axes in Polar Coordinates" example (both axes are value axes): the
// data is a spiral of [radius, angle] pairs, so the scatter symbols fan out around the pole.
extension EChartsDemoRegistry {
    static let demo_polar_basic = EChartsDemo(
        name: "polar-basic", category: "Polar",
        summary: "single polar (angle + radius axis) + scatter series (spiral)",
        width: 460, height: 360,
        option: [
            "polar": [
                "center": ["50%", "54%"],
                "radius": "70%"
            ] as [String: Any],
            "angleAxis": [
                "type": "value",
                "startAngle": 0.0
            ] as [String: Any],
            "radiusAxis": [
                "type": "value"
            ] as [String: Any],
            "series": [[
                "type": "scatter",
                "coordinateSystem": "polar",
                "symbolSize": 10.0,
                // Spiral of [radius, angle] pairs (radius = dim 0, angle = dim 1).
                "data": [
                    [1.0, 0.0], [2.0, 40.0], [3.0, 80.0], [4.0, 120.0],
                    [5.0, 160.0], [6.0, 200.0], [7.0, 240.0], [8.0, 280.0],
                    [9.0, 320.0], [10.0, 360.0]
                ]
            ] as [String: Any]]
        ])
}
