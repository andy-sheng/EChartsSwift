// official-tree-basic — replica of https://echarts.apache.org/examples/zh/editor.html?c=tree-basic
// title: From Left to Right Tree / titleCN: 从左到右树状图
//
// A left-to-right `tree` series over the classic flare package hierarchy: internal nodes label on
// their left, leaves on their right, every OTHER top-level child starts collapsed, and hovering a
// node focuses its descendants (`emphasis.focus: 'descendant'`).
//
// DEVIATIONS from the official source:
//   - Data INLINED. The example does `myChart.showLoading(); $.get(ROOT_PATH + '/data/asset/data/
//     flare.json', function (data) { ... })`; the gallery page has no network, so flare.json is read
//     from the repo asset (assets/data/flare.json, via Upstream.repoRoot — the same #filePath-relative
//     read WebPage.swift uses for the echarts dist) and spliced into the web JS as a literal. The
//     showLoading/hideLoading pair and the $.get wrapper are dropped; the CALLBACK BODY — including
//     the `data.children.forEach(... index % 2 === 0 && (datum.collapsed = true))` mutation — is kept
//     verbatim, so the web pane still collapses the same alternating children.
//   - `expandAndCollapse: true` keeps its upstream value, but the gallery renders ONE static frame
//     (animation forced off, no clicks), so only the initial expand/collapse state is ever visible;
//     animationDuration / animationDurationUpdate likewise never play.
//
// No option key is a JS closure, so the native option is a COMPLETE port of the web one — every key of
// the upstream option (tooltip, series[0].{type,data,top,left,bottom,right,symbolSize,label,leaves,
// emphasis,expandAndCollapse,animationDuration,animationDurationUpdate}) is present below, nothing
// omitted or simplified.
//
// KNOWN NATIVE-vs-WEB DIVERGENCE (framework gap, NOT an option simplification): `leaves.label` has no
// effect on the native pane. Upstream parents each leaf's item model to a `leavesModel` inside
// `TreeSeries.getInitialData`'s `beforeLink` via `SeriesData.wrapMethod('getItemModel', ...)`, but the
// ported `wrapMethod` is bookkeeping-only (it cannot rebind a method by name — see the POTENTIAL-BUG
// note at Sources/EChartsKit/chart/tree/TreeSeries.swift and SeriesData.getItemModel, which never
// consults the injection). Leaf labels therefore inherit the SERIES `label` (position 'left',
// align 'right') instead of `leaves.label` (position 'right', align 'left'): the web pane fans leaf
// names out to the right of the tree, the native pane draws them to the left of their symbol. The
// `leaves` block is still passed verbatim so the demo lights up the moment `wrapMethod` becomes real.
import Foundation

// The flare hierarchy (name/children/value), parsed ONCE from the repo asset. A parse failure degrades
// to a bare root (the pane renders an empty tree rather than crashing).
private let flareTreeData: [String: Any] = {
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
// file's own bytes (not a re-serialization of `flareTreeData`) so the web pane sees exactly what the
// upstream request would have returned — including the un-mutated `collapsed`, which the forEach in the
// JS then applies itself.
private let flareJSONText: String = {
    let url = Upstream.repoRoot.appendingPathComponent("assets/data/flare.json")
    return (try? String(contentsOf: url, encoding: .utf8)) ?? #"{ "name": "flare", "children": [] }"#
}()

extension EChartsDemoRegistry {
    static let official_tree_basic = EChartsDemo(
        name: "official-tree-basic", category: "tree",
        summary: "从左到右树状图 — From Left to Right Tree",
        width: 640, height: 420,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
var data = \#(flareJSONText);

data.children.forEach(function (datum, index) {
  index % 2 === 0 && (datum.collapsed = true);
});

option = {
  tooltip: {
    trigger: 'item',
    triggerOn: 'mousemove'
  },
  series: [
    {
      type: 'tree',

      data: [data],

      top: '1%',
      left: '7%',
      bottom: '1%',
      right: '20%',

      symbolSize: 7,

      label: {
        position: 'left',
        verticalAlign: 'middle',
        align: 'right',
        fontSize: 9
      },

      leaves: {
        label: {
          position: 'right',
          verticalAlign: 'middle',
          align: 'left'
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
                    "data": [flareTreeData] as [Any],
                    "top": "1%",
                    "left": "7%",
                    "bottom": "1%",
                    "right": "20%",
                    "symbolSize": 7.0,
                    "label": [
                        "position": "left",
                        "verticalAlign": "middle",
                        "align": "right",
                        "fontSize": 9.0
                    ] as [String: Any],
                    "leaves": [
                        "label": [
                            "position": "right",
                            "verticalAlign": "middle",
                            "align": "left"
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
