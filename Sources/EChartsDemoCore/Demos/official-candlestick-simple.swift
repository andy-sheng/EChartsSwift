// official-candlestick-simple — replica of https://echarts.apache.org/examples/zh/editor.html?c=candlestick-simple
// title: Basic Candlestick / titleCN: 基础 K 线图
// Four OHLC bars ([open, close, lowest, highest]) on a category x-axis; no styling, no dataZoom.
// DEVIATIONS: none — the official source is a single static `option` literal with no data fetch,
// no closures and no timers, so both panes carry it verbatim.
extension EChartsDemoRegistry {
    static let official_candlestick_simple = EChartsDemo(
        name: "official-candlestick-simple", category: "candlestick",
        summary: "基础 K 线图 — Basic Candlestick",
        width: 640, height: 420,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
option = {
  xAxis: {
    data: ['2017-10-24', '2017-10-25', '2017-10-26', '2017-10-27']
  },
  yAxis: {},
  series: [
    {
      type: 'candlestick',
      data: [
        [20, 34, 10, 38],
        [40, 35, 30, 50],
        [31, 38, 33, 44],
        [38, 15, 5, 42]
      ]
    }
  ]
};
"""#,
        option: [
            "xAxis": [
                "data": ["2017-10-24", "2017-10-25", "2017-10-26", "2017-10-27"]
            ] as [String: Any],
            "yAxis": [:] as [String: Any],
            "series": [
                [
                    "type": "candlestick",
                    "data": candlestickSimpleData
                ] as [String: Any]
            ]
        ])
}

// [open, close, lowest, highest] per bar.
private let candlestickSimpleData: [[Double]] = [
    [20, 34, 10, 38],
    [40, 35, 30, 50],
    [31, 38, 33, 44],
    [38, 15, 5, 42]
]
