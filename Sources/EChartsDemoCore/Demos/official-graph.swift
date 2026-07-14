// official-graph — replica of https://echarts.apache.org/examples/zh/editor.html?c=graph
// title: Les Miserables / titleCN: 悲惨世界人物关系图
// The 77-character / 254-link Les Miserables co-occurrence graph drawn with `layout: 'none'` — every
// node sits at the x/y baked into the asset (the "Default layout"), coloured by its community
// `category` (9 legend entries), links tinted by their source node (`lineStyle.color: 'source'`,
// `curveness: 0.3`), and only the 5 nodes with `symbolSize > 30` labelled.
//
// DEVIATIONS from the official source:
//   - DATA: the example does `myChart.showLoading(); $.getJSON(ROOT_PATH + '/data/asset/data/
//     les-miserables.json', function (graph) { ... })` and builds the whole option inside the callback.
//     The page has no network, so the asset is vendored at assets/data/les-miserables.json and INLINED:
//     the web pane splices the raw JSON text in as `var graph = {...}` and then runs the callback body
//     VERBATIM at the top level — the `graph.nodes.forEach(...)` label pass, the
//     `graph.categories.map(...)` legend data and the closing `myChart.setOption(option)` all still
//     execute as the example wrote them. `showLoading()` / `hideLoading()` are kept (they now bracket
//     nothing, since the fetch is gone). The native pane does the same `forEach` / `map` in Swift below.
//   - TS: the `GraphNode` interface, the `(node: GraphNode)` / `(a: { name: string })` parameter
//     annotations and the trailing `export {}` module marker are dropped — the reference pane is a
//     classic script, not TypeScript. Everything else in webOptionJS is byte-identical to upstream,
//     including the commented-out `// selectedMode: 'single'` line inside legend[0].
//   - `roam` / `emphasis.focus: 'adjacency'` are carried by both panes but are pure INTERACTION
//     (hover / pan-zoom), so neither pane shows them in a still frame; `animationDuration` /
//     `animationEasingUpdate` are likewise inert once animation is off for the snapshot.
//   - `tooltip: {}` is carried by both panes; it only shows on hover, so it draws nothing here.
import Foundation

// The raw asset text, spliced into the web pane so the example's own forEach/map closures run on it.
private let officialGraphJSONText: String = {
    let url = Upstream.repoRoot.appendingPathComponent("assets/data/les-miserables.json")
    return (try? String(contentsOf: url, encoding: .utf8)) ?? #"{"nodes":[],"links":[],"categories":[]}"#
}()

// The same asset, parsed for the native pane. A parse failure degrades to an empty graph (blank pane)
// rather than a crash.
private let officialGraphJSON: [String: Any] = {
    guard let data = officialGraphJSONText.data(using: .utf8),
          let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
        return ["nodes": [] as [Any], "links": [] as [Any], "categories": [] as [Any]]
    }
    return obj
}()

// graph.nodes.forEach(node => { node.label = { show: node.symbolSize > 30 }; })
// — every other key of the raw node (id / name / symbolSize / x / y / value / category) is kept as-is;
// with `layout: 'none'` the x/y ARE the layout, so they must survive verbatim.
private let officialGraphNodes: [[String: Any]] = {
    let raw = (officialGraphJSON["nodes"] as? [[String: Any]]) ?? []
    return raw.map { node in
        var n = node
        n["label"] = ["show": ((node["symbolSize"] as? Double) ?? 0) > 30] as [String: Any]
        return n
    }
}()

private let officialGraphLinks: [[String: Any]] = (officialGraphJSON["links"] as? [[String: Any]]) ?? []

private let officialGraphCategories: [[String: Any]] = (officialGraphJSON["categories"] as? [[String: Any]]) ?? []

// legend[0].data = graph.categories.map(a => a.name)
private let officialGraphLegendData: [String] = officialGraphCategories.map { ($0["name"] as? String) ?? "" }

extension EChartsDemoRegistry {
    static let official_graph = EChartsDemo(
        name: "official-graph", category: "graph",
        summary: "悲惨世界人物关系图 — Les Miserables",
        width: 720, height: 460,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
var graph = \#(officialGraphJSONText);

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
  animationDuration: 1500,
  animationEasingUpdate: 'quinticInOut',
  series: [
    {
      name: 'Les Miserables',
      type: 'graph',
      legendHoverLink: false,
      layout: 'none',
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
      },
      emphasis: {
        focus: 'adjacency',
        lineStyle: {
          width: 10
        }
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
                    "data": officialGraphLegendData
                ] as [String: Any]
            ],
            "animationDuration": 1500.0,
            "animationEasingUpdate": "quinticInOut",
            "series": [
                [
                    "name": "Les Miserables",
                    "type": "graph",
                    "legendHoverLink": false,
                    "layout": "none",
                    "data": officialGraphNodes as [Any],
                    "links": officialGraphLinks as [Any],
                    "categories": officialGraphCategories as [Any],
                    "roam": true,
                    "label": [
                        "position": "right",
                        "formatter": "{b}"
                    ] as [String: Any],
                    "lineStyle": [
                        "color": "source",
                        "curveness": 0.3
                    ] as [String: Any],
                    "emphasis": [
                        "focus": "adjacency",
                        "lineStyle": [
                            "width": 10.0
                        ] as [String: Any]
                    ] as [String: Any]
                ] as [String: Any]
            ]
        ])
}
