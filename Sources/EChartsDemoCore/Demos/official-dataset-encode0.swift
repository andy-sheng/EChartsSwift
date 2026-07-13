// official-dataset-encode0 — replica of https://echarts.apache.org/examples/zh/editor.html?c=dataset-encode0
// title: Simple Encode / titleCN: 指定数据到坐标轴的映射
// A dataset whose `source` is a header row + rows of [score, amount, product]; the bar series uses
// `encode` to map the "amount" column to X and the "product" column to Y, while a horizontal
// visualMap maps dimension 0 ("score") to bar color.
// DEVIATIONS: none — the official source is a single static `option` literal (no data fetch, no
// closures, no timers). Both panes carry it verbatim; the Swift pane only hoists `dataset.source`
// into a file-scope `private let` so the type-checker can chew the mixed String/Number rows.
extension EChartsDemoRegistry {
    static let official_dataset_encode0 = EChartsDemo(
        name: "official-dataset-encode0", category: "dataset",
        summary: "指定数据到坐标轴的映射 — Simple Encode",
        width: 640, height: 420,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
option = {
  dataset: {
    source: [
      ['score', 'amount', 'product'],
      [89.3, 58212, 'Matcha Latte'],
      [57.1, 78254, 'Milk Tea'],
      [74.4, 41032, 'Cheese Cocoa'],
      [50.1, 12755, 'Cheese Brownie'],
      [89.7, 20145, 'Matcha Cocoa'],
      [68.1, 79146, 'Tea'],
      [19.6, 91852, 'Orange Juice'],
      [10.6, 101852, 'Lemon Juice'],
      [32.7, 20112, 'Walnut Brownie']
    ]
  },
  grid: { containLabel: true },
  xAxis: { name: 'amount' },
  yAxis: { type: 'category' },
  visualMap: {
    orient: 'horizontal',
    left: 'center',
    min: 10,
    max: 100,
    text: ['High Score', 'Low Score'],
    // Map the score column to color
    dimension: 0,
    inRange: {
      color: ['#65B581', '#FFCE34', '#FD665F']
    }
  },
  series: [
    {
      type: 'bar',
      encode: {
        // Map the "amount" column to X axis.
        x: 'amount',
        // Map the "product" column to Y axis
        y: 'product'
      }
    }
  ]
};
"""#,
        option: [
            "dataset": [
                "source": datasetEncode0Source
            ] as [String: Any],
            "grid": [
                "containLabel": true
            ] as [String: Any],
            "xAxis": [
                "name": "amount"
            ] as [String: Any],
            "yAxis": [
                "type": "category"
            ] as [String: Any],
            "visualMap": [
                "orient": "horizontal",
                "left": "center",
                "min": 10.0,
                "max": 100.0,
                "text": ["High Score", "Low Score"],
                // Map the score column to color
                "dimension": 0.0,
                "inRange": [
                    "color": ["#65B581", "#FFCE34", "#FD665F"]
                ] as [String: Any]
            ] as [String: Any],
            "series": [
                [
                    "type": "bar",
                    "encode": [
                        // Map the "amount" column to X axis.
                        "x": "amount",
                        // Map the "product" column to Y axis
                        "y": "product"
                    ] as [String: Any]
                ] as [String: Any]
            ]
        ])
}

// Header row + one row per product: [score, amount, product].
private let datasetEncode0Source: [[Any]] = [
    ["score", "amount", "product"],
    [89.3, 58212.0, "Matcha Latte"],
    [57.1, 78254.0, "Milk Tea"],
    [74.4, 41032.0, "Cheese Cocoa"],
    [50.1, 12755.0, "Cheese Brownie"],
    [89.7, 20145.0, "Matcha Cocoa"],
    [68.1, 79146.0, "Tea"],
    [19.6, 91852.0, "Orange Juice"],
    [10.6, 101852.0, "Lemon Juice"],
    [32.7, 20112.0, "Walnut Brownie"]
]
