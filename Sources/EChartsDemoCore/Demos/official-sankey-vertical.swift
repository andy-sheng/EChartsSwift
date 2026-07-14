// official-sankey-vertical — replica of https://echarts.apache.org/examples/zh/editor.html?c=sankey-vertical
// title: Sankey Orient Vertical / titleCN: 垂直方向的桑基图
// A 6-node sankey laid out top-to-bottom (`orient: 'vertical'`, labels above each node), links tinted
// by their source node and bowed with `curveness: 0.5`; `animation: false`, adjacency-focus emphasis.
// DEVIATIONS: none — the official source is a single static `option` literal: no data fetch, no
// closures, no timers, so both panes carry it verbatim (only the TS `export {};` is dropped, since a
// bare export is a SyntaxError in the classic script the web pane runs).
extension EChartsDemoRegistry {
    static let official_sankey_vertical = EChartsDemo(
        name: "official-sankey-vertical", category: "sankey",
        summary: "垂直方向的桑基图 — Sankey Orient Vertical",
        width: 720, height: 460,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
option = {
  tooltip: {
    trigger: 'item',
    triggerOn: 'mousemove'
  },
  animation: false,
  series: [
    {
      type: 'sankey',
      bottom: '10%',
      emphasis: {
        focus: 'adjacency'
      },
      data: [
        { name: 'a' },
        { name: 'b' },
        { name: 'a1' },
        { name: 'b1' },
        { name: 'c' },
        { name: 'e' }
      ],
      links: [
        { source: 'a', target: 'a1', value: 5 },
        { source: 'e', target: 'b', value: 3 },
        { source: 'a', target: 'b1', value: 3 },
        { source: 'b1', target: 'a1', value: 1 },
        { source: 'b1', target: 'c', value: 2 },
        { source: 'b', target: 'c', value: 1 }
      ],
      orient: 'vertical',
      label: {
        position: 'top'
      },
      lineStyle: {
        color: 'source',
        curveness: 0.5
      }
    }
  ]
};
"""#,
        option: [
            "tooltip": [
                "trigger": "item",
                "triggerOn": "mousemove"
            ] as [String: Any],
            "animation": false,
            "series": [
                [
                    "type": "sankey",
                    "bottom": "10%",
                    "emphasis": [
                        "focus": "adjacency"
                    ] as [String: Any],
                    "data": sankeyVerticalNodes,
                    "links": sankeyVerticalLinks,
                    "orient": "vertical",
                    "label": [
                        "position": "top"
                    ] as [String: Any],
                    "lineStyle": [
                        "color": "source",
                        "curveness": 0.5
                    ] as [String: Any]
                ] as [String: Any]
            ]
        ])
}

private let sankeyVerticalNodes: [[String: Any]] = [
    ["name": "a"],
    ["name": "b"],
    ["name": "a1"],
    ["name": "b1"],
    ["name": "c"],
    ["name": "e"]
]

private let sankeyVerticalLinks: [[String: Any]] = [
    ["source": "a", "target": "a1", "value": 5.0],
    ["source": "e", "target": "b", "value": 3.0],
    ["source": "a", "target": "b1", "value": 3.0],
    ["source": "b1", "target": "a1", "value": 1.0],
    ["source": "b1", "target": "c", "value": 2.0],
    ["source": "b", "target": "c", "value": 1.0]
]
