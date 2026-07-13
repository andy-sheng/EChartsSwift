// official-bar-y-category — replica of https://echarts.apache.org/examples/zh/editor.html?c=bar-y-category
// title: World Population / titleCN: 世界人口总量 - 条形图
// Two bar series (2011 / 2012) on a value x-axis + category y-axis, i.e. a horizontal bar chart;
// shadow axisPointer on an axis-trigger tooltip, legend fed by the series names.
// DEVIATIONS: only the official editor's trailing `export {};` is dropped (a bare export is a
// SyntaxError in the reference pane's classic script). No data fetch, no closures, no timers in the
// source, so both panes carry the option verbatim.
extension EChartsDemoRegistry {
    static let official_bar_y_category = EChartsDemo(
        name: "official-bar-y-category", category: "bar",
        summary: "世界人口总量 - 条形图 — World Population",
        width: 640, height: 420,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
option = {
  title: {
    text: 'World Population'
  },
  tooltip: {
    trigger: 'axis',
    axisPointer: {
      type: 'shadow'
    }
  },
  legend: {},
  xAxis: {
    type: 'value',
    boundaryGap: [0, 0.01]
  },
  yAxis: {
    type: 'category',
    data: ['Brazil', 'Indonesia', 'USA', 'India', 'China', 'World']
  },
  series: [
    {
      name: '2011',
      type: 'bar',
      data: [18203, 23489, 29034, 104970, 131744, 630230]
    },
    {
      name: '2012',
      type: 'bar',
      data: [19325, 23438, 31000, 121594, 134141, 681807]
    }
  ]
};
"""#,
        option: [
            "title": [
                "text": "World Population"
            ] as [String: Any],
            "tooltip": [
                "trigger": "axis",
                "axisPointer": [
                    "type": "shadow"
                ] as [String: Any]
            ] as [String: Any],
            "legend": [:] as [String: Any],
            "xAxis": [
                "type": "value",
                "boundaryGap": [0.0, 0.01]
            ] as [String: Any],
            "yAxis": [
                "type": "category",
                "data": ["Brazil", "Indonesia", "USA", "India", "China", "World"]
            ] as [String: Any],
            "series": [
                [
                    "name": "2011",
                    "type": "bar",
                    "data": barYCategory2011
                ] as [String: Any],
                [
                    "name": "2012",
                    "type": "bar",
                    "data": barYCategory2012
                ] as [String: Any]
            ]
        ])
}

// Population per country, in the y-axis category order (Brazil … World).
private let barYCategory2011: [Double] = [18203, 23489, 29034, 104970, 131744, 630230]
private let barYCategory2012: [Double] = [19325, 23438, 31000, 121594, 134141, 681807]
