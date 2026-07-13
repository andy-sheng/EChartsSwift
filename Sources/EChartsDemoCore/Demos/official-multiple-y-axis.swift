// official-multiple-y-axis — replica of https://echarts.apache.org/examples/zh/editor.html?c=multiple-y-axis
// title: Multiple Y Axes / titleCN: 多 Y 轴示例
// Two bars (Evaporation, Precipitation) + one line (Temperature) on a shared category x-axis, each
// bound to its OWN value y-axis: two stacked on the right (the second pushed out by `offset: 80`),
// one on the left. Each axis is tinted with its series' colour via axisLine.lineStyle and labelled
// with a unit suffix; `alignTicks` makes the three independent scales share tick rows. `grid.right:
// '20%'` reserves the room the offset right-hand axis needs.
// DEVIATIONS: none of substance — both panes carry the official option. The 12-point series arrays
// are hoisted to file-scope `private let`s in the Swift pane (type-checker budget), and the `colors`
// const is inlined into the Swift `color` array. Every axisLabel.formatter here is a STRING template
// ('{value} ml'), not a JS closure, so the native pane keeps them verbatim — nothing is omitted.
// The toolbox (dataView / restore / saveAsImage) renders as icons in both panes; its features are
// interactive-only and do nothing in a static snapshot.
extension EChartsDemoRegistry {
    static let official_multiple_y_axis = EChartsDemo(
        name: "official-multiple-y-axis", category: "bar",
        summary: "多 Y 轴示例 — Multiple Y Axes",
        width: 640, height: 420,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
const colors = ['#5070dd', '#b6d634', '#505372'];

option = {
  color: colors,

  tooltip: {
    trigger: 'axis',
    axisPointer: {
      type: 'cross'
    }
  },
  grid: {
    right: '20%'
  },
  toolbox: {
    feature: {
      dataView: { show: true, readOnly: false },
      restore: { show: true },
      saveAsImage: { show: true }
    }
  },
  legend: {
    data: ['Evaporation', 'Precipitation', 'Temperature']
  },
  xAxis: [
    {
      type: 'category',
      axisTick: {
        alignWithLabel: true
      },
      // prettier-ignore
      data: ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']
    }
  ],
  yAxis: [
    {
      type: 'value',
      name: 'Evaporation',
      position: 'right',
      alignTicks: true,
      axisLine: {
        show: true,
        lineStyle: {
          color: colors[0]
        }
      },
      axisLabel: {
        formatter: '{value} ml'
      }
    },
    {
      type: 'value',
      name: 'Precipitation',
      position: 'right',
      alignTicks: true,
      offset: 80,
      axisLine: {
        show: true,
        lineStyle: {
          color: colors[1]
        }
      },
      axisLabel: {
        formatter: '{value} ml'
      }
    },
    {
      type: 'value',
      name: '温度',
      position: 'left',
      alignTicks: true,
      axisLine: {
        show: true,
        lineStyle: {
          color: colors[2]
        }
      },
      axisLabel: {
        formatter: '{value} °C'
      }
    }
  ],
  series: [
    {
      name: 'Evaporation',
      type: 'bar',
      data: [
        2.0, 4.9, 7.0, 23.2, 25.6, 76.7, 135.6, 162.2, 32.6, 20.0, 6.4, 3.3
      ]
    },
    {
      name: 'Precipitation',
      type: 'bar',
      yAxisIndex: 1,
      data: [
        2.6, 5.9, 9.0, 26.4, 28.7, 70.7, 175.6, 182.2, 48.7, 18.8, 6.0, 2.3
      ]
    },
    {
      name: 'Temperature',
      type: 'line',
      yAxisIndex: 2,
      data: [2.0, 2.2, 3.3, 4.5, 6.3, 10.2, 20.3, 23.4, 23.0, 16.5, 12.0, 6.2]
    }
  ]
};
"""#,
        option: [
            "color": multipleYAxisColors,
            "tooltip": [
                "trigger": "axis",
                "axisPointer": [
                    "type": "cross"
                ] as [String: Any]
            ] as [String: Any],
            "grid": [
                "right": "20%"
            ] as [String: Any],
            "toolbox": [
                "feature": [
                    "dataView": ["show": true, "readOnly": false] as [String: Any],
                    "restore": ["show": true] as [String: Any],
                    "saveAsImage": ["show": true] as [String: Any]
                ] as [String: Any]
            ] as [String: Any],
            "legend": [
                "data": ["Evaporation", "Precipitation", "Temperature"]
            ] as [String: Any],
            "xAxis": [
                [
                    "type": "category",
                    "axisTick": [
                        "alignWithLabel": true
                    ] as [String: Any],
                    "data": multipleYAxisMonths
                ] as [String: Any]
            ],
            "yAxis": [
                [
                    "type": "value",
                    "name": "Evaporation",
                    "position": "right",
                    "alignTicks": true,
                    "axisLine": [
                        "show": true,
                        "lineStyle": [
                            "color": multipleYAxisColors[0]
                        ] as [String: Any]
                    ] as [String: Any],
                    "axisLabel": [
                        "formatter": "{value} ml"
                    ] as [String: Any]
                ] as [String: Any],
                [
                    "type": "value",
                    "name": "Precipitation",
                    "position": "right",
                    "alignTicks": true,
                    "offset": 80.0,
                    "axisLine": [
                        "show": true,
                        "lineStyle": [
                            "color": multipleYAxisColors[1]
                        ] as [String: Any]
                    ] as [String: Any],
                    "axisLabel": [
                        "formatter": "{value} ml"
                    ] as [String: Any]
                ] as [String: Any],
                [
                    "type": "value",
                    "name": "温度",
                    "position": "left",
                    "alignTicks": true,
                    "axisLine": [
                        "show": true,
                        "lineStyle": [
                            "color": multipleYAxisColors[2]
                        ] as [String: Any]
                    ] as [String: Any],
                    "axisLabel": [
                        "formatter": "{value} °C"
                    ] as [String: Any]
                ] as [String: Any]
            ],
            "series": [
                [
                    "name": "Evaporation",
                    "type": "bar",
                    "data": multipleYAxisEvaporation
                ] as [String: Any],
                [
                    "name": "Precipitation",
                    "type": "bar",
                    "yAxisIndex": 1.0,
                    "data": multipleYAxisPrecipitation
                ] as [String: Any],
                [
                    "name": "Temperature",
                    "type": "line",
                    "yAxisIndex": 2.0,
                    "data": multipleYAxisTemperature
                ] as [String: Any]
            ]
        ])
}

// The example's `const colors` — one per series, reused to tint each series' own y-axis line.
private let multipleYAxisColors: [String] = ["#5070dd", "#b6d634", "#505372"]

private let multipleYAxisMonths: [String] = [
    "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"
]

private let multipleYAxisEvaporation: [Double] = [
    2.0, 4.9, 7.0, 23.2, 25.6, 76.7, 135.6, 162.2, 32.6, 20.0, 6.4, 3.3
]

private let multipleYAxisPrecipitation: [Double] = [
    2.6, 5.9, 9.0, 26.4, 28.7, 70.7, 175.6, 182.2, 48.7, 18.8, 6.0, 2.3
]

private let multipleYAxisTemperature: [Double] = [
    2.0, 2.2, 3.3, 4.5, 6.3, 10.2, 20.3, 23.4, 23.0, 16.5, 12.0, 6.2
]
