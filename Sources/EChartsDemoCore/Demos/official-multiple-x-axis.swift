// official-multiple-x-axis — replica of https://echarts.apache.org/examples/zh/editor.html?c=multiple-x-axis
// title: Multiple X Axes / titleCN: 多 X 轴
// Two smoothed precipitation lines, each bound to its own category x-axis (2016 on xAxis[0],
// 2015 on xAxis[1]); a cross axisPointer labels both axes at once.
// DEVIATIONS:
//   - webOptionJS: the official source is TypeScript — its two `function (params: any)` axisPointer
//     label formatters are copied verbatim except the `: any` type annotation, which is a SyntaxError
//     in the plain <script> the reference pane runs. Bodies are untouched. Trailing `export {};` dropped.
//   - option (native): both axisPointer label formatters use the equivalent typed Swift callback.
//     Everything else is carried over. Nothing else changed — no data fetch, no timers in the source.
import EChartsKit

extension EChartsDemoRegistry {
    static let official_multiple_x_axis = EChartsDemo(
        name: "official-multiple-x-axis", category: "line",
        summary: "多 X 轴 — Multiple X Axes",
        width: 640, height: 420,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
const colors = ['#5470C6', '#EE6666'];

option = {
  color: colors,

  tooltip: {
    trigger: 'none',
    axisPointer: {
      type: 'cross'
    }
  },
  legend: {},
  grid: {
    top: 70,
    bottom: 50
  },
  xAxis: [
    {
      type: 'category',
      axisTick: {
        alignWithLabel: true
      },
      axisLine: {
        onZero: false,
        lineStyle: {
          color: colors[1]
        }
      },
      axisPointer: {
        label: {
          formatter: function (params) {
            return (
              'Precipitation  ' +
              params.value +
              (params.seriesData.length ? '：' + params.seriesData[0].data : '')
            );
          }
        }
      },

      // prettier-ignore
      data: ['2016-1', '2016-2', '2016-3', '2016-4', '2016-5', '2016-6', '2016-7', '2016-8', '2016-9', '2016-10', '2016-11', '2016-12']
    },
    {
      type: 'category',
      axisTick: {
        alignWithLabel: true
      },
      axisLine: {
        onZero: false,
        lineStyle: {
          color: colors[0]
        }
      },
      axisPointer: {
        label: {
          formatter: function (params) {
            return (
              'Precipitation  ' +
              params.value +
              (params.seriesData.length ? '：' + params.seriesData[0].data : '')
            );
          }
        }
      },

      // prettier-ignore
      data: ['2015-1', '2015-2', '2015-3', '2015-4', '2015-5', '2015-6', '2015-7', '2015-8', '2015-9', '2015-10', '2015-11', '2015-12']
    }
  ],
  yAxis: [
    {
      type: 'value'
    }
  ],
  series: [
    {
      name: 'Precipitation(2015)',
      type: 'line',
      xAxisIndex: 1,
      smooth: true,
      emphasis: {
        focus: 'series'
      },
      data: [
        2.6, 5.9, 9.0, 26.4, 28.7, 70.7, 175.6, 182.2, 48.7, 18.8, 6.0, 2.3
      ]
    },
    {
      name: 'Precipitation(2016)',
      type: 'line',
      smooth: true,
      emphasis: {
        focus: 'series'
      },
      data: [
        3.9, 5.9, 11.1, 18.7, 48.3, 69.2, 231.6, 46.6, 55.4, 18.4, 10.3, 0.7
      ]
    }
  ]
};
"""#,
        option: [
            "color": multipleXAxisColors,
            "tooltip": [
                "trigger": "none",
                "axisPointer": [
                    "type": "cross"
                ] as [String: Any]
            ] as [String: Any],
            "legend": [:] as [String: Any],
            "grid": [
                "top": 70.0,
                "bottom": 50.0
            ] as [String: Any],
            "xAxis": [
                [
                    "type": "category",
                    "axisTick": [
                        "alignWithLabel": true
                    ] as [String: Any],
                    "axisLine": [
                        "onZero": false,
                        "lineStyle": [
                            "color": multipleXAxisColors[1]
                        ] as [String: Any]
                    ] as [String: Any],
                    "axisPointer": [
                        "label": [
                            "formatter": multipleXAxisPointerLabelFormatter
                        ] as [String: Any]
                    ] as [String: Any],
                    "data": multipleXAxis2016Categories
                ] as [String: Any],
                [
                    "type": "category",
                    "axisTick": [
                        "alignWithLabel": true
                    ] as [String: Any],
                    "axisLine": [
                        "onZero": false,
                        "lineStyle": [
                            "color": multipleXAxisColors[0]
                        ] as [String: Any]
                    ] as [String: Any],
                    "axisPointer": [
                        "label": [
                            "formatter": multipleXAxisPointerLabelFormatter
                        ] as [String: Any]
                    ] as [String: Any],
                    "data": multipleXAxis2015Categories
                ] as [String: Any]
            ],
            "yAxis": [
                [
                    "type": "value"
                ] as [String: Any]
            ],
            "series": [
                [
                    "name": "Precipitation(2015)",
                    "type": "line",
                    "xAxisIndex": 1.0,
                    "smooth": true,
                    "emphasis": [
                        "focus": "series"
                    ] as [String: Any],
                    "data": multipleXAxis2015Data
                ] as [String: Any],
                [
                    "name": "Precipitation(2016)",
                    "type": "line",
                    "smooth": true,
                    "emphasis": [
                        "focus": "series"
                    ] as [String: Any],
                    "data": multipleXAxis2016Data
                ] as [String: Any]
            ]
        ])
}

private let multipleXAxisColors: [String] = ["#5470C6", "#EE6666"]

private let multipleXAxisPointerLabelFormatter: ([String: Any]) -> String = { params in
    let value = params["value"].map(String.init(describing:)) ?? ""
    let seriesData = params["seriesData"] as? [CallbackDataParams]
    let data = seriesData?.first.map { multipleXAxisValueString($0.data) } ?? ""
    let suffix = data.isEmpty ? "" : "：\(data)"
    return "Precipitation  \(value)\(suffix)"
}

private func multipleXAxisValueString(_ value: Any) -> String {
    if let value = value as? Double { return String(value) }
    if let value = value as? Int { return String(value) }
    let mirror = Mirror(reflecting: value)
    if mirror.displayStyle == .optional, let child = mirror.children.first {
        return multipleXAxisValueString(child.value)
    }
    return String(describing: value)
}

private let multipleXAxis2016Categories: [String] = [
    "2016-1", "2016-2", "2016-3", "2016-4", "2016-5", "2016-6",
    "2016-7", "2016-8", "2016-9", "2016-10", "2016-11", "2016-12"
]

private let multipleXAxis2015Categories: [String] = [
    "2015-1", "2015-2", "2015-3", "2015-4", "2015-5", "2015-6",
    "2015-7", "2015-8", "2015-9", "2015-10", "2015-11", "2015-12"
]

private let multipleXAxis2015Data: [Double] = [
    2.6, 5.9, 9.0, 26.4, 28.7, 70.7, 175.6, 182.2, 48.7, 18.8, 6.0, 2.3
]

private let multipleXAxis2016Data: [Double] = [
    3.9, 5.9, 11.1, 18.7, 48.3, 69.2, 231.6, 46.6, 55.4, 18.4, 10.3, 0.7
]
