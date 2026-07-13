// official-scatter-anscombe-quartet — replica of https://echarts.apache.org/examples/zh/editor.html?c=scatter-anscombe-quartet
// title: Anscomb's quartet / titleCN: 安斯库姆四重奏
// Four scatter series (I–IV) on four separate grids, each pinned to min 0 / max 20 (x) and 0 / 15 (y),
// each carrying the SAME markLine — the regression line y = 0.5x + 3, drawn coord [0,3] → [20,13].
// The point: four datasets with near-identical summary statistics but wildly different shapes.
// DEVIATIONS:
//   - webOptionJS drops the TypeScript type annotation on `markLineOpt`
//     (`const markLineOpt: echarts.MarkLineComponentOption = {...}` → `const markLineOpt = {...}`) —
//     the reference pane runs a classic script, where a type annotation is a SyntaxError. Value is verbatim.
//   - webOptionJS drops the trailing `export {};` (a bare export kills a classic script).
//   - No data fetch, no timers, no closures in the original: both formatters are ECharts STRING
//     templates ('Group {a}: ({c})', 'y = 0.5 * x + 3'), not functions, so the native option carries
//     the full example — nothing omitted.
extension EChartsDemoRegistry {
    static let official_scatter_anscombe_quartet = EChartsDemo(
        name: "official-scatter-anscombe-quartet", category: "scatter",
        summary: "安斯库姆四重奏 — Anscomb's quartet",
        width: 640, height: 420,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
const dataAll = [
  [
    [10.0, 8.04],
    [8.0, 6.95],
    [13.0, 7.58],
    [9.0, 8.81],
    [11.0, 8.33],
    [14.0, 9.96],
    [6.0, 7.24],
    [4.0, 4.26],
    [12.0, 10.84],
    [7.0, 4.82],
    [5.0, 5.68]
  ],
  [
    [10.0, 9.14],
    [8.0, 8.14],
    [13.0, 8.74],
    [9.0, 8.77],
    [11.0, 9.26],
    [14.0, 8.1],
    [6.0, 6.13],
    [4.0, 3.1],
    [12.0, 9.13],
    [7.0, 7.26],
    [5.0, 4.74]
  ],
  [
    [10.0, 7.46],
    [8.0, 6.77],
    [13.0, 12.74],
    [9.0, 7.11],
    [11.0, 7.81],
    [14.0, 8.84],
    [6.0, 6.08],
    [4.0, 5.39],
    [12.0, 8.15],
    [7.0, 6.42],
    [5.0, 5.73]
  ],
  [
    [8.0, 6.58],
    [8.0, 5.76],
    [8.0, 7.71],
    [8.0, 8.84],
    [8.0, 8.47],
    [8.0, 7.04],
    [8.0, 5.25],
    [19.0, 12.5],
    [8.0, 5.56],
    [8.0, 7.91],
    [8.0, 6.89]
  ]
];

const markLineOpt = {
  animation: false,
  label: {
    formatter: 'y = 0.5 * x + 3',
    align: 'right'
  },
  lineStyle: {
    type: 'solid'
  },
  tooltip: {
    formatter: 'y = 0.5 * x + 3'
  },
  data: [
    [
      {
        coord: [0, 3],
        symbol: 'none'
      },
      {
        coord: [20, 13],
        symbol: 'none'
      }
    ]
  ]
};

option = {
  title: {
    text: "Anscombe's quartet",
    left: 'center',
    top: 0
  },
  grid: [
    { left: '7%', top: '7%', width: '38%', height: '38%' },
    { right: '7%', top: '7%', width: '38%', height: '38%' },
    { left: '7%', bottom: '7%', width: '38%', height: '38%' },
    { right: '7%', bottom: '7%', width: '38%', height: '38%' }
  ],
  tooltip: {
    formatter: 'Group {a}: ({c})'
  },
  xAxis: [
    { gridIndex: 0, min: 0, max: 20 },
    { gridIndex: 1, min: 0, max: 20 },
    { gridIndex: 2, min: 0, max: 20 },
    { gridIndex: 3, min: 0, max: 20 }
  ],
  yAxis: [
    { gridIndex: 0, min: 0, max: 15 },
    { gridIndex: 1, min: 0, max: 15 },
    { gridIndex: 2, min: 0, max: 15 },
    { gridIndex: 3, min: 0, max: 15 }
  ],
  series: [
    {
      name: 'I',
      type: 'scatter',
      xAxisIndex: 0,
      yAxisIndex: 0,
      data: dataAll[0],
      markLine: markLineOpt
    },
    {
      name: 'II',
      type: 'scatter',
      xAxisIndex: 1,
      yAxisIndex: 1,
      data: dataAll[1],
      markLine: markLineOpt
    },
    {
      name: 'III',
      type: 'scatter',
      xAxisIndex: 2,
      yAxisIndex: 2,
      data: dataAll[2],
      markLine: markLineOpt
    },
    {
      name: 'IV',
      type: 'scatter',
      xAxisIndex: 3,
      yAxisIndex: 3,
      data: dataAll[3],
      markLine: markLineOpt
    }
  ]
};
"""#,
        option: [
            "title": [
                "text": "Anscombe's quartet",
                "left": "center",
                "top": 0.0
            ] as [String: Any],
            "grid": anscombeGrids,
            "tooltip": [
                // The official `formatter` is an ECharts string template, not a closure — it ports as-is.
                "formatter": "Group {a}: ({c})"
            ] as [String: Any],
            "xAxis": anscombeXAxes,
            "yAxis": anscombeYAxes,
            "series": [
                [
                    "name": "I",
                    "type": "scatter",
                    "xAxisIndex": 0.0,
                    "yAxisIndex": 0.0,
                    "data": anscombeDataAll[0],
                    "markLine": anscombeMarkLineOpt
                ] as [String: Any],
                [
                    "name": "II",
                    "type": "scatter",
                    "xAxisIndex": 1.0,
                    "yAxisIndex": 1.0,
                    "data": anscombeDataAll[1],
                    "markLine": anscombeMarkLineOpt
                ] as [String: Any],
                [
                    "name": "III",
                    "type": "scatter",
                    "xAxisIndex": 2.0,
                    "yAxisIndex": 2.0,
                    "data": anscombeDataAll[2],
                    "markLine": anscombeMarkLineOpt
                ] as [String: Any],
                [
                    "name": "IV",
                    "type": "scatter",
                    "xAxisIndex": 3.0,
                    "yAxisIndex": 3.0,
                    "data": anscombeDataAll[3],
                    "markLine": anscombeMarkLineOpt
                ] as [String: Any]
            ]
        ])
}

// The four datasets of Anscombe's quartet: near-identical mean/variance/correlation/regression,
// utterly different scatter. Each point is [x, y].
private let anscombeDataAll: [[[Double]]] = [
    [
        [10.0, 8.04],
        [8.0, 6.95],
        [13.0, 7.58],
        [9.0, 8.81],
        [11.0, 8.33],
        [14.0, 9.96],
        [6.0, 7.24],
        [4.0, 4.26],
        [12.0, 10.84],
        [7.0, 4.82],
        [5.0, 5.68]
    ],
    [
        [10.0, 9.14],
        [8.0, 8.14],
        [13.0, 8.74],
        [9.0, 8.77],
        [11.0, 9.26],
        [14.0, 8.1],
        [6.0, 6.13],
        [4.0, 3.1],
        [12.0, 9.13],
        [7.0, 7.26],
        [5.0, 4.74]
    ],
    [
        [10.0, 7.46],
        [8.0, 6.77],
        [13.0, 12.74],
        [9.0, 7.11],
        [11.0, 7.81],
        [14.0, 8.84],
        [6.0, 6.08],
        [4.0, 5.39],
        [12.0, 8.15],
        [7.0, 6.42],
        [5.0, 5.73]
    ],
    [
        [8.0, 6.58],
        [8.0, 5.76],
        [8.0, 7.71],
        [8.0, 8.84],
        [8.0, 8.47],
        [8.0, 7.04],
        [8.0, 5.25],
        [19.0, 12.5],
        [8.0, 5.56],
        [8.0, 7.91],
        [8.0, 6.89]
    ]
]

// The regression line y = 0.5x + 3, shared verbatim by all four series (as in the original, where a
// single `markLineOpt` object is referenced four times).
private let anscombeMarkLineOpt: [String: Any] = [
    "animation": false,
    "label": [
        // Also a string template in the original, not a closure.
        "formatter": "y = 0.5 * x + 3",
        "align": "right"
    ] as [String: Any],
    "lineStyle": [
        "type": "solid"
    ] as [String: Any],
    "tooltip": [
        "formatter": "y = 0.5 * x + 3"
    ] as [String: Any],
    "data": [
        [
            ["coord": [0.0, 3.0], "symbol": "none"] as [String: Any],
            ["coord": [20.0, 13.0], "symbol": "none"] as [String: Any]
        ]
    ]
]

// 2x2 arrangement of grids, one per dataset.
private let anscombeGrids: [[String: Any]] = [
    ["left": "7%", "top": "7%", "width": "38%", "height": "38%"],
    ["right": "7%", "top": "7%", "width": "38%", "height": "38%"],
    ["left": "7%", "bottom": "7%", "width": "38%", "height": "38%"],
    ["right": "7%", "bottom": "7%", "width": "38%", "height": "38%"]
]

// Identical extents on every grid — the whole point is that the four shapes are comparable.
private let anscombeXAxes: [[String: Any]] = [
    ["gridIndex": 0.0, "min": 0.0, "max": 20.0],
    ["gridIndex": 1.0, "min": 0.0, "max": 20.0],
    ["gridIndex": 2.0, "min": 0.0, "max": 20.0],
    ["gridIndex": 3.0, "min": 0.0, "max": 20.0]
]

private let anscombeYAxes: [[String: Any]] = [
    ["gridIndex": 0.0, "min": 0.0, "max": 15.0],
    ["gridIndex": 1.0, "min": 0.0, "max": 15.0],
    ["gridIndex": 2.0, "min": 0.0, "max": 15.0],
    ["gridIndex": 3.0, "min": 0.0, "max": 15.0]
]
