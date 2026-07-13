// official-treemap-simple — replica of https://echarts.apache.org/examples/zh/editor.html?c=treemap-simple
// title: Basic Treemap / titleCN: 基础矩形树图
// Two hierarchical trees (nodeA with 2 leaves, nodeB with a 3-level chain) laid out as a treemap.
// DEVIATIONS: none — the official source is a single static `option` with no data fetch, no closures
// and no timers, so both panes carry it verbatim.

/// The `series[0].data` forest, hoisted out of the option literal: nested heterogeneous dictionaries
/// (String / Double / [[String: Any]]) are exactly what stalls Swift's type-checker inline.
private let treemapSimpleData: [[String: Any]] = [
    [
        "name": "nodeA",                // First tree
        "value": 10.0,
        "children": [
            [
                "name": "nodeAa",       // First leaf of first tree
                "value": 4.0
            ] as [String: Any],
            [
                "name": "nodeAb",       // Second leaf of first tree
                "value": 6.0
            ] as [String: Any]
        ]
    ] as [String: Any],
    [
        "name": "nodeB",                // Second tree
        "value": 20.0,
        "children": [
            [
                "name": "nodeBa",       // Son of first tree
                "value": 20.0,
                "children": [
                    [
                        "name": "nodeBa1",  // Granson of first tree
                        "value": 20.0
                    ] as [String: Any]
                ]
            ] as [String: Any]
        ]
    ] as [String: Any]
]

extension EChartsDemoRegistry {
    static let official_treemap_simple = EChartsDemo(
        name: "official-treemap-simple", category: "treemap",
        summary: "基础矩形树图 — Basic Treemap",
        width: 640, height: 420,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
option = {
  series: [
    {
      type: 'treemap',
      data: [
        {
          name: 'nodeA', // First tree
          value: 10,
          children: [
            {
              name: 'nodeAa', // First leaf of first tree
              value: 4
            },
            {
              name: 'nodeAb', // Second leaf of first tree
              value: 6
            }
          ]
        },
        {
          name: 'nodeB', // Second tree
          value: 20,
          children: [
            {
              name: 'nodeBa', // Son of first tree
              value: 20,
              children: [
                {
                  name: 'nodeBa1', // Granson of first tree
                  value: 20
                }
              ]
            }
          ]
        }
      ]
    }
  ]
};
"""#,
        option: [
            "series": [
                [
                    "type": "treemap",
                    "data": treemapSimpleData
                ] as [String: Any]
            ]
        ])
}
