// official-line-simple — replica of https://echarts.apache.org/examples/zh/editor.html?c=line-simple
// title: Basic Line Chart / titleCN: 基础折线图
extension EChartsDemoRegistry {
    static let official_line_simple = EChartsDemo(
        name: "official-line-simple", category: "line",
        summary: "基础折线图 — Basic Line Chart",
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
      data: [150, 230, 224, 218, 135, 147, 260],
      type: 'line'
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
                    "data": [150.0, 230.0, 224.0, 218.0, 135.0, 147.0, 260.0],
                    "type": "line"
                ] as [String: Any]
            ]
        ])
}
