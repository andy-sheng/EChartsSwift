// line-stacked-area — the canonical ECharts "Stacked Area Chart" example ported verbatim: FIVE line
// series (Email / Union Ads / Video Ads / Direct / Search Engine) sharing one `stack: 'Total'` group so
// each series' area is drawn on top of the cumulative sum, with `areaStyle: {}` filling under every
// line. Carries the full official config surface: a `title`, an axis-trigger `tooltip` with a CROSS
// axisPointer, a `legend` naming the five series, a `toolbox` (saveAsImage), a category `xAxis` with
// boundaryGap:false (lines meet the y-axis), a value `yAxis`, per-series `emphasis.focus:'series'`
// (dim the others on hover) and a top `label` on the last (Search Engine) series. Renders on BOTH
// panes: native (EChartsKit) and echarts.js.
extension EChartsDemoRegistry {
    static let demo_line_stacked_area = EChartsDemo(
        name: "line-stacked-area", category: "Line",
        summary: "5-series stacked area (Email/Union Ads/Video Ads/Direct/Search Engine): title + legend + toolbox + cross tooltip",
        width: 720, height: 440,
        option: [
            "title": ["text": "Stacked Area Chart"] as [String: Any],
            "tooltip": [
                "trigger": "axis",
                "axisPointer": [
                    "type": "cross",
                    "label": ["backgroundColor": "#6a7985"] as [String: Any]
                ] as [String: Any]
            ] as [String: Any],
            "legend": [
                "data": ["Email", "Union Ads", "Video Ads", "Direct", "Search Engine"]
            ] as [String: Any],
            "toolbox": [
                "feature": [
                    "saveAsImage": [:] as [String: Any]
                ] as [String: Any]
            ] as [String: Any],
            "xAxis": [[
                "type": "category",
                "boundaryGap": false,
                "data": ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
            ] as [String: Any]],
            "yAxis": [[
                "type": "value"
            ] as [String: Any]],
            "series": [
                [
                    "name": "Email",
                    "type": "line",
                    "stack": "Total",
                    "areaStyle": [:] as [String: Any],
                    "emphasis": ["focus": "series"] as [String: Any],
                    "data": [120.0, 132.0, 101.0, 134.0, 90.0, 230.0, 210.0]
                ] as [String: Any],
                [
                    "name": "Union Ads",
                    "type": "line",
                    "stack": "Total",
                    "areaStyle": [:] as [String: Any],
                    "emphasis": ["focus": "series"] as [String: Any],
                    "data": [220.0, 182.0, 191.0, 234.0, 290.0, 330.0, 310.0]
                ] as [String: Any],
                [
                    "name": "Video Ads",
                    "type": "line",
                    "stack": "Total",
                    "areaStyle": [:] as [String: Any],
                    "emphasis": ["focus": "series"] as [String: Any],
                    "data": [150.0, 232.0, 201.0, 154.0, 190.0, 330.0, 410.0]
                ] as [String: Any],
                [
                    "name": "Direct",
                    "type": "line",
                    "stack": "Total",
                    "areaStyle": [:] as [String: Any],
                    "emphasis": ["focus": "series"] as [String: Any],
                    "data": [320.0, 332.0, 301.0, 334.0, 390.0, 330.0, 320.0]
                ] as [String: Any],
                [
                    "name": "Search Engine",
                    "type": "line",
                    "stack": "Total",
                    "label": ["show": true, "position": "top"] as [String: Any],
                    "areaStyle": [:] as [String: Any],
                    "emphasis": ["focus": "series"] as [String: Any],
                    "data": [820.0, 932.0, 901.0, 934.0, 1290.0, 1330.0, 1320.0]
                ] as [String: Any]
            ]
        ])
}
