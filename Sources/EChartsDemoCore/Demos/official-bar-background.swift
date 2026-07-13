// official-bar-background — replica of https://echarts.apache.org/examples/zh/editor.html?c=bar-background
// title: Bar with Background / titleCN: 带背景色的柱状图
// Seven category bars, each drawn over a translucent grey full-height track (`showBackground` +
// `backgroundStyle.color`).
// DEVIATIONS: none — the official source is a single static `option` literal with no data fetch,
// no closures and no timers, so both panes carry it verbatim (only the official editor's trailing
// `export {};` is dropped, since a bare export is a SyntaxError in the classic-script web pane).
extension EChartsDemoRegistry {
    static let official_bar_background = EChartsDemo(
        name: "official-bar-background", category: "bar",
        summary: "带背景色的柱状图 — Bar with Background",
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
      type: 'bar',
      showBackground: true,
      backgroundStyle: {
        color: 'rgba(180, 180, 180, 0.2)'
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
                    "type": "bar",
                    "showBackground": true,
                    "backgroundStyle": [
                        "color": "rgba(180, 180, 180, 0.2)"
                    ] as [String: Any]
                ] as [String: Any]
            ]
        ])
}
