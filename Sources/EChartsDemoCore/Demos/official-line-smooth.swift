// official-line-smooth — replica of https://echarts.apache.org/examples/zh/editor.html?c=line-smooth
// title: Smoothed Line Chart / titleCN: 基础平滑折线图
// One `line` series with `smooth: true` over a 7-point category axis (Mon–Sun).
// DEVIATIONS: none — the official source is a single static `option` literal with no data fetch,
// no closures and no timers, so both panes carry it verbatim (only the source's trailing
// `export {};` is dropped: a bare export is a SyntaxError in the reference pane's classic script).
extension EChartsDemoRegistry {
    static let official_line_smooth = EChartsDemo(
        name: "official-line-smooth", category: "line",
        summary: "基础平滑折线图 — Smoothed Line Chart",
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
      data: [820, 932, 901, 934, 1290, 1330, 1320],
      type: 'line',
      smooth: true
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
                    "data": [820.0, 932.0, 901.0, 934.0, 1290.0, 1330.0, 1320.0],
                    "type": "line",
                    "smooth": true
                ] as [String: Any]
            ]
        ])
}
