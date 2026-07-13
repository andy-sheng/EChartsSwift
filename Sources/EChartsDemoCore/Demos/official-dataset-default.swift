// official-dataset-default — replica of https://echarts.apache.org/examples/zh/editor.html?c=dataset-default
// title: Default arrangement / titleCN: 默认 encode 设置
// One `dataset.source` (a header row + 4 product rows) feeding four pie series in a 2x2 grid. The
// first pie declares NO `encode` — it exercises the default arrangement (itemName = first column
// 'product', value = first non-header column '2012'); the other three encode '2013'/'2014'/'2015'
// explicitly, so the four pies read as year-over-year slices of the same table.
// DEVIATIONS: only the trailing `export {};` is dropped (a bare export is a SyntaxError in the
// classic script the reference pane runs). No data fetch, no closures, no timers in the official
// source — both panes carry the option otherwise verbatim.
extension EChartsDemoRegistry {
    static let official_dataset_default = EChartsDemo(
        name: "official-dataset-default", category: "dataset",
        summary: "默认 encode 设置 — Default arrangement",
        width: 640, height: 420,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
option = {
  legend: {},
  tooltip: {},
  dataset: {
    source: [
      ['product', '2012', '2013', '2014', '2015', '2016', '2017'],
      ['Milk Tea', 86.5, 92.1, 85.7, 83.1, 73.4, 55.1],
      ['Matcha Latte', 41.1, 30.4, 65.1, 53.3, 83.8, 98.7],
      ['Cheese Cocoa', 24.1, 67.2, 79.5, 86.4, 65.2, 82.5],
      ['Walnut Brownie', 55.2, 67.1, 69.2, 72.4, 53.9, 39.1]
    ]
  },
  series: [
    {
      type: 'pie',
      radius: '20%',
      center: ['25%', '30%']
      // No encode specified, by default, it is '2012'.
    },
    {
      type: 'pie',
      radius: '20%',
      center: ['75%', '30%'],
      encode: {
        itemName: 'product',
        value: '2013'
      }
    },
    {
      type: 'pie',
      radius: '20%',
      center: ['25%', '75%'],
      encode: {
        itemName: 'product',
        value: '2014'
      }
    },
    {
      type: 'pie',
      radius: '20%',
      center: ['75%', '75%'],
      encode: {
        itemName: 'product',
        value: '2015'
      }
    }
  ]
};
"""#,
        option: [
            "legend": [:] as [String: Any],
            "tooltip": [:] as [String: Any],
            "dataset": [
                "source": datasetDefaultSource
            ] as [String: Any],
            "series": [
                // No encode specified, by default, it is '2012'.
                [
                    "type": "pie",
                    "radius": "20%",
                    "center": ["25%", "30%"]
                ] as [String: Any],
                [
                    "type": "pie",
                    "radius": "20%",
                    "center": ["75%", "30%"],
                    "encode": [
                        "itemName": "product",
                        "value": "2013"
                    ] as [String: Any]
                ] as [String: Any],
                [
                    "type": "pie",
                    "radius": "20%",
                    "center": ["25%", "75%"],
                    "encode": [
                        "itemName": "product",
                        "value": "2014"
                    ] as [String: Any]
                ] as [String: Any],
                [
                    "type": "pie",
                    "radius": "20%",
                    "center": ["75%", "75%"],
                    "encode": [
                        "itemName": "product",
                        "value": "2015"
                    ] as [String: Any]
                ] as [String: Any]
            ]
        ])
}

// Header row (dimension names) + one row per product; columns are the years 2012...2017.
private let datasetDefaultSource: [[Any]] = [
    ["product", "2012", "2013", "2014", "2015", "2016", "2017"],
    ["Milk Tea", 86.5, 92.1, 85.7, 83.1, 73.4, 55.1],
    ["Matcha Latte", 41.1, 30.4, 65.1, 53.3, 83.8, 98.7],
    ["Cheese Cocoa", 24.1, 67.2, 79.5, 86.4, 65.2, 82.5],
    ["Walnut Brownie", 55.2, 67.1, 69.2, 72.4, 53.9, 39.1]
]
