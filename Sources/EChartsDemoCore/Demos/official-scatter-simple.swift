// official-scatter-simple — replica of https://echarts.apache.org/examples/zh/editor.html?c=scatter-simple
// title: Basic Scatter Chart / titleCN: 基础散点图
// 22 (x, y) points on a default value/value cartesian grid (both axes empty `{}`, so ECharts infers
// `type: 'value'` and the extents from the data), drawn as `symbolSize: 20` circles.
//
// DEVIATIONS FROM THE OFFICIAL SOURCE: none semantically. The example has no data fetch, no closures
// (symbolSize is the literal 20, not a callback) and no setInterval/re-setOption, so both panes are the
// example as-is — the `option` literal below is the official file line for line, and the Swift `option`
// is its 1:1 transcription. Three purely mechanical changes:
//   - the JS drops the official file's trailing `export {};`. REQUIRED: WebPage.swift inlines this into a
//     classic (non-module) <script>, where a bare `export` is a SyntaxError that aborts the WHOLE script —
//     `option` would never be assigned and the reference pane would render blank.
//   - the JS drops the official file's `/* title: ... */` frontmatter comment (metadata, restated above).
//   - the 22-point data array is hoisted into a typed `private let` so Swift's type-checker does not choke
//     on a large untyped nested literal.
// Nothing is omitted from the Swift `option`: the official option has no function-valued key, so there is
// nothing to PORT-NOTE. `xAxis: {}` / `yAxis: {}` stay empty dicts rather than being "helpfully" expanded
// to `type: 'value'` — the port infers the same default upstream does (Axis2D: `axisType ?? "value"`).
import Foundation

// series[0].data — the 22 (x, y) pairs, verbatim from the official example.
private let scatterSimpleData: [[Double]] = [
    [10.0, 8.04],
    [8.07, 6.95],
    [13.0, 7.58],
    [9.05, 8.81],
    [11.0, 8.33],
    [14.0, 7.66],
    [13.4, 6.81],
    [10.0, 6.33],
    [14.0, 8.96],
    [12.5, 6.82],
    [9.15, 7.2],
    [11.5, 7.2],
    [3.03, 4.23],
    [12.2, 7.83],
    [2.02, 4.47],
    [1.05, 3.33],
    [4.05, 4.96],
    [6.03, 7.24],
    [12.0, 6.26],
    [12.0, 8.84],
    [7.08, 5.82],
    [5.02, 5.68]
]

extension EChartsDemoRegistry {
    static let official_scatter_simple = EChartsDemo(
        name: "official-scatter-simple", category: "scatter",
        summary: "基础散点图 — Basic Scatter Chart",
        width: 640, height: 420,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
option = {
  xAxis: {},
  yAxis: {},
  series: [
    {
      symbolSize: 20,
      data: [
        [10.0, 8.04],
        [8.07, 6.95],
        [13.0, 7.58],
        [9.05, 8.81],
        [11.0, 8.33],
        [14.0, 7.66],
        [13.4, 6.81],
        [10.0, 6.33],
        [14.0, 8.96],
        [12.5, 6.82],
        [9.15, 7.2],
        [11.5, 7.2],
        [3.03, 4.23],
        [12.2, 7.83],
        [2.02, 4.47],
        [1.05, 3.33],
        [4.05, 4.96],
        [6.03, 7.24],
        [12.0, 6.26],
        [12.0, 8.84],
        [7.08, 5.82],
        [5.02, 5.68]
      ],
      type: 'scatter'
    }
  ]
};
"""#,
        option: [
            "xAxis": [:] as [String: Any],
            "yAxis": [:] as [String: Any],
            "series": [
                [
                    "symbolSize": 20.0,
                    "data": scatterSimpleData as [Any],
                    "type": "scatter"
                ] as [String: Any]
            ]
        ])
}
