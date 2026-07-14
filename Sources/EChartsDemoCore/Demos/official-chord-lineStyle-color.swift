// official-chord-lineStyle-color — replica of https://echarts.apache.org/examples/zh/editor.html?c=chord-lineStyle-color
// title: Chord lineStyle.color / titleCN: 和弦图边的颜色
// Three identical 4-node chord series (A/B/C/D, 5 weighted links) side by side, differing only in
// `lineStyle.color`: 'source' (ribbon takes the source node's color), 'target', and 'gradient'
// (source→target linear gradient). A titled label sits over each so the three modes read as one
// comparison. The example builds series and titles with two plain JS factory functions —
// `generateSeries(id, lineColor)` / `generateTitle(id, text)` — that return object literals; they are
// data, not option closures, so the Swift port evaluates the same factories at file scope.
// DEVIATIONS:
//   - canvas 900x420 rather than the gallery's usual 640x420 — a FRAMING choice, nothing more. The
//     example lays three chords across the width at x = 1/6, 3/6, 5/6, so it wants the wide,
//     letterboxed frame the official editor gives it. It does not need one: `radius` is a percentage
//     of min(w, h)/2 (getCircleLayout), so the rings are the same ~67px either way and at 640 the
//     centers are still 213px apart — they would not overlap. 900 only spreads them out. Both panes
//     render at the SAME size, so the diff stays honest.
//   - TypeScript-only syntax dropped from the reference pane's JS (the `id: number` /
//     `lineColor: 'source' | 'target' | 'gradient'` / `text: string` annotations and the two
//     `as const` casts) — a classic script cannot parse it. The functions themselves are verbatim.
//   - no data fetch, no timers, no option closures: everything else is carried as-is on both panes.
extension EChartsDemoRegistry {
    static let official_chord_linestyle_color = EChartsDemo(
        name: "official-chord-lineStyle-color", category: "chord",
        summary: "和弦图边的颜色 — Chord lineStyle.color",
        width: 900, height: 420,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
function generateSeries(id, lineColor) {
  return {
    type: 'chord',
    label: { show: true },
    center: [((id * 2 + 1) / 6) * 100 + '%', '50%'],
    radius: ['28%', '32%'],
    lineStyle: {
      color: lineColor
    },
    data: [{ name: 'A' }, { name: 'B' }, { name: 'C' }, { name: 'D' }],
    links: [
      { source: 'A', target: 'B', value: 30 },
      { source: 'A', target: 'C', value: 20 },
      { source: 'B', target: 'D', value: 10 },
      { source: 'C', target: 'A', value: 15 },
      { source: 'D', target: 'A', value: 25 }
    ]
  };
}

function generateTitle(id, text) {
  return {
    text,
    left: ((id * 2 + 1) / 6) * 100 + '%',
    top: '25%',
    textAlign: 'center',
    padding: 0
  };
}

option = {
  tooltip: {},
  legend: {},
  series: [
    generateSeries(0, 'source'),
    generateSeries(1, 'target'),
    generateSeries(2, 'gradient')
  ],
  title: [
    {
      text: 'lineStyle.color',
      textStyle: {
        fontSize: 24
      }
    },
    generateTitle(0, 'source'),
    generateTitle(1, 'target'),
    generateTitle(2, 'gradient')
  ]
};
"""#,
        option: [
            "tooltip": [:] as [String: Any],
            "legend": [:] as [String: Any],
            "series": [
                chordLineStyleColorSeries(0, "source"),
                chordLineStyleColorSeries(1, "target"),
                chordLineStyleColorSeries(2, "gradient")
            ],
            "title": [
                [
                    "text": "lineStyle.color",
                    "textStyle": [
                        "fontSize": 24.0
                    ] as [String: Any]
                ] as [String: Any],
                chordLineStyleColorTitle(0, "source"),
                chordLineStyleColorTitle(1, "target"),
                chordLineStyleColorTitle(2, "gradient")
            ]
        ])
}

// The example's `((id * 2 + 1) / 6) * 100 + '%'` — the x of the id-th of three evenly spaced chords.
// Spelled out (rather than recomputed) so the percent STRINGS match the reference pane's byte for
// byte: JS renders 3 / 6 * 100 as "50", Swift's Double description as "50.0".
private let chordLineStyleColorCenters: [String] = [
    "16.666666666666664%",   // (1 / 6) * 100
    "50%",                   // (3 / 6) * 100
    "83.33333333333334%"     // (5 / 6) * 100
]

// upstream: function generateSeries(id, lineColor)
private func chordLineStyleColorSeries(_ id: Int, _ lineColor: String) -> [String: Any] {
    return [
        "type": "chord",
        "label": ["show": true] as [String: Any],
        "center": [chordLineStyleColorCenters[id], "50%"],
        "radius": ["28%", "32%"],
        "lineStyle": [
            "color": lineColor      // 'source' | 'target' | 'gradient'
        ] as [String: Any],
        "data": chordLineStyleColorNodes,
        "links": chordLineStyleColorLinks
    ]
}

// upstream: function generateTitle(id, text)
private func chordLineStyleColorTitle(_ id: Int, _ text: String) -> [String: Any] {
    return [
        "text": text,
        "left": chordLineStyleColorCenters[id],
        "top": "25%",
        "textAlign": "center",
        "padding": 0.0
    ]
}

private let chordLineStyleColorNodes: [[String: Any]] = [
    ["name": "A"],
    ["name": "B"],
    ["name": "C"],
    ["name": "D"]
]

private let chordLineStyleColorLinks: [[String: Any]] = [
    ["source": "A", "target": "B", "value": 30.0],
    ["source": "A", "target": "C", "value": 20.0],
    ["source": "B", "target": "D", "value": 10.0],
    ["source": "C", "target": "A", "value": 15.0],
    ["source": "D", "target": "A", "value": 25.0]
]
