// gallery-decal — decal (repeating-texture) pattern demos: an explicit `itemStyle.decal` bar and an
// accessibility auto-decal bar (`aria.decal.show`). Exercises util/decal.swift + visual/decalVisual +
// the Path._decalEl paint path (the decal texture tiles over each series fill).
extension EChartsDemoRegistry {

    // A bar series with an explicit per-series `itemStyle.decal` (white dots over the palette fill).
    static let demo_bar_decal = EChartsDemo(
        name: "bar-decal", category: "Bar",
        summary: "bar with itemStyle.decal (repeating dot texture over the fill)",
        width: 460, height: 300,
        option: [
            "grid": ["left": 50.0, "top": 30.0, "width": 380.0, "height": 230.0] as [String: Any],
            "xAxis": ["type": "category", "data": ["A", "B", "C", "D", "E"]] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [[
                "type": "bar",
                "itemStyle": [
                    "decal": [
                        "symbol": "circle",
                        "color": "rgba(255, 255, 255, 0.9)",
                        "dashArrayX": [[8, 8], [0, 8, 8, 0]],
                        "dashArrayY": [6, 0],
                        "symbolSize": 0.8
                    ] as [String: Any]
                ] as [String: Any],
                "data": [22.0, 20, 15, 28, 18]
            ] as [String: Any]]
        ])

    // Accessibility auto-decal: `aria.decal.show:true` assigns successive palette decals per series.
    static let demo_bar_aria_decal = EChartsDemo(
        name: "bar-aria-decal", category: "Bar",
        summary: "aria.decal.show auto-textures each series (accessibility)",
        width: 460, height: 300,
        option: [
            "aria": ["decal": ["show": true] as [String: Any]] as [String: Any],
            "grid": ["left": 50.0, "top": 30.0, "width": 380.0, "height": 230.0] as [String: Any],
            "xAxis": ["type": "category", "data": ["A", "B", "C", "D", "E"]] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [
                ["type": "bar", "name": "Alpha", "data": [12.0, 20, 15, 28, 18]] as [String: Any],
                ["type": "bar", "name": "Beta", "data": [10.0, 14, 22, 16, 24]] as [String: Any]
            ]
        ])
}
