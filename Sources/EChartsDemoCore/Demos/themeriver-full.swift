// themeriver-full — the canonical ECharts "ThemeRiver" example ported verbatim: one themeRiver
// (streamgraph) series with SIX named layers (DQ / TY / SS / QG / SY / DD) flowing across 21 daily time
// points (2015/11/08 → 2015/11/28) on the SINGLE coordinate system. Carries the full official config
// surface: a top `legend` naming the six layers (driven by the themeRiver DATA-ITEM/layer names via the
// series' legendVisualProvider), an axis-trigger `tooltip` with a solid line axisPointer (the combined
// hover tooltip lists every layer's value at the hovered time), a `time` singleAxis with dashed
// splitLine grid + animated axisPointer label, and per-band emphasis (shadow blur on hover). singleAxis
// draws the horizontal time-axis backdrop; ThemeRiverView draws one filled Polygon band per layer,
// stacked around a centered baseline, positioned by the themeRiverLayout stage. Renders on BOTH panes:
// native (EChartsKit) and echarts.js — legend toggle re-layout AND the trigger:'axis' tooltip both work
// natively (the singleAxis tooltip needed the Single coord-sys model protocol-witness fix +
// modelHelper/indicesOfNearest Single branches + ThemeRiverSeries.formatTooltip).
extension EChartsDemoRegistry {
    static let demo_themeriver_full = EChartsDemo(
        name: "themeriver-full", category: "ThemeRiver",
        summary: "6-layer themeRiver (DQ/TY/SS/QG/SY/DD) over 21 days: tooltip + legend + time axis",
        width: 720, height: 420,
        option: [
            "tooltip": [
                "trigger": "axis",
                "axisPointer": [
                    "type": "line",
                    "lineStyle": [
                        "color": "rgba(0,0,0,0.2)",
                        "width": 1.0,
                        "type": "solid"
                    ] as [String: Any]
                ] as [String: Any]
            ] as [String: Any],
            "legend": [
                "data": ["DQ", "TY", "SS", "QG", "SY", "DD"],
                "top": 15.0
            ] as [String: Any],
            "singleAxis": [
                "top": 50.0,
                "bottom": 50.0,
                "axisTick": [:] as [String: Any],
                "axisLabel": [:] as [String: Any],
                "type": "time",
                "axisPointer": [
                    "animation": true,
                    "label": ["show": true] as [String: Any]
                ] as [String: Any],
                "splitLine": [
                    "show": true,
                    "lineStyle": ["type": "dashed", "opacity": 0.2] as [String: Any]
                ] as [String: Any]
            ] as [String: Any],
            "series": [[
                "type": "themeRiver",
                "emphasis": [
                    "itemStyle": [
                        "shadowBlur": 20.0,
                        "shadowColor": "rgba(0, 0, 0, 0.8)"
                    ] as [String: Any]
                ] as [String: Any],
                "data": [
                    ["2015/11/08", 10.0, "DQ"], ["2015/11/09", 15.0, "DQ"], ["2015/11/10", 35.0, "DQ"],
                    ["2015/11/11", 38.0, "DQ"], ["2015/11/12", 22.0, "DQ"], ["2015/11/13", 16.0, "DQ"],
                    ["2015/11/14", 7.0, "DQ"],  ["2015/11/15", 2.0, "DQ"],  ["2015/11/16", 17.0, "DQ"],
                    ["2015/11/17", 33.0, "DQ"], ["2015/11/18", 40.0, "DQ"], ["2015/11/19", 32.0, "DQ"],
                    ["2015/11/20", 26.0, "DQ"], ["2015/11/21", 35.0, "DQ"], ["2015/11/22", 40.0, "DQ"],
                    ["2015/11/23", 32.0, "DQ"], ["2015/11/24", 26.0, "DQ"], ["2015/11/25", 22.0, "DQ"],
                    ["2015/11/26", 16.0, "DQ"], ["2015/11/27", 22.0, "DQ"], ["2015/11/28", 10.0, "DQ"],
                    ["2015/11/08", 35.0, "TY"], ["2015/11/09", 36.0, "TY"], ["2015/11/10", 37.0, "TY"],
                    ["2015/11/11", 22.0, "TY"], ["2015/11/12", 24.0, "TY"], ["2015/11/13", 26.0, "TY"],
                    ["2015/11/14", 34.0, "TY"], ["2015/11/15", 21.0, "TY"], ["2015/11/16", 18.0, "TY"],
                    ["2015/11/17", 45.0, "TY"], ["2015/11/18", 32.0, "TY"], ["2015/11/19", 35.0, "TY"],
                    ["2015/11/20", 30.0, "TY"], ["2015/11/21", 28.0, "TY"], ["2015/11/22", 27.0, "TY"],
                    ["2015/11/23", 26.0, "TY"], ["2015/11/24", 15.0, "TY"], ["2015/11/25", 30.0, "TY"],
                    ["2015/11/26", 35.0, "TY"], ["2015/11/27", 42.0, "TY"], ["2015/11/28", 42.0, "TY"],
                    ["2015/11/08", 21.0, "SS"], ["2015/11/09", 25.0, "SS"], ["2015/11/10", 27.0, "SS"],
                    ["2015/11/11", 23.0, "SS"], ["2015/11/12", 24.0, "SS"], ["2015/11/13", 21.0, "SS"],
                    ["2015/11/14", 35.0, "SS"], ["2015/11/15", 39.0, "SS"], ["2015/11/16", 40.0, "SS"],
                    ["2015/11/17", 36.0, "SS"], ["2015/11/18", 33.0, "SS"], ["2015/11/19", 43.0, "SS"],
                    ["2015/11/20", 40.0, "SS"], ["2015/11/21", 34.0, "SS"], ["2015/11/22", 28.0, "SS"],
                    ["2015/11/23", 26.0, "SS"], ["2015/11/24", 37.0, "SS"], ["2015/11/25", 41.0, "SS"],
                    ["2015/11/26", 46.0, "SS"], ["2015/11/27", 47.0, "SS"], ["2015/11/28", 41.0, "SS"],
                    ["2015/11/08", 10.0, "QG"], ["2015/11/09", 15.0, "QG"], ["2015/11/10", 35.0, "QG"],
                    ["2015/11/11", 38.0, "QG"], ["2015/11/12", 22.0, "QG"], ["2015/11/13", 16.0, "QG"],
                    ["2015/11/14", 7.0, "QG"],  ["2015/11/15", 2.0, "QG"],  ["2015/11/16", 17.0, "QG"],
                    ["2015/11/17", 33.0, "QG"], ["2015/11/18", 40.0, "QG"], ["2015/11/19", 32.0, "QG"],
                    ["2015/11/20", 26.0, "QG"], ["2015/11/21", 35.0, "QG"], ["2015/11/22", 40.0, "QG"],
                    ["2015/11/23", 32.0, "QG"], ["2015/11/24", 26.0, "QG"], ["2015/11/25", 22.0, "QG"],
                    ["2015/11/26", 16.0, "QG"], ["2015/11/27", 22.0, "QG"], ["2015/11/28", 10.0, "QG"],
                    ["2015/11/08", 10.0, "SY"], ["2015/11/09", 15.0, "SY"], ["2015/11/10", 35.0, "SY"],
                    ["2015/11/11", 38.0, "SY"], ["2015/11/12", 22.0, "SY"], ["2015/11/13", 16.0, "SY"],
                    ["2015/11/14", 7.0, "SY"],  ["2015/11/15", 2.0, "SY"],  ["2015/11/16", 17.0, "SY"],
                    ["2015/11/17", 33.0, "SY"], ["2015/11/18", 40.0, "SY"], ["2015/11/19", 32.0, "SY"],
                    ["2015/11/20", 26.0, "SY"], ["2015/11/21", 35.0, "SY"], ["2015/11/22", 4.0, "SY"],
                    ["2015/11/23", 32.0, "SY"], ["2015/11/24", 26.0, "SY"], ["2015/11/25", 22.0, "SY"],
                    ["2015/11/26", 16.0, "SY"], ["2015/11/27", 22.0, "SY"], ["2015/11/28", 10.0, "SY"],
                    ["2015/11/08", 10.0, "DD"], ["2015/11/09", 15.0, "DD"], ["2015/11/10", 35.0, "DD"],
                    ["2015/11/11", 38.0, "DD"], ["2015/11/12", 22.0, "DD"], ["2015/11/13", 16.0, "DD"],
                    ["2015/11/14", 7.0, "DD"],  ["2015/11/15", 2.0, "DD"],  ["2015/11/16", 17.0, "DD"],
                    ["2015/11/17", 33.0, "DD"], ["2015/11/18", 4.0, "DD"],  ["2015/11/19", 32.0, "DD"],
                    ["2015/11/20", 26.0, "DD"], ["2015/11/21", 35.0, "DD"], ["2015/11/22", 40.0, "DD"],
                    ["2015/11/23", 32.0, "DD"], ["2015/11/24", 26.0, "DD"], ["2015/11/25", 22.0, "DD"],
                    ["2015/11/26", 16.0, "DD"], ["2015/11/27", 22.0, "DD"], ["2015/11/28", 10.0, "DD"]
                ]
            ] as [String: Any]]
        ])
}
