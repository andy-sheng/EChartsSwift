// official-graph-force — replica of https://echarts.apache.org/examples/zh/editor.html?c=graph-force
// title: Force Layout / titleCN: 力引导布局
// The 77-character / 254-link Les Miserables co-occurrence graph run through the FORCE layout
// (`layout: 'force'`, `force: { repulsion: 100 }`), every node flattened to `symbolSize: 5` and
// coloured by its community `category` (9 legend entries). The asset's per-node `x`/`y` survive the
// forEach, so — with no `force.initLayout` set — both engines seed the simulation from them
// (forceLayout.ts: `!initLayout` -> simpleLayout), i.e. the layout starts from the SAME state on both
// panes rather than from a random cloud (which is what graph-force2 has to live with).
//
// DEVIATIONS from the official source:
//   - DATA: the example does `myChart.showLoading(); $.get(ROOT_PATH + '/data/asset/data/
//     les-miserables.json', function (graph) { ... })` and builds the option inside the callback. The
//     page has no network, so the asset is vendored at assets/data/les-miserables.json and INLINED: the
//     web pane splices the raw JSON text in as `var graph = {...}` and then runs the callback BODY
//     VERBATIM at the top level — the `graph.nodes.forEach(...)` symbolSize pass, the
//     `graph.categories.map(...)` legend data and the closing `myChart.setOption(option)` all still
//     execute as the example wrote them. `showLoading()` / `hideLoading()` are kept (they now bracket
//     nothing, since the fetch is gone). The native pane does the same forEach / map in Swift below.
//   - TS: the `GraphNode` interface, the `(node: GraphNode)` / `(a: { name: string })` parameter
//     annotations and the trailing `export {};` module marker are dropped — the reference pane is a
//     classic script, not TypeScript. Everything else in webOptionJS is byte-identical to upstream.
//   - No `drive`: the example never schedules a timer and never re-setOptions. The settling you see in
//     the browser is echarts' OWN per-frame layout iteration (GraphView + `force.layoutAnimation`), not
//     example code — there is no timeline to reproduce.
//   - SETTLING (expect a pane diff, do not "fix" it here): the web pane animates the force simulation
//     frame by frame from the asset's x/y, so at any given instant it shows an INTERMEDIATE state; the
//     native still-frame render instead runs the simulation synchronously to completion
//     (`graphForceLayout`, 1500-iteration cap) and draws the SETTLED graph. Same seed, same topology,
//     different point on the same trajectory.
//   - `roam: true` is carried by both panes but is inert natively — GraphView.swift does not wire a
//     RoamController (documented deferral; the infra is ported).
//   - `label: { position: 'right' }` is carried by both panes; graph `label.show` defaults false, so no
//     node labels are drawn on either. `tooltip: {}` likewise only shows on hover.
import Foundation

// The raw asset text, spliced into the web pane so the example's own forEach/map closures run on it.
private let graphForceJSONText: String = {
    let url = Upstream.repoRoot.appendingPathComponent("assets/data/les-miserables.json")
    return (try? String(contentsOf: url, encoding: .utf8)) ?? #"{"nodes":[],"links":[],"categories":[]}"#
}()

// The same asset, parsed for the native pane. A parse failure degrades to an empty graph (blank pane)
// rather than a crash.
private let graphForceJSON: [String: Any] = {
    guard let data = graphForceJSONText.data(using: .utf8),
          let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
        return ["nodes": [] as [Any], "links": [] as [Any], "categories": [] as [Any]]
    }
    return obj
}()

// graph.nodes.forEach(node => { node.symbolSize = 5; })
// — the asset's own symbolSize (a per-character weight, 6..80) is OVERWRITTEN with a flat 5; every other
// key of the raw node (id / name / x / y / value / category) is kept as-is, x/y included: they seed the
// force simulation.
private let graphForceNodes: [[String: Any]] = {
    let raw = (graphForceJSON["nodes"] as? [[String: Any]]) ?? []
    return raw.map { node in
        var n = node
        n["symbolSize"] = 5.0
        return n
    }
}()

private let graphForceLinks: [[String: Any]] = (graphForceJSON["links"] as? [[String: Any]]) ?? []

private let graphForceCategories: [[String: Any]] = (graphForceJSON["categories"] as? [[String: Any]]) ?? []

// legend[0].data = graph.categories.map(a => a.name)
private let graphForceLegendData: [String] = graphForceCategories.map { ($0["name"] as? String) ?? "" }

extension EChartsDemoRegistry {
    static let official_graph_force = EChartsDemo(
        name: "official-graph-force", category: "graph",
        summary: "力引导布局 — Force Layout",
        width: 720, height: 460,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
var graph = \#(graphForceJSONText);

myChart.showLoading();
myChart.hideLoading();

graph.nodes.forEach(function (node) {
  node.symbolSize = 5;
});

option = {
  title: {
    text: 'Les Miserables',
    subtext: 'Default layout',
    top: 'bottom',
    left: 'right'
  },
  tooltip: {},
  legend: [
    {
      // selectedMode: 'single',
      data: graph.categories.map(function (a) {
        return a.name;
      })
    }
  ],
  series: [
    {
      name: 'Les Miserables',
      type: 'graph',
      layout: 'force',
      data: graph.nodes,
      links: graph.links,
      categories: graph.categories,
      roam: true,
      label: {
        position: 'right'
      },
      force: {
        repulsion: 100
      }
    }
  ]
};

myChart.setOption(option);
"""#,
        option: [
            "title": [
                "text": "Les Miserables",
                "subtext": "Default layout",
                "top": "bottom",
                "left": "right"
            ] as [String: Any],
            "tooltip": [:] as [String: Any],
            "legend": [
                [
                    // upstream leaves `selectedMode: 'single'` commented out; kept commented here too.
                    "data": graphForceLegendData
                ] as [String: Any]
            ],
            "series": [
                [
                    "name": "Les Miserables",
                    "type": "graph",
                    "layout": "force",
                    "data": graphForceNodes as [Any],
                    "links": graphForceLinks as [Any],
                    "categories": graphForceCategories as [Any],
                    "roam": true,
                    "label": [
                        "position": "right"
                    ] as [String: Any],
                    "force": [
                        "repulsion": 100.0
                    ] as [String: Any]
                ] as [String: Any]
            ]
        ])
}
