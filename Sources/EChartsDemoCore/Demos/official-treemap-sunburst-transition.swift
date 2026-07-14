// official-treemap-sunburst-transition — replica of
// https://echarts.apache.org/examples/zh/editor.html?c=treemap-sunburst-transition
// title: Transition between Treemap and Sunburst / titleCN: 矩形树图和旭日图的动画过渡
//
// The echarts source tree (30 top-level packages, sized by bytes) drawn as a `treemap` and as a
// `sunburst` that share `id: 'echarts-package-size'` + `universalTransition: true`, swapped every 3s:
// each package's TILE morphs into its sunburst SECTOR and back (animationDurationUpdate: 1000).
//
// THE 3s SWAP IS PORTED, on both panes. The web pane runs the example's own
// `setInterval(function () { myChart.setOption(currentOption); }, 3000)` verbatim; the native pane
// replays the same timeline through `drive` (see EChartsDemoChart). Note the swap MERGES (upstream
// passes no `true` to setOption — unlike map-bar-morph): the incoming series is matched to the
// outgoing one BY ID, which is what arms the universal transition, so `drive` passes
// `notMerge: false`. The still-frame PNG paths capture the first frame — the treemap — and neuter the
// timer, so a snapshot stays deterministic.
//
// DEVIATIONS from the official source:
//   - DATA INLINED. Upstream does `$.getJSON(ROOT_PATH + '/data/asset/data/echarts-package-size.json',
//     function (data) { ... })`. The page has no network, so the asset is vendored at
//     assets/data/echarts-package-size.json and read at demo time via Upstream.repoRoot (the same
//     #filePath-relative read WebPage.swift uses for the echarts dist). The web pane keeps the CALLBACK
//     BODY verbatim at top level with the raw JSON spliced in as `data`, and drops only the fetch
//     wrapper.
//   - TypeScript-only text dropped: the `: echarts.EChartsOption` annotations on the two `const`s and
//     the trailing `export {};` (a bare export is a SyntaxError in a classic script).
//   - `nodeClick: undefined` (upstream's way of DISABLING the default node click — a key that is
//     present-but-undefined survives echarts' `merge`, so the default 'zoomToNode'/'rootToNode' is
//     never applied) is kept verbatim in the web pane; Swift has no `undefined`, so the native option
//     carries `NSNull()`, which behaves identically through the ported `ZRUtil.merge` (`target[key] !=
//     nil` ⇒ the default does not overwrite it) and reads back as a non-String ⇒ no drill-down.
//
// No option key is a JS closure and nothing else is simplified: every key of the upstream options
// (series[0].{type,id,animationDurationUpdate,roam,nodeClick,data,universalTransition,label,breadcrumb}
// for the treemap; series[0].{type,id,radius,animationDurationUpdate,nodeClick,data,universalTransition,
// itemStyle,label} for the sunburst) is present below.
import Foundation

// The echarts package-size hierarchy ({name, size, children, value}), parsed ONCE from the repo asset.
// A parse failure degrades to an empty list (the pane renders blank rather than crashing).
// `data.children` — the 30 top-level packages — is what both series are fed.
private let treemapSunburstTransitionChildren: [Any] = {
    let url = Upstream.repoRoot.appendingPathComponent("assets/data/echarts-package-size.json")
    guard let data = try? Data(contentsOf: url),
          let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
          let children = obj["children"] as? [Any] else {
        return []
    }
    return children
}()

// The SAME asset as raw JSON text, spliced into webOptionJS in place of the `$.getJSON` fetch (the page
// cannot reach the filesystem). Kept as the file's own bytes, not a re-serialization of the above.
private let treemapSunburstTransitionJSONText: String = {
    let url = Upstream.repoRoot.appendingPathComponent("assets/data/echarts-package-size.json")
    return (try? String(contentsOf: url, encoding: .utf8)) ?? #"{ "name": "echarts", "children": [] }"#
}()

extension EChartsDemoRegistry {
    static let official_treemap_sunburst_transition = EChartsDemo(
        name: "official-treemap-sunburst-transition", category: "treemap",
        summary: "矩形树图和旭日图的动画过渡 — Transition between Treemap and Sunburst",
        width: 720, height: 460,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
var data = \#(treemapSunburstTransitionJSONText);

const treemapOption = {
  series: [
    {
      type: 'treemap',
      id: 'echarts-package-size',
      animationDurationUpdate: 1000,
      roam: false,
      nodeClick: undefined,
      data: data.children,
      universalTransition: true,
      label: {
        show: true
      },
      breadcrumb: {
        show: false
      }
    }
  ]
};

const sunburstOption = {
  series: [
    {
      type: 'sunburst',
      id: 'echarts-package-size',
      radius: ['20%', '90%'],
      animationDurationUpdate: 1000,
      nodeClick: undefined,
      data: data.children,
      universalTransition: true,
      itemStyle: {
        borderWidth: 1,
        borderColor: 'rgba(255,255,255,.5)'
      },
      label: {
        show: false
      }
    }
  ]
};

let currentOption = treemapOption;

myChart.setOption(currentOption);

setInterval(function () {
  currentOption =
    currentOption === treemapOption ? sunburstOption : treemapOption;
  myChart.setOption(currentOption);
}, 3000);
"""#,
        // The native pane's half of the same timeline: swap the two options every 3s, exactly as the
        // example's setInterval does. MERGING (notMerge: false) is upstream's plain
        // `myChart.setOption(currentOption)` — the shared `id` is how the incoming series finds the
        // outgoing one, and that pairing is what `universalTransition` morphs across.
        drive: { chart in
            // Upstream keeps `currentOption` and compares by identity; a Bool says the same thing.
            var showingTreemap = true
            chart.every(3) {
                showingTreemap.toggle()
                chart.setOption(showingTreemap ? treemapSunburstTransitionTreemapOption
                                               : treemapSunburstTransitionSunburstOption,
                                notMerge: false)
            }
        },
        // Upstream's `myChart.setOption(currentOption)` with `currentOption = treemapOption`.
        option: treemapSunburstTransitionTreemapOption)
}

// The two halves of the transition, as Swift options. `option:` starts on the treemap; `drive:` swaps.
private let treemapSunburstTransitionTreemapOption: [String: Any] = [
    "series": [
        [
            "type": "treemap",
            "id": "echarts-package-size",
            "animationDurationUpdate": 1000.0,
            "roam": false,
            "nodeClick": NSNull(),                 // upstream `nodeClick: undefined` — see header
            "data": treemapSunburstTransitionChildren,
            "universalTransition": true,
            "label": ["show": true] as [String: Any],
            "breadcrumb": ["show": false] as [String: Any]
        ] as [String: Any]
    ]
]

private let treemapSunburstTransitionSunburstOption: [String: Any] = [
    "series": [
        [
            "type": "sunburst",
            "id": "echarts-package-size",
            "radius": ["20%", "90%"],
            "animationDurationUpdate": 1000.0,
            "nodeClick": NSNull(),                 // upstream `nodeClick: undefined` — see header
            "data": treemapSunburstTransitionChildren,
            "universalTransition": true,
            "itemStyle": [
                "borderWidth": 1.0,
                "borderColor": "rgba(255,255,255,.5)"
            ] as [String: Any],
            "label": ["show": false] as [String: Any]
        ] as [String: Any]
    ]
]
