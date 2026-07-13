// official-geo-graph — replica of https://echarts.apache.org/examples/zh/editor.html?c=geo-graph
// title: Geo Graph / titleCN: 地理坐标系上的关系图
// A `graph` series laid out on a `geo` coordinate system: 11 waypoints (a…k) across Switzerland,
// chained a→b→…→k by arrow-headed edges, over the 26-canton `ch` map. `aspectScale` is
// cos(47°) — the rough latitude of Switzerland — so the geo projection is not visibly stretched.
//
// DEVIATIONS from the official source:
//   - The `$.get(ROOT_PATH + '/data/asset/geo/ch.geo.json', ...)` fetch is gone. The GeoJSON is read
//     from the repo asset assets/geo/ch.geo.json (via Upstream.repoRoot) and handed to BOTH panes
//     through `mapRegistrations` — WebPage.swift injects `echarts.registerMap('ch', ...)` into the
//     page before the option script, and the native pane calls ECharts.registerMap. So neither the
//     `fetchGeoJSON()` wrapper nor its `echarts.registerMap` call appears in webOptionJS; the
//     `createChart()` body is inlined at top level and `option` is assigned unconditionally.
//   - myChart.showLoading()/hideLoading()/setOption() and the trailing `export {}` are dropped
//     (the gallery owns init + setOption; a bare export is a SyntaxError in a classic script).
// Everything else — title, geo, tooltip, the graph data/edges/edgeSymbol/lineStyle — is verbatim.
import Foundation
import EChartsKit

// The Swiss cantons GeoJSON (26 features, properties: name / name_en). Parsed ONCE from the repo
// asset; a parse failure degrades to an empty FeatureCollection (the pane renders blank, not a crash).
private let geoGraphChGeoJSON: [String: Any] = {
    let url = Upstream.repoRoot.appendingPathComponent("assets/geo/ch.geo.json")
    guard let data = try? Data(contentsOf: url),
          let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
        return ["type": "FeatureCollection", "features": [] as [Any]]
    }
    return obj
}()

// `var chRoughLatitude = 47; aspectScale: Math.cos(chRoughLatitude * Math.PI / 180)`
private let geoGraphAspectScale: Double = cos(47.0 * Double.pi / 180.0)

// Waypoints: value is [longitude, latitude] in the geo coordinate system.
private let geoGraphNodes: [[String: Any]] = [
    ["name": "a", "value": [7.667821250000001, 46.791734269956265]],
    ["name": "b", "value": [7.404848750000001, 46.516308805996054]],
    ["name": "c", "value": [7.376673125000001, 46.24728858538375]],
    ["name": "d", "value": [8.015320625000001, 46.39460918238572]],
    ["name": "e", "value": [8.616400625, 46.7020608630855]],
    ["name": "f", "value": [8.869981250000002, 46.37539345234199]],
    ["name": "g", "value": [9.546196250000001, 46.58676648282309]],
    ["name": "h", "value": [9.311399375, 47.182454114178896]],
    ["name": "i", "value": [9.085994375000002, 47.55395822835779]],
    ["name": "j", "value": [8.653968125000002, 47.47709530818285]],
    ["name": "k", "value": [8.203158125000002, 47.44506909144329]]
]

// The single a→b→…→k chain.
private let geoGraphEdges: [[String: Any]] = [
    ["source": "a", "target": "b"],
    ["source": "b", "target": "c"],
    ["source": "c", "target": "d"],
    ["source": "d", "target": "e"],
    ["source": "e", "target": "f"],
    ["source": "f", "target": "g"],
    ["source": "g", "target": "h"],
    ["source": "h", "target": "i"],
    ["source": "i", "target": "j"],
    ["source": "j", "target": "k"]
]

extension EChartsDemoRegistry {
    static let official_geo_graph = EChartsDemo(
        name: "official-geo-graph", category: "map",
        summary: "地理坐标系上的关系图 — Geo Graph",
        width: 720, height: 460,
        nativeSupported: true,
        mapRegistrations: ["ch": geoGraphChGeoJSON],
        collection: .official,
        webOptionJS: #"""
var chRoughLatitude = 47;
option = {
  title: {
    text: 'Travel Routes',
  },
  geo: {
    map: 'ch',
    roam: true,
    aspectScale: Math.cos(chRoughLatitude * Math.PI / 180),
    // nameProperty: 'name_en', // If using en name.
    label: {
      show: true,
      textBorderColor: '#fff',
      textBorderWidth: 2,
    }
  },
  tooltip: {},
  series: [
    {
      type: 'graph',
      coordinateSystem: 'geo',
      data: [
        {name: 'a', value: [7.667821250000001, 46.791734269956265]},
        {name: 'b', value: [7.404848750000001, 46.516308805996054]},
        {name: 'c', value: [7.376673125000001, 46.24728858538375]},
        {name: 'd', value: [8.015320625000001, 46.39460918238572]},
        {name: 'e', value: [8.616400625, 46.7020608630855]},
        {name: 'f', value: [8.869981250000002, 46.37539345234199]},
        {name: 'g', value: [9.546196250000001, 46.58676648282309]},
        {name: 'h', value: [9.311399375, 47.182454114178896]},
        {name: 'i', value: [9.085994375000002, 47.55395822835779]},
        {name: 'j', value: [8.653968125000002, 47.47709530818285]},
        {name: 'k', value: [8.203158125000002, 47.44506909144329]},
      ],
      edges: [{
        source: 'a', target: 'b',
      }, {
        source: 'b', target: 'c',
      }, {
        source: 'c', target: 'd',
      }, {
        source: 'd', target: 'e',
      }, {
        source: 'e', target: 'f',
      }, {
        source: 'f', target: 'g',
      }, {
        source: 'g', target: 'h',
      }, {
        source: 'h', target: 'i',
      }, {
        source: 'i', target: 'j',
      }, {
        source: 'j', target: 'k',
      }],
      edgeSymbol: ['none', 'arrow'],
      edgeSymbolSize: 5,
      lineStyle: {
        color: '#718adbff',
        opacity: 1,
      }
    },
  ]
};
"""#,
        option: {
            // Upstream registers the map in the $.get callback: echarts.registerMap('ch', geoJSON).
            ECharts.registerMap("ch", geoGraphChGeoJSON)
            return [
                "title": [
                    "text": "Travel Routes"
                ] as [String: Any],
                "geo": [
                    "map": "ch",
                    "roam": true,
                    "aspectScale": geoGraphAspectScale,
                    // nameProperty: 'name_en' — commented out upstream too (would label in English).
                    "label": [
                        "show": true,
                        "textBorderColor": "#fff",
                        "textBorderWidth": 2.0
                    ] as [String: Any]
                ] as [String: Any],
                "tooltip": [:] as [String: Any],
                "series": [
                    [
                        "type": "graph",
                        "coordinateSystem": "geo",
                        "data": geoGraphNodes as [Any],
                        "edges": geoGraphEdges as [Any],
                        "edgeSymbol": ["none", "arrow"],
                        "edgeSymbolSize": 5.0,
                        "lineStyle": [
                            "color": "#718adbff",
                            "opacity": 1.0
                        ] as [String: Any]
                    ] as [String: Any]
                ]
            ]
        }())
}
