// legend-selector — a legend with the "All"/"Inv" selector buttons (`legend.selector`). Clicking a
// button dispatches legendAllSelect / legendInverseSelect (wired in LegendView._createSelector), which
// selects-all / inverts the selection and shows/hides the matching series. Renders on BOTH panes
// (native EChartsKit + echarts.js).
extension EChartsDemoRegistry {
    static let demo_legend_selector = EChartsDemo(
        name: "legend-selector", category: "Component",
        summary: "legend with All/Inv selector buttons over two line series",
        width: 520, height: 340,
        option: [
            "legend": [
                "data": ["Alpha", "Beta"],
                "top": 10.0,
                "selector": [
                    ["type": "all"] as [String: Any],
                    ["type": "inverse"] as [String: Any]
                ] as [Any]
            ] as [String: Any],
            "grid": ["left": 50.0, "top": 60.0, "right": 30.0, "bottom": 30.0] as [String: Any],
            "xAxis": ["type": "category", "data": ["A", "B", "C", "D", "E"]] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [
                ["name": "Alpha", "type": "line", "data": [120.0, 200.0, 150.0, 80.0, 170.0]] as [String: Any],
                ["name": "Beta", "type": "line", "data": [60.0, 90.0, 130.0, 210.0, 100.0]] as [String: Any]
            ]
        ])
}
