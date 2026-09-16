// official-geo-svg-lines — replica of https://echarts.apache.org/examples/zh/editor.html?c=geo-svg-lines
// title: GEO SVG Lines / titleCN: GEO 路径图（SVG）
// A library floor plan registered as an SVG map (`registerMap(name, { svg })`), with a single 18-point
// `lines` polyline drawn on `coordinateSystem: 'geo'` in the SVG's own coordinate space — a dotted walking
// route through the stacks, with a walker-shaped `effect` symbol pacing along it.
//
// DEVIATIONS from the official source:
//   - The `$.get(ROOT_PATH + '/data/asset/geo/MacOdrum-LV5-floorplan-web.svg', ...)` fetch is dropped: the
//     SVG lives at assets/geo/MacOdrum-LV5-floorplan-web.svg and is read at demo time via Upstream.repoRoot
//     (the same #filePath-relative repo read WebPage.swift uses for the echarts dist). The callback body is
//     hoisted to the top level unchanged, `myChart.setOption(option)` and all.
//   - `echarts.registerMap('MacOdrum-LV5-floorplan-web', { svg: svg })` is NOT called inside webOptionJS;
//     it moves to `mapRegistrations` so BOTH panes register the same map (WebPage.swift injects registerMap
//     into the page ahead of the option script; the native pane registers it in the option IIFE).
//   - Native pane only: `geo.emphasis.itemStyle.color: undefined` is omitted (see note) — Swift has no
//     `undefined`, and the key is a no-op upstream.
// NOT a deviation: `series[0].effect` (the walker running the route) is a plain option key, carried verbatim
// by both panes and animated by each — no timeline is involved, so this demo needs no `drive`.
import Foundation
import EChartsKit

// The MacOdrum library LV5 floor plan, as an SVG string. Parsed by zrender's parseSVG (ported into
// ZRenderKit) and wrapped as a geo coordinate system by GeoSVGResource. A read failure degrades to an
// empty SVG (the pane renders blank rather than crashing).
private let macOdrumFloorplanSVG: String = {
    let url = Upstream.repoRoot.appendingPathComponent("assets/geo/MacOdrum-LV5-floorplan-web.svg")
    guard let svg = try? String(contentsOf: url, encoding: .utf8) else {
        return #"<svg xmlns="http://www.w3.org/2000/svg" width="1" height="1"></svg>"#
    }
    return svg
}()

// The `effect.symbol`: a walker-with-a-bag glyph, verbatim from the official example.
private let macOdrumWalkerSymbol = "path://M35.5 40.5c0-22.16 17.84-40 40-40s40 17.84 40 40c0 1.6939-.1042 3.3626-.3067 5H35.8067c-.2025-1.6374-.3067-3.3061-.3067-5zm90.9621-2.6663c-.62-1.4856-.9621-3.1182-.9621-4.8337 0-6.925 5.575-12.5 12.5-12.5s12.5 5.575 12.5 12.5a12.685 12.685 0 0 1-.1529 1.9691l.9537.5506-15.6454 27.0986-.1554-.0897V65.5h-28.7285c-7.318 9.1548-18.587 15-31.2715 15s-23.9535-5.8452-31.2715-15H15.5v-2.8059l-.0937.0437-8.8727-19.0274C2.912 41.5258.5 37.5549.5 33c0-6.925 5.575-12.5 12.5-12.5S25.5 26.075 25.5 33c0 .9035-.0949 1.784-.2753 2.6321L29.8262 45.5h92.2098z"

// The visit route: 18 points in the SVG's own coordinate space (coordinateSystem: 'geo' on an SVG map).
private let macOdrumRouteCoords: [[Double]] = [
    [110.6189462165178, 456.64349563895087],
    [124.10988522879458, 450.8570048730469],
    [123.9272226116071, 389.9520693708147],
    [61.58708083147317, 386.87942320312504],
    [61.58708083147317, 72.8954315876116],
    [258.29514854771196, 72.8954315876116],
    [260.75457021484374, 336.8559607533482],
    [280.5277985253906, 410.2406672084263],
    [275.948185765904, 528.0254369698661],
    [111.06907909458701, 552.795792593471],
    [118.87138231445309, 701.365737015904],
    [221.36468155133926, 758.7870354617745],
    [307.86195445452006, 742.164737297712],
    [366.8489324762834, 560.9895157073103],
    [492.8750778390066, 560.9895157073103],
    [492.8750778390066, 827.9639780566406],
    [294.9255269587053, 827.9639780566406],
    [282.79803391043527, 868.2476088113839]
]

extension EChartsDemoRegistry {
    static let official_geo_svg_lines = EChartsDemo(
        name: "official-geo-svg-lines", category: "map",
        summary: "GEO 路径图（SVG） — GEO SVG Lines",
        width: 720, height: 460,
        nativeSupported: true,
        mapRegistrations: ["MacOdrum-LV5-floorplan-web": ["svg": macOdrumFloorplanSVG] as [String: Any]],
        collection: .official,
        webOptionJS: #"""
option = {
  title: {
    text: 'Visit Route',
    left: 'center',
    bottom: 10
  },
  tooltip: {},
  geo: {
    map: 'MacOdrum-LV5-floorplan-web',
    roam: true,
    emphasis: {
      itemStyle: {
        color: undefined
      },
      label: {
        show: false
      }
    }
  },
  series: [
    {
      name: 'Route',
      type: 'lines',
      coordinateSystem: 'geo',
      geoIndex: 0,
      emphasis: {
        label: {
          show: false
        }
      },
      polyline: true,
      lineStyle: {
        color: '#c46e54',
        width: 5,
        opacity: 1,
        type: 'dotted'
      },
      effect: {
        show: true,
        period: 8,
        color: '#a10000',
        constantSpeed: 80,
        trailLength: 0,
        symbolSize: [20, 12],
        symbol:
          'path://M35.5 40.5c0-22.16 17.84-40 40-40s40 17.84 40 40c0 1.6939-.1042 3.3626-.3067 5H35.8067c-.2025-1.6374-.3067-3.3061-.3067-5zm90.9621-2.6663c-.62-1.4856-.9621-3.1182-.9621-4.8337 0-6.925 5.575-12.5 12.5-12.5s12.5 5.575 12.5 12.5a12.685 12.685 0 0 1-.1529 1.9691l.9537.5506-15.6454 27.0986-.1554-.0897V65.5h-28.7285c-7.318 9.1548-18.587 15-31.2715 15s-23.9535-5.8452-31.2715-15H15.5v-2.8059l-.0937.0437-8.8727-19.0274C2.912 41.5258.5 37.5549.5 33c0-6.925 5.575-12.5 12.5-12.5S25.5 26.075 25.5 33c0 .9035-.0949 1.784-.2753 2.6321L29.8262 45.5h92.2098z'
      },
      data: [
        {
          coords: [
            [110.6189462165178, 456.64349563895087],
            [124.10988522879458, 450.8570048730469],
            [123.9272226116071, 389.9520693708147],
            [61.58708083147317, 386.87942320312504],
            [61.58708083147317, 72.8954315876116],
            [258.29514854771196, 72.8954315876116],
            [260.75457021484374, 336.8559607533482],
            [280.5277985253906, 410.2406672084263],
            [275.948185765904, 528.0254369698661],
            [111.06907909458701, 552.795792593471],
            [118.87138231445309, 701.365737015904],
            [221.36468155133926, 758.7870354617745],
            [307.86195445452006, 742.164737297712],
            [366.8489324762834, 560.9895157073103],
            [492.8750778390066, 560.9895157073103],
            [492.8750778390066, 827.9639780566406],
            [294.9255269587053, 827.9639780566406],
            [282.79803391043527, 868.2476088113839]
          ]
        }
      ]
    }
  ]
};

myChart.setOption(option);
"""#,
        option: {
            // Register the floor-plan SVG map before the option is consumed
            // (upstream `echarts.registerMap('MacOdrum-LV5-floorplan-web', { svg: svg })`).
            ECharts.registerMap("MacOdrum-LV5-floorplan-web", ["svg": macOdrumFloorplanSVG] as [String: Any])
            return [
                "title": [
                    "text": "Visit Route",
                    "left": "center",
                    "bottom": 10.0
                ] as [String: Any],
                "tooltip": [:] as [String: Any],
                "geo": [
                    "map": "MacOdrum-LV5-floorplan-web",
                    "roam": true,
                    "emphasis": [
                        // emphasis.itemStyle omitted — upstream sets `color: undefined`, i.e. an
                        // explicit "no emphasis fill" that JS spells as undefined; Swift has no `undefined`
                        // ([:] / NSNull would both read as a real value), and the key is a no-op upstream.
                        "label": ["show": false] as [String: Any]
                    ] as [String: Any]
                ] as [String: Any],
                "series": [
                    [
                        "name": "Route",
                        "type": "lines",
                        "coordinateSystem": "geo",
                        "geoIndex": 0.0,
                        "emphasis": [
                            "label": ["show": false] as [String: Any]
                        ] as [String: Any],
                        "polyline": true,
                        "lineStyle": [
                            "color": "#c46e54",
                            "width": 5.0,
                            "opacity": 1.0,
                            "type": "dotted"
                        ] as [String: Any],
                        "effect": [
                            "show": true,
                            "period": 8.0,
                            "color": "#a10000",
                            "constantSpeed": 80.0,
                            "trailLength": 0.0,
                            "symbolSize": [20.0, 12.0],
                            "symbol": macOdrumWalkerSymbol
                        ] as [String: Any],
                        "data": [
                            ["coords": macOdrumRouteCoords] as [String: Any]
                        ] as [Any]
                    ] as [String: Any]
                ]
            ]
        }())
}
