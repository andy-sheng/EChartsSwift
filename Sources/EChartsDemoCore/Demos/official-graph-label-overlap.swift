// official-graph-label-overlap — replica of https://echarts.apache.org/examples/zh/editor.html?c=graph-label-overlap
// title: Hide Overlapped Label / titleCN: 关系图自动隐藏重叠标签
// The 77-character / 254-link Les Miserables co-occurrence graph drawn at the coordinates baked into
// the asset (`layout: 'none'` — each node's own x/y), EVERY node labelled (`label.show: true`) and the
// crowding resolved by `labelLayout: { hideOverlap: true }`: labels whose boxes collide are dropped,
// so only a non-overlapping subset survives. Nodes are coloured by their community `category`
// (9 legend entries) and links are tinted by their source node (`lineStyle.color: 'source'`).
//
// DEVIATIONS from the official source:
//   - DATA: the example does `myChart.showLoading(); $.getJSON(ROOT_PATH + '/data/asset/data/
//     les-miserables.json', function (graph) { ... })` and builds the option inside the callback. The
//     page has no network, so the asset is vendored at assets/data/les-miserables.json and INLINED:
//     the web pane splices the raw JSON text in as `var graph = {...}` and then runs the callback body
//     VERBATIM at the top level — the `graph.categories.map(...)` legend data and the closing
//     `myChart.setOption(option)` still execute as the example wrote them. `showLoading()` /
//     `hideLoading()` are kept (they now bracket nothing, since the fetch is gone). The native pane
//     does the same `map` in Swift below.
//   - TS: the `(a: { name: string })` parameter annotation and the trailing `export {}` module marker
//     are dropped — the reference pane is a classic script, not TypeScript. Everything else in
//     webOptionJS is byte-identical to upstream.
//   - `roam` / `scaleLimit` are carried by BOTH panes but are pure interaction (pan/zoom bounds), so
//     they draw nothing in a still frame — and GraphView's RoamController is a documented port
//     deferral anyway.
//   - `tooltip: {}` is carried by both panes; it only shows on hover, so it draws nothing here.
//   - No timers, no dispatchAction: the example is static once the data lands, so there is no `drive`.
import Foundation

// The raw asset text, spliced into the web pane so the example's own `map` closure runs on it.
private let graphLabelOverlapJSONText: String = {
    let url = Upstream.repoRoot.appendingPathComponent("assets/data/les-miserables.json")
    return (try? String(contentsOf: url, encoding: .utf8)) ?? #"{"nodes":[],"links":[],"categories":[]}"#
}()

// The same asset, parsed for the native pane. A parse failure degrades to an empty graph (blank pane)
// rather than a crash.
private let graphLabelOverlapJSON: [String: Any] = {
    guard let data = graphLabelOverlapJSONText.data(using: .utf8),
          let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
        return ["nodes": [] as [Any], "links": [] as [Any], "categories": [] as [Any]]
    }
    return obj
}()

// Unlike graph-circular-layout, this example touches the nodes NOT AT ALL — `data: graph.nodes` is the
// raw asset (id / name / symbolSize / x / y / value / category); the labels are governed entirely by
// series.label + series.labelLayout.
private let graphLabelOverlapNodes: [[String: Any]] = (graphLabelOverlapJSON["nodes"] as? [[String: Any]]) ?? []

private let graphLabelOverlapLinks: [[String: Any]] = (graphLabelOverlapJSON["links"] as? [[String: Any]]) ?? []

private let graphLabelOverlapCategories: [[String: Any]] = (graphLabelOverlapJSON["categories"] as? [[String: Any]]) ?? []

// legend[0].data = graph.categories.map(a => a.name)
private let graphLabelOverlapLegendData: [String] = graphLabelOverlapCategories.map { ($0["name"] as? String) ?? "" }

extension EChartsDemoRegistry {
    static let official_graph_label_overlap = EChartsDemo(
        name: "official-graph-label-overlap", category: "graph",
        summary: "关系图自动隐藏重叠标签 — Hide Overlapped Label",
        width: 720, height: 460,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
var graph = \#(graphLabelOverlapJSONText);

myChart.showLoading();
myChart.hideLoading();

option = {
  tooltip: {},
  legend: [
    {
      data: graph.categories.map(function (a) {
        return a.name;
      })
    }
  ],
  series: [
    {
      name: 'Les Miserables',
      type: 'graph',
      layout: 'none',
      data: graph.nodes,
      links: graph.links,
      categories: graph.categories,
      roam: true,
      label: {
        show: true,
        position: 'right',
        formatter: '{b}'
      },
      labelLayout: {
        hideOverlap: true
      },
      scaleLimit: {
        min: 0.4,
        max: 2
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
            "tooltip": [:] as [String: Any],
            "legend": [
                [
                    "data": graphLabelOverlapLegendData
                ] as [String: Any]
            ],
            "series": [
                [
                    "name": "Les Miserables",
                    "type": "graph",
                    "layout": "none",
                    "data": graphLabelOverlapNodes as [Any],
                    "links": graphLabelOverlapLinks as [Any],
                    "categories": graphLabelOverlapCategories as [Any],
                    "roam": true,
                    "label": [
                        "show": true,
                        "position": "right",
                        "formatter": "{b}"
                    ] as [String: Any],
                    "labelLayout": [
                        "hideOverlap": true
                    ] as [String: Any],
                    "scaleLimit": [
                        "min": 0.4,
                        "max": 2.0
                    ] as [String: Any],
                    "lineStyle": [
                        "color": "source",
                        "curveness": 0.3
                    ] as [String: Any]
                ] as [String: Any]
            ]
        ])
}
