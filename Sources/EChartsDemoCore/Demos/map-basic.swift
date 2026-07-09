// map-basic — the MAP chart on the GEO coordinate system (Phase 24). A `series.map` with `map:"toy"`
// draws a choropleth: one CompoundPath per GeoJSON region, FILLED by the region's datum value. The map
// series depends on the geo coord — geoCreator builds an exclusive Geo for the series' map-series group
// (`map:"toy"`) and injects it as the series' coordinateSystem; MapView then projects each region's
// polygon rings through that Geo and colors them.
//
// The per-region fill comes from a continuous visualMap (low → #e0f3f8, high → #d94e5d): the visualMap
// VISUAL stage runs after the series' own visual stage and writes each datum's encoded color, which
// MapView reads back (`getItemVisual(dataIdx,'style').fill`, gated on `visualMeta`). Regions with no datum
// fall back to the series `itemStyle.areaColor`.
//
// The toy map MUST be registered before setOption (upstream `echarts.registerMap('toy', geoJson)`), so the
// registration runs in the option initializer below (IIFE) via `ECharts.registerMap`.
//
// NATIVE-only note: the native pane (EChartsKit/MapView) renders this fully. The HTML pane feeds the same
// option to real echarts.js, which ALSO needs `echarts.registerMap('toy', ...)` injected into the page —
// the gallery's JS generator does not do that yet (same follow-up as geo-basic), so nativeSupported holds.
import EChartsKit

private let toyMapGeoJSON: [String: Any] = [
    "type": "FeatureCollection",
    "features": [
        // West region: lng 0..10, lat 0..10
        [
            "type": "Feature",
            "properties": ["name": "West"] as [String: Any],
            "geometry": [
                "type": "Polygon",
                "coordinates": [[[0.0, 0.0], [10.0, 0.0], [10.0, 10.0], [0.0, 10.0], [0.0, 0.0]]]
            ] as [String: Any]
        ] as [String: Any],
        // Central region: lng 10..20, lat 0..10
        [
            "type": "Feature",
            "properties": ["name": "Central"] as [String: Any],
            "geometry": [
                "type": "Polygon",
                "coordinates": [[[10.0, 0.0], [20.0, 0.0], [20.0, 10.0], [10.0, 10.0], [10.0, 0.0]]]
            ] as [String: Any]
        ] as [String: Any],
        // East region: lng 20..30, lat 0..10
        [
            "type": "Feature",
            "properties": ["name": "East"] as [String: Any],
            "geometry": [
                "type": "Polygon",
                "coordinates": [[[20.0, 0.0], [30.0, 0.0], [30.0, 10.0], [20.0, 10.0], [20.0, 0.0]]]
            ] as [String: Any]
        ] as [String: Any]
    ] as [Any]
]

extension EChartsDemoRegistry {
    static let demo_map_basic = EChartsDemo(
        name: "map-basic", category: "Map",
        summary: "choropleth map — three toy GeoJSON regions filled by value via a continuous visualMap",
        width: 520, height: 320,
        mapRegistrations: ["toy": toyMapGeoJSON],
        option: {
            // Register the toy map before the option is consumed (echarts.registerMap('toy', geoJson)).
            ECharts.registerMap("toy", toyMapGeoJSON)
            return [
                "visualMap": [
                    "type": "continuous",
                    "min": 0.0,
                    "max": 100.0,
                    "calculable": true,
                    "inRange": ["color": ["#e0f3f8", "#91bfdb", "#d94e5d"]] as [String: Any]
                ] as [String: Any],
                "series": [
                    [
                        "type": "map",
                        "map": "toy",
                        "top": 40.0, "left": 40.0, "right": 40.0, "bottom": 40.0,
                        "label": ["show": true] as [String: Any],
                        "data": [
                            ["name": "West", "value": 20.0] as [String: Any],
                            ["name": "Central", "value": 60.0] as [String: Any],
                            ["name": "East", "value": 95.0] as [String: Any]
                        ] as [Any]
                    ] as [String: Any]
                ]
            ]
        }())
}
