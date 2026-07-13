// official-bar-simple — replica of https://echarts.apache.org/examples/zh/editor.html?c=bar-simple
// title: Basic Bar / titleCN: 基础柱状图
// A single category-axis bar series over seven weekdays.
// DEVIATIONS: none — the official source is a bare top-level `option` with no data fetch, no
// closures, and no animation/dynamic re-setOption; webOptionJS is verbatim.
extension EChartsDemoRegistry {
    static let official_bar_simple = EChartsDemo(
        name: "official-bar-simple", category: "bar",
        summary: "基础柱状图 — Basic Bar",
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
      type: 'bar'
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
                    "type": "bar"
                ] as [String: Any]
            ]
        ])
}
