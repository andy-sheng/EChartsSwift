// official-line-log — replica of https://echarts.apache.org/examples/zh/editor.html?c=line-log
// title: Log Axis / titleCN: 对数轴示例
// Three line series (x3, x2, x1/2 progressions) on a `type: 'log'` y-axis with minorSplitLine on,
// so geometric growth/decay plots as straight lines spanning ~1/512 … 6669.
// DEVIATIONS: none of substance — the official source is a single static `option` literal with no
// data fetch, no timers and no JS closures (its `tooltip.formatter` is a template STRING, not a
// function, so it ports verbatim to the native pane). The trailing `export {};` is dropped from
// webOptionJS (a bare export is a SyntaxError in the page's classic script), and the Log1/2 series'
// `1 / 2, 1 / 4, …` divisions are pre-evaluated in the Swift pane only.
extension EChartsDemoRegistry {
    static let official_line_log = EChartsDemo(
        name: "official-line-log", category: "line",
        summary: "对数轴示例 — Log Axis",
        width: 640, height: 420,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
option = {
  title: {
    text: 'Log Axis',
    left: 'center'
  },
  tooltip: {
    trigger: 'item',
    formatter: '{a} <br/>{b} : {c}'
  },
  legend: {
    left: 'left'
  },
  xAxis: {
    type: 'category',
    name: 'x',
    splitLine: { show: false },
    data: ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I']
  },
  grid: {
    left: '3%',
    right: '4%',
    bottom: '3%',
    containLabel: true
  },
  yAxis: {
    type: 'log',
    name: 'y',
    minorSplitLine: {
      show: true
    }
  },
  series: [
    {
      name: 'Log2',
      type: 'line',
      data: [1, 3, 9, 27, 81, 247, 741, 2223, 6669]
    },
    {
      name: 'Log3',
      type: 'line',
      data: [1, 2, 4, 8, 16, 32, 64, 128, 256]
    },
    {
      name: 'Log1/2',
      type: 'line',
      data: [
        1 / 2,
        1 / 4,
        1 / 8,
        1 / 16,
        1 / 32,
        1 / 64,
        1 / 128,
        1 / 256,
        1 / 512
      ]
    }
  ]
};
"""#,
        option: [
            "title": [
                "text": "Log Axis",
                "left": "center"
            ] as [String: Any],
            "tooltip": [
                "trigger": "item",
                "formatter": "{a} <br/>{b} : {c}"
            ] as [String: Any],
            "legend": [
                "left": "left"
            ] as [String: Any],
            "xAxis": [
                "type": "category",
                "name": "x",
                "splitLine": ["show": false] as [String: Any],
                "data": ["A", "B", "C", "D", "E", "F", "G", "H", "I"]
            ] as [String: Any],
            "grid": [
                "left": "3%",
                "right": "4%",
                "bottom": "3%",
                "containLabel": true
            ] as [String: Any],
            "yAxis": [
                "type": "log",
                "name": "y",
                "minorSplitLine": ["show": true] as [String: Any]
            ] as [String: Any],
            "series": [
                [
                    "name": "Log2",
                    "type": "line",
                    "data": lineLogPow3Data
                ] as [String: Any],
                [
                    "name": "Log3",
                    "type": "line",
                    "data": lineLogPow2Data
                ] as [String: Any],
                [
                    "name": "Log1/2",
                    "type": "line",
                    "data": lineLogHalfData
                ] as [String: Any]
            ]
        ])
}

// Series names are the official example's (they read as "Log2"/"Log3" but the progressions are
// x3 / x2 / x(1/2) respectively — kept as-is so both panes' legends match the website).
private let lineLogPow3Data: [Double] = [1, 3, 9, 27, 81, 247, 741, 2223, 6669]
private let lineLogPow2Data: [Double] = [1, 2, 4, 8, 16, 32, 64, 128, 256]
// Upstream writes these as `1 / 2, 1 / 4, … 1 / 512`; pre-evaluated here.
private let lineLogHalfData: [Double] = [
    1.0 / 2, 1.0 / 4, 1.0 / 8, 1.0 / 16, 1.0 / 32,
    1.0 / 64, 1.0 / 128, 1.0 / 256, 1.0 / 512
]
