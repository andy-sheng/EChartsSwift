// official-area-basic — replica of https://echarts.apache.org/examples/zh/editor.html?c=area-basic
// title: Basic area chart / titleCN: 基础面积图
// One `line` series with an empty `areaStyle: {}` (which is what turns a line into an area — the fill
// color defaults to the series' line color), on a category x-axis with `boundaryGap: false` so the
// area meets both edges of the grid.
// DEVIATIONS: none of substance — the official source is a single static `option` literal: no data
// fetch, no closures, no timers. Only the editor's leading /* title/category/difficulty */ metadata
// comment and the trailing `export {};` are dropped (a bare `export` is a SyntaxError in the web
// pane's classic script and would blank the whole page). Both panes otherwise carry it verbatim.
extension EChartsDemoRegistry {
    static let official_area_basic = EChartsDemo(
        name: "official-area-basic", category: "line",
        summary: "基础面积图 — Basic area chart",
        width: 640, height: 420,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
option = {
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
      data: [820, 932, 901, 934, 1290, 1330, 1320],
      type: 'line',
      areaStyle: {}
    }
  ]
};
"""#,
        option: [
            "xAxis": [
                "type": "category",
                "boundaryGap": false,
                "data": ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
            ] as [String: Any],
            "yAxis": [
                "type": "value"
            ] as [String: Any],
            "series": [
                [
                    "data": [820.0, 932.0, 901.0, 934.0, 1290.0, 1330.0, 1320.0],
                    "type": "line",
                    // Empty on purpose: `areaStyle: {}` is the whole point of the example.
                    "areaStyle": [:] as [String: Any]
                ] as [String: Any]
            ]
        ])
}
