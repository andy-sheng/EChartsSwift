// official-line-style — replica of https://echarts.apache.org/examples/zh/editor.html?c=line-style
// title: Line Style and Item Style / titleCN: 自定义折线图样式
// One category line series with a hand-styled look: 'triangle' symbols at size 20, a 4px dashed
// #5470C6 lineStyle, and a yellow itemStyle with a 3px #EE6666 border.
// DEVIATIONS: only the trailing `export {};` is dropped from webOptionJS (a bare export is a
// SyntaxError in a classic script). No data fetch, no closures, no timers in the official source —
// both panes carry the option verbatim.
extension EChartsDemoRegistry {
    static let official_line_style = EChartsDemo(
        name: "official-line-style", category: "line",
        summary: "自定义折线图样式 — Line Style and Item Style",
        width: 640, height: 420,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
option = {
  xAxis: {
    type: 'category',
    data: ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']
  },
  yAxis: {
    type: 'value'
  },
  series: [
    {
      data: [120, 200, 150, 80, 70, 110, 130],
      type: 'line',
      symbol: 'triangle',
      symbolSize: 20,
      lineStyle: {
        color: '#5470C6',
        width: 4,
        type: 'dashed'
      },
      itemStyle: {
        borderWidth: 3,
        borderColor: '#EE6666',
        color: 'yellow'
      }
    }
  ]
};
"""#,
        option: [
            "xAxis": [
                "type": "category",
                "data": ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
            ] as [String: Any],
            "yAxis": [
                "type": "value"
            ] as [String: Any],
            "series": [
                [
                    "data": [120.0, 200.0, 150.0, 80.0, 70.0, 110.0, 130.0],
                    "type": "line",
                    "symbol": "triangle",
                    "symbolSize": 20.0,
                    "lineStyle": [
                        "color": "#5470C6",
                        "width": 4.0,
                        "type": "dashed"
                    ] as [String: Any],
                    "itemStyle": [
                        "borderWidth": 3.0,
                        "borderColor": "#EE6666",
                        "color": "yellow"
                    ] as [String: Any]
                ] as [String: Any]
            ]
        ])
}
