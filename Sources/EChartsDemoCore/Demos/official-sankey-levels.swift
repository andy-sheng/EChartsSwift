// official-sankey-levels — replica of https://echarts.apache.org/examples/zh/editor.html?c=sankey-levels
// title: Sankey with Levels Setting / titleCN: 桑基图层级自定义样式
// A 26-node / 104-link product-footprint sankey whose `levels` give each depth (0..3) its own node
// colour and a source-tinted, 0.6-opacity link colour; links are curved (`lineStyle.curveness: 0.5`)
// and hovering focuses the adjacency (`emphasis.focus: 'adjacency'`).
//
// DEVIATIONS from the official source:
//   - The `$.get(ROOT_PATH + '/data/asset/data/product.json', function (data) {...})` fetch is dropped
//     (the page has no jQuery and cannot reach the network). The asset is vendored at
//     assets/data/product.json and its RAW TEXT is spliced into the web pane as `var data = {...}`;
//     the callback BODY (hideLoading + setOption) is otherwise verbatim and now runs at top level.
//     `myChart.showLoading()` / `hideLoading()` are kept — they simply bracket a synchronous load now.
//   - A trailing `export {};` is dropped (a bare export is a SyntaxError in a classic script).
//   - The native pane parses the SAME assets/data/product.json via Upstream.repoRoot.
// No closures in the option, so the Swift port carries every key; nothing else differs.
import Foundation

// The vendored asset's raw text — spliced verbatim into the web pane (the fetch it replaces) and
// parsed for the native pane. A missing/unreadable file degrades to an empty graph (blank pane,
// no crash).
private let sankeyLevelsRawJSON: String = {
    let url = Upstream.repoRoot.appendingPathComponent("assets/data/product.json")
    return (try? String(contentsOf: url, encoding: .utf8)) ?? #"{"nodes":[],"links":[]}"#
}()

// { nodes: [{ name }], links: [{ source, target, value }] } — sankey feeds on both.
private let sankeyLevelsNodes: [[String: Any]] = sankeyLevelsGraph.nodes
private let sankeyLevelsLinks: [[String: Any]] = sankeyLevelsGraph.links

private let sankeyLevelsGraph: (nodes: [[String: Any]], links: [[String: Any]]) = {
    guard let data = sankeyLevelsRawJSON.data(using: .utf8),
          let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
          let nodes = obj["nodes"] as? [[String: Any]],
          let links = obj["links"] as? [[String: Any]] else { return ([], []) }
    return (nodes, links)
}()

// One entry per depth: the node colour plus a source-tinted, translucent link colour.
private let sankeyLevelsLevels: [[String: Any]] = [
    [
        "depth": 0.0,
        "itemStyle": ["color": "#fbb4ae"] as [String: Any],
        "lineStyle": ["color": "source", "opacity": 0.6] as [String: Any]
    ],
    [
        "depth": 1.0,
        "itemStyle": ["color": "#b3cde3"] as [String: Any],
        "lineStyle": ["color": "source", "opacity": 0.6] as [String: Any]
    ],
    [
        "depth": 2.0,
        "itemStyle": ["color": "#ccebc5"] as [String: Any],
        "lineStyle": ["color": "source", "opacity": 0.6] as [String: Any]
    ],
    [
        "depth": 3.0,
        "itemStyle": ["color": "#decbe4"] as [String: Any],
        "lineStyle": ["color": "source", "opacity": 0.6] as [String: Any]
    ]
]

extension EChartsDemoRegistry {
    static let official_sankey_levels = EChartsDemo(
        name: "official-sankey-levels", category: "sankey",
        summary: "桑基图层级自定义样式 — Sankey with Levels Setting",
        width: 720, height: 460,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
myChart.showLoading();
// upstream: $.get(ROOT_PATH + '/data/asset/data/product.json', function (data) { ... })
var data = \#(sankeyLevelsRawJSON);
myChart.hideLoading();

myChart.setOption(
  (option = {
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
        levels: [
          {
            depth: 0,
            itemStyle: {
              color: '#fbb4ae'
            },
            lineStyle: {
              color: 'source',
              opacity: 0.6
            }
          },
          {
            depth: 1,
            itemStyle: {
              color: '#b3cde3'
            },
            lineStyle: {
              color: 'source',
              opacity: 0.6
            }
          },
          {
            depth: 2,
            itemStyle: {
              color: '#ccebc5'
            },
            lineStyle: {
              color: 'source',
              opacity: 0.6
            }
          },
          {
            depth: 3,
            itemStyle: {
              color: '#decbe4'
            },
            lineStyle: {
              color: 'source',
              opacity: 0.6
            }
          }
        ],
        lineStyle: {
          curveness: 0.5
        }
      }
    ]
  })
);
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
                    "data": sankeyLevelsNodes as [Any],
                    "links": sankeyLevelsLinks as [Any],
                    "emphasis": ["focus": "adjacency"] as [String: Any],
                    "levels": sankeyLevelsLevels as [Any],
                    "lineStyle": ["curveness": 0.5] as [String: Any]
                ] as [String: Any]
            ]
        ])
}
