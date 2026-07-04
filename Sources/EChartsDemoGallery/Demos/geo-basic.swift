// geo-basic — the GEO coordinate system (the 7th, after cartesian/radar/polar/single/parallel/calendar),
// a projection coord that maps [lng, lat] → pixel via the `View` transform. This demo registers a SMALL
// toy GeoJSON (three side-by-side rectangular "regions") under the map name "toy" and renders the geo
// component BACKDROP: the `geo` component + GeoView draw each region's polygon outline (Polygon subpaths)
// and its name label (ZRText) at the projected centroid. Region geometry comes from the Geo coord
// ([lng,lat] → [x,y]).
//
// The toy map MUST be registered before setOption (upstream `echarts.registerMap('toy', geoJson)`), so the
// registration runs in the option initializer below (IIFE) via `EChartsSlim.registerMap`.
//
// NATIVE-only note: the native pane (EChartsKit/GeoView) renders this fully. The HTML pane feeds the same
// option to real echarts.js, which ALSO needs `echarts.registerMap('toy', ...)` injected into the page —
// the gallery's JS generator does not do that yet, so the HTML pane is a follow-up (nativeSupported: true).
import EChartsKit

private let toyGeoJSON: [String: Any] = [
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
    static let demo_geo_basic = EChartsDemo(
        name: "geo-basic", category: "Geo",
        summary: "geo coordinate-system backdrop — three toy GeoJSON regions with outlines + labels",
        width: 520, height: 300,
        option: {
            // Register the toy map before the option is consumed (echarts.registerMap('toy', geoJson)).
            EChartsSlim.registerMap("toy", toyGeoJSON)
            return [
                "geo": [
                    "map": "toy",
                    "top": 40.0, "left": 40.0, "right": 40.0, "bottom": 40.0,
                    "itemStyle": [
                        "borderColor": "#333",
                        "borderWidth": 1.0,
                        "areaColor": "#e0e6ef"
                    ] as [String: Any],
                    "label": ["show": true] as [String: Any]
                ] as [String: Any]
            ]
        }())
}
