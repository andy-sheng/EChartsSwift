// official-map-usa — replica of https://echarts.apache.org/examples/zh/editor.html?c=map-usa
// title: USA Population Estimates (2012) / titleCN: 2012 年美国人口统计
//
// A choropleth of the 50 states + DC + Puerto Rico, coloured by 2012 census population through a
// continuous `visualMap`. Renders on BOTH panes: native (EChartsKit) + echarts.js.
//
// DEVIATIONS from the official source:
//   - The upstream example fetches the map with `$.get(ROOT_PATH + '/data/asset/geo/USA.json', ...)`.
//     The gallery page has no network, so the GeoJSON is loaded from the repo asset assets/geo/USA.json
//     at demo time via Upstream.repoRoot (the same #filePath-relative read WebPage.swift uses for the
//     echarts dist — it resolves on macOS and the iOS simulator alike). The fetch wrapper is dropped and
//     the callback body kept, so `option` is assigned unconditionally at the top level.
//   - `echarts.registerMap('USA', usaJson, { Alaska: {...}, Hawaii: {...}, 'Puerto Rico': {...} })` is
//     NOT called inside webOptionJS. It moves to `mapRegistrations`, which registers the SAME map (and
//     the SAME specialAreas repositioning Alaska / Hawaii / Puerto Rico under the lower-left of the
//     continental US) on both panes — WebPage.swift injects registerMap before the option script.
//   - `myChart.showLoading()` / `hideLoading()` / `setOption(option)` dropped (gallery harness owns those).
//   - toolbox `feature.dataView` is kept verbatim, but EChartsKit does not register the dataView feature
//     (it is the HTML-overlay table editor — host-dependent, deferred upstream-side). ToolboxView skips
//     an unregistered feature the way upstream does (`if (!Feature) return`), so the native pane simply
//     shows one icon fewer than the web pane. Everything else is identical.
//
// No option key is a JS closure, so the native option is a complete port — nothing omitted.
import Foundation
import EChartsKit

// The USA states GeoJSON (50 states + DC + Puerto Rico). Parsed ONCE from the repo asset; a parse
// failure degrades to an empty FeatureCollection (the pane renders blank rather than crashing).
//
// NOTE on the `mapUSA*` prefix: top-level `private` is FILE-scoped, so these could legally share the
// names Demos/map-bar-morph.swift uses for its own copies of the same three values — but every demo
// file compiles into the one EChartsDemoCore module, so the names are kept distinct to stay robust
// if either declaration ever loses its `private`.
private let mapUSAGeoJSON: [String: Any] = {
    let url = Upstream.repoRoot.appendingPathComponent("assets/geo/USA.json")
    guard let data = try? Data(contentsOf: url),
          let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
        return ["type": "FeatureCollection", "features": [] as [Any]]
    }
    return obj
}()

// specialAreas — reposition + resize the three non-contiguous regions (upstream registerMap 3rd arg).
// NATIVE form: a typed GeoSpecialAreas ([regionName: GeoSpecialArea]) passed to ECharts.registerMap.
private let mapUSASpecialAreas: GeoSpecialAreas = [
    "Alaska": GeoSpecialArea(left: -131, top: 25, width: 15),   // moved under the mainland's lower-left
    "Hawaii": GeoSpecialArea(left: -110, top: 28, width: 5),
    "Puerto Rico": GeoSpecialArea(left: -76, top: 26, width: 2)
]

// HTML form: the SAME areas as a JSON-serialisable dict, fed to real echarts via the
// `{ geoJSON, specialAreas }` registerMap object form (WebPage.swift serialises each value).
private let mapUSASpecialAreasJSON: [String: Any] = [
    "Alaska": ["left": -131.0, "top": 25.0, "width": 15.0] as [String: Any],
    "Hawaii": ["left": -110.0, "top": 28.0, "width": 5.0] as [String: Any],
    "Puerto Rico": ["left": -76.0, "top": 26.0, "width": 2.0] as [String: Any]
]

// 2012 US Census population estimates (verbatim from the upstream example, incl. Puerto Rico).
// Hoisted into an explicitly-typed `private let`: 52 heterogeneous dict literals inline in the option
// would blow the Swift type-checker's budget.
private let mapUSAPopulationData: [[String: Any]] = [
    ["name": "Alabama", "value": 4822023.0], ["name": "Alaska", "value": 731449.0],
    ["name": "Arizona", "value": 6553255.0], ["name": "Arkansas", "value": 2949131.0],
    ["name": "California", "value": 38041430.0], ["name": "Colorado", "value": 5187582.0],
    ["name": "Connecticut", "value": 3590347.0], ["name": "Delaware", "value": 917092.0],
    ["name": "District of Columbia", "value": 632323.0], ["name": "Florida", "value": 19317568.0],
    ["name": "Georgia", "value": 9919945.0], ["name": "Hawaii", "value": 1392313.0],
    ["name": "Idaho", "value": 1595728.0], ["name": "Illinois", "value": 12875255.0],
    ["name": "Indiana", "value": 6537334.0], ["name": "Iowa", "value": 3074186.0],
    ["name": "Kansas", "value": 2885905.0], ["name": "Kentucky", "value": 4380415.0],
    ["name": "Louisiana", "value": 4601893.0], ["name": "Maine", "value": 1329192.0],
    ["name": "Maryland", "value": 5884563.0], ["name": "Massachusetts", "value": 6646144.0],
    ["name": "Michigan", "value": 9883360.0], ["name": "Minnesota", "value": 5379139.0],
    ["name": "Mississippi", "value": 2984926.0], ["name": "Missouri", "value": 6021988.0],
    ["name": "Montana", "value": 1005141.0], ["name": "Nebraska", "value": 1855525.0],
    ["name": "Nevada", "value": 2758931.0], ["name": "New Hampshire", "value": 1320718.0],
    ["name": "New Jersey", "value": 8864590.0], ["name": "New Mexico", "value": 2085538.0],
    ["name": "New York", "value": 19570261.0], ["name": "North Carolina", "value": 9752073.0],
    ["name": "North Dakota", "value": 699628.0], ["name": "Ohio", "value": 11544225.0],
    ["name": "Oklahoma", "value": 3814820.0], ["name": "Oregon", "value": 3899353.0],
    ["name": "Pennsylvania", "value": 12763536.0], ["name": "Rhode Island", "value": 1050292.0],
    ["name": "South Carolina", "value": 4723723.0], ["name": "South Dakota", "value": 833354.0],
    ["name": "Tennessee", "value": 6456243.0], ["name": "Texas", "value": 26059203.0],
    ["name": "Utah", "value": 2855287.0], ["name": "Vermont", "value": 626011.0],
    ["name": "Virginia", "value": 8185867.0], ["name": "Washington", "value": 6897012.0],
    ["name": "West Virginia", "value": 1855413.0], ["name": "Wisconsin", "value": 5726398.0],
    ["name": "Wyoming", "value": 576412.0], ["name": "Puerto Rico", "value": 3667084.0]
]

extension EChartsDemoRegistry {
    static let official_map_usa = EChartsDemo(
        name: "official-map-usa", category: "map",
        summary: "2012 年美国人口统计 — USA Population Estimates (2012)",
        width: 720, height: 460,
        nativeSupported: true,
        mapRegistrations: ["USA": ["geoJSON": mapUSAGeoJSON, "specialAreas": mapUSASpecialAreasJSON] as [String: Any]],
        collection: .official,
        webOptionJS: #"""
option = {
  title: {
    text: 'USA Population Estimates (2012)',
    subtext: 'Data from www.census.gov',
    sublink: 'http://www.census.gov/popest/data/datasets.html',
    left: 'right'
  },
  tooltip: {
    trigger: 'item',
    showDelay: 0,
    transitionDuration: 0.2
  },
  visualMap: {
    left: 'right',
    min: 500000,
    max: 38000000,
    inRange: {
      color: [
        '#313695',
        '#4575b4',
        '#74add1',
        '#abd9e9',
        '#e0f3f8',
        '#ffffbf',
        '#fee090',
        '#fdae61',
        '#f46d43',
        '#d73027',
        '#a50026'
      ]
    },
    text: ['High', 'Low'],
    calculable: true
  },
  toolbox: {
    show: true,
    //orient: 'vertical',
    left: 'left',
    top: 'top',
    feature: {
      dataView: { readOnly: false },
      restore: {},
      saveAsImage: {}
    }
  },
  series: [
    {
      name: 'USA PopEstimates',
      type: 'map',
      roam: true,
      map: 'USA',
      emphasis: {
        label: {
          show: true
        }
      },
      data: [
        { name: 'Alabama', value: 4822023 },
        { name: 'Alaska', value: 731449 },
        { name: 'Arizona', value: 6553255 },
        { name: 'Arkansas', value: 2949131 },
        { name: 'California', value: 38041430 },
        { name: 'Colorado', value: 5187582 },
        { name: 'Connecticut', value: 3590347 },
        { name: 'Delaware', value: 917092 },
        { name: 'District of Columbia', value: 632323 },
        { name: 'Florida', value: 19317568 },
        { name: 'Georgia', value: 9919945 },
        { name: 'Hawaii', value: 1392313 },
        { name: 'Idaho', value: 1595728 },
        { name: 'Illinois', value: 12875255 },
        { name: 'Indiana', value: 6537334 },
        { name: 'Iowa', value: 3074186 },
        { name: 'Kansas', value: 2885905 },
        { name: 'Kentucky', value: 4380415 },
        { name: 'Louisiana', value: 4601893 },
        { name: 'Maine', value: 1329192 },
        { name: 'Maryland', value: 5884563 },
        { name: 'Massachusetts', value: 6646144 },
        { name: 'Michigan', value: 9883360 },
        { name: 'Minnesota', value: 5379139 },
        { name: 'Mississippi', value: 2984926 },
        { name: 'Missouri', value: 6021988 },
        { name: 'Montana', value: 1005141 },
        { name: 'Nebraska', value: 1855525 },
        { name: 'Nevada', value: 2758931 },
        { name: 'New Hampshire', value: 1320718 },
        { name: 'New Jersey', value: 8864590 },
        { name: 'New Mexico', value: 2085538 },
        { name: 'New York', value: 19570261 },
        { name: 'North Carolina', value: 9752073 },
        { name: 'North Dakota', value: 699628 },
        { name: 'Ohio', value: 11544225 },
        { name: 'Oklahoma', value: 3814820 },
        { name: 'Oregon', value: 3899353 },
        { name: 'Pennsylvania', value: 12763536 },
        { name: 'Rhode Island', value: 1050292 },
        { name: 'South Carolina', value: 4723723 },
        { name: 'South Dakota', value: 833354 },
        { name: 'Tennessee', value: 6456243 },
        { name: 'Texas', value: 26059203 },
        { name: 'Utah', value: 2855287 },
        { name: 'Vermont', value: 626011 },
        { name: 'Virginia', value: 8185867 },
        { name: 'Washington', value: 6897012 },
        { name: 'West Virginia', value: 1855413 },
        { name: 'Wisconsin', value: 5726398 },
        { name: 'Wyoming', value: 576412 },
        { name: 'Puerto Rico', value: 3667084 }
      ]
    }
  ]
};
"""#,
        option: {
            // Register the USA map (with special areas) before the option is consumed — upstream
            // `echarts.registerMap('USA', usaJson, { Alaska: {...}, Hawaii: {...}, 'Puerto Rico': {...} })`.
            ECharts.registerMap("USA", mapUSAGeoJSON, mapUSASpecialAreas)
            return [
                "title": [
                    "text": "USA Population Estimates (2012)",
                    "subtext": "Data from www.census.gov",
                    "sublink": "http://www.census.gov/popest/data/datasets.html",
                    "left": "right"
                ] as [String: Any],
                "tooltip": [
                    "trigger": "item",
                    "showDelay": 0.0,
                    "transitionDuration": 0.2
                ] as [String: Any],
                "visualMap": [
                    "left": "right",
                    "min": 500000.0,
                    "max": 38000000.0,
                    "inRange": [
                        "color": ["#313695", "#4575b4", "#74add1", "#abd9e9", "#e0f3f8", "#ffffbf",
                                  "#fee090", "#fdae61", "#f46d43", "#d73027", "#a50026"]
                    ] as [String: Any],
                    "text": ["High", "Low"],
                    "calculable": true
                ] as [String: Any],
                "toolbox": [
                    "show": true,
                    // upstream leaves `//orient: 'vertical'` commented out — omitted here too.
                    "left": "left",
                    "top": "top",
                    "feature": [
                        // dataView: EChartsKit does not register this feature (HTML-overlay table
                        // editor, host-dependent). ToolboxView skips it like upstream's
                        // `if (!Feature) return`, so the native pane shows one icon fewer.
                        "dataView": ["readOnly": false] as [String: Any],
                        "restore": [:] as [String: Any],
                        "saveAsImage": [:] as [String: Any]
                    ] as [String: Any]
                ] as [String: Any],
                "series": [
                    [
                        "name": "USA PopEstimates",
                        "type": "map",
                        "roam": true,
                        "map": "USA",
                        "emphasis": [
                            "label": ["show": true] as [String: Any]
                        ] as [String: Any],
                        "data": mapUSAPopulationData as [Any]
                    ] as [String: Any]
                ]
            ]
        }())
}
