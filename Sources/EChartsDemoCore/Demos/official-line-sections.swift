// official-line-sections — replica of https://echarts.apache.org/examples/zh/editor.html?c=line-sections
// title: Distribution of Electricity / titleCN: 一天用电量分布
// Smooth line of a day's power draw over 20 quarter-hour-ish ticks. A piecewise `visualMap` on
// dimension 0 (the x index) recolors the line green/red by time-of-day band, and two `markArea`
// bands shade the morning and evening peaks. Also exercises axisPointer 'cross' + snap, a
// '{value} W' axisLabel template, and the saveAsImage toolbox feature.
// DEVIATIONS: none of substance — the official source is a single static `option` literal with no
// data fetch, no timers and no closures, so both panes carry it verbatim. Only the trailing
// `export {};` is dropped (a bare export is a SyntaxError in the classic-script web pane).
// The axisLabel formatter is a STRING TEMPLATE, not a function, so the native option keeps it.
extension EChartsDemoRegistry {
    static let official_line_sections = EChartsDemo(
        name: "official-line-sections", category: "line",
        summary: "一天用电量分布 — Distribution of Electricity",
        width: 640, height: 420,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
option = {
  title: {
    text: 'Distribution of Electricity',
    subtext: 'Fake Data'
  },
  tooltip: {
    trigger: 'axis',
    axisPointer: {
      type: 'cross'
    }
  },
  toolbox: {
    show: true,
    feature: {
      saveAsImage: {}
    }
  },
  xAxis: {
    type: 'category',
    boundaryGap: false,
    // prettier-ignore
    data: ['00:00', '01:15', '02:30', '03:45', '05:00', '06:15', '07:30', '08:45', '10:00', '11:15', '12:30', '13:45', '15:00', '16:15', '17:30', '18:45', '20:00', '21:15', '22:30', '23:45']
  },
  yAxis: {
    type: 'value',
    axisLabel: {
      formatter: '{value} W'
    },
    axisPointer: {
      snap: true
    }
  },
  visualMap: {
    show: false,
    dimension: 0,
    pieces: [
      {
        lte: 6,
        color: 'green'
      },
      {
        gt: 6,
        lte: 8,
        color: 'red'
      },
      {
        gt: 8,
        lte: 14,
        color: 'green'
      },
      {
        gt: 14,
        lte: 17,
        color: 'red'
      },
      {
        gt: 17,
        color: 'green'
      }
    ]
  },
  series: [
    {
      name: 'Electricity',
      type: 'line',
      smooth: true,
      // prettier-ignore
      data: [300, 280, 250, 260, 270, 300, 550, 500, 400, 390, 380, 390, 400, 500, 600, 750, 800, 700, 600, 400],
      markArea: {
        itemStyle: {
          color: 'rgba(255, 173, 177, 0.4)'
        },
        data: [
          [
            {
              name: 'Morning Peak',
              xAxis: '07:30'
            },
            {
              xAxis: '10:00'
            }
          ],
          [
            {
              name: 'Evening Peak',
              xAxis: '17:30'
            },
            {
              xAxis: '21:15'
            }
          ]
        ]
      }
    }
  ]
};
"""#,
        option: [
            "title": [
                "text": "Distribution of Electricity",
                "subtext": "Fake Data"
            ] as [String: Any],
            "tooltip": [
                "trigger": "axis",
                "axisPointer": [
                    "type": "cross"
                ] as [String: Any]
            ] as [String: Any],
            "toolbox": [
                "show": true,
                "feature": [
                    "saveAsImage": [:] as [String: Any]
                ] as [String: Any]
            ] as [String: Any],
            "xAxis": [
                "type": "category",
                "boundaryGap": false,
                "data": lineSectionsHours
            ] as [String: Any],
            "yAxis": [
                "type": "value",
                "axisLabel": [
                    "formatter": "{value} W"   // string template, not a closure — portable as-is
                ] as [String: Any],
                "axisPointer": [
                    "snap": true
                ] as [String: Any]
            ] as [String: Any],
            "visualMap": [
                "show": false,
                "dimension": 0.0,
                "pieces": lineSectionsPieces
            ] as [String: Any],
            "series": [
                [
                    "name": "Electricity",
                    "type": "line",
                    "smooth": true,
                    "data": lineSectionsData,
                    "markArea": [
                        "itemStyle": [
                            "color": "rgba(255, 173, 177, 0.4)"
                        ] as [String: Any],
                        "data": lineSectionsMarkAreas
                    ] as [String: Any]
                ] as [String: Any]
            ]
        ])
}

// Quarter-past ticks across one day (20 samples).
private let lineSectionsHours: [String] = [
    "00:00", "01:15", "02:30", "03:45", "05:00", "06:15", "07:30", "08:45", "10:00", "11:15",
    "12:30", "13:45", "15:00", "16:15", "17:30", "18:45", "20:00", "21:15", "22:30", "23:45"
]

// Watts drawn at each tick.
private let lineSectionsData: [Double] = [
    300, 280, 250, 260, 270, 300, 550, 500, 400, 390,
    380, 390, 400, 500, 600, 750, 800, 700, 600, 400
]

// Piecewise recolor by x-index band: green off-peak, red across the two peaks.
private let lineSectionsPieces: [[String: Any]] = [
    ["lte": 6.0, "color": "green"],
    ["gt": 6.0, "lte": 8.0, "color": "red"],
    ["gt": 8.0, "lte": 14.0, "color": "green"],
    ["gt": 14.0, "lte": 17.0, "color": "red"],
    ["gt": 17.0, "color": "green"]
]

// Each entry is a [start, end] pair of x-axis-anchored corners.
private let lineSectionsMarkAreas: [[[String: Any]]] = [
    [
        ["name": "Morning Peak", "xAxis": "07:30"],
        ["xAxis": "10:00"]
    ],
    [
        ["name": "Evening Peak", "xAxis": "17:30"],
        ["xAxis": "21:15"]
    ]
]
