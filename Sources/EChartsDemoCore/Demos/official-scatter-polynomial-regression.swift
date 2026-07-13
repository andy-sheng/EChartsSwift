// official-scatter-polynomial-regression — replica of
// https://echarts.apache.org/examples/zh/editor.html?c=scatter-polynomial-regression
// title: Polynomial Regression / titleCN: 多项式回归（使用统计插件）
//
// 18 companies' (main business income, net profit) pairs as a `scatter` series over `dataset[0]`, plus a
// smooth `line` series over `dataset[1]` — a cubic (order 3) least-squares fit produced by the ecStat
// dataset transform `ecStat:regression`. The fit's expression string is the 3rd column of the transform
// result, surfaced by `encode: { label: 2 }` as the line's (single, `labelLayout.dx: -20`-nudged) label.
//
// DEVIATIONS from the official source:
//   - ECSTAT IS INLINED. The example's first statement is
//     `echarts.registerTransform(ecStat.transform.regression)` — `ecStat` is the third-party
//     echarts-stat plugin (https://github.com/ecomfe/echarts-stat), which the official editor page
//     loads from a CDN. The gallery page has NO network, so the ecStat UMD bundle vendored with
//     upstream echarts (upstream/echarts/test/lib/ecStat.min.js — the same bundle echarts' own
//     test/data-transform-ecStat.html requires) is read via Upstream.repoRoot and spliced in ABOVE the
//     example source in `webOptionJS`. It is a UMD with no `exports`/`define` in a classic script, so it
//     assigns the global `ecStat` exactly as the CDN <script> would. From `echarts.registerTransform(...)`
//     down, webOptionJS is the official source VERBATIM (only the trailing `export {};` is dropped — a
//     bare export is a SyntaxError in a classic script). If that vendored file is missing the reference
//     pane goes blank (ReferenceError) rather than rendering a silently different chart.
//   - NATIVE PANE OFF (nativeSupported: false). Nothing in this `option` is a JS closure — the whole
//     thing is declarative and is ported below verbatim, dataset transform included. What the Swift
//     option cannot carry is the transform's IMPLEMENTATION: `ecStat.transform.regression` is a JS
//     function object handed to `echarts.registerTransform`, and EChartsKit's `externalTransformMap`
//     (data/helper/transform.swift) holds only the two built-ins registered by
//     component/transform/transformInstall.swift — `filter` and `sort`. Looking up "ecStat:regression"
//     therefore misses and `applySingleDataTransform` throws
//     `Can not find transform on type "ecStat:regression".`, so dataset[1] — i.e. the regression line,
//     i.e. the point of the example — cannot be built. Flip this to true if an ecStat port ever lands;
//     the option needs no change. (Registering a Swift regression transform from THIS file was rejected
//     on purpose: `externalTransformMap` is keyed by type string and global, so the sibling ecStat
//     examples would race to overwrite each other's closure.)
import Foundation

// The ecStat UMD, read from the vendored upstream echarts checkout (the same #filePath-relative repo read
// WebPage.swift uses for upstream/echarts/dist/echarts.js). Spliced into webOptionJS; defines global `ecStat`.
private let ecStatUMD: String = {
    let url = Upstream.repoRoot.appendingPathComponent("upstream/echarts/test/lib/ecStat.min.js")
    return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
}()

// [main business income, net profit] (million) for 18 companies — inline in the official source too.
private let scatterPolynomialRegressionData: [[Double]] = [
    [96.24, 11.35],
    [33.09, 85.11],
    [57.6, 36.61],
    [36.77, 27.26],
    [20.1, 6.72],
    [45.53, 36.37],
    [110.07, 80.13],
    [72.05, 20.88],
    [39.82, 37.15],
    [48.05, 70.5],
    [0.85, 2.57],
    [51.66, 63.7],
    [61.07, 127.13],
    [64.54, 33.59],
    [35.5, 25.01],
    [226.55, 664.02],
    [188.6, 175.31],
    [81.31, 108.68]
]

extension EChartsDemoRegistry {
    static let official_scatter_polynomial_regression = EChartsDemo(
        name: "official-scatter-polynomial-regression", category: "scatter",
        summary: "多项式回归（使用统计插件） — Polynomial Regression",
        width: 640, height: 420,
        nativeSupported: false,
        collection: .official,
        webOptionJS: #"""
// --- echarts-stat (ecStat) UMD, inlined: the gallery page has no network and no CDN. Everything below
// --- the next banner is the official example source, verbatim.
\#(ecStatUMD)
// --- official source ---------------------------------------------------------------------------------
// See https://github.com/ecomfe/echarts-stat
echarts.registerTransform(ecStat.transform.regression);

const data = [
  [96.24, 11.35],
  [33.09, 85.11],
  [57.6, 36.61],
  [36.77, 27.26],
  [20.1, 6.72],
  [45.53, 36.37],
  [110.07, 80.13],
  [72.05, 20.88],
  [39.82, 37.15],
  [48.05, 70.5],
  [0.85, 2.57],
  [51.66, 63.7],
  [61.07, 127.13],
  [64.54, 33.59],
  [35.5, 25.01],
  [226.55, 664.02],
  [188.6, 175.31],
  [81.31, 108.68]
];

option = {
  dataset: [
    {
      source: data
    },
    {
      transform: {
        type: 'ecStat:regression',
        config: { method: 'polynomial', order: 3 }
      }
    }
  ],
  title: {
    text: '18 companies net profit and main business income (million)',
    subtext: 'By ecStat.regression',
    sublink: 'https://github.com/ecomfe/echarts-stat',
    left: 'center',
    top: 16
  },
  tooltip: {
    trigger: 'axis',
    axisPointer: {
      type: 'cross'
    }
  },
  xAxis: {
    splitLine: {
      lineStyle: {
        type: 'dashed'
      }
    },
    splitNumber: 20
  },
  yAxis: {
    min: -40,
    splitLine: {
      lineStyle: {
        type: 'dashed'
      }
    }
  },
  series: [
    {
      name: 'scatter',
      type: 'scatter'
    },
    {
      name: 'line',
      type: 'line',
      smooth: true,
      datasetIndex: 1,
      symbolSize: 0.1,
      symbol: 'circle',
      label: { show: true, fontSize: 16 },
      labelLayout: { dx: -20 },
      encode: { label: 2, tooltip: 1 }
    }
  ]
};
"""#,
        option: [
            // dataset[0] = the raw 18 pairs; dataset[1] = the cubic fit.
            // PORT-NOTE: the `ecStat:regression` transform is DECLARED here exactly as upstream, but its
            // implementation (`ecStat.transform.regression`, a JS function registered via
            // echarts.registerTransform) has no EChartsKit counterpart — see the header. This is the one
            // reason nativeSupported is false.
            "dataset": [
                [
                    "source": scatterPolynomialRegressionData
                ] as [String: Any],
                [
                    "transform": [
                        "type": "ecStat:regression",
                        "config": ["method": "polynomial", "order": 3.0] as [String: Any]
                    ] as [String: Any]
                ] as [String: Any]
            ],
            "title": [
                "text": "18 companies net profit and main business income (million)",
                "subtext": "By ecStat.regression",
                "sublink": "https://github.com/ecomfe/echarts-stat",
                "left": "center",
                "top": 16.0
            ] as [String: Any],
            "tooltip": [
                "trigger": "axis",
                "axisPointer": [
                    "type": "cross"
                ] as [String: Any]
            ] as [String: Any],
            "xAxis": [
                "splitLine": [
                    "lineStyle": [
                        "type": "dashed"
                    ] as [String: Any]
                ] as [String: Any],
                "splitNumber": 20.0
            ] as [String: Any],
            "yAxis": [
                "min": -40.0,
                "splitLine": [
                    "lineStyle": [
                        "type": "dashed"
                    ] as [String: Any]
                ] as [String: Any]
            ] as [String: Any],
            "series": [
                [
                    "name": "scatter",
                    "type": "scatter"
                ] as [String: Any],
                [
                    "name": "line",
                    "type": "line",
                    "smooth": true,
                    "datasetIndex": 1.0,
                    "symbolSize": 0.1,
                    "symbol": "circle",
                    "label": [
                        "show": true,
                        "fontSize": 16.0
                    ] as [String: Any],
                    // dx: -20 nudges the fit's expression label left of the last point.
                    "labelLayout": [
                        "dx": -20.0
                    ] as [String: Any],
                    // dim 2 of the transform result is the regression expression string; tooltip reads dim 1.
                    "encode": [
                        "label": 2.0,
                        "tooltip": 1.0
                    ] as [String: Any]
                ] as [String: Any]
            ]
        ])
}
