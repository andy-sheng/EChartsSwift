// official-sankey-energy — replica of https://echarts.apache.org/examples/zh/editor.html?c=sankey-energy
// title: Gradient Edge / titleCN: 桑基图渐变色边
// A UK-energy-flow sankey (48 nodes, 68 links) whose ribbons take `lineStyle.color: 'gradient'` —
// each link fades from its source node's colour to its target's — with curveness 0.5 and
// `emphasis.focus: 'adjacency'`.
//
// DEVIATIONS from the official source:
//   - DATA INLINED. Upstream wraps the whole option in `$.get(ROOT_PATH + '/data/asset/data/energy.json',
//     function (data) { ... })`; the demo page has no network, so the asset is mirrored at
//     assets/data/energy.json (read via Upstream.repoRoot) and spliced into the web pane verbatim as
//     `var data = {...}`. The callback body is otherwise unchanged and `option` is assigned at top level.
//   - `myChart.showLoading()` / `hideLoading()` and the trailing `export {}` are dropped (harness-only).
//   - `tooltip` is kept in both panes but never fires: the gallery snapshots one static, hover-free
//     frame, so `emphasis.focus: 'adjacency'` is likewise inert (it is still declared, verbatim).
// No JS closures in this example, so the native option carries every key the web pane does.
import Foundation

// The raw asset text, read ONCE, spliced into webOptionJS in place of the `$.get` fetch.
private let sankeyEnergyJSONText: String = {
    let url = Upstream.repoRoot.appendingPathComponent("assets/data/energy.json")
    return (try? String(contentsOf: url, encoding: .utf8)) ?? #"{"nodes":[],"links":[]}"#
}()

// The SAME text, parsed for the native pane (so both panes provably see the same bytes). A parse
// failure degrades to an empty graph (blank pane, no crash).
private let sankeyEnergyJSON: [String: Any] = {
    guard let data = sankeyEnergyJSONText.data(using: .utf8),
          let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
        return ["nodes": [] as [Any], "links": [] as [Any]]
    }
    return obj
}()

// data.nodes — [{ name }], 48 entries.
private let sankeyEnergyNodes: [[String: Any]] = (sankeyEnergyJSON["nodes"] as? [[String: Any]]) ?? []
// data.links — [{ source, target, value }], 68 entries.
private let sankeyEnergyLinks: [[String: Any]] = (sankeyEnergyJSON["links"] as? [[String: Any]]) ?? []

extension EChartsDemoRegistry {
    static let official_sankey_energy = EChartsDemo(
        name: "official-sankey-energy", category: "sankey",
        summary: "桑基图渐变色边 — Gradient Edge",
        width: 720, height: 460,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
var data = \#(sankeyEnergyJSONText);

option = {
  title: {
    text: 'Sankey Diagram'
  },
  tooltip: {
    trigger: 'item',
    triggerOn: 'mousemove'
  },
  series: [
    {
      type: 'sankey',
      data: data.nodes,
      links: data.links,
      emphasis: {
        focus: 'adjacency'
      },
      lineStyle: {
        color: 'gradient',
        curveness: 0.5
      }
    }
  ]
};
"""#,
        option: [
            "title": [
                "text": "Sankey Diagram"
            ] as [String: Any],
            "tooltip": [
                "trigger": "item",
                "triggerOn": "mousemove"
            ] as [String: Any],
            "series": [
                [
                    "type": "sankey",
                    "data": sankeyEnergyNodes as [Any],
                    "links": sankeyEnergyLinks as [Any],
                    "emphasis": [
                        "focus": "adjacency"
                    ] as [String: Any],
                    "lineStyle": [
                        "color": "gradient",
                        "curveness": 0.5
                    ] as [String: Any]
                ] as [String: Any]
            ]
        ])
}
