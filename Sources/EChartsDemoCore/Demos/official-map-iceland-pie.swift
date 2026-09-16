// official-map-iceland-pie — replica of https://echarts.apache.org/examples/zh/editor.html?c=map-iceland-pie
// title: Pie Charts on GEO Map / titleCN: 在地图上显示饼图
// Four pie series with `coordinateSystem: 'geo'` pinned onto an Iceland choropleth outline; each pie's
// `center` is a [lng, lat] pair (the 4th uses the region NAME 'Vestfirðir', supported since echarts 5.4.1).
//
// DEVIATIONS from the official source:
//   - DATA IS DETERMINISTIC. Upstream `randomPieSeries` fills each pie with
//     `Math.round(Math.random() * 100)`, so every reload draws different slices. The gallery diffs the
//     native pane against the echarts.js pane, which requires BOTH to carry the same numbers, so the
//     four pies use a fixed 4x4 value table (`icelandPieValues`). Everything else in `randomPieSeries`
//     — the 'Category A'..'Category D' names, tooltip/label/labelLine/animationDuration — is verbatim.
//   - The GeoJSON (assets/geo/iceland.geo.json, mirrored from the official asset tree) is read at demo
//     time via Upstream.repoRoot instead of `$.get(ROOT_PATH + '/data/asset/geo/iceland.geo.json')`, and
//     is registered through `mapRegistrations` (WebPage.swift injects `echarts.registerMap` into the page
//     before the option script; the native pane registers the same map) — so webOptionJS carries only the
//     `$.get` CALLBACK BODY, minus its `echarts.registerMap` call.
//   - `myChart.showLoading()/hideLoading()/setOption` and `export {}` dropped (harness-only).
//
// nativeSupported: true — geo + pie are both registered in EChartsKit. NOTE the gap this demo exists to
// surface: pie's geo-anchored `center` needs the `point` branch of `layout.createBoxLayoutReference`
// (`enableLayoutOnlyByCenter` + `boxCoordSys.dataToPoint`), which is still TODO: — the
// port always returns the `rect` kind — so the native pane currently lays the pies out in box space
// (treating the lng/lat as pixel offsets) rather than at their map coordinates.
import Foundation
import EChartsKit

// Iceland outline GeoJSON. Parsed ONCE from the repo asset; a parse failure degrades to an empty
// FeatureCollection (the pane renders blank rather than crashing).
private let icelandGeoJSON: [String: Any] = {
    let url = Upstream.repoRoot.appendingPathComponent("assets/geo/iceland.geo.json")
    guard let data = try? Data(contentsOf: url),
          let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
        return ["type": "FeatureCollection", "features": [] as [Any]]
    }
    return obj
}()

// Replaces upstream's Math.random() — see DEVIATIONS. One row per pie, one value per 'Category A'..'D'.
private let icelandPieValues: [[Double]] = [
    [42, 25, 18, 15],
    [30, 22, 28, 20],
    [12, 44, 26, 18],
    [24, 16, 35, 25]
]

private let icelandPieNames = ["Category A", "Category B", "Category C", "Category D"]

// upstream `randomPieSeries(center, radius)`, with the value row passed in instead of randomised.
private func icelandPieSeries(_ center: Any, _ radius: Double, _ values: [Double]) -> [String: Any] {
    let data: [[String: Any]] = zip(icelandPieNames, values).map { (name: String, value: Double) -> [String: Any] in
        ["value": value, "name": name]
    }
    return [
        "type": "pie",
        "coordinateSystem": "geo",
        "tooltip": ["formatter": "{b}: {c} ({d}%)"] as [String: Any],
        "label": ["show": false] as [String: Any],
        "labelLine": ["show": false] as [String: Any],
        "animationDuration": 0.0,
        "radius": radius,
        "center": center,
        "data": data as [Any]
    ]
}

extension EChartsDemoRegistry {
    static let official_map_iceland_pie = EChartsDemo(
        name: "official-map-iceland-pie", category: "map",
        summary: "在地图上显示饼图 — Pie Charts on GEO Map",
        width: 720, height: 460,
        nativeSupported: true,
        mapRegistrations: ["iceland": icelandGeoJSON],
        collection: .official,
        webOptionJS: #"""
// DEVIATION: upstream fills each pie with Math.round(Math.random() * 100); the gallery diffs this pane
// against the native one, so the four pies carry a fixed value table instead.
var pieValues = [
  [42, 25, 18, 15],
  [30, 22, 28, 20],
  [12, 44, 26, 18],
  [24, 16, 35, 25]
];
var pieIndex = 0;

function randomPieSeries(center, radius) {
  const values = pieValues[pieIndex++];
  const data = ['A', 'B', 'C', 'D'].map((t, i) => {
    return {
      value: values[i],
      name: 'Category ' + t
    };
  });
  return {
    type: 'pie',
    coordinateSystem: 'geo',
    tooltip: {
      formatter: '{b}: {c} ({d}%)'
    },
    label: {
      show: false
    },
    labelLine: {
      show: false
    },
    animationDuration: 0,
    radius,
    center,
    data
  };
}

option = {
  geo: {
    map: 'iceland',
    roam: true,
    aspectScale: Math.cos(65 * Math.PI / 180),
    // nameProperty: 'name_en', // If using en name.
    itemStyle: {
      areaColor: '#e7e8ea'
    },
    emphasis: {
      label: {show: false}
    }
  },
  tooltip: {},
  legend: {},
  series: [
    randomPieSeries([-19.007740346534653, 64.1780281585128], 45),
    randomPieSeries([-17.204666089108912, 65.44804833928391], 25),
    randomPieSeries([-15.264995297029705, 64.8592208009264], 30),
    randomPieSeries(
      // it's also supported to use geo region name as center since v5.4.1
      +echarts.version.split('.').slice(0, 3).join('') > 540
        ? 'Vestfirðir'
        : // or you can only use the LngLat array
          [-13, 66],
      30
    )
  ]
};
"""#,
        option: {
            // Upstream registers the map inside the $.get callback: echarts.registerMap('iceland', geoJSON).
            ECharts.registerMap("iceland", icelandGeoJSON)
            return [
                "geo": [
                    "map": "iceland",
                    "roam": true,
                    "aspectScale": cos(65.0 * Double.pi / 180.0),
                    // nameProperty: 'name_en', // If using en name.
                    "itemStyle": ["areaColor": "#e7e8ea"] as [String: Any],
                    "emphasis": ["label": ["show": false] as [String: Any]] as [String: Any]
                ] as [String: Any],
                "tooltip": [:] as [String: Any],
                "legend": [:] as [String: Any],
                "series": [
                    icelandPieSeries([-19.007740346534653, 64.1780281585128] as [Double], 45, icelandPieValues[0]),
                    icelandPieSeries([-17.204666089108912, 65.44804833928391] as [Double], 25, icelandPieValues[1]),
                    icelandPieSeries([-15.264995297029705, 64.8592208009264] as [Double], 30, icelandPieValues[2]),
                    // echarts 6.1.0 > 5.4.1, so the version branch upstream takes is the region NAME.
                    icelandPieSeries("Vestfirðir", 30, icelandPieValues[3])
                ]
            ]
        }())
}
