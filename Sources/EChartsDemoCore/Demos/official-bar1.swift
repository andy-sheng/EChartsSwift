// official-bar1 — replica of https://echarts.apache.org/examples/zh/editor.html?c=bar1
// title: Rainfall and Evaporation / titleCN: 某地区蒸发量和降水量
// Two bar series over 12 months, each with markLine (average) and markPoint (max/min — the first
// series by `type`, the second by explicit xAxis/yAxis coords); axis tooltip, legend, toolbox.
// DEVIATIONS from the official source:
//   - the trailing `export {};` is dropped (a bare export is a SyntaxError in the page's classic
//     script and would kill the whole reference pane). Nothing else is changed in webOptionJS.
//   - no data fetch, no closures and no timers in the original, so both panes carry the option verbatim.
//   - `calculable: true` is kept as-is: it is a dead ECharts-2 key that current echarts ignores; the
//     native pane ignores it too, so the panes stay aligned.
extension EChartsDemoRegistry {
    static let official_bar1 = EChartsDemo(
        name: "official-bar1", category: "bar",
        summary: "某地区蒸发量和降水量 — Rainfall and Evaporation",
        width: 640, height: 420,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
option = {
  title: {
    text: 'Rainfall vs Evaporation',
    subtext: 'Fake Data'
  },
  tooltip: {
    trigger: 'axis'
  },
  legend: {
    data: ['Rainfall', 'Evaporation']
  },
  toolbox: {
    show: true,
    feature: {
      dataView: { show: true, readOnly: false },
      magicType: { show: true, type: ['line', 'bar'] },
      restore: { show: true },
      saveAsImage: { show: true }
    }
  },
  calculable: true,
  xAxis: [
    {
      type: 'category',
      // prettier-ignore
      data: ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']
    }
  ],
  yAxis: [
    {
      type: 'value'
    }
  ],
  series: [
    {
      name: 'Rainfall',
      type: 'bar',
      data: [
        2.0, 4.9, 7.0, 23.2, 25.6, 76.7, 135.6, 162.2, 32.6, 20.0, 6.4, 3.3
      ],
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
      name: 'Evaporation',
      type: 'bar',
      data: [
        2.6, 5.9, 9.0, 26.4, 28.7, 70.7, 175.6, 182.2, 48.7, 18.8, 6.0, 2.3
      ],
      markPoint: {
        data: [
          { name: 'Max', value: 182.2, xAxis: 7, yAxis: 183 },
          { name: 'Min', value: 2.3, xAxis: 11, yAxis: 3 }
        ]
      },
      markLine: {
        data: [{ type: 'average', name: 'Avg' }]
      }
    }
  ]
};
"""#,
        option: [
            "title": [
                "text": "Rainfall vs Evaporation",
                "subtext": "Fake Data"
            ] as [String: Any],
            "tooltip": [
                "trigger": "axis"
            ] as [String: Any],
            "legend": [
                "data": ["Rainfall", "Evaporation"]
            ] as [String: Any],
            "toolbox": [
                "show": true,
                "feature": [
                    "dataView": ["show": true, "readOnly": false] as [String: Any],
                    "magicType": ["show": true, "type": ["line", "bar"]] as [String: Any],
                    "restore": ["show": true] as [String: Any],
                    "saveAsImage": ["show": true] as [String: Any]
                ] as [String: Any]
            ] as [String: Any],
            // Dead ECharts-2 key, kept for fidelity with the official source (both panes ignore it).
            "calculable": true,
            "xAxis": [
                [
                    "type": "category",
                    "data": bar1Months
                ] as [String: Any]
            ],
            "yAxis": [
                [
                    "type": "value"
                ] as [String: Any]
            ],
            "series": [
                [
                    "name": "Rainfall",
                    "type": "bar",
                    "data": bar1Rainfall,
                    "markPoint": ["data": bar1RainfallMarkPoints] as [String: Any],
                    "markLine": ["data": bar1AvgMarkLine] as [String: Any]
                ] as [String: Any],
                [
                    "name": "Evaporation",
                    "type": "bar",
                    "data": bar1Evaporation,
                    "markPoint": ["data": bar1EvaporationMarkPoints] as [String: Any],
                    "markLine": ["data": bar1AvgMarkLine] as [String: Any]
                ] as [String: Any]
            ]
        ])
}

private let bar1Months: [String] = [
    "Jan", "Feb", "Mar", "Apr", "May", "Jun",
    "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"
]

private let bar1Rainfall: [Double] = [
    2.0, 4.9, 7.0, 23.2, 25.6, 76.7, 135.6, 162.2, 32.6, 20.0, 6.4, 3.3
]

private let bar1Evaporation: [Double] = [
    2.6, 5.9, 9.0, 26.4, 28.7, 70.7, 175.6, 182.2, 48.7, 18.8, 6.0, 2.3
]

// Rainfall: max/min resolved by ECharts from the series data.
private let bar1RainfallMarkPoints: [[String: Any]] = [
    ["type": "max", "name": "Max"],
    ["type": "min", "name": "Min"]
]

// Evaporation: the official example pins these two by explicit axis coords instead of `type`.
private let bar1EvaporationMarkPoints: [[String: Any]] = [
    ["name": "Max", "value": 182.2, "xAxis": 7.0, "yAxis": 183.0],
    ["name": "Min", "value": 2.3, "xAxis": 11.0, "yAxis": 3.0]
]

private let bar1AvgMarkLine: [[String: Any]] = [
    ["type": "average", "name": "Avg"]
]
