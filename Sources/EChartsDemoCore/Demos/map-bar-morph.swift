// map-bar-morph — the canonical ECharts "Map and Bar Morphing" example
// (https://echarts.apache.org/examples/zh/editor.html?c=map-bar-morph). The upstream example toggles,
// every 2s via setInterval, between a `map` series (USA population choropleth) and a `bar` series that
// share `id:"population"` + `universalTransition:true`, so each datum's region MORPHS into its bar and
// back. That toggle is an ANIMATION across two setOption calls; the demo gallery renders a SINGLE static
// frame (animation forced off), so a morph cannot be captured — this demo therefore ports the INITIAL
// state, `myChart.setOption(mapOption)`: the choropleth of the 50 states + DC + Puerto Rico coloured by
// population through a continuous `visualMap`.
//
// The USA GeoJSON (52 features) is loaded from assets/geo/USA.json at demo time via Upstream.repoRoot —
// the SAME #filePath-relative repo read the echarts.js web pane uses for the upstream dist (WebPage.swift),
// so it resolves on macOS and the iOS simulator alike. Alaska / Hawaii / Puerto Rico sit far from the
// mainland, so — exactly like the upstream `echarts.registerMap('USA', usaJson, { Alaska: {...}, ... })`
// third argument — they are repositioned + shrunk under the lower-left of the continental US via
// `specialAreas` (GeoJSONRegion.transformTo). The NATIVE pane passes a typed `GeoSpecialAreas` as
// registerMap's 3rd arg; the HTML pane gets the SAME areas through the `{ geoJSON, specialAreas }` object
// form of mapRegistrations (echarts.registerMap accepts it). Renders on BOTH panes: native + echarts.js.
import Foundation
import EChartsKit

// The USA states GeoJSON (50 states + DC + Puerto Rico). Parsed ONCE from the repo asset; a parse failure
// degrades to an empty FeatureCollection (the pane then renders blank rather than crashing).
private let usaGeoJSON: [String: Any] = {
    let url = Upstream.repoRoot.appendingPathComponent("assets/geo/USA.json")
    guard let data = try? Data(contentsOf: url),
          let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
        return ["type": "FeatureCollection", "features": [] as [Any]]
    }
    return obj
}()

// specialAreas — reposition + resize the three non-contiguous regions (upstream registerMap 3rd arg).
// NATIVE form: a typed GeoSpecialAreas ([regionName: GeoSpecialArea]) passed to ECharts.registerMap.
private let usaSpecialAreas: GeoSpecialAreas = [
    "Alaska": GeoSpecialArea(left: -131, top: 25, width: 15),        // moved to the mainland's lower-left
    "Hawaii": GeoSpecialArea(left: -110, top: 28, width: 5),
    "Puerto Rico": GeoSpecialArea(left: -76, top: 26, width: 2)
]

// HTML form: the SAME areas as a JSON-serialisable dict, fed to real echarts via the `{ geoJSON,
// specialAreas }` registerMap object form (WebPage.swift serialises each mapRegistrations value).
private let usaSpecialAreasJSON: [String: Any] = [
    "Alaska": ["left": -131.0, "top": 25.0, "width": 15.0] as [String: Any],
    "Hawaii": ["left": -110.0, "top": 28.0, "width": 5.0] as [String: Any],
    "Puerto Rico": ["left": -76.0, "top": 26.0, "width": 2.0] as [String: Any]
]

// 2012 US Census population estimates (verbatim from the upstream example, incl. Puerto Rico).
private let populationData: [[String: Any]] = [
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
    static let demo_map_bar_morph = EChartsDemo(
        name: "map-bar-morph", category: "Map",
        summary: "USA population choropleth — the map↔bar universalTransition example (static map frame), 50 states + DC + PR via continuous visualMap",
        width: 720, height: 460,
        mapRegistrations: ["USA": ["geoJSON": usaGeoJSON, "specialAreas": usaSpecialAreasJSON] as [String: Any]],
        option: {
            // Register the USA map (with special areas) before the option is consumed — upstream
            // `echarts.registerMap('USA', usaJson, { Alaska: {...}, Hawaii: {...}, 'Puerto Rico': {...} })`.
            ECharts.registerMap("USA", usaGeoJSON, usaSpecialAreas)
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
                        "data": populationData as [Any]
                    ] as [String: Any]
                ]
            ]
        }())
}
