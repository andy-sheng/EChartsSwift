// official-pie-alignTo — replica of https://echarts.apache.org/examples/zh/editor.html?c=pie-alignTo
// title: Pie Label Align / titleCN: 饼图标签对齐
// Three pies over the SAME 7-item dataset, each laid out into its own third of the canvas via the
// series' own left/right/top/bottom rect, demonstrating the three outer-label alignment modes:
// alignTo 'none' (default, labels hug each sector), 'labelLine' (label text aligned to the end of the
// label line) and 'edge' (label text flush to the container edge, margin: 20). A `title` array
// captions each third; the main title sits centered on top.
// DEVIATIONS:
//   - canvas widened to 900x500 (the prescribed 640x420 squeezes three side-by-side pies + their
//     outer labels into ~213px columns, which hides the very alignment differences the example is
//     about). BOTH panes render at the same size, so the diff stays apples-to-apples.
//   - the trailing `export {};` is dropped from webOptionJS (a bare export is a SyntaxError in a
//     classic script).
//   - no data fetch, no closures, no timers in the official source — everything else is verbatim.
extension EChartsDemoRegistry {
    static let official_pie_alignto = EChartsDemo(
        name: "official-pie-alignTo", category: "pie",
        summary: "饼图标签对齐 — Pie Label Align",
        width: 900, height: 500,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
const data = [
  {
    name: 'Apples',
    value: 70
  },
  {
    name: 'Strawberries',
    value: 68
  },
  {
    name: 'Bananas',
    value: 48
  },
  {
    name: 'Oranges',
    value: 40
  },
  {
    name: 'Pears',
    value: 32
  },
  {
    name: 'Pineapples',
    value: 27
  },
  {
    name: 'Grapes',
    value: 18
  }
];

option = {
  title: [
    {
      text: 'Pie label alignTo',
      left: 'center'
    },
    {
      subtext: 'alignTo: "none" (default)',
      left: '16.67%',
      top: '75%',
      textAlign: 'center'
    },
    {
      subtext: 'alignTo: "labelLine"',
      left: '50%',
      top: '75%',
      textAlign: 'center'
    },
    {
      subtext: 'alignTo: "edge"',
      left: '83.33%',
      top: '75%',
      textAlign: 'center'
    }
  ],
  series: [
    {
      type: 'pie',
      radius: '25%',
      center: ['50%', '50%'],
      data: data,
      label: {
        position: 'outer',
        alignTo: 'none',
        bleedMargin: 5
      },
      left: 0,
      right: '66.6667%',
      top: 0,
      bottom: 0
    },
    {
      type: 'pie',
      radius: '25%',
      center: ['50%', '50%'],
      data: data,
      label: {
        position: 'outer',
        alignTo: 'labelLine',
        bleedMargin: 5
      },
      left: '33.3333%',
      right: '33.3333%',
      top: 0,
      bottom: 0
    },
    {
      type: 'pie',
      radius: '25%',
      center: ['50%', '50%'],
      data: data,
      label: {
        position: 'outer',
        alignTo: 'edge',
        margin: 20
      },
      left: '66.6667%',
      right: 0,
      top: 0,
      bottom: 0
    }
  ]
};
"""#,
        option: [
            "title": [
                [
                    "text": "Pie label alignTo",
                    "left": "center"
                ] as [String: Any],
                [
                    "subtext": "alignTo: \"none\" (default)",
                    "left": "16.67%",
                    "top": "75%",
                    "textAlign": "center"
                ] as [String: Any],
                [
                    "subtext": "alignTo: \"labelLine\"",
                    "left": "50%",
                    "top": "75%",
                    "textAlign": "center"
                ] as [String: Any],
                [
                    "subtext": "alignTo: \"edge\"",
                    "left": "83.33%",
                    "top": "75%",
                    "textAlign": "center"
                ] as [String: Any]
            ],
            "series": [
                [
                    "type": "pie",
                    "radius": "25%",
                    "center": ["50%", "50%"],
                    "data": pieAlignToData,
                    "label": [
                        "position": "outer",
                        "alignTo": "none",
                        "bleedMargin": 5.0
                    ] as [String: Any],
                    "left": 0.0,
                    "right": "66.6667%",
                    "top": 0.0,
                    "bottom": 0.0
                ] as [String: Any],
                [
                    "type": "pie",
                    "radius": "25%",
                    "center": ["50%", "50%"],
                    "data": pieAlignToData,
                    "label": [
                        "position": "outer",
                        "alignTo": "labelLine",
                        "bleedMargin": 5.0
                    ] as [String: Any],
                    "left": "33.3333%",
                    "right": "33.3333%",
                    "top": 0.0,
                    "bottom": 0.0
                ] as [String: Any],
                [
                    "type": "pie",
                    "radius": "25%",
                    "center": ["50%", "50%"],
                    "data": pieAlignToData,
                    "label": [
                        "position": "outer",
                        "alignTo": "edge",
                        "margin": 20.0
                    ] as [String: Any],
                    "left": "66.6667%",
                    "right": 0.0,
                    "top": 0.0,
                    "bottom": 0.0
                ] as [String: Any]
            ]
        ])
}

// The single `const data` of the official source, shared by all three pies.
private let pieAlignToData: [[String: Any]] = [
    ["name": "Apples", "value": 70.0],
    ["name": "Strawberries", "value": 68.0],
    ["name": "Bananas", "value": 48.0],
    ["name": "Oranges", "value": 40.0],
    ["name": "Pears", "value": 32.0],
    ["name": "Pineapples", "value": 27.0],
    ["name": "Grapes", "value": 18.0]
]
