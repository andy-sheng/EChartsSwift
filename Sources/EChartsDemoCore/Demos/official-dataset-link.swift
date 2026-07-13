// official-dataset-link — replica of https://echarts.apache.org/examples/zh/editor.html?c=dataset-link
// title: Share Dataset / titleCN: 联动和共享数据集
// One `dataset` shared by five series: four `seriesLayoutBy: 'row'` line series (one per product row)
// in a grid pushed to the bottom half, plus a pie in the top half `encode`d onto the 2012 column.
// DEVIATIONS from the official source:
//   - The official code wraps everything in `setTimeout(function () { ... })` (an editor-only trick so
//     `myChart` exists). Dropped: `option` is assigned unconditionally at the top level in both panes.
//   - The official `myChart.on('updateAxisPointer', ...)` handler — which re-`setOption`s the pie's
//     `encode.value` / `label.formatter` to the hovered year as the axis pointer moves — is dropped in
//     BOTH panes. The gallery renders one static frame with no pointer, so it never fires; the pie
//     keeps its initial 2012 encoding. (The web pane has no `myChart` in scope at option-eval time.)
//   - Trailing `export {};` dropped (a bare export is a SyntaxError in a classic script).
// Everything else, including the pie's string label formatter '{b}: {@2012} ({d}%)', is verbatim and
// carries into the native option as-is (it is a template string, not a JS closure).
extension EChartsDemoRegistry {
    static let official_dataset_link = EChartsDemo(
        name: "official-dataset-link", category: "dataset",
        summary: "联动和共享数据集 — Share Dataset",
        width: 640, height: 420,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
option = {
  legend: {},
  tooltip: {
    trigger: 'axis',
    showContent: false
  },
  dataset: {
    source: [
      ['product', '2012', '2013', '2014', '2015', '2016', '2017'],
      ['Milk Tea', 56.5, 82.1, 88.7, 70.1, 53.4, 85.1],
      ['Matcha Latte', 51.1, 51.4, 55.1, 53.3, 73.8, 68.7],
      ['Cheese Cocoa', 40.1, 62.2, 69.5, 36.4, 45.2, 32.5],
      ['Walnut Brownie', 25.2, 37.1, 41.2, 18, 33.9, 49.1]
    ]
  },
  xAxis: { type: 'category' },
  yAxis: { gridIndex: 0 },
  grid: { top: '55%' },
  series: [
    {
      type: 'line',
      smooth: true,
      seriesLayoutBy: 'row',
      emphasis: { focus: 'series' }
    },
    {
      type: 'line',
      smooth: true,
      seriesLayoutBy: 'row',
      emphasis: { focus: 'series' }
    },
    {
      type: 'line',
      smooth: true,
      seriesLayoutBy: 'row',
      emphasis: { focus: 'series' }
    },
    {
      type: 'line',
      smooth: true,
      seriesLayoutBy: 'row',
      emphasis: { focus: 'series' }
    },
    {
      type: 'pie',
      id: 'pie',
      radius: '30%',
      center: ['50%', '25%'],
      emphasis: {
        focus: 'self'
      },
      label: {
        formatter: '{b}: {@2012} ({d}%)'
      },
      encode: {
        itemName: 'product',
        value: '2012',
        tooltip: '2012'
      }
    }
  ]
};
"""#,
        option: [
            "legend": [:] as [String: Any],
            "tooltip": [
                "trigger": "axis",
                "showContent": false
            ] as [String: Any],
            "dataset": [
                "source": datasetLinkSource
            ] as [String: Any],
            "xAxis": ["type": "category"] as [String: Any],
            "yAxis": ["gridIndex": 0.0] as [String: Any],
            "grid": ["top": "55%"] as [String: Any],
            "series": [
                datasetLinkLineSeries,
                datasetLinkLineSeries,
                datasetLinkLineSeries,
                datasetLinkLineSeries,
                [
                    "type": "pie",
                    "id": "pie",
                    "radius": "30%",
                    "center": ["50%", "25%"],
                    "emphasis": ["focus": "self"] as [String: Any],
                    "label": ["formatter": "{b}: {@2012} ({d}%)"] as [String: Any],
                    "encode": [
                        "itemName": "product",
                        "value": "2012",
                        "tooltip": "2012"
                    ] as [String: Any]
                ] as [String: Any]
            ]
        ])
}

// The shared dataset: header row of years, then one row per product (`seriesLayoutBy: 'row'`).
private let datasetLinkSource: [[Any]] = [
    ["product", "2012", "2013", "2014", "2015", "2016", "2017"],
    ["Milk Tea", 56.5, 82.1, 88.7, 70.1, 53.4, 85.1],
    ["Matcha Latte", 51.1, 51.4, 55.1, 53.3, 73.8, 68.7],
    ["Cheese Cocoa", 40.1, 62.2, 69.5, 36.4, 45.2, 32.5],
    ["Walnut Brownie", 25.2, 37.1, 41.2, 18.0, 33.9, 49.1]
]

// The four line series are identical in the official source (each picks up the next dataset row).
private let datasetLinkLineSeries: [String: Any] = [
    "type": "line",
    "smooth": true,
    "seriesLayoutBy": "row",
    "emphasis": ["focus": "series"] as [String: Any]
]
