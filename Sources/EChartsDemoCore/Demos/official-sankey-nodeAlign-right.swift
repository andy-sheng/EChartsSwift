// official-sankey-nodeAlign-right — replica of https://echarts.apache.org/examples/zh/editor.html?c=sankey-nodeAlign-right
// title: Node Align Right in Sankey / titleCN: 桑基图右对齐布局
// The same UK-energy-flow graph as sankey-energy (48 nodes, 68 links), laid out with
// `nodeAlign: 'right'` — leaf/terminal nodes are pushed to the right edge instead of ECharts'
// default `justify` — with `lineStyle.color: 'source'` (each ribbon takes its SOURCE node's colour),
// curveness 0.5, `emphasis.focus: 'adjacency'` and `animation: false`.
//
// DEVIATIONS from the official source:
//   - DATA INLINED. Upstream wraps the whole option in `$.get(ROOT_PATH + '/data/asset/data/energy.json',
//     function (data) { ... })`; the demo page has no network, so the asset is mirrored at
//     assets/data/energy.json (read via Upstream.repoRoot) and spliced into the web pane verbatim as
//     `var data = {...}`. The callback body is otherwise unchanged and runs at top level, so the
//     example's own `myChart.setOption((option = {...}))` is what applies the option — as upstream.
//   - `myChart.showLoading()` / `hideLoading()` are KEPT verbatim but are a no-op here: with the fetch
//     gone there is no async gap between them, so no loading layer is ever painted.
//   - The trailing `export {};` is dropped (a bare export is a SyntaxError in a classic script).
//   - `tooltip` is declared verbatim in both panes but never fires: the gallery snapshots one static,
//     hover-free frame, so `emphasis.focus: 'adjacency'` is likewise inert (still declared).
// No JS closures in this example, so the native option carries every key the web pane does.
import Foundation

// The raw asset text, read ONCE, spliced into webOptionJS in place of the `$.get` fetch.
private let sankeyNodeAlignRightJSONText: String = {
    let url = Upstream.repoRoot.appendingPathComponent("assets/data/energy.json")
    return (try? String(contentsOf: url, encoding: .utf8)) ?? #"{"nodes":[],"links":[]}"#
}()

// The SAME text, parsed for the native pane (so both panes provably see the same bytes). A parse
// failure degrades to an empty graph (blank pane, no crash).
private let sankeyNodeAlignRightJSON: [String: Any] = {
    guard let data = sankeyNodeAlignRightJSONText.data(using: .utf8),
          let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
        return ["nodes": [] as [Any], "links": [] as [Any]]
    }
    return obj
}()

// data.nodes — [{ name }], 48 entries.
private let sankeyNodeAlignRightNodes: [[String: Any]] =
    (sankeyNodeAlignRightJSON["nodes"] as? [[String: Any]]) ?? []
// data.links — [{ source, target, value }], 68 entries.
private let sankeyNodeAlignRightLinks: [[String: Any]] =
    (sankeyNodeAlignRightJSON["links"] as? [[String: Any]]) ?? []

extension EChartsDemoRegistry {
    static let official_sankey_nodealign_right = EChartsDemo(
        name: "official-sankey-nodeAlign-right", category: "sankey",
        summary: "桑基图右对齐布局 — Node Align Right in Sankey",
        width: 720, height: 460,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
var data = \#(sankeyNodeAlignRightJSONText);

myChart.showLoading();
myChart.hideLoading();

myChart.setOption(
  (option = {
    title: {
      text: 'Node Align Right'
    },
    tooltip: {
      trigger: 'item',
      triggerOn: 'mousemove'
    },
    animation: false,
    series: [
      {
        type: 'sankey',
        emphasis: {
          focus: 'adjacency'
        },
        nodeAlign: 'right',
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
                "text": "Node Align Right"
            ] as [String: Any],
            "tooltip": [
                "trigger": "item",
                "triggerOn": "mousemove"
            ] as [String: Any],
            "animation": false,
            "series": [
                [
                    "type": "sankey",
                    "emphasis": [
                        "focus": "adjacency"
                    ] as [String: Any],
                    "nodeAlign": "right",
                    "data": sankeyNodeAlignRightNodes as [Any],
                    "links": sankeyNodeAlignRightLinks as [Any],
                    "lineStyle": [
                        "color": "source",
                        "curveness": 0.5
                    ] as [String: Any]
                ] as [String: Any]
            ]
        ])
}
