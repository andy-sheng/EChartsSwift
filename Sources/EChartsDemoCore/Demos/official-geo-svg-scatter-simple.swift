// official-geo-svg-scatter-simple — replica of https://echarts.apache.org/examples/zh/editor.html?c=geo-svg-scatter-simple
// title: GEO SVG Scatter / titleCN: 散点图（SVG）
// An SVG map of Iceland (registered as the geo coordinate system, roam on) with six `effectScatter`
// points plotted in the SVG's own pixel space (geoIndex 0), sized by each datum's 3rd value.
//
// DEVIATIONS from the official source:
//  - Data fetch: upstream wraps everything in `$.get(ROOT_PATH + '/data/asset/geo/Map_of_Iceland.svg',
//    function (svg) { ... })`. The SVG ships in the repo (assets/geo/Map_of_Iceland.svg) and is read at
//    demo time via Upstream.repoRoot — the same #filePath-relative read WebPage.swift uses for the
//    echarts dist. `option` is therefore assigned unconditionally at the top level.
//  - Map registration: upstream's `echarts.registerMap('iceland_svg', { svg: svg })` is NOT in
//    webOptionJS. It goes through `mapRegistrations`, which registers the SAME map on both panes
//    (WebPage.swift injects registerMap into the page before the option script; the native pane calls
//    ECharts.registerMap in the option IIFE).
//  - Dropped the trailing `myChart.getZr().on('click', ...)` handler (it console.logs
//    convertFromPixel of the clicked point): the gallery renders one static frame and dispatches no
//    events, and `myChart` does not exist in the option script's scope.
//  - NATIVE pane: `series.symbolSize` is a JS closure and is omitted (see PORT-NOTE). The six points
//    render at the default symbol size instead of scaling with their 3rd value; every other key is
//    ported. Also, upstream's bare `series: { ... }` object is written as a one-element array — echarts
//    normalizes an object to an array itself, so it is the same option.
import Foundation
import EChartsKit

// The Iceland SVG map (1834x1489 viewBox, 3061 <path> outlines). Read ONCE from the repo asset; a read
// failure degrades to an empty SVG (the pane renders blank rather than crashing).
private let icelandSVG: String = {
    let url = Upstream.repoRoot.appendingPathComponent("assets/geo/Map_of_Iceland.svg")
    guard let svg = try? String(contentsOf: url, encoding: .utf8) else {
        return #"<svg xmlns="http://www.w3.org/2000/svg" width="1834" height="1489" viewBox="0 0 1834 1489"></svg>"#
    }
    return svg
}()

// [x, y, value] in the SVG's own coordinate space; `value` drives symbolSize (web pane) and the tooltip.
private let icelandScatterData: [[Double]] = [
    [488.2358421078053, 459.70913833075736, 100],
    [770.3415644319939, 757.9672194986475, 30],
    [1180.0329284196291, 743.6141808346214, 80],
    [894.03790632245, 1188.1985153835008, 61],
    [1372.98925630313, 477.3839988649537, 70],
    [1378.62251255796, 935.6708486282843, 81]
]

extension EChartsDemoRegistry {
    static let official_geo_svg_scatter_simple = EChartsDemo(
        name: "official-geo-svg-scatter-simple", category: "map",
        summary: "散点图（SVG） — GEO SVG Scatter",
        width: 720, height: 460,
        nativeSupported: true,
        mapRegistrations: ["iceland_svg": ["svg": icelandSVG] as [String: Any]],
        collection: .official,
        webOptionJS: #"""
option = {
  tooltip: {},
  geo: {
    tooltip: {
      show: true
    },
    map: 'iceland_svg',
    roam: true
  },
  series: {
    type: 'effectScatter',
    coordinateSystem: 'geo',
    geoIndex: 0,
    symbolSize: function (params) {
      return (params[2] / 100) * 15 + 5;
    },
    itemStyle: {
      color: '#b02a02'
    },
    encode: {
      tooltip: 2
    },
    data: [
      [488.2358421078053, 459.70913833075736, 100],
      [770.3415644319939, 757.9672194986475, 30],
      [1180.0329284196291, 743.6141808346214, 80],
      [894.03790632245, 1188.1985153835008, 61],
      [1372.98925630313, 477.3839988649537, 70],
      [1378.62251255796, 935.6708486282843, 81]
    ]
  }
};
"""#,
        option: {
            // Upstream: `echarts.registerMap('iceland_svg', { svg: svg })` inside the $.get callback —
            // must run before the option naming the map is consumed.
            ECharts.registerMap("iceland_svg", ["svg": icelandSVG])
            return [
                "tooltip": [:] as [String: Any],
                "geo": [
                    "tooltip": [
                        "show": true
                    ] as [String: Any],
                    "map": "iceland_svg",
                    "roam": true
                ] as [String: Any],
                "series": [
                    [
                        "type": "effectScatter",
                        "coordinateSystem": "geo",
                        "geoIndex": 0.0,
                        // PORT-NOTE: symbolSize omitted — a JS closure `(params) => (params[2] / 100) * 15 + 5`,
                        // sizing each symbol from its datum's 3rd value (5–20px). Swift cannot express it, so
                        // the native points fall back to the default symbol size.
                        "itemStyle": [
                            "color": "#b02a02"
                        ] as [String: Any],
                        "encode": [
                            "tooltip": 2.0
                        ] as [String: Any],
                        "data": icelandScatterData
                    ] as [String: Any]
                ]
            ]
        }())
}
