// official-geo-choropleth-scatter — replica of
// https://echarts.apache.org/examples/zh/editor.html?c=geo-choropleth-scatter
// title: Geo Choropleth and Scatter / titleCN: 地理坐标系上的等值区划图和散点图
//
// One `geo` component (Iceland, roam on, aspectScale = cos(65°) to compensate for the latitude) shared by
// TWO series via `geoIndex: 0`: a `scatter` whose bubbles are sized by data dimension 2 (a 3rd value per
// point) through visualMap[0].inRange.symbolSize, and a `map` series (`map: ''` — verbatim upstream; it
// borrows the geo coord sys instead of creating its own) whose 4 regions are coloured by dimension 0
// through visualMap[1]. Two horizontal, calculable visualMaps sit side by side along the bottom.
//
// DEVIATIONS from the official source:
//   - The `$.get(ROOT_PATH + '/data/asset/geo/iceland.geo.json', ...)` fetch and the
//     showLoading()/hideLoading() pair around it are dropped. The GeoJSON is read from the repo asset
//     assets/geo/iceland.geo.json (via Upstream.repoRoot) and registered through `mapRegistrations`, so
//     BOTH panes get `echarts.registerMap('iceland', geoJSON)` — WebPage.swift injects it into the page
//     before the option script, and the native pane calls ECharts.registerMap. `option` is therefore
//     assigned unconditionally at the top level instead of inside the fetch callback (the callback body,
//     i.e. the whole of `createChart()` minus `myChart.setOption(option)`, is kept verbatim).
//   - No other change: the option has no closures and no timers, so both panes carry it as-is.
import Foundation
import EChartsKit

// The Iceland regions GeoJSON (9 features; `properties.name` is Icelandic, `name_en` English — the
// example keys its map data off the Icelandic names and leaves `nameProperty` at its default).
// Parsed ONCE from the repo asset; a parse failure degrades to an empty FeatureCollection (the pane
// then renders blank rather than crashing).
private let icelandGeoJSON: [String: Any] = {
    let url = Upstream.repoRoot.appendingPathComponent("assets/geo/iceland.geo.json")
    guard let data = try? Data(contentsOf: url),
          let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
        return ["type": "FeatureCollection", "features": [] as [Any]]
    }
    return obj
}()

// [lng, lat, value] — dimension 2 drives symbolSize through visualMap[0].
private let icelandScatterData: [[Double]] = [
    [-21.9348415, 64.1334671, 14523],
    [-19.028531, 63.710241, 45126],
    [-17.089925, 65.37887072, 12345],
    [-19.15936, 65.6218101, 56789],
    [-19.849175, 65.7287035, 67890],
    [-23.18326, 65.582939, 89012],
    [-14.9515, 64.475135, 34567],
    [-20.88389, 63.85321, 45678]
]

// The choropleth values — dimension 0 drives colour through visualMap[1]. Only 4 of the 9 regions
// carry a value (upstream leaves the rest unmapped, so they render in the default area colour).
private let icelandChoroplethData: [[String: Any]] = [
    ["name": "Austurland", "value": 423.0],
    ["name": "Suðurland", "value": 256.0],
    ["name": "Norðurland vestra", "value": 489.0],
    ["name": "Norðurland eystra", "value": 51.0]
]

// Upstream: `var icelandRoughLatitude = 65; ... aspectScale: Math.cos(icelandRoughLatitude * Math.PI / 180)`.
private let icelandRoughLatitude = 65.0

extension EChartsDemoRegistry {
    static let official_geo_choropleth_scatter = EChartsDemo(
        name: "official-geo-choropleth-scatter", category: "map",
        summary: "地理坐标系上的等值区划图和散点图 — Geo Choropleth and Scatter",
        width: 720, height: 460,
        nativeSupported: true,
        mapRegistrations: ["iceland": icelandGeoJSON],
        collection: .official,
        webOptionJS: #"""
var icelandRoughLatitude = 65;
option = {
  geo: {
    map: 'iceland',
    roam: true,
    aspectScale: Math.cos(icelandRoughLatitude * Math.PI / 180),
    // nameProperty: 'name_en', // If using en name.
    label: {
      show: true,
      color: '#555',
    }
  },
  tooltip: {},
  visualMap: [{
    orient: 'horizontal',
    calculable: true,
    right: 0,
    bottom: 0,
    seriesIndex: 0,
    // min/max is specified as series.data value extent.
    min: 0,
    max: 1e5,
    dimension: 2,
    inRange: {
      symbolSize: [5, 30]
    },
    controller: {
      inRange: {
        color: ['#66c2a5']
      }
    }
  }, {
    orient: 'horizontal',
    calculable: true,
    left: 0,
    bottom: 0,
    seriesIndex: 1,
    // min/max is specified as series.data value extent.
    min: 0,
    max: 1e3,
    dimension: 0,
    inRange: {
      color: ['#deebf7', '#3182bd']
    }
  }],
  series: [
    {
      type: 'scatter',
      coordinateSystem: 'geo',
      geoIndex: 0,
      encode: {
        // `2` is the dimension index of series.data
        tooltip: 2,
        label: 2,
      },
      data: [
        [-21.9348415, 64.1334671, 14523],
        [-19.028531, 63.710241, 45126],
        [-17.089925, 65.37887072, 12345],
        [-19.15936, 65.6218101, 56789],
        [-19.849175, 65.7287035, 67890],
        [-23.18326, 65.582939, 89012],
        [-14.9515, 64.475135, 34567],
        [-20.88389, 63.85321, 45678]
      ],
      itemStyle: {
        color: '#66c2a5',
        borderWidth: 1,
        borderColor: '#3c7865',
      }
    },
    {
      // Effectively this is a choropleth map.
      type: 'map',
      // Specify geoIndex to share the geo component with the scatter series above,
      // instead of creating an internal geo coord sys.
      geoIndex: 0,
      map: '',
      data: [
        { name: 'Austurland', value: 423 },
        { name: 'Suðurland', value: 256 },
        { name: 'Norðurland vestra', value: 489 },
        { name: 'Norðurland eystra', value: 51 }
      ]
    }
  ]
};
"""#,
        option: {
            // Register the Iceland map before the option is consumed — upstream
            // `echarts.registerMap('iceland', geoJSON)` inside the $.get callback.
            ECharts.registerMap("iceland", icelandGeoJSON)
            return [
                "geo": [
                    "map": "iceland",
                    "roam": true,
                    "aspectScale": cos(icelandRoughLatitude * Double.pi / 180.0),
                    // nameProperty: 'name_en' — commented out upstream too (would key off the English names).
                    "label": [
                        "show": true,
                        "color": "#555"
                    ] as [String: Any]
                ] as [String: Any],
                "tooltip": [:] as [String: Any],
                "visualMap": [
                    [
                        "orient": "horizontal",
                        "calculable": true,
                        "right": 0.0,
                        "bottom": 0.0,
                        "seriesIndex": 0.0,
                        // min/max is specified as series.data value extent.
                        "min": 0.0,
                        "max": 1e5,
                        "dimension": 2.0,
                        "inRange": [
                            "symbolSize": [5.0, 30.0]
                        ] as [String: Any],
                        "controller": [
                            "inRange": [
                                "color": ["#66c2a5"]
                            ] as [String: Any]
                        ] as [String: Any]
                    ] as [String: Any],
                    [
                        "orient": "horizontal",
                        "calculable": true,
                        "left": 0.0,
                        "bottom": 0.0,
                        "seriesIndex": 1.0,
                        // min/max is specified as series.data value extent.
                        "min": 0.0,
                        "max": 1e3,
                        "dimension": 0.0,
                        "inRange": [
                            "color": ["#deebf7", "#3182bd"]
                        ] as [String: Any]
                    ] as [String: Any]
                ],
                "series": [
                    [
                        "type": "scatter",
                        "coordinateSystem": "geo",
                        "geoIndex": 0.0,
                        "encode": [
                            // `2` is the dimension index of series.data
                            "tooltip": 2.0,
                            "label": 2.0
                        ] as [String: Any],
                        "data": icelandScatterData,
                        "itemStyle": [
                            "color": "#66c2a5",
                            "borderWidth": 1.0,
                            "borderColor": "#3c7865"
                        ] as [String: Any]
                    ] as [String: Any],
                    [
                        // Effectively this is a choropleth map.
                        "type": "map",
                        // Specify geoIndex to share the geo component with the scatter series above,
                        // instead of creating an internal geo coord sys.
                        "geoIndex": 0.0,
                        "map": "",
                        "data": icelandChoroplethData
                    ] as [String: Any]
                ]
            ]
        }())
}
