// official-dataset-simple1 — replica of https://echarts.apache.org/examples/zh/editor.html?c=dataset-simple1
// title: Dataset in Object Array / titleCN: 对象数组的输入格式
// The object-array form of `dataset`: `dimensions` names the four columns and `source` is a row of
// key→value objects (rather than the 2-D table of dataset-simple0). Three bar series each map to one
// dimension of the dataset by default (no `encode`).
// DEVIATIONS from the official source: none — the option is verbatim (the editor's trailing
// `export {};` is dropped; it is a SyntaxError in the reference pane's classic script). The Swift
// `option` mirrors it 1:1; the source rows are hoisted into a `private let` typed `[[String: Any]]`
// only to keep Swift's type-checker off the untyped-literal path. Note the Swift rows are unordered
// dictionaries, which is harmless here precisely because `dimensions` declares the column order.

/// dataset.source in the object-row format: one dictionary per product, keyed by dimension name.
/// Heterogeneous by construction — `product` is the category name, the year keys carry the values.
private let datasetSimple1Source: [[String: Any]] = [
    ["product": "Matcha Latte", "2015": 43.3, "2016": 85.8, "2017": 93.7],
    ["product": "Milk Tea", "2015": 83.1, "2016": 73.4, "2017": 55.1],
    ["product": "Cheese Cocoa", "2015": 86.4, "2016": 65.2, "2017": 82.5],
    ["product": "Walnut Brownie", "2015": 72.4, "2016": 53.9, "2017": 39.1]
]

extension EChartsDemoRegistry {
    static let official_dataset_simple1 = EChartsDemo(
        name: "official-dataset-simple1", category: "dataset",
        summary: "对象数组的输入格式 — Dataset in Object Array",
        width: 640, height: 420,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
option = {
  legend: {},
  tooltip: {},
  dataset: {
    dimensions: ['product', '2015', '2016', '2017'],
    source: [
      { product: 'Matcha Latte', '2015': 43.3, '2016': 85.8, '2017': 93.7 },
      { product: 'Milk Tea', '2015': 83.1, '2016': 73.4, '2017': 55.1 },
      { product: 'Cheese Cocoa', '2015': 86.4, '2016': 65.2, '2017': 82.5 },
      { product: 'Walnut Brownie', '2015': 72.4, '2016': 53.9, '2017': 39.1 }
    ]
  },
  xAxis: { type: 'category' },
  yAxis: {},
  // Declare several bar series, each will be mapped
  // to a column of dataset.source by default.
  series: [{ type: 'bar' }, { type: 'bar' }, { type: 'bar' }]
};
"""#,
        option: [
            "legend": [:] as [String: Any],
            "tooltip": [:] as [String: Any],
            "dataset": [
                "dimensions": ["product", "2015", "2016", "2017"],
                "source": datasetSimple1Source
            ] as [String: Any],
            "xAxis": ["type": "category"] as [String: Any],
            "yAxis": [:] as [String: Any],
            // Three bar series, each mapped to a column of dataset.source by default.
            "series": [
                ["type": "bar"] as [String: Any],
                ["type": "bar"] as [String: Any],
                ["type": "bar"] as [String: Any]
            ]
        ])
}
