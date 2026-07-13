// official-dataset-series-layout-by — replica of https://echarts.apache.org/examples/zh/editor.html?c=dataset-series-layout-by
// title: Series Layout By Column or Row / titleCN: 系列按行和按列排布
// One dataset, two grids. The top grid's three bar series take `seriesLayoutBy: 'row'` (one series per
// dataset ROW → per product, categories are the years); the bottom grid's four series use the default
// column layout (one series per dataset COLUMN → per year, categories are the products).
// DEVIATIONS: the trailing `export {};` is dropped from webOptionJS (a bare export is a SyntaxError in
// a classic script and would kill the page). Otherwise both panes carry the official source verbatim —
// it is a single static `option` literal with no data fetch, no closures and no timers.
extension EChartsDemoRegistry {
    static let official_dataset_series_layout_by = EChartsDemo(
        name: "official-dataset-series-layout-by", category: "dataset",
        summary: "系列按行和按列排布 — Series Layout By Column or Row",
        width: 640, height: 420,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
option = {
  legend: {},
  tooltip: {},
  dataset: {
    source: [
      ['product', '2012', '2013', '2014', '2015'],
      ['Matcha Latte', 41.1, 30.4, 65.1, 53.3],
      ['Milk Tea', 86.5, 92.1, 85.7, 83.1],
      ['Cheese Cocoa', 24.1, 67.2, 79.5, 86.4]
    ]
  },
  xAxis: [
    { type: 'category', gridIndex: 0 },
    { type: 'category', gridIndex: 1 }
  ],
  yAxis: [{ gridIndex: 0 }, { gridIndex: 1 }],
  grid: [{ bottom: '55%' }, { top: '55%' }],
  series: [
    // These series are in the first grid.
    { type: 'bar', seriesLayoutBy: 'row' },
    { type: 'bar', seriesLayoutBy: 'row' },
    { type: 'bar', seriesLayoutBy: 'row' },
    // These series are in the second grid.
    { type: 'bar', xAxisIndex: 1, yAxisIndex: 1 },
    { type: 'bar', xAxisIndex: 1, yAxisIndex: 1 },
    { type: 'bar', xAxisIndex: 1, yAxisIndex: 1 },
    { type: 'bar', xAxisIndex: 1, yAxisIndex: 1 }
  ]
};
"""#,
        option: [
            "legend": [:] as [String: Any],
            "tooltip": [:] as [String: Any],
            "dataset": [
                "source": datasetSeriesLayoutBySource
            ] as [String: Any],
            "xAxis": [
                ["type": "category", "gridIndex": 0.0] as [String: Any],
                ["type": "category", "gridIndex": 1.0] as [String: Any]
            ],
            "yAxis": [
                ["gridIndex": 0.0] as [String: Any],
                ["gridIndex": 1.0] as [String: Any]
            ],
            "grid": [
                ["bottom": "55%"] as [String: Any],
                ["top": "55%"] as [String: Any]
            ],
            "series": [
                // These series are in the first grid.
                ["type": "bar", "seriesLayoutBy": "row"] as [String: Any],
                ["type": "bar", "seriesLayoutBy": "row"] as [String: Any],
                ["type": "bar", "seriesLayoutBy": "row"] as [String: Any],
                // These series are in the second grid.
                ["type": "bar", "xAxisIndex": 1.0, "yAxisIndex": 1.0] as [String: Any],
                ["type": "bar", "xAxisIndex": 1.0, "yAxisIndex": 1.0] as [String: Any],
                ["type": "bar", "xAxisIndex": 1.0, "yAxisIndex": 1.0] as [String: Any],
                ["type": "bar", "xAxisIndex": 1.0, "yAxisIndex": 1.0] as [String: Any]
            ]
        ])
}

// Header row + one row per product; columns are the years 2012–2015.
private let datasetSeriesLayoutBySource: [[Any]] = [
    ["product", "2012", "2013", "2014", "2015"],
    ["Matcha Latte", 41.1, 30.4, 65.1, 53.3],
    ["Milk Tea", 86.5, 92.1, 85.7, 83.1],
    ["Cheese Cocoa", 24.1, 67.2, 79.5, 86.4]
]
