// map-svg-basic — an SVG-backed geo map. Instead of a GeoJSON, `registerMap` is given a hand-written
// SVG string (`{ svg: <string> }`); zrender's `parseSVG` (ported into ZRenderKit) turns the SVG DOM into
// zrender shapes, `GeoSVGResource` wraps them as a geo coordinate system, and GeoView renders the parsed
// shapes (a <rect>, a <circle> and a <path>), transformed from the SVG viewBox into the geo view rect.
//
// Each shape carries a `name` so it registers as a geo REGION (styleable via `geo.regions`); for a geoSVG
// map the default itemStyle has NO fill, so each shape keeps its authored SVG `fill` (only a light border
// is applied). The map MUST be registered before setOption (upstream `echarts.registerMap`).
import EChartsKit

private let toySVG = """
<svg width="200" height="120" viewBox="0 0 200 120">
  <rect name="alpha" x="10" y="10" width="60" height="90" fill="#4e79a7"/>
  <circle name="beta" cx="120" cy="55" r="40" fill="#e15759"/>
  <path name="gamma" d="M150 100 L190 100 L170 20 Z" fill="#59a14f"/>
</svg>
"""

extension EChartsDemoRegistry {
    static let demo_map_svg_basic = EChartsDemo(
        name: "map-svg-basic", category: "Geo",
        summary: "SVG-backed geo map — parseSVG shapes with region name LABELS, hover-emphasis + roam (pan/zoom)",
        width: 520, height: 320,
        mapRegistrations: ["toySVG": ["svg": toySVG] as [String: Any]],
        option: {
            // Register the toy SVG map before the option is consumed (echarts.registerMap('toySVG', {svg})).
            ECharts.registerMap("toySVG", ["svg": toySVG] as [String: Any])
            return [
                "geo": [
                    "map": "toySVG",
                    "roam": true,                                    // pan/zoom the SVG root group
                    "label": ["show": true] as [String: Any],        // draw each named region's name label
                    "emphasis": [                                    // hovering a region highlights it
                        "itemStyle": ["borderColor": "#111", "borderWidth": 2.0] as [String: Any]
                    ] as [String: Any],
                    "top": 20.0, "left": 20.0, "right": 20.0, "bottom": 20.0
                ] as [String: Any]
            ]
        }())

    // A series:"map" on the SAME SVG map, coloured BY VALUE through a continuous visualMap. Each datum
    //   (alpha/beta/gamma) binds to its named SVG region; MapView._buildSVG fills the region with the
    //   visualMap-encoded colour and marks it a hover dispatcher.
    static let demo_map_svg_series = EChartsDemo(
        name: "map-svg-series", category: "Geo",
        summary: "series:\"map\" on an SVG map — data values colour named regions via a continuous visualMap",
        width: 520, height: 340,
        mapRegistrations: ["toySVGSeries": ["svg": toySVG] as [String: Any]],
        option: {
            ECharts.registerMap("toySVGSeries", ["svg": toySVG] as [String: Any])
            return [
                "visualMap": [
                    "type": "continuous",
                    "min": 0.0, "max": 100.0, "calculable": true,
                    "inRange": ["color": ["#e0f3f8", "#91bfdb", "#d94e5d"]] as [String: Any]
                ] as [String: Any],
                "series": [
                    [
                        "type": "map",
                        "map": "toySVGSeries",
                        "roam": true,
                        "label": ["show": true] as [String: Any],
                        "top": 40.0, "left": 40.0, "right": 40.0, "bottom": 40.0,
                        "data": [
                            ["name": "alpha", "value": 20.0] as [String: Any],
                            ["name": "beta", "value": 60.0] as [String: Any],
                            ["name": "gamma", "value": 95.0] as [String: Any]
                        ] as [Any]
                    ] as [String: Any]
                ]
            ]
        }())
}
