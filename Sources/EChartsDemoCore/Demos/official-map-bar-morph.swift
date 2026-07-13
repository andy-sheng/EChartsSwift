// official-map-bar-morph — replica of https://echarts.apache.org/examples/zh/editor.html?c=map-bar-morph
// title: Morphing between Map and Bar / titleCN: 地图柱状图变形动画
// A USA population choropleth (50 states + DC + Puerto Rico, continuous visualMap) that upstream
// toggles every 2s with a `bar` series sharing `id:'population'` + `universalTransition:true`, so each
// state MORPHS into its bar and back.
//
// DEVIATIONS from the official source:
//   - ANIMATION REDUCED TO ITS FIRST FRAME. The morph is an animation across two `setOption` calls
//     driven by `setInterval(..., 2000)`; the gallery renders ONE static frame with animation forced
//     off, so only the INITIAL state — `myChart.setOption(mapOption)` — is ported. The web pane still
//     defines `barOption` verbatim (inert) so the reference JS stays a faithful copy; the `setInterval`
//     toggle and `myChart.setOption` calls are gone from both panes.
//   - DATA INLINED. Upstream fetches the USA GeoJSON with `$.get(ROOT_PATH + '/data/asset/geo/USA.json')`
//     and builds the option in the callback. The page has no network, so the map is read from the repo
//     asset assets/geo/USA.json (via Upstream.repoRoot, the same #filePath-relative read WebPage.swift
//     uses for the echarts dist) and handed to BOTH panes through `mapRegistrations`; `option` is
//     assigned unconditionally at the top level instead of inside the callback.
//   - `echarts.registerMap('USA', usaJson, { Alaska: {...} })` is NOT called inside webOptionJS: the map
//     plus its `specialAreas` (Alaska/Hawaii/Puerto Rico repositioned under the mainland's lower-left)
//     goes through `mapRegistrations`, which WebPage.swift injects into the page before the option
//     script, and which the native pane registers via `ECharts.registerMap`.
//   - The TS type annotations (`const mapOption: echarts.EChartsOption`) are dropped — a classic script
//     cannot parse them. `myChart.showLoading()/hideLoading()` and the trailing `export {}` are dropped.
import Foundation
import EChartsKit

// The USA states GeoJSON (52 features). Parsed once from the repo asset; a parse failure degrades to an
// empty FeatureCollection so the pane renders blank rather than crashing.
private let officialMapBarMorphGeoJSON: [String: Any] = {
    let url = Upstream.repoRoot.appendingPathComponent("assets/geo/USA.json")
    guard let data = try? Data(contentsOf: url),
          let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
        return ["type": "FeatureCollection", "features": [] as [Any]]
    }
    return obj
}()

// registerMap's 3rd argument, upstream: move + shrink the three non-contiguous regions.
// NATIVE form (typed) for ECharts.registerMap …
private let officialMapBarMorphSpecialAreas: GeoSpecialAreas = [
    "Alaska": GeoSpecialArea(left: -131, top: 25, width: 15),   // 把阿拉斯加移到美国主大陆左下方
    "Hawaii": GeoSpecialArea(left: -110, top: 28, width: 5),    // 夏威夷
    "Puerto Rico": GeoSpecialArea(left: -76, top: 26, width: 2) // 波多黎各
]

// … and the SAME areas as a JSON-serialisable dict, fed to the real echarts through the
// `{ geoJSON, specialAreas }` object form of registerMap (WebPage.swift serialises mapRegistrations).
private let officialMapBarMorphSpecialAreasJSON: [String: Any] = [
    "Alaska": ["left": -131.0, "top": 25.0, "width": 15.0] as [String: Any],
    "Hawaii": ["left": -110.0, "top": 28.0, "width": 5.0] as [String: Any],
    "Puerto Rico": ["left": -76.0, "top": 26.0, "width": 2.0] as [String: Any]
]

// 2012 US Census population estimates, in the upstream source's order.
private let officialMapBarMorphPopulation: [(name: String, value: Double)] = [
    ("Alabama", 4822023), ("Alaska", 731449), ("Arizona", 6553255), ("Arkansas", 2949131),
    ("California", 38041430), ("Colorado", 5187582), ("Connecticut", 3590347), ("Delaware", 917092),
    ("District of Columbia", 632323), ("Florida", 19317568), ("Georgia", 9919945), ("Hawaii", 1392313),
    ("Idaho", 1595728), ("Illinois", 12875255), ("Indiana", 6537334), ("Iowa", 3074186),
    ("Kansas", 2885905), ("Kentucky", 4380415), ("Louisiana", 4601893), ("Maine", 1329192),
    ("Maryland", 5884563), ("Massachusetts", 6646144), ("Michigan", 9883360), ("Minnesota", 5379139),
    ("Mississippi", 2984926), ("Missouri", 6021988), ("Montana", 1005141), ("Nebraska", 1855525),
    ("Nevada", 2758931), ("New Hampshire", 1320718), ("New Jersey", 8864590), ("New Mexico", 2085538),
    ("New York", 19570261), ("North Carolina", 9752073), ("North Dakota", 699628), ("Ohio", 11544225),
    ("Oklahoma", 3814820), ("Oregon", 3899353), ("Pennsylvania", 12763536), ("Rhode Island", 1050292),
    ("South Carolina", 4723723), ("South Dakota", 833354), ("Tennessee", 6456243), ("Texas", 26059203),
    ("Utah", 2855287), ("Vermont", 626011), ("Virginia", 8185867), ("Washington", 6897012),
    ("West Virginia", 1855413), ("Wisconsin", 5726398), ("Wyoming", 576412), ("Puerto Rico", 3667084)
]

// `data.sort(function (a, b) { return a.value - b.value; })` — ascending by population, as upstream
// does before feeding BOTH options (the bar's category axis depends on this order).
private let officialMapBarMorphData: [[String: Any]] = officialMapBarMorphPopulation
    .sorted { $0.value < $1.value }
    .map { ["name": $0.name, "value": $0.value] as [String: Any] }

extension EChartsDemoRegistry {
    static let official_map_bar_morph = EChartsDemo(
        name: "official-map-bar-morph", category: "map",
        summary: "地图柱状图变形动画 — Morphing between Map and Bar",
        width: 720, height: 460,
        nativeSupported: true,
        mapRegistrations: ["USA": ["geoJSON": officialMapBarMorphGeoJSON,
                                   "specialAreas": officialMapBarMorphSpecialAreasJSON] as [String: Any]],
        collection: .official,
        webOptionJS: #"""
var data = [
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
];

data.sort(function (a, b) {
  return a.value - b.value;
});

var mapOption = {
  visualMap: {
    left: 'right',
    min: 500000,
    max: 38000000,
    inRange: {
      // prettier-ignore
      color: ['#313695', '#4575b4', '#74add1', '#abd9e9', '#e0f3f8', '#ffffbf', '#fee090', '#fdae61', '#f46d43', '#d73027', '#a50026']
    },
    text: ['High', 'Low'],
    calculable: true
  },
  series: [
    {
      id: 'population',
      type: 'map',
      roam: true,
      map: 'USA',
      animationDurationUpdate: 1000,
      universalTransition: true,
      data: data
    }
  ]
};

// The other half of the morph. Upstream flips to it every 2s via
// `setInterval(function () { myChart.setOption(currentOption = currentOption === mapOption ? barOption : mapOption, true); }, 2000)`.
// The gallery renders one static frame, so it stays inert here — kept for reference fidelity.
var barOption = {
  xAxis: {
    type: 'value'
  },
  yAxis: {
    type: 'category',
    axisLabel: {
      rotate: 30
    },
    data: data.map(function (item) {
      return item.name;
    })
  },
  animationDurationUpdate: 1000,
  series: {
    type: 'bar',
    id: 'population',
    data: data.map(function (item) {
      return item.value;
    }),
    universalTransition: true
  }
};

option = mapOption;
"""#,
        option: {
            // Upstream `echarts.registerMap('USA', usaJson, { Alaska: {...}, Hawaii: {...}, 'Puerto Rico': {...} })`.
            ECharts.registerMap("USA", officialMapBarMorphGeoJSON, officialMapBarMorphSpecialAreas)
            return [
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
                "series": [
                    [
                        "id": "population",
                        "type": "map",
                        "roam": true,
                        "map": "USA",
                        "animationDurationUpdate": 1000.0,
                        "universalTransition": true,
                        "data": officialMapBarMorphData as [Any]
                    ] as [String: Any]
                ]
            ]
        }())
}
