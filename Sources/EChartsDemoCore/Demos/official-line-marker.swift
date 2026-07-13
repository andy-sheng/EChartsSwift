// official-line-marker — replica of https://echarts.apache.org/examples/zh/editor.html?c=line-marker
// title: Temperature Change in the Coming Week / titleCN: 未来一周气温变化
// Two category-axis line series ("Highest"/"Lowest") exercising markPoint (type max/min + a manual
// coord-pinned point) and markLine (type average, plus a two-endpoint line built from an [start, end]
// pair), with title/legend/axis-trigger tooltip and the full toolbox feature set.
// DEVIATIONS: none. The official source is a single static `option` literal — no data fetch, no
// timers, no re-setOption. Both formatters it uses ('{value} °C' on the yAxis label, 'Max' on a
// markLine label) are STRING templates, not JS closures, so the native Swift option carries them
// verbatim too; nothing is omitted from the native pane. Only the editor boilerplate is stripped
// from webOptionJS (the leading `/* title: ... */` block and the trailing `export {};`).
extension EChartsDemoRegistry {
    static let official_line_marker = EChartsDemo(
        name: "official-line-marker", category: "line",
        summary: "未来一周气温变化 — Temperature Change in the Coming Week",
        width: 640, height: 420,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
option = {
  title: {
    text: 'Temperature Change in the Coming Week'
  },
  tooltip: {
    trigger: 'axis'
  },
  legend: {},
  toolbox: {
    show: true,
    feature: {
      dataZoom: {
        yAxisIndex: 'none'
      },
      dataView: { readOnly: false },
      magicType: { type: ['line', 'bar'] },
      restore: {},
      saveAsImage: {}
    }
  },
  xAxis: {
    type: 'category',
    boundaryGap: false,
    data: ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']
  },
  yAxis: {
    type: 'value',
    axisLabel: {
      formatter: '{value} °C'
    }
  },
  series: [
    {
      name: 'Highest',
      type: 'line',
      data: [10, 11, 13, 11, 12, 12, 9],
      markPoint: {
        data: [
          { type: 'max', name: 'Max' },
          { type: 'min', name: 'Min' }
        ]
      },
      markLine: {
        data: [{ type: 'average', name: 'Avg' }]
      }
    },
    {
      name: 'Lowest',
      type: 'line',
      data: [1, -2, 2, 5, 3, 2, 0],
      markPoint: {
        data: [{ name: '周最低', value: -2, xAxis: 1, yAxis: -1.5 }]
      },
      markLine: {
        data: [
          { type: 'average', name: 'Avg' },
          [
            {
              symbol: 'none',
              x: '90%',
              yAxis: 'max'
            },
            {
              symbol: 'circle',
              label: {
                position: 'start',
                formatter: 'Max'
              },
              type: 'max',
              name: '最高点'
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
                "text": "Temperature Change in the Coming Week"
            ] as [String: Any],
            "tooltip": [
                "trigger": "axis"
            ] as [String: Any],
            "legend": [:] as [String: Any],
            "toolbox": [
                "show": true,
                "feature": [
                    "dataZoom": ["yAxisIndex": "none"] as [String: Any],
                    "dataView": ["readOnly": false] as [String: Any],
                    "magicType": ["type": ["line", "bar"]] as [String: Any],
                    "restore": [:] as [String: Any],
                    "saveAsImage": [:] as [String: Any]
                ] as [String: Any]
            ] as [String: Any],
            "xAxis": [
                "type": "category",
                "boundaryGap": false,
                "data": ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
            ] as [String: Any],
            "yAxis": [
                "type": "value",
                "axisLabel": [
                    "formatter": "{value} °C"
                ] as [String: Any]
            ] as [String: Any],
            "series": [
                [
                    "name": "Highest",
                    "type": "line",
                    "data": lineMarkerHighestData,
                    "markPoint": [
                        "data": [
                            ["type": "max", "name": "Max"] as [String: Any],
                            ["type": "min", "name": "Min"] as [String: Any]
                        ]
                    ] as [String: Any],
                    "markLine": [
                        "data": [
                            ["type": "average", "name": "Avg"] as [String: Any]
                        ]
                    ] as [String: Any]
                ] as [String: Any],
                [
                    "name": "Lowest",
                    "type": "line",
                    "data": lineMarkerLowestData,
                    "markPoint": [
                        "data": [
                            [
                                "name": "周最低",
                                "value": -2.0,
                                "xAxis": 1.0,
                                "yAxis": -1.5
                            ] as [String: Any]
                        ]
                    ] as [String: Any],
                    "markLine": [
                        "data": lineMarkerLowestMarkLineData
                    ] as [String: Any]
                ] as [String: Any]
            ]
        ])
}

// Daily highs / lows, Mon…Sun.
private let lineMarkerHighestData: [Double] = [10, 11, 13, 11, 12, 12, 9]
private let lineMarkerLowestData: [Double] = [1, -2, 2, 5, 3, 2, 0]

// Heterogeneous by design: a single-point markLine spec (`type: 'average'`) alongside a
// [start, end] PAIR that draws one explicit line — from a pixel-x/axis-y anchor at 90% width up to
// the series max. Hoisted out of the option literal so the type-checker never has to unify them.
private let lineMarkerLowestMarkLineData: [Any] = [
    ["type": "average", "name": "Avg"] as [String: Any],
    [
        [
            "symbol": "none",
            "x": "90%",
            "yAxis": "max"
        ] as [String: Any],
        [
            "symbol": "circle",
            "label": [
                "position": "start",
                "formatter": "Max"
            ] as [String: Any],
            "type": "max",
            "name": "最高点"
        ] as [String: Any]
    ] as [Any]
]
