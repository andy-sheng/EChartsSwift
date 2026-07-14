// official-graph-circular-layout — replica of https://echarts.apache.org/examples/zh/editor.html?c=graph-circular-layout
// title: Les Miserables / titleCN: 悲惨世界人物关系图(环形布局)
// The 77-character / 254-link Les Miserables co-occurrence graph laid out on a circle
// (`layout: 'circular'` + `circular.rotateLabel`), nodes coloured by their community `category`
// (9 legend entries) and links tinted by their source node (`lineStyle.color: 'source'`).
//
// DEVIATIONS from the official source:
//   - DATA: the example does `myChart.showLoading(); $.getJSON(ROOT_PATH + '/data/asset/data/
//     les-miserables.json', function (graph) { ... })` and builds the option inside the callback. The
//     page has no network, so the asset is vendored at assets/data/les-miserables.json and INLINED:
//     the web pane splices the raw JSON text in as `var graph = {...}` and then runs the callback body
//     VERBATIM at the top level — the `graph.nodes.forEach(...)` label pass, the
//     `graph.categories.map(...)` legend data and the closing `myChart.setOption(option)` all still
//     execute as the example wrote them. `showLoading()` / `hideLoading()` are kept (they now bracket
//     nothing, since the fetch is gone). The native pane does the same `forEach` / `map` in Swift below.
//   - TS: the `GraphNode` interface, the `(node: GraphNode)` / `(a: { name: string })` parameter
//     annotations and the trailing `export {}` module marker are dropped — the reference pane is a
//     classic script, not TypeScript. Everything else in webOptionJS is byte-identical to upstream.
//   - `circular: { rotateLabel: true }` is carried by BOTH panes, but only the WEB pane rotates the
//     labels: it is applied in echarts' GraphView render pass (`rotateNodeLabel`), and EChartsKit's
//     GraphView.swift leaves that call out (`// rotateNodeLabel(node, circularRotateLabel, cx, cy);`
//     — a documented deferral; the helper IS ported, but only the node-drag path calls it). So the
//     native pane draws the 5 visible labels horizontally where the web pane lays them out radially.
//     Expect that pane diff; the layout of the nodes themselves is unaffected.
//   - `roam` / `animationDurationUpdate` / `animationEasingUpdate` are carried by both panes but are
//     inert in a still frame (roam is interaction — and GraphView's RoamController is a documented
//     deferral anyway; the update animation only fires on a re-setOption).
//   - `tooltip: {}` is carried by both panes; it only shows on hover, so it draws nothing here.
import Foundation

// The raw asset text, spliced into the web pane so the example's own forEach/map closures run on it.
private let lesMiserablesJSONText: String = {
    let url = Upstream.repoRoot.appendingPathComponent("assets/data/les-miserables.json")
    return (try? String(contentsOf: url, encoding: .utf8)) ?? #"{"nodes":[],"links":[],"categories":[]}"#
}()

// The same asset, parsed for the native pane. A parse failure degrades to an empty graph (blank pane)
// rather than a crash.
private let lesMiserablesJSON: [String: Any] = {
    guard let data = lesMiserablesJSONText.data(using: .utf8),
          let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
        return ["nodes": [] as [Any], "links": [] as [Any], "categories": [] as [Any]]
    }
    return obj
}()

// graph.nodes.forEach(node => { node.label = { show: node.symbolSize > 30 }; })
// — every other key of the raw node (id / name / symbolSize / x / y / value / category) is kept as-is.
private let lesMiserablesNodes: [[String: Any]] = {
    let raw = (lesMiserablesJSON["nodes"] as? [[String: Any]]) ?? []
    return raw.map { node in
        var n = node
        n["label"] = ["show": ((node["symbolSize"] as? Double) ?? 0) > 30] as [String: Any]
        return n
    }
}()

private let lesMiserablesLinks: [[String: Any]] = (lesMiserablesJSON["links"] as? [[String: Any]]) ?? []

private let lesMiserablesCategories: [[String: Any]] = (lesMiserablesJSON["categories"] as? [[String: Any]]) ?? []

// legend[0].data = graph.categories.map(a => a.name)
private let lesMiserablesLegendData: [String] = lesMiserablesCategories.map { ($0["name"] as? String) ?? "" }

extension EChartsDemoRegistry {
    static let official_graph_circular_layout = EChartsDemo(
        name: "official-graph-circular-layout", category: "graph",
        summary: "悲惨世界人物关系图(环形布局) — Les Miserables",
        width: 900, height: 560,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
var graph = \#(lesMiserablesJSONText);

myChart.showLoading();
myChart.hideLoading();

graph.nodes.forEach(function (node) {
  node.label = {
    show: node.symbolSize > 30
  };
});

option = {
  title: {
    text: 'Les Miserables',
    subtext: 'Circular layout',
    top: 'bottom',
    left: 'right'
  },
  tooltip: {},
  legend: [
    {
      data: graph.categories.map(function (a) {
        return a.name;
      })
    }
  ],
  animationDurationUpdate: 1500,
  animationEasingUpdate: 'quinticInOut',
  series: [
    {
      name: 'Les Miserables',
      type: 'graph',
      layout: 'circular',
      circular: {
        rotateLabel: true
      },
      data: graph.nodes,
      links: graph.links,
      categories: graph.categories,
      roam: true,
      label: {
        position: 'right',
        formatter: '{b}'
      },
      lineStyle: {
        color: 'source',
        curveness: 0.3
      }
    }
  ]
};

myChart.setOption(option);
"""#,
        option: [
            "title": [
                "text": "Les Miserables",
                "subtext": "Circular layout",
                "top": "bottom",
                "left": "right"
            ] as [String: Any],
            "tooltip": [:] as [String: Any],
            "legend": [
                [
                    "data": lesMiserablesLegendData
                ] as [String: Any]
            ],
            "animationDurationUpdate": 1500.0,
            "animationEasingUpdate": "quinticInOut",
            "series": [
                [
                    "name": "Les Miserables",
                    "type": "graph",
                    "layout": "circular",
                    "circular": [
                        "rotateLabel": true
                    ] as [String: Any],
                    "data": lesMiserablesNodes as [Any],
                    "links": lesMiserablesLinks as [Any],
                    "categories": lesMiserablesCategories as [Any],
                    "roam": true,
                    "label": [
                        "position": "right",
                        "formatter": "{b}"
                    ] as [String: Any],
                    "lineStyle": [
                        "color": "source",
                        "curveness": 0.3
                    ] as [String: Any]
                ] as [String: Any]
            ]
        ])
}
