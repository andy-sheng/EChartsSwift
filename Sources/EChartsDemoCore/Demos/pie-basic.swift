// pie-basic — a single pie series (no cartesian coord; box layout + angle layout). Renders on BOTH
// panes: native (EChartsKit's minimal PieView draws a Sector per datum) and real echarts.js.
extension EChartsDemoRegistry {
    static let demo_pie_basic = EChartsDemo(
        name: "pie-basic", category: "Pie",
        summary: "single pie series, 5 slices",
        width: 400, height: 320,
        option: [
            "series": [["type": "pie", "radius": "65%",
                        "data": [["value": 1048.0, "name": "Search"],
                                 ["value": 735.0, "name": "Direct"],
                                 ["value": 580.0, "name": "Email"],
                                 ["value": 484.0, "name": "Union Ads"],
                                 ["value": 300.0, "name": "Video"]]] as [String: Any]]
        ])
}
