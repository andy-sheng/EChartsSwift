// official-scatter-exponential-regression — replica of
// https://echarts.apache.org/examples/zh/editor.html?c=scatter-exponential-regression
// title: Exponential Regression / titleCN: 指数回归（使用统计插件）
// China's 1981–1998 GDP as a scatter over a two-entry `dataset`: entry 0 is the raw 18 [year, GDP]
// pairs; entry 1 is a `transform` of type 'ecStat:regression' (method 'exponential') that the
// echarts-stat PLUGIN — not echarts itself — contributes via `echarts.registerTransform(...)`. The
// smooth `line` series binds datasetIndex 1 and, through `encode: { label: 2 }`, prints the fitted
// formula (the transform's 3rd output dimension) at the curve's end.
// DEVIATIONS:
//   - webOptionJS PREPENDS the ecStat UMD bundle (read at demo time from the repo's vendored
//     upstream/echarts/test/lib/ecStat.min.js — the same file upstream's own
//     test/data-transform-ecStat.html loads). The official editor gets `ecStat` from a <script src>;
//     our reference page has no network and WebPage.swift inlines only the echarts dist, so the
//     bundle has to ride along inside the option script. The example's own
//     `echarts.registerTransform(ecStat.transform.regression)` line is kept VERBATIM, so the
//     reference pane runs the REAL regression transform, not a precomputed fit.
//   - webOptionJS drops the trailing `export {};` (a bare export is a SyntaxError in a classic script
//     and would kill the whole page). Everything else is verbatim.
//   - nativeSupported: FALSE. The example's core IS the plugin transform. EChartsKit has the
//     external-transform machinery (`registerExternalTransform`, data/helper/transform.swift) but no
//     Swift port of echarts-stat, so nothing is registered under 'ecStat:regression' and the dataset
//     chain throws. The Swift `option` below still carries the example in full (nothing omitted — the
//     source has no formatter/renderItem/symbolSize closures anywhere), so flipping this flag is a
//     one-liner the day an ecStat regression transform lands.
import Foundation

// The ecStat UMD bundle. Evaluated as a classic script it does `window.ecStat = factory()`, which is
// exactly what the official editor's <script src="…/ecStat.min.js"> does. A missing/unreadable file
// degrades to "" — the page then throws on `ecStat.transform` and renders blank rather than crashing.
private let ecStatMinJS: String = {
    let url = Upstream.repoRoot.appendingPathComponent("upstream/echarts/test/lib/ecStat.min.js")
    return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
}()

// The example's JS, verbatim (minus `export {};`). Concatenated after the bundle above rather than
// interpolated into it, so no escape sequence in the minified JS can ever be reinterpreted.
private let scatterExpRegressionOptionJS = #"""
// See https://github.com/ecomfe/echarts-stat
echarts.registerTransform(ecStat.transform.regression);

option = {
  dataset: [
    {
      source: [
        [1, 4862.4],
        [2, 5294.7],
        [3, 5934.5],
        [4, 7171.0],
        [5, 8964.4],
        [6, 10202.2],
        [7, 11962.5],
        [8, 14928.3],
        [9, 16909.2],
        [10, 18547.9],
        [11, 21617.8],
        [12, 26638.1],
        [13, 34634.4],
        [14, 46759.4],
        [15, 58478.1],
        [16, 67884.6],
        [17, 74462.6],
        [18, 79395.7]
      ]
    },
    {
      transform: {
        type: 'ecStat:regression',
        config: {
          method: 'exponential'
          // 'end' by default
          // formulaOn: 'start'
        }
      }
    }
  ],
  title: {
    text: '1981 - 1998 gross domestic product GDP (trillion yuan)',
    subtext: 'By ecStat.regression',
    sublink: 'https://github.com/ecomfe/echarts-stat',
    left: 'center'
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
    }
  },
  yAxis: {
    splitLine: {
      lineStyle: {
        type: 'dashed'
      }
    }
  },
  series: [
    {
      name: 'scatter',
      type: 'scatter',
      datasetIndex: 0
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
"""#

extension EChartsDemoRegistry {
    static let official_scatter_exponential_regression = EChartsDemo(
        name: "official-scatter-exponential-regression", category: "scatter",
        summary: "指数回归（使用统计插件） — Exponential Regression",
        width: 640, height: 420,
        nativeSupported: false,   // see header: 'ecStat:regression' has no Swift transform
        collection: .official,
        webOptionJS: ecStatMinJS + "\n" + scatterExpRegressionOptionJS,
        option: [
            "dataset": [
                ["source": scatterExpRegressionGDP] as [String: Any],
                [
                    "transform": [
                        "type": "ecStat:regression",
                        "config": [
                            "method": "exponential"
                            // 'end' by default; formulaOn: 'start'
                        ] as [String: Any]
                    ] as [String: Any]
                ] as [String: Any]
            ],
            "title": [
                "text": "1981 - 1998 gross domestic product GDP (trillion yuan)",
                "subtext": "By ecStat.regression",
                "sublink": "https://github.com/ecomfe/echarts-stat",
                "left": "center"
            ] as [String: Any],
            "tooltip": [
                "trigger": "axis",
                "axisPointer": ["type": "cross"] as [String: Any]
            ] as [String: Any],
            "xAxis": [
                "splitLine": [
                    "lineStyle": ["type": "dashed"] as [String: Any]
                ] as [String: Any]
            ] as [String: Any],
            "yAxis": [
                "splitLine": [
                    "lineStyle": ["type": "dashed"] as [String: Any]
                ] as [String: Any]
            ] as [String: Any],
            "series": [
                [
                    "name": "scatter",
                    "type": "scatter",
                    "datasetIndex": 0.0
                ] as [String: Any],
                [
                    "name": "line",
                    "type": "line",
                    "smooth": true,
                    "datasetIndex": 1.0,
                    "symbolSize": 0.1,
                    "symbol": "circle",
                    "label": ["show": true, "fontSize": 16.0] as [String: Any],
                    "labelLayout": ["dx": -20.0] as [String: Any],
                    // dim 2 of the transform's output is the fitted formula string; dim 1 is the GDP.
                    "encode": ["label": 2.0, "tooltip": 1.0] as [String: Any]
                ] as [String: Any]
            ]
        ])
}

// [year-index (1 = 1981 … 18 = 1998), GDP] — the 18 raw points, dataset entry 0. Values verbatim.
private let scatterExpRegressionGDP: [[Double]] = [
    [1, 4862.4],
    [2, 5294.7],
    [3, 5934.5],
    [4, 7171.0],
    [5, 8964.4],
    [6, 10202.2],
    [7, 11962.5],
    [8, 14928.3],
    [9, 16909.2],
    [10, 18547.9],
    [11, 21617.8],
    [12, 26638.1],
    [13, 34634.4],
    [14, 46759.4],
    [15, 58478.1],
    [16, 67884.6],
    [17, 74462.6],
    [18, 79395.7]
]
