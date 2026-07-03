// radar-basic — a single radar coordinate system (5 indicators) with two data series (Allocated vs
// Actual Budget). Radar is a non-cartesian coordinate system: the `radar` component draws the axis
// lines + split rings/areas backdrop, and RadarView draws one polyline outline + polygon area fill +
// vertex symbols per data item, positions coming from the radarLayout stage. Renders on BOTH panes:
// native (EChartsKit) and echarts.js.
extension EChartsDemoRegistry {
    static let demo_radar_basic = EChartsDemo(
        name: "radar-basic", category: "Radar",
        summary: "single radar (5 indicators) + 2 data series (polygon shape)",
        width: 460, height: 360,
        option: [
            "radar": [
                "center": ["50%", "55%"],
                "radius": "65%",
                "indicator": [
                    ["name": "Sales", "max": 6500.0],
                    ["name": "Administration", "max": 16000.0],
                    ["name": "Information Technology", "max": 30000.0],
                    ["name": "Customer Support", "max": 38000.0],
                    ["name": "Development", "max": 52000.0]
                ]
            ] as [String: Any],
            "series": [[
                "type": "radar",
                "data": [
                    [
                        "name": "Allocated Budget",
                        "value": [4200.0, 3000.0, 20000.0, 35000.0, 50000.0],
                        "areaStyle": ["opacity": 0.3] as [String: Any]
                    ] as [String: Any],
                    [
                        "name": "Actual Spending",
                        "value": [5000.0, 14000.0, 28000.0, 26000.0, 42000.0],
                        "areaStyle": ["opacity": 0.3] as [String: Any]
                    ] as [String: Any]
                ]
            ] as [String: Any]]
        ])
}
