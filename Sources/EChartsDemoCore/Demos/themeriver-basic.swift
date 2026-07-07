// themeriver-basic — a single themeRiver (streamgraph) series on the SINGLE coordinate system: three
// named layers (Alpha / Beta / Gamma) flowing across five time points. themeRiver is a non-cartesian
// chart: the `singleAxis` component draws the horizontal time-axis backdrop (axisLine + ticks +
// splitLine grid), and ThemeRiverView draws one filled Polygon band per named layer, stacked around a
// centered baseline, with band positions coming from the themeRiverLayout stage (each datum → a
// {layerIndex, x, y0, y} band point via Single.dataToPoint). Renders on BOTH panes: native (EChartsKit)
// and echarts.js.
extension EChartsDemoRegistry {
    static let demo_themeriver_basic = EChartsDemo(
        name: "themeriver-basic", category: "ThemeRiver",
        summary: "single themeRiver, 3 named layers (Alpha/Beta/Gamma) over 5 time points",
        width: 480, height: 360,
        option: [
            "singleAxis": [
                "type": "value",
                "left": "8%", "right": "8%", "top": "12%", "bottom": "12%"
            ] as [String: Any],
            "series": [[
                "type": "themeRiver",
                "data": [
                    [0.0, 10.0, "Alpha"], [1.0, 15.0, "Alpha"], [2.0, 12.0, "Alpha"],
                    [3.0, 18.0, "Alpha"], [4.0, 14.0, "Alpha"],
                    [0.0,  8.0, "Beta"],  [1.0,  6.0, "Beta"],  [2.0, 11.0, "Beta"],
                    [3.0,  9.0, "Beta"],  [4.0, 13.0, "Beta"],
                    [0.0,  5.0, "Gamma"], [1.0,  9.0, "Gamma"], [2.0,  7.0, "Gamma"],
                    [3.0,  4.0, "Gamma"], [4.0, 10.0, "Gamma"]
                ]
            ] as [String: Any]]
        ])
}
