// official-line-stack — replica of https://echarts.apache.org/examples/zh/editor.html?c=line-stack
// title: Stacked Line Chart / titleCN: 堆叠折线图
// Five `line` series sharing `stack: 'Total'` on a category x-axis (boundaryGap: false), with
// title / axis-trigger tooltip / legend / containLabel grid / saveAsImage toolbox.
// DEVIATIONS: only the trailing `export {};` is dropped (a bare export is a SyntaxError in the
// reference pane's classic script). Both panes otherwise carry the official option verbatim — no
// data fetch, no closures, no timers in the source.
extension EChartsDemoRegistry {
    static let official_line_stack = EChartsDemo(
        name: "official-line-stack", category: "line",
        summary: "堆叠折线图 — Stacked Line Chart",
        width: 640, height: 420,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
option = {
  title: {
    text: 'Stacked Line'
  },
  tooltip: {
    trigger: 'axis'
  },
  legend: {
    data: ['Email', 'Union Ads', 'Video Ads', 'Direct', 'Search Engine']
  },
  grid: {
    left: '3%',
    right: '4%',
    bottom: '3%',
    containLabel: true
  },
  toolbox: {
    feature: {
      saveAsImage: {}
    }
  },
  xAxis: {
    type: 'category',
    boundaryGap: false,
    data: ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']
  },
  yAxis: {
    type: 'value'
  },
  series: [
    {
      name: 'Email',
      type: 'line',
      stack: 'Total',
      data: [120, 132, 101, 134, 90, 230, 210]
    },
    {
      name: 'Union Ads',
      type: 'line',
      stack: 'Total',
      data: [220, 182, 191, 234, 290, 330, 310]
    },
    {
      name: 'Video Ads',
      type: 'line',
      stack: 'Total',
      data: [150, 232, 201, 154, 190, 330, 410]
    },
    {
      name: 'Direct',
      type: 'line',
      stack: 'Total',
      data: [320, 332, 301, 334, 390, 330, 320]
    },
    {
      name: 'Search Engine',
      type: 'line',
      stack: 'Total',
      data: [820, 932, 901, 934, 1290, 1330, 1320]
    }
  ]
};
"""#,
        option: [
            "title": [
                "text": "Stacked Line"
            ] as [String: Any],
            "tooltip": [
                "trigger": "axis"
            ] as [String: Any],
            "legend": [
                "data": lineStackSeriesNames
            ] as [String: Any],
            "grid": [
                "left": "3%",
                "right": "4%",
                "bottom": "3%",
                "containLabel": true
            ] as [String: Any],
            "toolbox": [
                "feature": [
                    "saveAsImage": [:] as [String: Any]
                ] as [String: Any]
            ] as [String: Any],
            "xAxis": [
                "type": "category",
                "boundaryGap": false,
                "data": ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
            ] as [String: Any],
            "yAxis": [
                "type": "value"
            ] as [String: Any],
            "series": lineStackSeries
        ])
}

private let lineStackSeriesNames: [String] = [
    "Email", "Union Ads", "Video Ads", "Direct", "Search Engine"
]

// One row per series, in `lineStackSeriesNames` order; 7 points each (Mon…Sun).
private let lineStackData: [[Double]] = [
    [120, 132, 101, 134, 90, 230, 210],
    [220, 182, 191, 234, 290, 330, 310],
    [150, 232, 201, 154, 190, 330, 410],
    [320, 332, 301, 334, 390, 330, 320],
    [820, 932, 901, 934, 1290, 1330, 1320]
]

private let lineStackSeries: [[String: Any]] = zip(lineStackSeriesNames, lineStackData).map { name, data in
    [
        "name": name,
        "type": "line",
        "stack": "Total",
        "data": data
    ] as [String: Any]
}
