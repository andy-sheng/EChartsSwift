// official-line-step — replica of https://echarts.apache.org/examples/zh/editor.html?c=line-step
// title: Step Line / titleCN: 阶梯折线图
// Three line series over the same weekday category axis, one per `step` mode ('start' / 'middle' /
// 'end'), plus title / axis tooltip / legend / containLabel grid / saveAsImage toolbox.
// DEVIATIONS: none — the official source is a single static `option` literal with no data fetch, no
// closures and no timers. Only the trailing `export {};` is dropped (a bare export is a SyntaxError
// in the reference pane's classic script).
extension EChartsDemoRegistry {
    static let official_line_step = EChartsDemo(
        name: "official-line-step", category: "line",
        summary: "阶梯折线图 — Step Line",
        width: 640, height: 420,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
option = {
  title: {
    text: 'Step Line'
  },
  tooltip: {
    trigger: 'axis'
  },
  legend: {
    data: ['Step Start', 'Step Middle', 'Step End']
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
    data: ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']
  },
  yAxis: {
    type: 'value'
  },
  series: [
    {
      name: 'Step Start',
      type: 'line',
      step: 'start',
      data: [120, 132, 101, 134, 90, 230, 210]
    },
    {
      name: 'Step Middle',
      type: 'line',
      step: 'middle',
      data: [220, 282, 201, 234, 290, 430, 410]
    },
    {
      name: 'Step End',
      type: 'line',
      step: 'end',
      data: [450, 432, 401, 454, 590, 530, 510]
    }
  ]
};
"""#,
        option: [
            "title": [
                "text": "Step Line"
            ] as [String: Any],
            "tooltip": [
                "trigger": "axis"
            ] as [String: Any],
            "legend": [
                "data": ["Step Start", "Step Middle", "Step End"]
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
                "data": ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
            ] as [String: Any],
            "yAxis": [
                "type": "value"
            ] as [String: Any],
            "series": lineStepSeries
        ])
}

// One series per `step` mode; same 7-point weekday category axis.
private let lineStepSeries: [[String: Any]] = [
    [
        "name": "Step Start",
        "type": "line",
        "step": "start",
        "data": [120.0, 132.0, 101.0, 134.0, 90.0, 230.0, 210.0]
    ],
    [
        "name": "Step Middle",
        "type": "line",
        "step": "middle",
        "data": [220.0, 282.0, 201.0, 234.0, 290.0, 430.0, 410.0]
    ],
    [
        "name": "Step End",
        "type": "line",
        "step": "end",
        "data": [450.0, 432.0, 401.0, 454.0, 590.0, 530.0, 510.0]
    ]
]
