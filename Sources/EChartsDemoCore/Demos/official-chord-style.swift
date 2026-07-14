// official-chord-style — replica of https://echarts.apache.org/examples/zh/editor.html?c=chord-style
// title: Chord Style / titleCN: 和弦图样式
// A 7-node chord diagram (A…G) exercising the series' styling knobs: padAngle, a ring radius,
// rounded/bordered node arcs (itemStyle.borderRadius [0, 15]), gradient-colored ribbons
// (lineStyle.color: 'gradient'), emphasis.focus 'self', and inside labels.
// DEVIATIONS: none — the official source is a single static `option` literal: no data fetch, no
// closures, no timers. Both panes carry it verbatim (the trailing `export {};` is dropped, as it is
// a SyntaxError in the reference pane's classic script).
extension EChartsDemoRegistry {
    static let official_chord_style = EChartsDemo(
        name: "official-chord-style", category: "chord",
        summary: "和弦图样式 — Chord Style",
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
      padAngle: 1,
      center: ['50%', '48%'],
      radius: ['70%', '80%'],
      data: [
        { name: 'A' },
        { name: 'B' },
        { name: 'C' },
        { name: 'D' },
        { name: 'E' },
        { name: 'F' },
        { name: 'G' }
      ],
      itemStyle: {
        borderRadius: [0, 15],
        borderWidth: 2,
        borderColor: '#fff'
      },
      lineStyle: {
        opacity: 0.3,
        color: 'gradient' // or 'source' (default), 'target'
      },
      emphasis: {
        focus: 'self' // or 'none', 'adjacency' (default)
      },
      label: {
        show: true,
        position: 'inside',
        color: '#fff',
        fontWeight: 'bold'
      },
      links: [
        { source: 'A', target: 'B', value: 14 },
        { source: 'A', target: 'C', value: 8 },
        { source: 'B', target: 'C', value: 20 },
        { source: 'B', target: 'E', value: 15 },
        { source: 'C', target: 'B', value: 8 },
        { source: 'C', target: 'E', value: 3 },
        { source: 'D', target: 'A', value: 12 },
        { source: 'D', target: 'B', value: 3 },
        { source: 'E', target: 'A', value: 15 },
        { source: 'E', target: 'C', value: 5 },
        { source: 'F', target: 'C', value: 5 },
        { source: 'G', target: 'A', value: 6 },
        { source: 'G', target: 'B', value: 8 },
        { source: 'G', target: 'D', value: 4 }
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
                    "padAngle": 1.0,
                    "center": ["50%", "48%"],
                    "radius": ["70%", "80%"],
                    "data": chordStyleNodes,
                    "itemStyle": [
                        "borderRadius": [0.0, 15.0],
                        "borderWidth": 2.0,
                        "borderColor": "#fff"
                    ] as [String: Any],
                    "lineStyle": [
                        "opacity": 0.3,
                        "color": "gradient"   // or 'source' (default), 'target'
                    ] as [String: Any],
                    "emphasis": [
                        "focus": "self"       // or 'none', 'adjacency' (default)
                    ] as [String: Any],
                    "label": [
                        "show": true,
                        "position": "inside",
                        "color": "#fff",
                        "fontWeight": "bold"
                    ] as [String: Any],
                    "links": chordStyleLinks
                ] as [String: Any]
            ]
        ])
}

private let chordStyleNodes: [[String: Any]] = [
    ["name": "A"],
    ["name": "B"],
    ["name": "C"],
    ["name": "D"],
    ["name": "E"],
    ["name": "F"],
    ["name": "G"]
]

private let chordStyleLinks: [[String: Any]] = [
    ["source": "A", "target": "B", "value": 14.0],
    ["source": "A", "target": "C", "value": 8.0],
    ["source": "B", "target": "C", "value": 20.0],
    ["source": "B", "target": "E", "value": 15.0],
    ["source": "C", "target": "B", "value": 8.0],
    ["source": "C", "target": "E", "value": 3.0],
    ["source": "D", "target": "A", "value": 12.0],
    ["source": "D", "target": "B", "value": 3.0],
    ["source": "E", "target": "A", "value": 15.0],
    ["source": "E", "target": "C", "value": 5.0],
    ["source": "F", "target": "C", "value": 5.0],
    ["source": "G", "target": "A", "value": 6.0],
    ["source": "G", "target": "B", "value": 8.0],
    ["source": "G", "target": "D", "value": 4.0]
]
