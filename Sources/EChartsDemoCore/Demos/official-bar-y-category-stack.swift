// official-bar-y-category-stack — replica of https://echarts.apache.org/examples/zh/editor.html?c=bar-y-category-stack
// title: Stacked Horizontal Bar / titleCN: 堆叠条形图
// Five bar series sharing one stack ('total') on a category y-axis / value x-axis, with in-bar
// labels, `emphasis.focus: 'series'` and a shadow axisPointer tooltip.
// DEVIATIONS: none — the official source is a single static `option` literal: no data fetch, no
// closures, no timers. Both panes carry it verbatim (the trailing `export {};` is dropped, as it is
// a SyntaxError in the reference pane's classic script).
extension EChartsDemoRegistry {
    static let official_bar_y_category_stack = EChartsDemo(
        name: "official-bar-y-category-stack", category: "bar",
        summary: "堆叠条形图 — Stacked Horizontal Bar",
        width: 640, height: 420,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
option = {
  tooltip: {
    trigger: 'axis',
    axisPointer: {
      // Use axis to trigger tooltip
      type: 'shadow' // 'shadow' as default; can also be 'line' or 'shadow'
    }
  },
  legend: {},
  xAxis: {
    type: 'value'
  },
  yAxis: {
    type: 'category',
    data: ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']
  },
  series: [
    {
      name: 'Direct',
      type: 'bar',
      stack: 'total',
      label: {
        show: true
      },
      emphasis: {
        focus: 'series'
      },
      data: [320, 302, 301, 334, 390, 330, 320]
    },
    {
      name: 'Mail Ad',
      type: 'bar',
      stack: 'total',
      label: {
        show: true
      },
      emphasis: {
        focus: 'series'
      },
      data: [120, 132, 101, 134, 90, 230, 210]
    },
    {
      name: 'Affiliate Ad',
      type: 'bar',
      stack: 'total',
      label: {
        show: true
      },
      emphasis: {
        focus: 'series'
      },
      data: [220, 182, 191, 234, 290, 330, 310]
    },
    {
      name: 'Video Ad',
      type: 'bar',
      stack: 'total',
      label: {
        show: true
      },
      emphasis: {
        focus: 'series'
      },
      data: [150, 212, 201, 154, 190, 330, 410]
    },
    {
      name: 'Search Engine',
      type: 'bar',
      stack: 'total',
      label: {
        show: true
      },
      emphasis: {
        focus: 'series'
      },
      data: [820, 832, 901, 934, 1290, 1330, 1320]
    }
  ]
};
"""#,
        option: [
            "tooltip": [
                "trigger": "axis",
                // Use axis to trigger tooltip
                "axisPointer": [
                    "type": "shadow"  // 'shadow' as default; can also be 'line' or 'shadow'
                ] as [String: Any]
            ] as [String: Any],
            "legend": [:] as [String: Any],
            "xAxis": [
                "type": "value"
            ] as [String: Any],
            "yAxis": [
                "type": "category",
                "data": ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
            ] as [String: Any],
            "series": barYCategoryStackSeries
        ])
}

// One entry per stacked series: (legend name, the seven weekday values).
private let barYCategoryStackData: [(String, [Double])] = [
    ("Direct", [320, 302, 301, 334, 390, 330, 320]),
    ("Mail Ad", [120, 132, 101, 134, 90, 230, 210]),
    ("Affiliate Ad", [220, 182, 191, 234, 290, 330, 310]),
    ("Video Ad", [150, 212, 201, 154, 190, 330, 410]),
    ("Search Engine", [820, 832, 901, 934, 1290, 1330, 1320])
]

// All five series are identical but for name/data, so build them from the table above rather than
// writing out five copies of the same literal.
private let barYCategoryStackSeries: [[String: Any]] = barYCategoryStackData.map { name, data in
    [
        "name": name,
        "type": "bar",
        "stack": "total",
        "label": [
            "show": true
        ] as [String: Any],
        "emphasis": [
            "focus": "series"
        ] as [String: Any],
        "data": data
    ] as [String: Any]
}
