// official-chord-simple — replica of https://echarts.apache.org/examples/zh/editor.html?c=chord-simple
// title: Basic Chord / titleCN: 基础和弦图
// Four nodes A/B/C/D on a ring, three weighted links drawn as ribbons; counter-clockwise layout,
// each ribbon tinted by its TARGET node's color (`lineStyle.color: 'target'`).
// DEVIATIONS: none — the official source is fully static (no data fetch, no timers, no closures),
// so both panes run the example verbatim.
extension EChartsDemoRegistry {
    static let official_chord_simple = EChartsDemo(
        name: "official-chord-simple", category: "chord",
        summary: "基础和弦图 — Basic Chord",
        width: 640, height: 420,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
option = {
  tooltip: {},
  legend: {},
  series: [
    {
      type: 'chord',
      clockwise: false,
      label: { show: true },
      lineStyle: { color: 'target' },
      data: [
        { name: 'A' },
        { name: 'B' },
        { name: 'C' },
        { name: 'D' }
      ],
      links: [
        { source: 'A', target: 'B', value: 40 },
        { source: 'A', target: 'C', value: 20 },
        { source: 'B', target: 'D', value: 20 },
      ]
    }
  ]
};
"""#,
        option: [
            "tooltip": [:] as [String: Any],
            "legend": [:] as [String: Any],
            "series": [
                [
                    "type": "chord",
                    "clockwise": false,
                    "label": ["show": true] as [String: Any],
                    "lineStyle": ["color": "target"] as [String: Any],
                    "data": [
                        ["name": "A"] as [String: Any],
                        ["name": "B"] as [String: Any],
                        ["name": "C"] as [String: Any],
                        ["name": "D"] as [String: Any]
                    ],
                    "links": [
                        ["source": "A", "target": "B", "value": 40.0] as [String: Any],
                        ["source": "A", "target": "C", "value": 20.0] as [String: Any],
                        ["source": "B", "target": "D", "value": 20.0] as [String: Any]
                    ]
                ] as [String: Any]
            ]
        ])
}
