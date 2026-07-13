// official-line-gradient — replica of https://echarts.apache.org/examples/zh/editor.html?c=line-gradient
// title: Line Gradient / titleCN: 折线图的渐变
// Two stacked grids over the same 50-point series, each colored by a `show: false` continuous
// visualMap: the top grid maps the value dimension (gradient along y), the bottom grid maps
// dimension 0 (gradient along x).
// DEVIATIONS:
//   - The inline `data` array (a literal in the official source, no fetch) is hoisted to file-scope
//     `lineGradientDates` / `lineGradientValues` in the native pane; webOptionJS keeps it verbatim.
//   - Canvas is 640x480 rather than the template's 640x420: two stacked grids plus two titles need
//     the extra height to stay legible. Both panes use the same size, so the diff stays honest.
//   - No closures, no timers, no assets in the official source — nothing else is elided.
extension EChartsDemoRegistry {
    static let official_line_gradient = EChartsDemo(
        name: "official-line-gradient", category: "line",
        summary: "折线图的渐变 — Line Gradient",
        width: 640, height: 480,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
// prettier-ignore
const data = [["2000-06-05",116],["2000-06-06",129],["2000-06-07",135],["2000-06-08",86],["2000-06-09",73],["2000-06-10",85],["2000-06-11",73],["2000-06-12",68],["2000-06-13",92],["2000-06-14",130],["2000-06-15",245],["2000-06-16",139],["2000-06-17",115],["2000-06-18",111],["2000-06-19",309],["2000-06-20",206],["2000-06-21",137],["2000-06-22",128],["2000-06-23",85],["2000-06-24",94],["2000-06-25",71],["2000-06-26",106],["2000-06-27",84],["2000-06-28",93],["2000-06-29",85],["2000-06-30",73],["2000-07-01",83],["2000-07-02",125],["2000-07-03",107],["2000-07-04",82],["2000-07-05",44],["2000-07-06",72],["2000-07-07",106],["2000-07-08",107],["2000-07-09",66],["2000-07-10",91],["2000-07-11",92],["2000-07-12",113],["2000-07-13",107],["2000-07-14",131],["2000-07-15",111],["2000-07-16",64],["2000-07-17",69],["2000-07-18",88],["2000-07-19",77],["2000-07-20",83],["2000-07-21",111],["2000-07-22",57],["2000-07-23",55],["2000-07-24",60]];

const dateList = data.map(function (item) {
  return item[0];
});
const valueList = data.map(function (item) {
  return item[1];
});

option = {
  // Make gradient line here
  visualMap: [
    {
      show: false,
      type: 'continuous',
      seriesIndex: 0,
      min: 0,
      max: 400
    },
    {
      show: false,
      type: 'continuous',
      seriesIndex: 1,
      dimension: 0,
      min: 0,
      max: dateList.length - 1
    }
  ],

  title: [
    {
      left: 'center',
      text: 'Gradient along the y axis'
    },
    {
      top: '55%',
      left: 'center',
      text: 'Gradient along the x axis'
    }
  ],
  tooltip: {
    trigger: 'axis'
  },
  xAxis: [
    {
      data: dateList
    },
    {
      data: dateList,
      gridIndex: 1
    }
  ],
  yAxis: [
    {},
    {
      gridIndex: 1
    }
  ],
  grid: [
    {
      bottom: '60%'
    },
    {
      top: '60%'
    }
  ],
  series: [
    {
      type: 'line',
      showSymbol: false,
      data: valueList
    },
    {
      type: 'line',
      showSymbol: false,
      data: valueList,
      xAxisIndex: 1,
      yAxisIndex: 1
    }
  ]
};
"""#,
        option: [
            // Make gradient line here
            "visualMap": [
                [
                    "show": false,
                    "type": "continuous",
                    "seriesIndex": 0.0,
                    "min": 0.0,
                    "max": 400.0
                ] as [String: Any],
                [
                    "show": false,
                    "type": "continuous",
                    "seriesIndex": 1.0,
                    "dimension": 0.0,
                    "min": 0.0,
                    "max": Double(lineGradientDates.count - 1)
                ] as [String: Any]
            ],
            "title": [
                [
                    "left": "center",
                    "text": "Gradient along the y axis"
                ] as [String: Any],
                [
                    "top": "55%",
                    "left": "center",
                    "text": "Gradient along the x axis"
                ] as [String: Any]
            ],
            "tooltip": [
                "trigger": "axis"
            ] as [String: Any],
            "xAxis": [
                [
                    "data": lineGradientDates
                ] as [String: Any],
                [
                    "data": lineGradientDates,
                    "gridIndex": 1.0
                ] as [String: Any]
            ],
            "yAxis": [
                [:] as [String: Any],
                [
                    "gridIndex": 1.0
                ] as [String: Any]
            ],
            "grid": [
                [
                    "bottom": "60%"
                ] as [String: Any],
                [
                    "top": "60%"
                ] as [String: Any]
            ],
            "series": [
                [
                    "type": "line",
                    "showSymbol": false,
                    "data": lineGradientValues
                ] as [String: Any],
                [
                    "type": "line",
                    "showSymbol": false,
                    "data": lineGradientValues,
                    "xAxisIndex": 1.0,
                    "yAxisIndex": 1.0
                ] as [String: Any]
            ]
        ])
}

// The official source's inline `data` array, pre-split into the `dateList` / `valueList` the option
// actually consumes (the JS does the same split with two `.map` calls).
private let lineGradientDates: [String] = [
    "2000-06-05", "2000-06-06", "2000-06-07", "2000-06-08", "2000-06-09",
    "2000-06-10", "2000-06-11", "2000-06-12", "2000-06-13", "2000-06-14",
    "2000-06-15", "2000-06-16", "2000-06-17", "2000-06-18", "2000-06-19",
    "2000-06-20", "2000-06-21", "2000-06-22", "2000-06-23", "2000-06-24",
    "2000-06-25", "2000-06-26", "2000-06-27", "2000-06-28", "2000-06-29",
    "2000-06-30", "2000-07-01", "2000-07-02", "2000-07-03", "2000-07-04",
    "2000-07-05", "2000-07-06", "2000-07-07", "2000-07-08", "2000-07-09",
    "2000-07-10", "2000-07-11", "2000-07-12", "2000-07-13", "2000-07-14",
    "2000-07-15", "2000-07-16", "2000-07-17", "2000-07-18", "2000-07-19",
    "2000-07-20", "2000-07-21", "2000-07-22", "2000-07-23", "2000-07-24"
]

private let lineGradientValues: [Double] = [
    116, 129, 135, 86, 73, 85, 73, 68, 92, 130,
    245, 139, 115, 111, 309, 206, 137, 128, 85, 94,
    71, 106, 84, 93, 85, 73, 83, 125, 107, 82,
    44, 72, 106, 107, 66, 91, 92, 113, 107, 131,
    111, 64, 69, 88, 77, 83, 111, 57, 55, 60
]
