// official-dataset-link — replica of https://echarts.apache.org/examples/zh/editor.html?c=dataset-link
// title: Share Dataset / titleCN: 联动和共享数据集
// One `dataset.source` (4 products × 6 years) feeds FIVE series: four `seriesLayoutBy: 'row'` lines in a
// grid pushed to the bottom half (`grid.top: '55%'`), plus a pie centred over the top half that `encode`s
// a single YEAR column. An `updateAxisPointer` listener re-`setOption`s the pie's `encode.value` /
// `label.formatter` to whatever year the axis pointer sits on, so hovering the lines re-slices the pie —
// that linkage IS the example.
//
// DEVIATIONS from the official source:
//   - TypeScript stripped: the `(event: any)` parameter annotation, the two
//     `setOption<echarts.EChartsOption>` type arguments, and the trailing `export {};` (a bare export is a
//     SyntaxError in a classic script). The `setTimeout(function () { ... })` wrapper, the
//     `myChart.on('updateAxisPointer', ...)` handler and both `myChart.setOption` calls are VERBATIM —
//     the web pane runs the example exactly as the site does, pointer linkage included.
//   - NATIVE pane: the JS listener is expressed by the equivalent `drive` closure. It subscribes through
//     `EChartsDemoChart.on`, reads `axesInfo[0].value`, and merges the same id-addressed pie option as the
//     official callback, so the interaction remains part of the example instead of a static-only replica.
import Foundation

extension EChartsDemoRegistry {
    static let official_dataset_link = EChartsDemo(
        name: "official-dataset-link", category: "dataset",
        summary: "联动和共享数据集 — Share Dataset",
        width: 640, height: 420,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
setTimeout(function () {
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

  myChart.on('updateAxisPointer', function (event) {
    const xAxisInfo = event.axesInfo[0];
    if (xAxisInfo) {
      const dimension = xAxisInfo.value + 1;
      myChart.setOption({
        series: {
          id: 'pie',
          label: {
            formatter: '{b}: {@[' + dimension + ']} ({d}%)'
          },
          encode: {
            value: dimension,
            tooltip: dimension
          }
        }
      });
    }
  });

  myChart.setOption(option);
});
"""#,
        drive: { chart in
            chart.on("updateAxisPointer") { event in
                guard let axesInfo = event["axesInfo"] as? [[String: Any]],
                      let firstAxis = axesInfo.first,
                      let axisValue = datasetLinkNumber(firstAxis["value"]) else { return }
                let dimension = Int(axisValue) + 1
                chart.setOption([
                    "series": [[
                        "id": "pie",
                        "label": [
                            "formatter": "{b}: {@[\(dimension)]} ({d}%)"
                        ] as [String: Any],
                        "encode": [
                            "value": Double(dimension),
                            "tooltip": Double(dimension)
                        ] as [String: Any]
                    ] as [String: Any]]
                ], notMerge: false)
            }
        },
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

private func datasetLinkNumber(_ value: Any?) -> Double? {
    if let value = value as? Double { return value }
    if let value = value as? Int { return Double(value) }
    if let value = value as? NSNumber { return value.doubleValue }
    return nil
}

// The shared dataset: a header row (product + six years), then one ROW per product — each line series
// takes a row (`seriesLayoutBy: 'row'`), the pie takes a single year COLUMN via `encode`.
private let datasetLinkSource: [[Any]] = [
    ["product", "2012", "2013", "2014", "2015", "2016", "2017"],
    ["Milk Tea", 56.5, 82.1, 88.7, 70.1, 53.4, 85.1],
    ["Matcha Latte", 51.1, 51.4, 55.1, 53.3, 73.8, 68.7],
    ["Cheese Cocoa", 40.1, 62.2, 69.5, 36.4, 45.2, 32.5],
    ["Walnut Brownie", 25.2, 37.1, 41.2, 18.0, 33.9, 49.1]
]

// The official source repeats this identical line-series entry four times — no `data` key, each series
// just picks up the next row of the shared dataset.
private let datasetLinkLineSeries: [String: Any] = [
    "type": "line",
    "smooth": true,
    "seriesLayoutBy": "row",
    "emphasis": ["focus": "series"] as [String: Any]
]
