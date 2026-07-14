// official-tree-orient-bottom-top — replica of https://echarts.apache.org/examples/zh/editor.html?c=tree-orient-bottom-top
// title: From Bottom to Top Tree / titleCN: 从下到上树状图
//
// The flare package hierarchy as a bottom-up `tree` (`orient: 'BT'`): the root sits at the BOTTOM and
// the tree grows upward. Every label is rotated 90°, internal nodes labelling below their symbol
// (`label.position: 'bottom'`, align right) and leaves above theirs (`leaves.label.position: 'top'`,
// align left), so the node names read as vertical text running off each end of the tree. Hovering a
// node focuses its descendants (`emphasis.focus: 'descendant'`). Nodes are `emptyCircle` symbols.
//
// DEVIATIONS from the official source:
//   - Data INLINED. The example does `myChart.showLoading(); $.get(ROOT_PATH + '/data/asset/data/
//     flare.json', function (data) { ... })`; the gallery page has no network, so flare.json is read
//     from the repo asset (assets/data/flare.json, via Upstream.repoRoot — the same #filePath-relative
//     read WebPage.swift uses for the echarts dist) and spliced into the web JS as a literal. The
//     showLoading/hideLoading pair and the $.get wrapper are dropped; the callback BODY (the whole
//     `option`) is kept verbatim and assigned at the top level. Unlike tree-basic, this example does
//     NOT mutate the fetched data (it stamps no `collapsed` flags), so the asset goes in untouched.
//   - `expandAndCollapse: true` keeps its upstream value, but the gallery renders ONE static frame
//     (animation forced off, no clicks), so only the INITIAL expansion state is ever visible, and
//     `animationDurationUpdate: 750` — which only ever plays on an expand/collapse click — never runs.
//     NOTE that the initial state is NOT the whole tree: with `expandAndCollapse` on and no
//     `initialTreeDepth` in the option, the series default (`initialTreeDepth: 2`) collapses every node
//     deeper than depth 2 (`TreeSeries.getInitialData`: `node.isExpand = node.depth <= expandTreeDepth`).
//     That is upstream behaviour, identical in BOTH panes — the official example opens the same way in
//     the browser — not a simplification of the port.
//
// No option key is a JS closure, so the native option is a COMPLETE port of the web one — every key of
// the upstream option (tooltip, series[0].{type,data,left,right,top,bottom,symbol,orient,
// expandAndCollapse,label,leaves,emphasis,animationDurationUpdate}) is present below, nothing omitted
// or simplified.
//
// KNOWN NATIVE-vs-WEB DIVERGENCE (framework gap, NOT an option simplification): `leaves.label` has no
// effect on the native pane — the same `wrapMethod` gap documented at length in official-tree-basic.swift
// (TreeSeries.getInitialData's `beforeLink` cannot rebind `getItemModel` to parent leaf items to a
// `leavesModel`). Leaf labels therefore inherit the SERIES `label` (position 'bottom', align 'right')
// instead of `leaves.label` (position 'top', align 'left'): the web pane fans leaf names ABOVE the
// tree's top edge, the native pane draws them below their symbol, overlapping the tree. The `leaves`
// block is still passed verbatim so the demo lights up the moment `wrapMethod` becomes real.
import Foundation

// The flare hierarchy (name/children/value), parsed ONCE from the repo asset, unmutated (upstream feeds
// the fetched JSON straight to `data: [data]`). A parse failure degrades to a bare root (the pane renders
// an empty tree rather than crashing).
private let treeOrientBTData: [String: Any] = {
    let url = Upstream.repoRoot.appendingPathComponent("assets/data/flare.json")
    guard let data = try? Data(contentsOf: url),
          let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
        return ["name": "flare", "children": [] as [Any]]
    }
    return obj
}()

// The SAME asset as raw JSON text, spliced into webOptionJS in place of the `$.get` fetch — the file's
// own bytes, so the web pane sees exactly what the upstream request would have returned.
private let treeOrientBTJSONText: String = {
    let url = Upstream.repoRoot.appendingPathComponent("assets/data/flare.json")
    return (try? String(contentsOf: url, encoding: .utf8)) ?? #"{ "name": "flare", "children": [] }"#
}()

extension EChartsDemoRegistry {
    static let official_tree_orient_bottom_top = EChartsDemo(
        name: "official-tree-orient-bottom-top", category: "tree",
        summary: "从下到上树状图 — From Bottom to Top Tree",
        width: 720, height: 460,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
var data = \#(treeOrientBTJSONText);

option = {
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
      top: '20%',
      bottom: '8%',

      symbol: 'emptyCircle',

      orient: 'BT',

      expandAndCollapse: true,

      label: {
        position: 'bottom',
        rotate: 90,
        verticalAlign: 'middle',
        align: 'right'
      },

      leaves: {
        label: {
          position: 'top',
          rotate: 90,
          verticalAlign: 'middle',
          align: 'left'
        }
      },

      emphasis: {
        focus: 'descendant'
      },

      animationDurationUpdate: 750
    }
  ]
};
"""#,
        option: [
            "tooltip": [
                "trigger": "item",
                "triggerOn": "mousemove"
            ] as [String: Any],
            "series": [
                [
                    "type": "tree",
                    "data": [treeOrientBTData] as [Any],
                    "left": "2%",
                    "right": "2%",
                    "top": "20%",
                    "bottom": "8%",
                    "symbol": "emptyCircle",
                    "orient": "BT",
                    "expandAndCollapse": true,
                    "label": [
                        "position": "bottom",
                        "rotate": 90.0,
                        "verticalAlign": "middle",
                        "align": "right"
                    ] as [String: Any],
                    "leaves": [
                        "label": [
                            "position": "top",
                            "rotate": 90.0,
                            "verticalAlign": "middle",
                            "align": "left"
                        ] as [String: Any]
                    ] as [String: Any],
                    "emphasis": [
                        "focus": "descendant"
                    ] as [String: Any],
                    "animationDurationUpdate": 750.0
                ] as [String: Any]
            ]
        ])
}
