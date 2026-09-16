// official-radar-custom — replica of https://echarts.apache.org/examples/zh/editor.html?c=radar-custom
// title: Customized Radar Chart / titleCN: 自定义雷达图
//
// Two radar coordinate systems side by side, each with its own series (radarIndex 0/1):
//   - LEFT  (center 25%): a `shape: 'circle'` radar, startAngle 90, splitNumber 4, indicators with no
//     `max` (auto-ranged from the data), a 4-band coloured splitArea with a drop shadow, and an
//     axisName decorated by the STRING formatter '【{value}】'. Its two data items ('Data A' / 'Data B')
//     carry an emphasis lineStyle and a per-item areaStyle.
//   - RIGHT (center 75%): a plain polygon radar with explicit per-indicator `max`, axisName rendered as
//     white text on a rounded grey chip. 'Data C' uses rect symbols + a dashed line + a value label;
//     'Data D' is filled with a RadialGradient.
//
// DEVIATIONS from the official source:
//   1. The trailing `export {};` is dropped — a bare export is a SyntaxError in the reference pane's
//      classic script and would blank the whole page.
//   2. The `label.formatter: function (params: any) { return params.value as string; }` on 'Data C'
//      loses its TypeScript annotation/cast in webOptionJS (`function (params) { return params.value; }`).
//      The official editor compiles TS; the reference pane runs the snippet as plain JS, where `: any`
//      is a SyntaxError. The closure's behaviour is unchanged.
//   3. The Swift option spells 'Data D's fill as the plain-object gradient form
//      (`{type:'radial', x:.., y:.., r:.., colorStops:[...]}`) instead of
//      `new echarts.graphic.RadialGradient(0.1, 0.6, 1, [...])` — echarts accepts both, and it is the
//      only form a `[String: Any]` can carry. webOptionJS keeps the `new echarts.graphic...` call verbatim.
//   4. The Swift option omits the one JS closure ('Data C's `label.formatter`) — see the note where
//      it would have gone. The label still shows (`show: true`), just with the default text.
// No data fetch, no map, no timer/animation in the source — everything else is carried verbatim.
extension EChartsDemoRegistry {
    static let official_radar_custom = EChartsDemo(
        name: "official-radar-custom", category: "radar",
        summary: "自定义雷达图 — Customized Radar Chart",
        width: 640, height: 420,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
option = {
  color: ['#67F9D8', '#FFE434', '#56A3F1', '#FF917C'],
  title: {
    text: 'Customized Radar Chart'
  },
  legend: {},
  radar: [
    {
      indicator: [
        { text: 'Indicator1' },
        { text: 'Indicator2' },
        { text: 'Indicator3' },
        { text: 'Indicator4' },
        { text: 'Indicator5' }
      ],
      center: ['25%', '50%'],
      radius: 120,
      startAngle: 90,
      splitNumber: 4,
      shape: 'circle',
      axisName: {
        formatter: '【{value}】',
        color: '#428BD4'
      },
      splitArea: {
        areaStyle: {
          color: ['#77EADF', '#26C3BE', '#64AFE9', '#428BD4'],
          shadowColor: 'rgba(0, 0, 0, 0.2)',
          shadowBlur: 10
        }
      },
      axisLine: {
        lineStyle: {
          color: 'rgba(211, 253, 250, 0.8)'
        }
      },
      splitLine: {
        lineStyle: {
          color: 'rgba(211, 253, 250, 0.8)'
        }
      }
    },
    {
      indicator: [
        { text: 'Indicator1', max: 150 },
        { text: 'Indicator2', max: 150 },
        { text: 'Indicator3', max: 150 },
        { text: 'Indicator4', max: 120 },
        { text: 'Indicator5', max: 108 },
        { text: 'Indicator6', max: 72 }
      ],
      center: ['75%', '50%'],
      radius: 120,
      axisName: {
        color: '#fff',
        backgroundColor: '#666',
        borderRadius: 3,
        padding: [3, 5]
      }
    }
  ],
  series: [
    {
      type: 'radar',
      emphasis: {
        lineStyle: {
          width: 4
        }
      },
      data: [
        {
          value: [100, 8, 0.4, -80, 2000],
          name: 'Data A'
        },
        {
          value: [60, 5, 0.3, -100, 1500],
          name: 'Data B',
          areaStyle: {
            color: 'rgba(255, 228, 52, 0.6)'
          }
        }
      ]
    },
    {
      type: 'radar',
      radarIndex: 1,
      data: [
        {
          value: [120, 118, 130, 100, 99, 70],
          name: 'Data C',
          symbol: 'rect',
          symbolSize: 12,
          lineStyle: {
            type: 'dashed'
          },
          label: {
            show: true,
            formatter: function (params) {
              return params.value;
            }
          }
        },
        {
          value: [100, 93, 50, 90, 70, 60],
          name: 'Data D',
          areaStyle: {
            color: new echarts.graphic.RadialGradient(0.1, 0.6, 1, [
              {
                color: 'rgba(255, 145, 124, 0.1)',
                offset: 0
              },
              {
                color: 'rgba(255, 145, 124, 0.9)',
                offset: 1
              }
            ])
          }
        }
      ]
    }
  ]
};
"""#,
        option: [
            "color": ["#67F9D8", "#FFE434", "#56A3F1", "#FF917C"],
            "title": [
                "text": "Customized Radar Chart"
            ] as [String: Any],
            "legend": [:] as [String: Any],
            "radar": [
                [
                    "indicator": radarCustomIndicatorsLeft,
                    "center": ["25%", "50%"],
                    "radius": 120.0,
                    "startAngle": 90.0,
                    "splitNumber": 4.0,
                    "shape": "circle",
                    "axisName": [
                        "formatter": "【{value}】",
                        "color": "#428BD4"
                    ] as [String: Any],
                    "splitArea": [
                        "areaStyle": [
                            "color": ["#77EADF", "#26C3BE", "#64AFE9", "#428BD4"],
                            "shadowColor": "rgba(0, 0, 0, 0.2)",
                            "shadowBlur": 10.0
                        ] as [String: Any]
                    ] as [String: Any],
                    "axisLine": [
                        "lineStyle": [
                            "color": "rgba(211, 253, 250, 0.8)"
                        ] as [String: Any]
                    ] as [String: Any],
                    "splitLine": [
                        "lineStyle": [
                            "color": "rgba(211, 253, 250, 0.8)"
                        ] as [String: Any]
                    ] as [String: Any]
                ] as [String: Any],
                [
                    "indicator": radarCustomIndicatorsRight,
                    "center": ["75%", "50%"],
                    "radius": 120.0,
                    "axisName": [
                        "color": "#fff",
                        "backgroundColor": "#666",
                        "borderRadius": 3.0,
                        "padding": [3.0, 5.0]
                    ] as [String: Any]
                ] as [String: Any]
            ] as [Any],
            "series": [
                [
                    "type": "radar",
                    "emphasis": [
                        "lineStyle": [
                            "width": 4.0
                        ] as [String: Any]
                    ] as [String: Any],
                    "data": [
                        [
                            "value": [100.0, 8.0, 0.4, -80.0, 2000.0],
                            "name": "Data A"
                        ] as [String: Any],
                        [
                            "value": [60.0, 5.0, 0.3, -100.0, 1500.0],
                            "name": "Data B",
                            "areaStyle": [
                                "color": "rgba(255, 228, 52, 0.6)"
                            ] as [String: Any]
                        ] as [String: Any]
                    ] as [Any]
                ] as [String: Any],
                [
                    "type": "radar",
                    "radarIndex": 1.0,
                    "data": [
                        [
                            "value": [120.0, 118.0, 130.0, 100.0, 99.0, 70.0],
                            "name": "Data C",
                            "symbol": "rect",
                            "symbolSize": 12.0,
                            "lineStyle": [
                                "type": "dashed"
                            ] as [String: Any],
                            "label": [
                                "show": true
                                // formatter omitted — the JS closure returned `params.value`
                                //   (the item's whole value array, stringified by echarts into a
                                //   comma-joined list) as the point label. Native uses the default label
                                //   text instead.
                            ] as [String: Any]
                        ] as [String: Any],
                        [
                            "value": [100.0, 93.0, 50.0, 90.0, 70.0, 60.0],
                            "name": "Data D",
                            "areaStyle": [
                                "color": radarCustomDataDFill
                            ] as [String: Any]
                        ] as [String: Any]
                    ] as [Any]
                ] as [String: Any]
            ] as [Any]
        ])
}

// MARK: - file-scope data (hoisted + explicitly typed: inline dictionary-array literals stall the type-checker)

/// Left radar: no `max` — each axis is auto-ranged from the series data.
private let radarCustomIndicatorsLeft: [[String: Any]] = [
    ["text": "Indicator1"],
    ["text": "Indicator2"],
    ["text": "Indicator3"],
    ["text": "Indicator4"],
    ["text": "Indicator5"]
]

/// Right radar: explicit per-indicator maxima.
private let radarCustomIndicatorsRight: [[String: Any]] = [
    ["text": "Indicator1", "max": 150.0],
    ["text": "Indicator2", "max": 150.0],
    ["text": "Indicator3", "max": 150.0],
    ["text": "Indicator4", "max": 120.0],
    ["text": "Indicator5", "max": 108.0],
    ["text": "Indicator6", "max": 72.0]
]

/// `new echarts.graphic.RadialGradient(0.1, 0.6, 1, [...])` in plain-object form (deviation 3).
private let radarCustomDataDFill: [String: Any] = [
    "type": "radial",
    "x": 0.1, "y": 0.6, "r": 1.0,
    "colorStops": [
        ["color": "rgba(255, 145, 124, 0.1)", "offset": 0.0] as [String: Any],
        ["color": "rgba(255, 145, 124, 0.9)", "offset": 1.0] as [String: Any]
    ] as [Any]
]
