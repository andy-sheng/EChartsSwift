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
        summary: "SVG-backed geo map — registerMap({svg}) → parseSVG shapes (rect + circle + path) rendered by GeoView",
        width: 520, height: 320,
        option: {
            // Register the toy SVG map before the option is consumed (echarts.registerMap('toySVG', {svg})).
            EChartsSlim.registerMap("toySVG", ["svg": toySVG] as [String: Any])
            return [
                "geo": [
                    "map": "toySVG",
                    "top": 20.0, "left": 20.0, "right": 20.0, "bottom": 20.0
                ] as [String: Any]
            ]
        }())
}
