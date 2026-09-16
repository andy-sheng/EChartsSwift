// official-tree-radial — replica of https://echarts.apache.org/examples/zh/editor.html?c=tree-radial
// title: Radial Tree / titleCN: 径向树状图
//
// The flare package hierarchy as a RADIAL `tree` (`layout: 'radial'`): the root sits at the centre of the
// available rect and each generation fans out on a wider ring, edges drawn as radial curves. Nodes are
// `emptyCircle` symbols (size 7); `initialTreeDepth: 3` opens the first three levels and leaves the rest
// folded; hovering a node focuses its whole subtree (`emphasis.focus: 'descendant'`).
//
// DEVIATIONS from the official source:
//   - Data INLINED. The example does `myChart.showLoading(); $.get(ROOT_PATH + '/data/asset/data/
//     flare.json', function (data) { ... })`; the gallery page has no network, so flare.json is read from
//     the repo asset (assets/data/flare.json, via Upstream.repoRoot — the same #filePath-relative read
//     WebPage.swift uses for the echarts dist) and spliced into the web JS as a literal. Only the `$.get`
//     WRAPPER is dropped: the callback body (`myChart.hideLoading()` + the `myChart.setOption((option =
//     {...}))` call) and the preceding `myChart.showLoading()` are kept verbatim at the top level. This
//     example does not mutate the fetched data (unlike tree-basic, it stamps no `collapsed` flags), so the
//     asset goes in untouched.
//   - `export {};` dropped (a bare export is a SyntaxError in the page's classic script).
//   - `animationDurationUpdate: 750` keeps its upstream value, but it only ever plays on an
//     expand/collapse click, and the still-frame render has no clicks (animation forced off) — so it never
//     runs there. Only the INITIAL expansion state (`initialTreeDepth: 3`) is captured, which is exactly
//     how the official example opens in the browser.
//
// No option key is a JS closure, and the example drives no timeline (its only dynamics are clicks), so
// there is no `drive` and the native option is a COMPLETE port of the web one — every key of the upstream
// option (tooltip, series[0].{type,data,top,bottom,layout,symbol,symbolSize,initialTreeDepth,
// animationDurationUpdate,emphasis}) is present below, nothing omitted or simplified.
//
// KNOWN NATIVE-vs-WEB DIVERGENCE (framework gap, NOT an option simplification): upstream rotates each
// node's label to follow its ray in a radial tree (TreeView's node update derives `label.rotation` /
// alignment from the node's angle, flipping the text on the left half of the circle). The port's TreeView
// routes node symbols through the shared SymbolDraw and marks radial label rotation DEFERRED (see the
// deferred note at Sources/EChartsKit/chart/tree/TreeView.swift, "node/link scale + radial label
// rotation are DEFERRED"), so the native pane draws every label horizontally: the ring of names reads
// upright instead of fanning out along the spokes. Node/edge GEOMETRY is radial on both panes
// (treeLayout.swift + TreeView's `radialCoordinate` are ported) — only the label transform differs.
import Foundation

// The flare hierarchy (name/children/value), parsed ONCE from the repo asset, unmutated (upstream feeds
// the fetched JSON straight to `data: [data]`). A parse failure degrades to a bare root (the pane renders
// an empty tree rather than crashing).
private let treeRadialData: [String: Any] = {
    let url = Upstream.repoRoot.appendingPathComponent("assets/data/flare.json")
    guard let data = try? Data(contentsOf: url),
          let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
        return ["name": "flare", "children": [] as [Any]]
    }
    return obj
}()

// The SAME asset as raw JSON text, spliced into webOptionJS in place of the `$.get` fetch — the file's
// own bytes, so the web pane sees exactly what the upstream request would have returned.
private let treeRadialJSONText: String = {
    let url = Upstream.repoRoot.appendingPathComponent("assets/data/flare.json")
    return (try? String(contentsOf: url, encoding: .utf8)) ?? #"{ "name": "flare", "children": [] }"#
}()

extension EChartsDemoRegistry {
    static let official_tree_radial = EChartsDemo(
        name: "official-tree-radial", category: "tree",
        summary: "径向树状图 — Radial Tree",
        width: 720, height: 460,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
myChart.showLoading();

// The flare.json fetch, inlined (the asset's own bytes), bound to the same `data` the upstream
// callback receives. Everything below is that callback's body, verbatim.
var data = \#(treeRadialJSONText);

myChart.hideLoading();

myChart.setOption(
  (option = {
    tooltip: {
      trigger: 'item',
      triggerOn: 'mousemove'
    },
    series: [
      {
        type: 'tree',

        data: [data],

        top: '18%',
        bottom: '14%',

        layout: 'radial',

        symbol: 'emptyCircle',

        symbolSize: 7,

        initialTreeDepth: 3,

        animationDurationUpdate: 750,

        emphasis: {
          focus: 'descendant'
        }
      }
    ]
  })
);
"""#,
        option: [
            "tooltip": [
                "trigger": "item",
                "triggerOn": "mousemove"
            ] as [String: Any],
            "series": [
                [
                    "type": "tree",
                    "data": [treeRadialData] as [Any],
                    "top": "18%",
                    "bottom": "14%",
                    "layout": "radial",
                    "symbol": "emptyCircle",
                    "symbolSize": 7.0,
                    "initialTreeDepth": 3.0,
                    "animationDurationUpdate": 750.0,
                    "emphasis": [
                        "focus": "descendant"
                    ] as [String: Any]
                ] as [String: Any]
            ]
        ])
}
