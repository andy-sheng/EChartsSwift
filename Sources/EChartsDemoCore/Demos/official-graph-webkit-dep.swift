// official-graph-webkit-dep — replica of https://echarts.apache.org/examples/zh/editor.html?c=graph-webkit-dep
// title: Graph Webkit Dep / titleCN: WebKit 模块关系依赖图
// A 492-node / 806-edge `graph` series laid out with `layout: 'force'` (edgeLength 5, repulsion 20,
// gravity 0.2): every WebKit IDL interface is a node, coloured by one of the 5 categories
// (HTMLElement / WebGL / SVG / CSS / Other) the legend selects, and every `source`/`target` pair in
// the asset (numeric NODE INDICES, which echarts' Graph.addEdge resolves positionally) is an edge.
//
// DEVIATIONS from the official source:
//   - DATA: the example fetches `$.get(ROOT_PATH + '/data/asset/data/webkit-dep.json', function (webkitDep) {...})`
//     and builds the option inside the callback. The page has no network, so the asset is vendored at
//     assets/data/webkit-dep.json and INLINED: the web pane splices the raw JSON text in as
//     `var webkitDep = {...}` and then runs the callback's BODY verbatim at the top level — including
//     the `webkitDep.nodes.map(function (node, idx) { node.id = idx; return node; })` closure, the
//     `myChart.showLoading()` / `hideLoading()` pair and the closing `myChart.setOption(option)`. The
//     native pane does the same id-stamping mapping in Swift below.
//   - TS: the `(node: any, idx: number)` parameter annotations and the trailing `export {}` module
//     marker are dropped — the reference pane is a classic script, not TypeScript. Everything else in
//     webOptionJS is byte-identical to upstream (the duplicated `myChart.showLoading();` included).
//   - LAYOUT: `layout: 'force'` is a physics simulation, so the two panes CANNOT match node-for-node.
//     The web pane starts from echarts' random initial positions and iterates one step per animation
//     frame; EChartsKit's GraphView does not drive that frame loop (documented deferral), so its
//     forceLayout stage instead runs the simulation to convergence inside the layout stage. Both panes
//     therefore show a settled force graph — of the same 492 nodes and 806 edges, at different
//     positions. Expect that pane diff; it is the layout, not the data.
//   - `thumbnail` is carried by BOTH panes, but only the web pane draws the minimap: EChartsKit's
//     Thumbnail component is not ported yet (GraphView.swift `_renderThumbnail` is a documented
//     deferral), so the native pane silently ignores the key.
//   - `roam` / `roamTrigger` / `scaleLimit` / `draggable` are kept verbatim but are inert in the
//     gallery: both panes render a still frame, and GraphView's RoamController is a documented deferral.
import Foundation

// The raw asset text, spliced into the web pane so the example's own map() closure runs on it.
private let webkitDepJSONText: String = {
    let url = Upstream.repoRoot.appendingPathComponent("assets/data/webkit-dep.json")
    return (try? String(contentsOf: url, encoding: .utf8))
        ?? #"{"nodes":[],"links":[],"categories":[]}"#
}()

// The same asset, parsed for the native pane. A parse failure degrades to an empty graph (blank pane)
// rather than a crash.
private let webkitDepJSON: [String: Any] = {
    guard let data = webkitDepJSONText.data(using: .utf8),
          let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
        return ["nodes": [] as [Any], "links": [] as [Any], "categories": [] as [Any]]
    }
    return obj
}()

// webkitDep.nodes.map(function (node, idx) { node.id = idx; return node; })
// Each raw node is `{ name, value, category }`; the example stamps its index on as `id` (a NUMBER —
// jsPlus stringifies it to "0", "1", ... exactly as JS does, so the ids stay index-aligned).
private let webkitDepNodes: [[String: Any]] = {
    let raw = (webkitDepJSON["nodes"] as? [[String: Any]]) ?? []
    return raw.enumerated().map { idx, node in
        [
            "id": Double(idx),
            "name": (node["name"] as? String) ?? "",
            "value": (node["value"] as? Double) ?? 0.0,
            "category": (node["category"] as? Double) ?? 0.0
        ] as [String: Any]
    }
}()

// webkitDep.links — `{ source, target }`, both numeric NODE INDICES.
private let webkitDepLinks: [[String: Any]] = {
    let raw = (webkitDepJSON["links"] as? [[String: Any]]) ?? []
    return raw.map { link in
        [
            "source": (link["source"] as? Double) ?? 0.0,
            "target": (link["target"] as? Double) ?? 0.0
        ] as [String: Any]
    }
}()

// webkitDep.categories — `{ name, keyword, base }`; the 5 names the legend selects on.
private let webkitDepCategories: [[String: Any]] = {
    return (webkitDepJSON["categories"] as? [[String: Any]]) ?? []
}()

extension EChartsDemoRegistry {
    static let official_graph_webkit_dep = EChartsDemo(
        name: "official-graph-webkit-dep", category: "graph",
        summary: "WebKit 模块关系依赖图 — Graph Webkit Dep",
        width: 720, height: 460,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
var webkitDep = \#(webkitDepJSONText);

myChart.showLoading();

myChart.showLoading();
myChart.hideLoading();

option = {
  legend: {
    data: ['HTMLElement', 'WebGL', 'SVG', 'CSS', 'Other']
  },
  series: [
    {
      type: 'graph',
      layout: 'force',
      animation: false,
      roam: true,
      roamTrigger: 'global',
      scaleLimit: {
        max: 8,
        min: 0.5
      },
      label: {
        position: 'right',
        formatter: '{b}'
      },
      draggable: true,
      data: webkitDep.nodes.map(function (node, idx) {
        node.id = idx;
        return node;
      }),
      categories: webkitDep.categories,
      force: {
        edgeLength: 5,
        repulsion: 20,
        gravity: 0.2
      },
      edges: webkitDep.links
    }
  ],
  thumbnail: {
    width: '15%',
    height: '15%',
    windowStyle: {
      color: 'rgba(140, 212, 250, 0.5)',
      borderColor: 'rgba(30, 64, 175, 0.7)',
      opacity: 1,
    }
  }
};

myChart.setOption(option);
"""#,
        option: [
            "legend": [
                "data": ["HTMLElement", "WebGL", "SVG", "CSS", "Other"]
            ] as [String: Any],
            "series": [
                [
                    "type": "graph",
                    "layout": "force",
                    "animation": false,
                    "roam": true,
                    "roamTrigger": "global",
                    "scaleLimit": [
                        "max": 8.0,
                        "min": 0.5
                    ] as [String: Any],
                    "label": [
                        "position": "right",
                        // '{b}' is a STRING template (the node name), not a JS closure — it ports as-is.
                        "formatter": "{b}"
                    ] as [String: Any],
                    "draggable": true,
                    "data": webkitDepNodes as [Any],
                    "categories": webkitDepCategories as [Any],
                    "force": [
                        "edgeLength": 5.0,
                        "repulsion": 20.0,
                        "gravity": 0.2
                    ] as [String: Any],
                    "edges": webkitDepLinks as [Any]
                ] as [String: Any]
            ],
            // PORT-NOTE: `thumbnail` is kept verbatim, but EChartsKit has no Thumbnail component yet
            // (deferred in GraphView.swift), so the native pane ignores it — web draws a minimap, native does not.
            "thumbnail": [
                "width": "15%",
                "height": "15%",
                "windowStyle": [
                    "color": "rgba(140, 212, 250, 0.5)",
                    "borderColor": "rgba(30, 64, 175, 0.7)",
                    "opacity": 1.0
                ] as [String: Any]
            ] as [String: Any]
        ])
}
