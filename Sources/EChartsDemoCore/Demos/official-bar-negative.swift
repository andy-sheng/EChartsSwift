// official-bar-negative — replica of https://echarts.apache.org/examples/zh/editor.html?c=bar-negative
// title: Bar Chart with Negative Value / titleCN: 正负条形图
// Horizontal bars (value x-axis, category y-axis): an unstacked 'Profit' series plus a 'Total'-stacked
// 'Income' (positive) / 'Expenses' (negative) pair, so the stacked bars straddle the zero line.
// Inline labels, shadow axisPointer tooltip, emphasis focus:'series'.
// DEVIATIONS: the trailing `export {};` is dropped (a bare export is a SyntaxError in the reference
// pane's classic script). Nothing else — the official source is a single static `option` literal
// with no data fetch, no closures and no timers, so both panes carry it verbatim.
extension EChartsDemoRegistry {
    static let official_bar_negative = EChartsDemo(
        name: "official-bar-negative", category: "bar",
        summary: "正负条形图 — Bar Chart with Negative Value",
        width: 640, height: 420,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
option = {
  tooltip: {
    trigger: 'axis',
    axisPointer: {
      type: 'shadow'
    }
  },
  legend: {
    data: ['Profit', 'Expenses', 'Income']
  },
  xAxis: [
    {
      type: 'value'
    }
  ],
  yAxis: [
    {
      type: 'category',
      axisTick: {
        show: false
      },
      data: ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']
    }
  ],
  series: [
    {
      name: 'Profit',
      type: 'bar',
      label: {
        show: true,
        position: 'inside'
      },
      emphasis: {
        focus: 'series'
      },
      data: [200, 170, 240, 244, 200, 220, 210]
    },
    {
      name: 'Income',
      type: 'bar',
      stack: 'Total',
      label: {
        show: true
      },
      emphasis: {
        focus: 'series'
      },
      data: [320, 302, 341, 374, 390, 450, 420]
    },
    {
      name: 'Expenses',
      type: 'bar',
      stack: 'Total',
      label: {
        show: true,
        position: 'left'
      },
      emphasis: {
        focus: 'series'
      },
      data: [-120, -132, -101, -134, -190, -230, -210]
    }
  ]
};
"""#,
        option: [
            "tooltip": [
                "trigger": "axis",
                "axisPointer": [
                    "type": "shadow"
                ] as [String: Any]
            ] as [String: Any],
            "legend": [
                "data": ["Profit", "Expenses", "Income"]
            ] as [String: Any],
            "xAxis": [
                [
                    "type": "value"
                ] as [String: Any]
            ],
            "yAxis": [
                [
                    "type": "category",
                    "axisTick": [
                        "show": false
                    ] as [String: Any],
                    "data": ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
                ] as [String: Any]
            ],
            "series": [
                [
                    "name": "Profit",
                    "type": "bar",
                    "label": [
                        "show": true,
                        "position": "inside"
                    ] as [String: Any],
                    "emphasis": [
                        "focus": "series"
                    ] as [String: Any],
                    "data": barNegativeProfitData
                ] as [String: Any],
                [
                    "name": "Income",
                    "type": "bar",
                    "stack": "Total",
                    "label": [
                        "show": true
                    ] as [String: Any],
                    "emphasis": [
                        "focus": "series"
                    ] as [String: Any],
                    "data": barNegativeIncomeData
                ] as [String: Any],
                [
                    "name": "Expenses",
                    "type": "bar",
                    "stack": "Total",
                    "label": [
                        "show": true,
                        "position": "left"
                    ] as [String: Any],
                    "emphasis": [
                        "focus": "series"
                    ] as [String: Any],
                    "data": barNegativeExpensesData
                ] as [String: Any]
            ]
        ])
}

// One value per Mon…Sun category. Expenses are negative — they run left of the zero line, stacked
// against Income under the shared 'Total' stack.
private let barNegativeProfitData: [Double] = [200, 170, 240, 244, 200, 220, 210]
private let barNegativeIncomeData: [Double] = [320, 302, 341, 374, 390, 450, 420]
private let barNegativeExpensesData: [Double] = [-120, -132, -101, -134, -190, -230, -210]
