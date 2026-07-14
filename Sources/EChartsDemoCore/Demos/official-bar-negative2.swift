// official-bar-negative2 — replica of https://echarts.apache.org/examples/zh/editor.html?c=bar-negative2
// title: Bar Chart with Negative Value / titleCN: 交错正负轴标签
// A single stacked bar series straddling zero on a value x-axis pinned to the top; the y-axis
// category names are hidden and instead drawn as the bars' own labels (`formatter: '{b}'`), flipped
// to `position: 'right'` on the negative items so every label sits on the outside of its bar.
// DEVIATIONS: none of substance — the official source is a static `option` literal with no data
// fetch, no timers and no closures (its only formatter is the STRING template '{b}', which the Swift
// option carries verbatim), so both panes render the same thing. The web pane drops only what a
// classic script cannot parse: the `as const` type assertion on `labelRight` and the trailing
// `export {};`.
extension EChartsDemoRegistry {
    static let official_bar_negative2 = EChartsDemo(
        name: "official-bar-negative2", category: "bar",
        summary: "交错正负轴标签 — Bar Chart with Negative Value",
        width: 640, height: 420,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
const labelRight = {
  position: 'right'
};

option = {
  title: {
    text: 'Bar Chart with Negative Value'
  },
  tooltip: {
    trigger: 'axis',
    axisPointer: {
      type: 'shadow'
    }
  },
  grid: {
    top: 80,
    bottom: 30
  },
  xAxis: {
    type: 'value',
    position: 'top',
    splitLine: {
      lineStyle: {
        type: 'dashed'
      }
    }
  },
  yAxis: {
    type: 'category',
    axisLine: { show: false },
    axisLabel: { show: false },
    axisTick: { show: false },
    splitLine: { show: false },
    data: [
      'ten',
      'nine',
      'eight',
      'seven',
      'six',
      'five',
      'four',
      'three',
      'two',
      'one'
    ]
  },
  series: [
    {
      name: 'Cost',
      type: 'bar',
      stack: 'Total',
      label: {
        show: true,
        formatter: '{b}'
      },
      data: [
        { value: -0.07, label: labelRight },
        { value: -0.09, label: labelRight },
        0.2,
        0.44,
        { value: -0.23, label: labelRight },
        0.08,
        { value: -0.17, label: labelRight },
        0.47,
        { value: -0.36, label: labelRight },
        0.18
      ]
    }
  ]
};
"""#,
        option: [
            "title": [
                "text": "Bar Chart with Negative Value"
            ] as [String: Any],
            "tooltip": [
                "trigger": "axis",
                "axisPointer": [
                    "type": "shadow"
                ] as [String: Any]
            ] as [String: Any],
            "grid": [
                "top": 80.0,
                "bottom": 30.0
            ] as [String: Any],
            "xAxis": [
                "type": "value",
                "position": "top",
                "splitLine": [
                    "lineStyle": [
                        "type": "dashed"
                    ] as [String: Any]
                ] as [String: Any]
            ] as [String: Any],
            "yAxis": [
                "type": "category",
                "axisLine": ["show": false] as [String: Any],
                "axisLabel": ["show": false] as [String: Any],
                "axisTick": ["show": false] as [String: Any],
                "splitLine": ["show": false] as [String: Any],
                "data": barNegative2Categories
            ] as [String: Any],
            "series": [
                [
                    "name": "Cost",
                    "type": "bar",
                    "stack": "Total",
                    "label": [
                        "show": true,
                        "formatter": "{b}"
                    ] as [String: Any],
                    "data": barNegative2Data
                ] as [String: Any]
            ]
        ])
}

private let barNegative2Categories: [String] = [
    "ten", "nine", "eight", "seven", "six", "five", "four", "three", "two", "one"
]

// The example's `labelRight` const: negative bars flip their label to the far side of zero so it
// never overlaps the bar it names.
private let barNegative2LabelRight: [String: Any] = ["position": "right"]

// Heterogeneous by design (upstream mixes bare numbers with `{ value, label }` item objects) —
// hence `[Any]` with an explicit type, which also keeps the type-checker off the literal.
private let barNegative2Data: [Any] = [
    ["value": -0.07, "label": barNegative2LabelRight] as [String: Any],
    ["value": -0.09, "label": barNegative2LabelRight] as [String: Any],
    0.2,
    0.44,
    ["value": -0.23, "label": barNegative2LabelRight] as [String: Any],
    0.08,
    ["value": -0.17, "label": barNegative2LabelRight] as [String: Any],
    0.47,
    ["value": -0.36, "label": barNegative2LabelRight] as [String: Any],
    0.18
]
