// official-sankey-nodeAlign-left — replica of https://echarts.apache.org/examples/zh/editor.html?c=sankey-nodeAlign-left
// title: Node Align Left in Sankey / titleCN: 桑基图左对齐布局
// The same UK-energy-flow sankey (48 nodes, 68 links) as sankey-energy, but laid out with
// `nodeAlign: 'left'` — every node is pushed to the LEFT edge of its depth column instead of the
// default 'justify' (which stretches leaf nodes to the right edge). Ribbons are coloured by their
// SOURCE node (`lineStyle.color: 'source'`, curveness 0.5), with `emphasis.focus: 'adjacency'`.
//
// DEVIATIONS from the official source:
//   - DATA INLINED. Upstream wraps the whole option in `$.get(ROOT_PATH + '/data/asset/data/energy.json',
//     function (data) { ... })`; the demo page has no network, so the asset is mirrored at
//     assets/data/energy.json (read via Upstream.repoRoot) and spliced into the web pane verbatim as
//     `var data = {...}`. The callback body is otherwise unchanged and runs at top level, so the
//     `myChart.showLoading()` / `hideLoading()` pair and `myChart.setOption((option = {...}))` are kept
//     verbatim — the example's own setOption is what applies the option, as upstream.
//   - `myChart.showLoading()` / `hideLoading()` are KEPT verbatim but are a no-op here: with the fetch
//     gone there is no async gap between them, so no loading layer is ever painted.
//   - The trailing `export {}` is dropped (a bare export is a SyntaxError in a classic script).
//   - `tooltip` is kept in both panes but never fires on the headless still frame; `emphasis.focus:
//     'adjacency'` is likewise inert without a hover, though both are declared verbatim.
// No JS closures in this example, so the native option carries every key the web pane does.
import Foundation

// The raw asset text, read ONCE, spliced into webOptionJS in place of the `$.get` fetch.
private let sankeyNodeAlignLeftJSONText: String = {
    let url = Upstream.repoRoot.appendingPathComponent("assets/data/energy.json")
    return (try? String(contentsOf: url, encoding: .utf8)) ?? #"{"nodes":[],"links":[]}"#
}()

// The SAME text, parsed for the native pane (so both panes provably see the same bytes). A parse
// failure degrades to an empty graph (blank pane, no crash).
private let sankeyNodeAlignLeftJSON: [String: Any] = {
    guard let data = sankeyNodeAlignLeftJSONText.data(using: .utf8),
          let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
        return ["nodes": [] as [Any], "links": [] as [Any]]
    }
    return obj
}()

// data.nodes — [{ name }], 48 entries.
private let sankeyNodeAlignLeftNodes: [[String: Any]] = (sankeyNodeAlignLeftJSON["nodes"] as? [[String: Any]]) ?? []
// data.links — [{ source, target, value }], 68 entries.
private let sankeyNodeAlignLeftLinks: [[String: Any]] = (sankeyNodeAlignLeftJSON["links"] as? [[String: Any]]) ?? []

extension EChartsDemoRegistry {
    static let official_sankey_nodealign_left = EChartsDemo(
        name: "official-sankey-nodeAlign-left", category: "sankey",
        summary: "桑基图左对齐布局 — Node Align Left in Sankey",
        width: 720, height: 460,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
var data = \#(sankeyNodeAlignLeftJSONText);

myChart.showLoading();
myChart.hideLoading();

myChart.setOption(
  (option = {
    title: {
      text: 'Node Align Left'
    },
    tooltip: {
      trigger: 'item',
      triggerOn: 'mousemove'
    },
    series: [
      {
        type: 'sankey',
        emphasis: {
          focus: 'adjacency'
        },
        nodeAlign: 'left',
        data: data.nodes,
        links: data.links,
        lineStyle: {
          color: 'source',
          curveness: 0.5
        }
      }
    ]
  })
);
"""#,
        option: [
            "title": [
                "text": "Node Align Left"
            ] as [String: Any],
            "tooltip": [
                "trigger": "item",
                "triggerOn": "mousemove"
            ] as [String: Any],
            "series": [
                [
                    "type": "sankey",
                    "emphasis": [
                        "focus": "adjacency"
                    ] as [String: Any],
                    "nodeAlign": "left",
                    "data": sankeyNodeAlignLeftNodes as [Any],
                    "links": sankeyNodeAlignLeftLinks as [Any],
                    "lineStyle": [
                        "color": "source",
                        "curveness": 0.5
                    ] as [String: Any]
                ] as [String: Any]
            ]
        ])
}
