// official-graph-simple — replica of https://echarts.apache.org/examples/zh/editor.html?c=graph-simple
// title: Simple Graph / titleCN: Graph 简单示例
// A 4-node network laid out by explicit x/y (layout: 'none'), directed edges drawn with an arrow
// edgeSymbol, two of them curved (curveness 0.2) and edge-labelled.
//
// DEVIATIONS from the official source:
//   - none in the option itself: the example has no closures, no fetched data, no setInterval.
//     webOptionJS is the source verbatim (minus the `export {}` TS tail).
//   - `roam: true` (drag/zoom the graph) and `animationDurationUpdate` / `animationEasingUpdate`
//     (the 1500ms quinticInOut transition on a re-setOption) are kept in both options but have no
//     visible effect here: the gallery renders ONE static, non-interactive frame with animation off.
extension EChartsDemoRegistry {
    static let official_graph_simple = EChartsDemo(
        name: "official-graph-simple", category: "graph",
        summary: "Graph 简单示例 — Simple Graph",
        width: 640, height: 420,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
option = {
  title: {
    text: 'Basic Graph'
  },
  tooltip: {},
  animationDurationUpdate: 1500,
  animationEasingUpdate: 'quinticInOut',
  series: [
    {
      type: 'graph',
      layout: 'none',
      symbolSize: 50,
      roam: true,
      label: {
        show: true
      },
      edgeSymbol: ['circle', 'arrow'],
      edgeSymbolSize: [4, 10],
      edgeLabel: {
        fontSize: 20
      },
      data: [
        {
          name: 'Node 1',
          x: 300,
          y: 300
        },
        {
          name: 'Node 2',
          x: 800,
          y: 300
        },
        {
          name: 'Node 3',
          x: 550,
          y: 100
        },
        {
          name: 'Node 4',
          x: 550,
          y: 500
        }
      ],
      // links: [],
      links: [
        {
          source: 0,
          target: 1,
          symbolSize: [5, 20],
          label: {
            show: true
          },
          lineStyle: {
            width: 5,
            curveness: 0.2
          }
        },
        {
          source: 'Node 2',
          target: 'Node 1',
          label: {
            show: true
          },
          lineStyle: {
            curveness: 0.2
          }
        },
        {
          source: 'Node 1',
          target: 'Node 3'
        },
        {
          source: 'Node 2',
          target: 'Node 3'
        },
        {
          source: 'Node 2',
          target: 'Node 4'
        },
        {
          source: 'Node 1',
          target: 'Node 4'
        }
      ],
      lineStyle: {
        opacity: 0.9,
        width: 2,
        curveness: 0
      }
    }
  ]
};
"""#,
        option: [
            "title": [
                "text": "Basic Graph"
            ] as [String: Any],
            "tooltip": [:] as [String: Any],
            "animationDurationUpdate": 1500.0,
            "animationEasingUpdate": "quinticInOut",
            "series": [
                [
                    "type": "graph",
                    "layout": "none",
                    "symbolSize": 50.0,
                    "roam": true,
                    "label": [
                        "show": true
                    ] as [String: Any],
                    "edgeSymbol": ["circle", "arrow"],
                    "edgeSymbolSize": [4.0, 10.0],
                    "edgeLabel": [
                        "fontSize": 20.0
                    ] as [String: Any],
                    "data": graphSimpleNodes,
                    "links": graphSimpleLinks,
                    "lineStyle": [
                        "opacity": 0.9,
                        "width": 2.0,
                        "curveness": 0.0
                    ] as [String: Any]
                ] as [String: Any]
            ]
        ])
}

// Hoisted out of the option literal: Swift's type-checker times out on large heterogeneous
// nested literals (see the porting notes in EChartsDemo.swift).
private let graphSimpleNodes: [[String: Any]] = [
    ["name": "Node 1", "x": 300.0, "y": 300.0],
    ["name": "Node 2", "x": 800.0, "y": 300.0],
    ["name": "Node 3", "x": 550.0, "y": 100.0],
    ["name": "Node 4", "x": 550.0, "y": 500.0]
]

// `source: 0` is a NODE INDEX (the rest are node names) — Graph.addEdge resolves a number as an
// index into `data`, a string against the node-name map. Kept as in the official source.
private let graphSimpleLinks: [[String: Any]] = [
    [
        "source": 0.0, "target": 1.0,
        "symbolSize": [5.0, 20.0],
        "label": ["show": true] as [String: Any],
        "lineStyle": ["width": 5.0, "curveness": 0.2] as [String: Any]
    ],
    [
        "source": "Node 2", "target": "Node 1",
        "label": ["show": true] as [String: Any],
        "lineStyle": ["curveness": 0.2] as [String: Any]
    ],
    ["source": "Node 1", "target": "Node 3"],
    ["source": "Node 2", "target": "Node 3"],
    ["source": "Node 2", "target": "Node 4"],
    ["source": "Node 1", "target": "Node 4"]
]
