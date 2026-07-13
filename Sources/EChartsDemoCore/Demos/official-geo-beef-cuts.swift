// official-geo-beef-cuts — replica of https://echarts.apache.org/examples/zh/editor.html?c=geo-beef-cuts
// title: GEO Beef Cuts / titleCN: 庖丁解牛
// A `series: "map"` over an SVG-backed geo map: the French butcher's diagram of beef cuts
// (Beef_cuts_France.svg), each named <path> region a cut, coloured by its "price" value through a
// continuous horizontal visualMap.
//
// DEVIATIONS from the official source:
//   - DATA FETCH: upstream wraps everything in `$.get(ROOT_PATH + '/data/asset/geo/Beef_cuts_France.svg',
//     function (svg) { ... })`. The gallery page has no network, so the SVG is read from the repo asset
//     assets/geo/Beef_cuts_France.svg (mirrored byte-for-byte from the official asset tree) via
//     Upstream.repoRoot, and `option` is assigned unconditionally at the top level of webOptionJS —
//     the fetch is gone, the callback BODY is verbatim.
//   - registerMap: upstream calls `echarts.registerMap('Beef_cuts_France', { svg: svg })` inside that
//     callback. Here it moves to `mapRegistrations`, so WebPage.swift injects the SAME registerMap into
//     the reference page before the option script, and the native pane registers it via ECharts.registerMap.
//   - `myChart.setOption(option)` / `export {}` dropped (the harness owns both panes; a bare export is a
//     SyntaxError in a classic script).
// Nothing else changed: no closures, no timers, no simplification. Both panes render.
import Foundation
import EChartsKit

// The butcher's-diagram SVG (~68 KB, ~29 named <path> regions). Read ONCE from the repo asset; a read
// failure degrades to an empty <svg> (the pane renders blank rather than crashing).
private let beefCutsSVG: String = {
    let url = Upstream.repoRoot.appendingPathComponent("assets/geo/Beef_cuts_France.svg")
    guard let svg = try? String(contentsOf: url, encoding: .utf8) else {
        return #"<svg width="1" height="1" viewBox="0 0 1 1"></svg>"#
    }
    return svg
}()

// One datum per named SVG region (the region `name` attribute is the join key); `value` is the cut's
// "price", encoded to colour by the visualMap. Verbatim from the upstream example, in source order.
private let beefCutsData: [[String: Any]] = [
    ["name": "Queue", "value": 15.0],
    ["name": "Langue", "value": 35.0],
    ["name": "Plat de joue", "value": 15.0],
    ["name": "Gros bout de poitrine", "value": 25.0],
    ["name": "Jumeau à pot-au-feu", "value": 45.0],
    ["name": "Onglet", "value": 85.0],
    ["name": "Plat de tranche", "value": 25.0],
    ["name": "Araignée", "value": 15.0],
    ["name": "Gîte à la noix", "value": 55.0],
    ["name": "Bavette d'aloyau", "value": 25.0],
    ["name": "Tende de tranche", "value": 65.0],
    ["name": "Rond de gîte", "value": 45.0],
    ["name": "Bavettede de flanchet", "value": 85.0],
    ["name": "Flanchet", "value": 35.0],
    ["name": "Hampe", "value": 75.0],
    ["name": "Plat de côtes", "value": 65.0],
    ["name": "Tendron Milieu de poitrine", "value": 65.0],
    ["name": "Macreuse à pot-au-feu", "value": 85.0],
    ["name": "Rumsteck", "value": 75.0],
    ["name": "Faux-filet", "value": 65.0],
    ["name": "Côtes Entrecôtes", "value": 55.0],
    ["name": "Basses côtes", "value": 45.0],
    ["name": "Collier", "value": 85.0],
    ["name": "Jumeau à biftek", "value": 15.0],
    ["name": "Paleron", "value": 65.0],
    ["name": "Macreuse à bifteck", "value": 45.0],
    ["name": "Gîte", "value": 85.0],
    ["name": "Aiguillette baronne", "value": 65.0],
    ["name": "Filet", "value": 95.0]
]

extension EChartsDemoRegistry {
    static let official_geo_beef_cuts = EChartsDemo(
        name: "official-geo-beef-cuts", category: "map",
        summary: "庖丁解牛 — GEO Beef Cuts",
        width: 720, height: 460,
        nativeSupported: true,
        mapRegistrations: ["Beef_cuts_France": ["svg": beefCutsSVG] as [String: Any]],
        collection: .official,
        webOptionJS: #"""
option = {
  tooltip: {},
  visualMap: {
    left: 'center',
    bottom: '10%',
    min: 5,
    max: 100,
    orient: 'horizontal',
    text: ['', 'Price'],
    realtime: true,
    calculable: true,
    inRange: {
      color: ['#dbac00', '#db6e00', '#cf0000']
    }
  },
  series: [
    {
      name: 'French Beef Cuts',
      type: 'map',
      map: 'Beef_cuts_France',
      roam: true,
      emphasis: {
        label: {
          show: false
        }
      },
      selectedMode: false,
      data: [
        { name: 'Queue', value: 15 },
        { name: 'Langue', value: 35 },
        { name: 'Plat de joue', value: 15 },
        { name: 'Gros bout de poitrine', value: 25 },
        { name: 'Jumeau à pot-au-feu', value: 45 },
        { name: 'Onglet', value: 85 },
        { name: 'Plat de tranche', value: 25 },
        { name: 'Araignée', value: 15 },
        { name: 'Gîte à la noix', value: 55 },
        { name: "Bavette d'aloyau", value: 25 },
        { name: 'Tende de tranche', value: 65 },
        { name: 'Rond de gîte', value: 45 },
        { name: 'Bavettede de flanchet', value: 85 },
        { name: 'Flanchet', value: 35 },
        { name: 'Hampe', value: 75 },
        { name: 'Plat de côtes', value: 65 },
        { name: 'Tendron Milieu de poitrine', value: 65 },
        { name: 'Macreuse à pot-au-feu', value: 85 },
        { name: 'Rumsteck', value: 75 },
        { name: 'Faux-filet', value: 65 },
        { name: 'Côtes Entrecôtes', value: 55 },
        { name: 'Basses côtes', value: 45 },
        { name: 'Collier', value: 85 },
        { name: 'Jumeau à biftek', value: 15 },
        { name: 'Paleron', value: 65 },
        { name: 'Macreuse à bifteck', value: 45 },
        { name: 'Gîte', value: 85 },
        { name: 'Aiguillette baronne', value: 65 },
        { name: 'Filet', value: 95 }
      ]
    }
  ]
};
"""#,
        option: {
            // Register the SVG map before the option is consumed — upstream
            // `echarts.registerMap('Beef_cuts_France', { svg: svg })`.
            ECharts.registerMap("Beef_cuts_France", ["svg": beefCutsSVG] as [String: Any])
            return [
                "tooltip": [:] as [String: Any],
                "visualMap": [
                    "left": "center",
                    "bottom": "10%",
                    "min": 5.0,
                    "max": 100.0,
                    "orient": "horizontal",
                    "text": ["", "Price"],
                    "realtime": true,
                    "calculable": true,
                    "inRange": [
                        "color": ["#dbac00", "#db6e00", "#cf0000"]
                    ] as [String: Any]
                ] as [String: Any],
                "series": [
                    [
                        "name": "French Beef Cuts",
                        "type": "map",
                        "map": "Beef_cuts_France",
                        "roam": true,
                        "emphasis": [
                            "label": ["show": false] as [String: Any]
                        ] as [String: Any],
                        "selectedMode": false,
                        "data": beefCutsData as [Any]
                    ] as [String: Any]
                ]
            ]
        }())
}
