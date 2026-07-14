// official-graph-npm — replica of https://echarts.apache.org/examples/zh/editor.html?c=graph-npm
// title: NPM Dependencies / titleCN: NPM 依赖关系图
// A 717-node / 942-edge `graph` series with `layout: 'none'` — every node carries its own pre-computed
// x/y (a Gephi-style force layout baked into the asset), its size and its community colour; the edges
// are drawn as thin, curved, semi-transparent links.
//
// DEVIATIONS from the official source:
//   - DATA: the example fetches `$.getJSON(ROOT_PATH + '/data/asset/data/npmdepgraph.min10.json')` and
//     builds the option inside the callback. The page has no network, so the asset is vendored at
//     assets/data/npmdepgraph.min10.json and INLINED: the web pane splices the raw JSON text in as
//     `var json = {...}` and then runs the example's `json.nodes.map(...)` / `json.edges.map(...)`
//     closures VERBATIM; the native pane does the same mapping in Swift below. `option` is assigned
//     unconditionally at the top level (no callback, no showLoading/hideLoading), so the callback's
//     `myChart.setOption(option, true)` becomes a bare `option = {...}` — the harness calls setOption
//     itself, and the `true` (notMerge) flag is a no-op on a chart that has no previous option.
//   - TS: the `RawNode` / `RawEdge` interfaces, the `(node: RawNode)` / `(edge: RawEdge)` parameter
//     annotations and the trailing `export {}` module marker are dropped — the reference pane is a
//     classic script, not TypeScript. Everything else in webOptionJS is byte-identical to upstream.
//   - `thumbnail` is carried by BOTH panes, but only the web pane draws the minimap: EChartsKit's
//     Thumbnail component is not ported yet (GraphView.swift `_renderThumbnail` is a documented
//     deferral), so the native pane silently ignores the key. Expect that pane diff.
//   - `roam` / `roamTrigger` / `animationDurationUpdate` / `animationEasingUpdate` are kept verbatim
//     but are inert here: the gallery renders one static frame with animation forced off.
import Foundation

// The raw asset text, spliced into the web pane so the example's own map() closures run on it.
private let npmDepGraphJSONText: String = {
    let url = Upstream.repoRoot.appendingPathComponent("assets/data/npmdepgraph.min10.json")
    return (try? String(contentsOf: url, encoding: .utf8)) ?? #"{"nodes":[],"edges":[]}"#
}()

// The same asset, parsed for the native pane. A parse failure degrades to an empty graph (blank pane)
// rather than a crash.
private let npmDepGraphJSON: [String: Any] = {
    guard let data = npmDepGraphJSONText.data(using: .utf8),
          let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
        return ["nodes": [] as [Any], "edges": [] as [Any]]
    }
    return obj
}()

// json.nodes.map(node => ({ x, y, id, name: node.label, symbolSize: node.size, itemStyle: { color } }))
private let npmDepGraphNodes: [[String: Any]] = {
    let raw = (npmDepGraphJSON["nodes"] as? [[String: Any]]) ?? []
    return raw.map { node in
        [
            "x": (node["x"] as? Double) ?? 0.0,
            "y": (node["y"] as? Double) ?? 0.0,
            "id": (node["id"] as? String) ?? "",
            "name": (node["label"] as? String) ?? "",
            "symbolSize": (node["size"] as? Double) ?? 0.0,
            "itemStyle": ["color": (node["color"] as? String) ?? "#000"] as [String: Any]
        ] as [String: Any]
    }
}()

// json.edges.map(edge => ({ source: edge.sourceID, target: edge.targetID }))
private let npmDepGraphEdges: [[String: Any]] = {
    let raw = (npmDepGraphJSON["edges"] as? [[String: Any]]) ?? []
    return raw.map { edge in
        [
            "source": (edge["sourceID"] as? String) ?? "",
            "target": (edge["targetID"] as? String) ?? ""
        ] as [String: Any]
    }
}()

extension EChartsDemoRegistry {
    static let official_graph_npm = EChartsDemo(
        name: "official-graph-npm", category: "graph",
        summary: "NPM 依赖关系图 — NPM Dependencies",
        width: 720, height: 460,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
var json = \#(npmDepGraphJSONText);
option = {
  title: {
    text: 'NPM Dependencies'
  },
  animationDurationUpdate: 1500,
  animationEasingUpdate: 'quinticInOut',
  series: [
    {
      type: 'graph',
      layout: 'none',
      // progressiveThreshold: 700,
      data: json.nodes.map(function (node) {
        return {
          x: node.x,
          y: node.y,
          id: node.id,
          name: node.label,
          symbolSize: node.size,
          itemStyle: {
            color: node.color
          }
        };
      }),
      edges: json.edges.map(function (edge) {
        return {
          source: edge.sourceID,
          target: edge.targetID
        };
      }),
      emphasis: {
        focus: 'adjacency',
        label: {
          position: 'right',
          show: true
        }
      },
      roam: true,
      roamTrigger: 'global',
      lineStyle: {
        width: 0.5,
        curveness: 0.3,
        opacity: 0.7
      }
    }
  ],
  thumbnail: {
    width: '20%',
    height: '20%',
    windowStyle: {
      color: 'rgba(140, 212, 250, 0.5)',
      borderColor: 'rgba(30, 64, 175, 0.7)',
      opacity: 1,
    }
  }
};
"""#,
        option: [
            "title": [
                "text": "NPM Dependencies"
            ] as [String: Any],
            "animationDurationUpdate": 1500.0,
            "animationEasingUpdate": "quinticInOut",
            "series": [
                [
                    "type": "graph",
                    "layout": "none",
                    "data": npmDepGraphNodes as [Any],
                    "edges": npmDepGraphEdges as [Any],
                    "emphasis": [
                        "focus": "adjacency",
                        "label": [
                            "position": "right",
                            "show": true
                        ] as [String: Any]
                    ] as [String: Any],
                    "roam": true,
                    "roamTrigger": "global",
                    "lineStyle": [
                        "width": 0.5,
                        "curveness": 0.3,
                        "opacity": 0.7
                    ] as [String: Any]
                ] as [String: Any]
            ],
            // PORT-NOTE: `thumbnail` is kept verbatim, but EChartsKit has no Thumbnail component yet
            // (deferred in GraphView.swift), so the native pane ignores it — web draws a minimap, native does not.
            "thumbnail": [
                "width": "20%",
                "height": "20%",
                "windowStyle": [
                    "color": "rgba(140, 212, 250, 0.5)",
                    "borderColor": "rgba(30, 64, 175, 0.7)",
                    "opacity": 1.0
                ] as [String: Any]
            ] as [String: Any]
        ])
}
