// official-scatter-stream-visual — replica of https://echarts.apache.org/examples/zh/editor.html?c=scatter-stream-visual
// title: Visual interaction with stream / titleCN: 流式渲染和视觉映射操作
// 16,174 Beijing house sales as a raw `scatter` (symbolSize 5) on a value/value cartesian: x = floor
// area (m², 18.06–399.48), y = unit price (15202–159980). A continuous `visualMap` maps DIMENSION 1
// (the price) onto a #f2c31a → #24b7f2 ramp, so colour and the y position encode the same channel and
// the ramp reads as a vertical gradient through the cloud. The "stream" of the title is echarts'
// automatic progressive (chunked) rendering of a point cloud this large — it is a renderer behaviour,
// not an option key: the official source sets no `progressive*` field, and neither do we.
//
// DEVIATIONS from the official source:
//   - DATA INLINED: upstream wraps the whole option in `$.getJSON(ROOT_PATH +
//     '/data/asset/data/house-price-area2.json', function (data) { ... })`. The page has no network, so
//     the asset is vendored at assets/data/house-price-area2.json and read via Upstream.repoRoot: the web
//     pane gets the raw JSON text spliced in as `var data = ...` (the callback BODY is otherwise verbatim),
//     the native pane gets the same bytes parsed into [[Double]]. The `$.getJSON` wrapper, the trailing
//     `myChart.setOption(option)` and `export {}` are gone, and the callback's `var option = {...}` becomes
//     a top-level `option = {...}` (WebPage.swift already declares `var option`).
//   - NATIVE PANE: nothing omitted. The option carries no closures at all (symbolSize is the number 5,
//     not a function), so the Swift port is the option verbatim.
import Foundation

private let housePriceAreaAssetURL =
    Upstream.repoRoot.appendingPathComponent("assets/data/house-price-area2.json")

// 16,174 [area, unitPrice] pairs. Parsed ONCE from the repo asset; a parse failure degrades to no data
// (the pane renders empty axes rather than crashing).
private let housePriceAreaData: [[Double]] = {
    guard let data = try? Data(contentsOf: housePriceAreaAssetURL),
          let arr = (try? JSONSerialization.jsonObject(with: data)) as? [[Double]] else { return [] }
    return arr
}()

// The raw JSON text, spliced into webOptionJS so the reference pane runs the official callback body
// against the exact bytes the native pane parses.
private let housePriceAreaJSONText: String =
    (try? String(contentsOf: housePriceAreaAssetURL, encoding: .utf8)) ?? "[]"

extension EChartsDemoRegistry {
    static let official_scatter_stream_visual = EChartsDemo(
        name: "official-scatter-stream-visual", category: "scatter",
        summary: "流式渲染和视觉映射操作 — Visual interaction with stream",
        width: 640, height: 420,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
var data = \#(housePriceAreaJSONText);

option = {
  title: {
    text: 'Dispersion of house price based on the area',
    left: 'center',
    top: 0
  },
  visualMap: {
    min: 15202,
    max: 159980,
    dimension: 1,
    orient: 'vertical',
    right: 10,
    top: 'center',
    text: ['HIGH', 'LOW'],
    calculable: true,
    inRange: {
      color: ['#f2c31a', '#24b7f2']
    }
  },
  tooltip: {
    trigger: 'item',
    axisPointer: {
      type: 'cross'
    }
  },
  xAxis: [
    {
      type: 'value'
    }
  ],
  yAxis: [
    {
      type: 'value'
    }
  ],
  series: [
    {
      name: 'price-area',
      type: 'scatter',
      symbolSize: 5,
      data: data
    }
  ]
};
"""#,
        option: [
            "title": [
                "text": "Dispersion of house price based on the area",
                "left": "center",
                "top": 0.0
            ] as [String: Any],
            "visualMap": [
                "min": 15202.0,
                "max": 159980.0,
                "dimension": 1.0,
                "orient": "vertical",
                "right": 10.0,
                "top": "center",
                "text": ["HIGH", "LOW"],
                "calculable": true,
                "inRange": [
                    "color": ["#f2c31a", "#24b7f2"]
                ] as [String: Any]
            ] as [String: Any],
            "tooltip": [
                "trigger": "item",
                "axisPointer": [
                    "type": "cross"
                ] as [String: Any]
            ] as [String: Any],
            "xAxis": [
                [
                    "type": "value"
                ] as [String: Any]
            ],
            "yAxis": [
                [
                    "type": "value"
                ] as [String: Any]
            ],
            "series": [
                [
                    "name": "price-area",
                    "type": "scatter",
                    "symbolSize": 5.0,
                    "data": housePriceAreaData
                ] as [String: Any]
            ]
        ])
}
