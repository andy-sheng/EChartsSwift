// official-tree-orient-right-left — replica of https://echarts.apache.org/examples/zh/editor.html?c=tree-orient-right-left
// title: From Right to Left Tree / titleCN: 从右到左树状图
//
// The mirror image of tree-basic: the same flare package hierarchy laid out with `orient: 'RL'`, so the
// root sits on the RIGHT and the tree grows leftwards. Internal nodes label to their right, leaves to
// their left, every OTHER top-level child starts collapsed, and hovering focuses the descendants
// (`emphasis.focus: 'descendant'`).
//
// DEVIATIONS from the official source:
//   - Data INLINED. The example does `myChart.showLoading(); $.get(ROOT_PATH + '/data/asset/data/
//     flare.json', function (data) { ... })`; the gallery page has no network, so flare.json is read from
//     the repo asset (assets/data/flare.json, via Upstream.repoRoot — the same #filePath-relative read
//     WebPage.swift uses for the echarts dist) and spliced into the web JS as a literal. ONLY the `$.get`
//     wrapper itself is dropped: every statement it contained is kept verbatim and in source order at the
//     top level — `myChart.showLoading()`, the resolved `data`, `myChart.hideLoading()`, the
//     `data.children.forEach(... index % 2 === 0 && (datum.collapsed = true))` mutation, and the
//     `myChart.setOption((option = {...}))` call, all of which still run on the web pane. (The
//     loading overlay is shown and hidden in the same tick now that there is nothing to wait for, which
//     is what the example itself does the instant the request returns.)
//   - TypeScript-only syntax removed: the forEach parameter annotations (`datum: { collapsed: boolean }`,
//     `index: number`) and the trailing `export {};` (a bare export is a SyntaxError in a classic script).
//   - `expandAndCollapse: true` keeps its upstream value, but a click-driven expand/collapse and the
//     animationDuration / animationDurationUpdate transitions only exist in the LIVE pane; the headless
//     still-frame render (animation forced off, no clicks) shows the initial collapse state only.
//
// No option key is a JS function, so the native option is a COMPLETE port of the web one — every key of
// the upstream option (tooltip, series[0].{type,data,top,left,bottom,right,symbolSize,orient,label,leaves,
// emphasis,expandAndCollapse,animationDuration,animationDurationUpdate}) is present below, nothing omitted
// or simplified. No `drive` hook: the example's only dynamics are interactive (expand/collapse on click),
// not a timeline.
//
// KNOWN NATIVE-vs-WEB DIVERGENCE (framework gap, NOT an option simplification): `leaves.label` has no
// effect on the native pane. Upstream parents each leaf's item model to a `leavesModel` inside
// `TreeSeries.getInitialData`'s `beforeLink` via `SeriesData.wrapMethod('getItemModel', ...)`, but the
// ported `wrapMethod` is bookkeeping-only (it cannot rebind a method by name — see the POTENTIAL-BUG note
// at Sources/EChartsKit/chart/tree/TreeSeries.swift and SeriesData.getItemModel, which never consults the
// injection). Leaf labels therefore inherit the SERIES `label` (position 'right', align 'left') instead of
// `leaves.label` (position 'left', align 'right'): the web pane tucks leaf names to the LEFT of their
// symbol, the native pane fans them out to the right. The `leaves` block is passed verbatim regardless, so
// the demo lights up the moment `wrapMethod` becomes real.
import Foundation

// The flare hierarchy (name/children/value), parsed ONCE from the repo asset. A parse failure degrades to
// a bare root (the pane renders an empty tree rather than crashing).
private let treeRLFlareData: [String: Any] = {
    let url = Upstream.repoRoot.appendingPathComponent("assets/data/flare.json")
    guard let data = try? Data(contentsOf: url),
          var obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
        return ["name": "flare", "children": [] as [Any]]
    }
    // Upstream, inside the $.get callback:
    //   data.children.forEach(function (datum, index) { index % 2 === 0 && (datum.collapsed = true); });
    if var children = obj["children"] as? [[String: Any]] {
        for i in children.indices where i % 2 == 0 { children[i]["collapsed"] = true }
        obj["children"] = children
    }
    return obj
}()

// The SAME asset as raw JSON text, spliced into webOptionJS in place of the `$.get` fetch. Kept as the
// file's own bytes (not a re-serialization of `treeRLFlareData`) so the web pane sees exactly what the
// upstream request would have returned — un-mutated, with the forEach in the JS applying `collapsed`.
private let treeRLFlareJSONText: String = {
    let url = Upstream.repoRoot.appendingPathComponent("assets/data/flare.json")
    return (try? String(contentsOf: url, encoding: .utf8)) ?? #"{ "name": "flare", "children": [] }"#
}()

extension EChartsDemoRegistry {
    static let official_tree_orient_right_left = EChartsDemo(
        name: "official-tree-orient-right-left", category: "tree",
        summary: "从右到左树状图 — From Right to Left Tree",
        width: 720, height: 460,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
myChart.showLoading();

var data = \#(treeRLFlareJSONText);

myChart.hideLoading();

data.children.forEach(function (datum, index) {
  index % 2 === 0 && (datum.collapsed = true);
});

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

        top: '1%',
        left: '15%',
        bottom: '1%',
        right: '7%',

        symbolSize: 7,

        orient: 'RL',

        label: {
          position: 'right',
          verticalAlign: 'middle',
          align: 'left'
        },

        leaves: {
          label: {
            position: 'left',
            verticalAlign: 'middle',
            align: 'right'
          }
        },

        emphasis: {
          focus: 'descendant'
        },

        expandAndCollapse: true,
        animationDuration: 550,
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
                    "data": [treeRLFlareData] as [Any],
                    "top": "1%",
                    "left": "15%",
                    "bottom": "1%",
                    "right": "7%",
                    "symbolSize": 7.0,
                    "orient": "RL",
                    "label": [
                        "position": "right",
                        "verticalAlign": "middle",
                        "align": "left"
                    ] as [String: Any],
                    "leaves": [
                        "label": [
                            "position": "left",
                            "verticalAlign": "middle",
                            "align": "right"
                        ] as [String: Any]
                    ] as [String: Any],
                    "emphasis": [
                        "focus": "descendant"
                    ] as [String: Any],
                    "expandAndCollapse": true,
                    "animationDuration": 550.0,
                    "animationDurationUpdate": 750.0
                ] as [String: Any]
            ]
        ])
}
