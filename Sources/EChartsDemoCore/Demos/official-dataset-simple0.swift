// official-dataset-simple0 — replica of https://echarts.apache.org/examples/zh/editor.html?c=dataset-simple0
// title: Simple Example of Dataset / titleCN: 最简单的数据集（dataset）
// A `dataset.source` 2-D table (header row + 4 product rows) feeding three bar series; each series
// maps to one column of the dataset by default (no `encode`, no `seriesLayoutBy`).
// DEVIATIONS from the official source: none — the option is verbatim (the editor's `app.*` harness and
// `myChart.setOption` are not part of the example body). The Swift `option` mirrors it 1:1; the
// dataset rows are hoisted into a `private let` typed `[[Any]]` (heterogeneous String/Double table)
// only to keep Swift's type-checker off the untyped-literal path.

/// dataset.source: header row (`product`, then the three year columns) + one row per product.
/// Heterogeneous by construction — column 0 is the category name, columns 1...3 are values.
private let datasetSimple0Source: [[Any]] = [
    ["product", "2015", "2016", "2017"],
    ["Matcha Latte", 43.3, 85.8, 93.7],
    ["Milk Tea", 83.1, 73.4, 55.1],
    ["Cheese Cocoa", 86.4, 65.2, 82.5],
    ["Walnut Brownie", 72.4, 53.9, 39.1]
]

extension EChartsDemoRegistry {
    static let official_dataset_simple0 = EChartsDemo(
        name: "official-dataset-simple0", category: "dataset",
        summary: "最简单的数据集（dataset） — Simple Example of Dataset",
        width: 640, height: 420,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
option = {
  legend: {},
  tooltip: {},
  dataset: {
    source: [
      ['product', '2015', '2016', '2017'],
      ['Matcha Latte', 43.3, 85.8, 93.7],
      ['Milk Tea', 83.1, 73.4, 55.1],
      ['Cheese Cocoa', 86.4, 65.2, 82.5],
      ['Walnut Brownie', 72.4, 53.9, 39.1]
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
                "source": datasetSimple0Source
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
