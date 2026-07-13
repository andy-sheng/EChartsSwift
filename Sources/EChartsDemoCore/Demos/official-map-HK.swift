// official-map-HK — replica of https://echarts.apache.org/examples/zh/editor.html?c=map-HK
// title: Population Density of HongKong (2011) / titleCN: 香港18区人口密度 （2011）
// A `map` series over Hong Kong's 18 districts, coloured by 2011 population density through a
// continuous `visualMap` (lightskyblue→yellow→orangered), with district labels, an item tooltip and
// the dataView/restore/saveAsImage toolbox. `nameMap` maps the GeoJSON's English region names onto
// the Chinese names the data uses.
//
// DEVIATIONS from the official source:
//   - The upstream example wraps everything in `$.get(ROOT_PATH + '/data/asset/geo/HK.json', ...)`
//     plus `myChart.showLoading()/hideLoading()`. Both panes have no network: the GeoJSON lives at
//     assets/geo/HK.json (read via Upstream.repoRoot) and the loading calls are dropped. The option
//     body inside the callback is otherwise verbatim.
//   - `echarts.registerMap('HK', geoJson)` is NOT called inside webOptionJS; the map goes through
//     `mapRegistrations`, so WebPage.swift injects registerMap into the reference page and the
//     native pane registers the same map via ECharts.registerMap (see map-bar-morph.swift).
//   - Nothing else: no closures, no timers — the native `option` carries every key, including the
//     string tooltip formatter.
import Foundation
import EChartsKit

// Hong Kong's 18 districts (assets/geo/HK.json, mirrored from the official asset tree). Parsed ONCE;
// a parse failure degrades to an empty FeatureCollection (the pane renders blank rather than crashing).
private let hkGeoJSON: [String: Any] = {
    let url = Upstream.repoRoot.appendingPathComponent("assets/geo/HK.json")
    guard let data = try? Data(contentsOf: url),
          let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
        return ["type": "FeatureCollection", "features": [] as [Any]]
    }
    return obj
}()

// 2011 population density, people per km² (verbatim from the upstream example).
private let hkDensityData: [[String: Any]] = [
    ["name": "中西区", "value": 20057.34],
    ["name": "湾仔", "value": 15477.48],
    ["name": "东区", "value": 31686.1],
    ["name": "南区", "value": 6992.6],
    ["name": "油尖旺", "value": 44045.49],
    ["name": "深水埗", "value": 40689.64],
    ["name": "九龙城", "value": 37659.78],
    ["name": "黄大仙", "value": 45180.97],
    ["name": "观塘", "value": 55204.26],
    ["name": "葵青", "value": 21900.9],
    ["name": "荃湾", "value": 4918.26],
    ["name": "屯门", "value": 5881.84],
    ["name": "元朗", "value": 4178.01],
    ["name": "北区", "value": 2227.92],
    ["name": "大埔", "value": 2180.98],
    ["name": "沙田", "value": 9172.94],
    ["name": "西贡", "value": 3368.0],
    ["name": "离岛", "value": 806.98]
]

// GeoJSON region name (English) → the Chinese name hkDensityData keys on (upstream `nameMap`).
private let hkNameMap: [String: String] = [
    "Central and Western": "中西区",
    "Eastern": "东区",
    "Islands": "离岛",
    "Kowloon City": "九龙城",
    "Kwai Tsing": "葵青",
    "Kwun Tong": "观塘",
    "North": "北区",
    "Sai Kung": "西贡",
    "Sha Tin": "沙田",
    "Sham Shui Po": "深水埗",
    "Southern": "南区",
    "Tai Po": "大埔",
    "Tsuen Wan": "荃湾",
    "Tuen Mun": "屯门",
    "Wan Chai": "湾仔",
    "Wong Tai Sin": "黄大仙",
    "Yau Tsim Mong": "油尖旺",
    "Yuen Long": "元朗"
]

extension EChartsDemoRegistry {
    static let official_map_hk = EChartsDemo(
        name: "official-map-HK", category: "map",
        summary: "香港18区人口密度 （2011） — Population Density of HongKong (2011)",
        width: 720, height: 460,
        nativeSupported: true,
        mapRegistrations: ["HK": hkGeoJSON],
        collection: .official,
        webOptionJS: #"""
option = {
  title: {
    text: 'Population Density of Hong Kong （2011）',
    subtext: 'Data from Wikipedia',
    sublink:
      'http://zh.wikipedia.org/wiki/%E9%A6%99%E6%B8%AF%E8%A1%8C%E6%94%BF%E5%8D%80%E5%8A%83#cite_note-12'
  },
  tooltip: {
    trigger: 'item',
    formatter: '{b}<br/>{c} (p / km2)'
  },
  toolbox: {
    show: true,
    orient: 'vertical',
    left: 'right',
    top: 'center',
    feature: {
      dataView: { readOnly: false },
      restore: {},
      saveAsImage: {}
    }
  },
  visualMap: {
    min: 800,
    max: 50000,
    text: ['High', 'Low'],
    realtime: false,
    calculable: true,
    inRange: {
      color: ['lightskyblue', 'yellow', 'orangered']
    }
  },
  series: [
    {
      name: '香港18区人口密度',
      type: 'map',
      map: 'HK',
      label: {
        show: true
      },
      data: [
        { name: '中西区', value: 20057.34 },
        { name: '湾仔', value: 15477.48 },
        { name: '东区', value: 31686.1 },
        { name: '南区', value: 6992.6 },
        { name: '油尖旺', value: 44045.49 },
        { name: '深水埗', value: 40689.64 },
        { name: '九龙城', value: 37659.78 },
        { name: '黄大仙', value: 45180.97 },
        { name: '观塘', value: 55204.26 },
        { name: '葵青', value: 21900.9 },
        { name: '荃湾', value: 4918.26 },
        { name: '屯门', value: 5881.84 },
        { name: '元朗', value: 4178.01 },
        { name: '北区', value: 2227.92 },
        { name: '大埔', value: 2180.98 },
        { name: '沙田', value: 9172.94 },
        { name: '西贡', value: 3368 },
        { name: '离岛', value: 806.98 }
      ],
      // 自定义名称映射
      nameMap: {
        'Central and Western': '中西区',
        Eastern: '东区',
        Islands: '离岛',
        'Kowloon City': '九龙城',
        'Kwai Tsing': '葵青',
        'Kwun Tong': '观塘',
        North: '北区',
        'Sai Kung': '西贡',
        'Sha Tin': '沙田',
        'Sham Shui Po': '深水埗',
        Southern: '南区',
        'Tai Po': '大埔',
        'Tsuen Wan': '荃湾',
        'Tuen Mun': '屯门',
        'Wan Chai': '湾仔',
        'Wong Tai Sin': '黄大仙',
        'Yau Tsim Mong': '油尖旺',
        'Yuen Long': '元朗'
      }
    }
  ]
};
"""#,
        option: {
            // Upstream `echarts.registerMap('HK', geoJson)` — run before the option is consumed.
            ECharts.registerMap("HK", hkGeoJSON)
            return [
                "title": [
                    "text": "Population Density of Hong Kong （2011）",
                    "subtext": "Data from Wikipedia",
                    "sublink": "http://zh.wikipedia.org/wiki/%E9%A6%99%E6%B8%AF%E8%A1%8C%E6%94%BF%E5%8D%80%E5%8A%83#cite_note-12"
                ] as [String: Any],
                "tooltip": [
                    "trigger": "item",
                    "formatter": "{b}<br/>{c} (p / km2)"
                ] as [String: Any],
                "toolbox": [
                    "show": true,
                    "orient": "vertical",
                    "left": "right",
                    "top": "center",
                    "feature": [
                        "dataView": ["readOnly": false] as [String: Any],
                        "restore": [:] as [String: Any],
                        "saveAsImage": [:] as [String: Any]
                    ] as [String: Any]
                ] as [String: Any],
                "visualMap": [
                    "min": 800.0,
                    "max": 50000.0,
                    "text": ["High", "Low"],
                    "realtime": false,
                    "calculable": true,
                    "inRange": [
                        "color": ["lightskyblue", "yellow", "orangered"]
                    ] as [String: Any]
                ] as [String: Any],
                "series": [
                    [
                        "name": "香港18区人口密度",
                        "type": "map",
                        "map": "HK",
                        "label": [
                            "show": true
                        ] as [String: Any],
                        "data": hkDensityData as [Any],
                        // 自定义名称映射
                        "nameMap": hkNameMap
                    ] as [String: Any]
                ]
            ]
        }())
}
