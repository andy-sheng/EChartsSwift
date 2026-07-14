// official-tree-vertical — replica of https://echarts.apache.org/examples/zh/editor.html?c=tree-vertical
// title: From Top to Bottom Tree / titleCN: 从上到下树状图
//
// The flare package hierarchy as a top-down `tree` (`orient: 'vertical'`, echarts' alias for 'TB'): the
// root sits at the TOP and the tree grows downward. Every label is rotated -90°, internal nodes labelling
// ABOVE their symbol (`label.position: 'top'`, align right) and leaves BELOW theirs
// (`leaves.label.position: 'bottom'`, align left), so node names read as vertical text running off each
// end of the tree. Nodes are `emptyCircle` symbols. `expandAndCollapse: true` — clicking an internal node
// folds/unfolds its subtree.
//
// DEVIATIONS from the official source:
//   - Data INLINED. The example does `myChart.showLoading(); $.get(ROOT_PATH + '/data/asset/data/
//     flare.json', function (data) { ... })`; the gallery page has no network, so flare.json is read from
//     the repo asset (assets/data/flare.json, via Upstream.repoRoot — the same #filePath-relative read
//     WebPage.swift uses for the echarts dist) and spliced into the web JS as a literal. Only the `$.get`
//     WRAPPER is dropped: the callback body (`myChart.hideLoading()` + the `myChart.setOption((option =
//     {...}))` call) and the preceding `myChart.showLoading()` are kept verbatim at the top level. This
//     example does not mutate the fetched data (unlike tree-basic, it stamps no `collapsed` flags), so
//     the asset goes in untouched.
//   - `export {};` dropped (a bare export is a SyntaxError in the page's classic script).
//   - `expandAndCollapse: true` keeps its upstream value, but the still-frame render has no clicks
//     (animation forced off), so only the INITIAL expansion state is captured there and
//     `animationDurationUpdate: 750` — which only ever plays on an expand/collapse click — never runs on
//     it. NOTE that the initial state is NOT the whole tree: with `expandAndCollapse` on and no
//     `initialTreeDepth` in the option, the series default (`initialTreeDepth: 2`) collapses everything
//     deeper than depth 2 (`TreeSeries.getInitialData`: `node.isExpand = node.depth <= expandTreeDepth`).
//     That is upstream behaviour, identical in BOTH panes — the official example opens the same way in the
//     browser — not a simplification of the port.
//
// No option key is a JS closure, and the example drives no timeline (its only dynamics are clicks), so
// there is no `drive` and the native option is a COMPLETE port of the web one — every key of the upstream
// option (tooltip, series[0].{type,data,left,right,top,bottom,symbol,orient,expandAndCollapse,label,
// leaves,animationDurationUpdate}) is present below, nothing omitted or simplified.
//
// KNOWN NATIVE-vs-WEB DIVERGENCE (framework gap, NOT an option simplification): `leaves.label` has no
// effect on the native pane — the same `wrapMethod` gap documented at length in official-tree-basic.swift
// (TreeSeries.getInitialData's `beforeLink` cannot rebind `getItemModel` to parent leaf items to a
// `leavesModel`). Leaf labels therefore inherit the SERIES `label` (position 'top', align 'right')
// instead of `leaves.label` (position 'bottom', align 'left'): the web pane fans leaf names DOWN off the
// tree's bottom edge, the native pane draws them upward from each leaf symbol, overlapping the tree. The
// `leaves` block is still passed verbatim so the demo lights up the moment `wrapMethod` becomes real.
import Foundation

// The flare hierarchy (name/children/value), parsed ONCE from the repo asset, unmutated (upstream feeds
// the fetched JSON straight to `data: [data]`). A parse failure degrades to a bare root (the pane renders
// an empty tree rather than crashing).
private let treeVerticalData: [String: Any] = {
    let url = Upstream.repoRoot.appendingPathComponent("assets/data/flare.json")
    guard let data = try? Data(contentsOf: url),
          let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
        return ["name": "flare", "children": [] as [Any]]
    }
    return obj
}()

// The SAME asset as raw JSON text, spliced into webOptionJS in place of the `$.get` fetch — the file's
// own bytes, so the web pane sees exactly what the upstream request would have returned.
private let treeVerticalJSONText: String = {
    let url = Upstream.repoRoot.appendingPathComponent("assets/data/flare.json")
    return (try? String(contentsOf: url, encoding: .utf8)) ?? #"{ "name": "flare", "children": [] }"#
}()

extension EChartsDemoRegistry {
    static let official_tree_vertical = EChartsDemo(
        name: "official-tree-vertical", category: "tree",
        summary: "从上到下树状图 — From Top to Bottom Tree",
        width: 720, height: 460,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
myChart.showLoading();

// The flare.json fetch, inlined (the asset's own bytes), bound to the same `data` the upstream
// callback receives. Everything below is that callback's body, verbatim.
var data = \#(treeVerticalJSONText);

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

        left: '2%',
        right: '2%',
        top: '8%',
        bottom: '20%',

        symbol: 'emptyCircle',

        orient: 'vertical',

        expandAndCollapse: true,

        label: {
          position: 'top',
          rotate: -90,
          verticalAlign: 'middle',
          align: 'right',
          fontSize: 9
        },

        leaves: {
          label: {
            position: 'bottom',
            rotate: -90,
            verticalAlign: 'middle',
            align: 'left'
          }
        },

        animationDurationUpdate: 750
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
                    "data": [treeVerticalData] as [Any],
                    "left": "2%",
                    "right": "2%",
                    "top": "8%",
                    "bottom": "20%",
                    "symbol": "emptyCircle",
                    "orient": "vertical",
                    "expandAndCollapse": true,
                    "label": [
                        "position": "top",
                        "rotate": -90.0,
                        "verticalAlign": "middle",
                        "align": "right",
                        "fontSize": 9.0
                    ] as [String: Any],
                    "leaves": [
                        "label": [
                            "position": "bottom",
                            "rotate": -90.0,
                            "verticalAlign": "middle",
                            "align": "left"
                        ] as [String: Any]
                    ] as [String: Any],
                    "animationDurationUpdate": 750.0
                ] as [String: Any]
            ]
        ])
}
