// official-chord-minAngle — replica of https://echarts.apache.org/examples/zh/editor.html?c=chord-minAngle
// title: Chord minAngle / titleCN: 和弦图 minAngle
// Six chord nodes (A–F) with three weighted links (A→B, B→C, E→A); `minAngle: 30` forces every node —
// including D and F, which carry no link at all — to occupy at least 30° of the circle, so none
// collapses to a sliver.
// DEVIATIONS: none — the official source is a single static `option` literal (no data fetch, no
// closures, no timers), so both panes carry it verbatim. Only the trailing `export {};` is dropped
// (a bare export is a SyntaxError in the reference pane's classic script).
extension EChartsDemoRegistry {
    static let official_chord_minangle = EChartsDemo(
        name: "official-chord-minAngle", category: "chord",
        summary: "和弦图 minAngle — Chord minAngle",
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
      label: { show: true },
      minAngle: 30,
      data: [
        { name: 'A' },
        { name: 'B' },
        { name: 'C' },
        { name: 'D' },
        { name: 'E' },
        { name: 'F' }
      ],
      links: [
        { source: 'A', target: 'B', value: 40 },
        { source: 'B', target: 'C', value: 20 },
        { source: 'E', target: 'A', value: 5 }
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
                    "label": ["show": true] as [String: Any],
                    "minAngle": 30.0,
                    "data": chordMinAngleNodes,
                    "links": chordMinAngleLinks
                ] as [String: Any]
            ]
        ])
}

// Nodes are name-only; D and F carry no link at all — they exist to show what `minAngle` rescues.
private let chordMinAngleNodes: [[String: Any]] = [
    ["name": "A"],
    ["name": "B"],
    ["name": "C"],
    ["name": "D"],
    ["name": "E"],
    ["name": "F"]
]

private let chordMinAngleLinks: [[String: Any]] = [
    ["source": "A", "target": "B", "value": 40.0],
    ["source": "B", "target": "C", "value": 20.0],
    ["source": "E", "target": "A", "value": 5.0]
]
