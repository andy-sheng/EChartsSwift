// official-scatter-logarithmic-regression — replica of
// https://echarts.apache.org/examples/zh/editor.html?c=scatter-logarithmic-regression
// title: Logarithmic Regression / titleCN: 对数回归（使用统计插件）
//
// Per-capita GDP (x) vs life expectancy (y) for 19 countries in two years. One 5-dimensional source
// (gdp, lifeExpectancy, population, country, year) fans out into four datasets: two built-in `filter`
// transforms split it by year into the '1990' and '2015' `scatter` series, and an `ecStat:regression`
// transform (the third-party echarts-stat plugin) fits a LOGARITHMIC curve — `config: { method:
// 'logarithmic' }` — drawn as the smoothed `line` series. A `visualMap` with `show: false` sizes the
// scatter symbols by dimension 2 (population) over `symbolSize: [10, 70]`, and the line's
// `encode: { label: 2 }` + `labelLayout: { dx: -20 }` prints the fitted formula text that the transform
// writes into dim 2 of its last point (ecStat's `formulaOn: 'end'` default).
//
// Worth knowing when diffing the panes: `dataset[3]` declares a transform but NO `fromDatasetIndex`, and
// per `SourceHelper.queryDatasetUpstreamDatasetModels` ("Only these attributes declared, we by default
// reference to `datasetIndex: 0`") that means it reads dataset[0] — NOT the preceding dataset[2]. The
// regression is therefore fitted over ALL 38 points (both years pooled), not over the 2015 subset.
//
// DEVIATIONS from the official source:
//   - ecStat IS THE EXAMPLE. `echarts.registerTransform(ecStat.transform.regression)` needs an `ecStat`
//     global, which the official editor page provides and our offline, self-contained web pane does not
//     (no CDN, no ROOT_PATH, no network). So the VENDORED ecStat UMD bundle is spliced into webOptionJS
//     ahead of the example's own JS: upstream/echarts/test/lib/ecStat.min.js, the exact build upstream's
//     own test/data-transform-ecStat.html loads (`'ecStat': 'lib/ecStat.min'` in test/lib/config.js), read
//     through Upstream.repoRoot — the same #filePath-relative repo read WebPage.swift uses for the echarts
//     dist, so it resolves on macOS and the iOS simulator alike. It is a UMD with no module system present,
//     so it assigns `window.ecStat` and the example's JS below then runs VERBATIM.
//   - trailing `export {};` dropped (a bare export is a SyntaxError in a classic script and would blank
//     the whole page).
//   - Nothing else: the option is static (no timers, no re-setOption) and contains no closures — the
//     symbolSize range is a plain `[10, 70]` array on `visualMap.inRange`, not a callback — so nothing had
//     to be omitted from the native option either. It is a 1:1 transcription.
//
// nativeSupported: FALSE — and the gap is the TRANSFORM TYPE, not a closure. EChartsKit has the whole
// dataset-transform pipeline (`data/helper/transform.swift`: `applyDataTransform` + the public
// `registerExternalTransform`; `sourceManager.swift` resolving `datasetIndex` / `fromTransformResult`), and
// the two `filter` datasets here would work fine — but it only ever registers the two BUILT-INS, `filter`
// and `sort` (component/transform/transformInstall.swift). `ecStat:regression` belongs to echarts-stat — a
// separate JS plugin, outside the echarts source tree, so it has no Swift port and nobody registers that
// type. `applyDataTransform` therefore throws `Can not find transform on type "ecStat:regression".`
// (transform.swift:573) while building `dataset[3]`, which kills the render before ANY series is laid out —
// the two scatter series die with the line. The fix is a thin `ExternalDataTransform` (least-squares fit of
// y = a·ln(x) + b, plus the formula expression string written into dim 2 of the last point) plus one
// `registerExternalTransform` call; the `option` below is already correct, so this demo lights up for free
// the moment that lands. Same shape of gap as official-scatter-linear-regression.
import Foundation

// The ecStat UMD (echarts-stat), spliced into the reference page — see DEVIATIONS above. A read failure
// degrades to "" (the pane then errors on `ecStat is not defined` rather than silently drawing a chart
// that is missing its regression curve, which is the honest failure for a reference pane).
private let ecStatUMDJS: String = {
    let url = Upstream.repoRoot.appendingPathComponent("upstream/echarts/test/lib/ecStat.min.js")
    return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
}()

// Upstream's `dataset[0].source`, verbatim: [gdp, lifeExpectancy, population, country, year] × 38.
// Hoisted out of the option literal with an EXPLICIT type — a 38-row heterogeneous (Double/String) nested
// literal inline is exactly what times out Swift's type-checker. Heterogeneous, hence [[Any]] not [[Double]].
private let scatterLogarithmicRegressionData: [[Any]] = [
    [28604.0, 77.0, 17096869.0, "Australia", 1990.0],
    [31163.0, 77.4, 27662440.0, "Canada", 1990.0],
    [1516.0, 68.0, 1154605773.0, "China", 1990.0],
    [13670.0, 74.7, 10582082.0, "Cuba", 1990.0],
    [28599.0, 75.0, 4986705.0, "Finland", 1990.0],
    [29476.0, 77.1, 56943299.0, "France", 1990.0],
    [31476.0, 75.4, 78958237.0, "Germany", 1990.0],
    [28666.0, 78.1, 254830.0, "Iceland", 1990.0],
    [1777.0, 57.7, 870601776.0, "India", 1990.0],
    [29550.0, 79.1, 122249285.0, "Japan", 1990.0],
    [2076.0, 67.9, 20194354.0, "North Korea", 1990.0],
    [12087.0, 72.0, 42972254.0, "South Korea", 1990.0],
    [24021.0, 75.4, 3397534.0, "New Zealand", 1990.0],
    [43296.0, 76.8, 4240375.0, "Norway", 1990.0],
    [10088.0, 70.8, 38195258.0, "Poland", 1990.0],
    [19349.0, 69.6, 147568552.0, "Russia", 1990.0],
    [10670.0, 67.3, 53994605.0, "Turkey", 1990.0],
    [26424.0, 75.7, 57110117.0, "United Kingdom", 1990.0],
    [37062.0, 75.4, 252847810.0, "United States", 1990.0],
    [44056.0, 81.8, 23968973.0, "Australia", 2015.0],
    [43294.0, 81.7, 35939927.0, "Canada", 2015.0],
    [13334.0, 76.9, 1376048943.0, "China", 2015.0],
    [21291.0, 78.5, 11389562.0, "Cuba", 2015.0],
    [38923.0, 80.8, 5503457.0, "Finland", 2015.0],
    [37599.0, 81.9, 64395345.0, "France", 2015.0],
    [44053.0, 81.1, 80688545.0, "Germany", 2015.0],
    [42182.0, 82.8, 329425.0, "Iceland", 2015.0],
    [5903.0, 66.8, 1311050527.0, "India", 2015.0],
    [36162.0, 83.5, 126573481.0, "Japan", 2015.0],
    [1390.0, 71.4, 25155317.0, "North Korea", 2015.0],
    [34644.0, 80.7, 50293439.0, "South Korea", 2015.0],
    [34186.0, 80.6, 4528526.0, "New Zealand", 2015.0],
    [64304.0, 81.6, 5210967.0, "Norway", 2015.0],
    [24787.0, 77.3, 38611794.0, "Poland", 2015.0],
    [23038.0, 73.13, 143456918.0, "Russia", 2015.0],
    [19360.0, 76.5, 78665830.0, "Turkey", 2015.0],
    [38225.0, 81.4, 64715810.0, "United Kingdom", 2015.0],
    [53354.0, 79.1, 321773631.0, "United States", 2015.0]
]

extension EChartsDemoRegistry {
    static let official_scatter_logarithmic_regression = EChartsDemo(
        name: "official-scatter-logarithmic-regression", category: "scatter",
        summary: "对数回归（使用统计插件） — Logarithmic Regression",
        width: 640, height: 420,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
// --- vendored ecStat UMD (upstream/echarts/test/lib/ecStat.min.js); assigns window.ecStat ---
\#(ecStatUMDJS)
// --- end ecStat; the official example's JS runs verbatim from here ---

// See https://github.com/ecomfe/echarts-stat
echarts.registerTransform(ecStat.transform.regression);

option = {
  dataset: [
    {
      source: [
        [28604, 77, 17096869, 'Australia', 1990],
        [31163, 77.4, 27662440, 'Canada', 1990],
        [1516, 68, 1154605773, 'China', 1990],
        [13670, 74.7, 10582082, 'Cuba', 1990],
        [28599, 75, 4986705, 'Finland', 1990],
        [29476, 77.1, 56943299, 'France', 1990],
        [31476, 75.4, 78958237, 'Germany', 1990],
        [28666, 78.1, 254830, 'Iceland', 1990],
        [1777, 57.7, 870601776, 'India', 1990],
        [29550, 79.1, 122249285, 'Japan', 1990],
        [2076, 67.9, 20194354, 'North Korea', 1990],
        [12087, 72, 42972254, 'South Korea', 1990],
        [24021, 75.4, 3397534, 'New Zealand', 1990],
        [43296, 76.8, 4240375, 'Norway', 1990],
        [10088, 70.8, 38195258, 'Poland', 1990],
        [19349, 69.6, 147568552, 'Russia', 1990],
        [10670, 67.3, 53994605, 'Turkey', 1990],
        [26424, 75.7, 57110117, 'United Kingdom', 1990],
        [37062, 75.4, 252847810, 'United States', 1990],
        [44056, 81.8, 23968973, 'Australia', 2015],
        [43294, 81.7, 35939927, 'Canada', 2015],
        [13334, 76.9, 1376048943, 'China', 2015],
        [21291, 78.5, 11389562, 'Cuba', 2015],
        [38923, 80.8, 5503457, 'Finland', 2015],
        [37599, 81.9, 64395345, 'France', 2015],
        [44053, 81.1, 80688545, 'Germany', 2015],
        [42182, 82.8, 329425, 'Iceland', 2015],
        [5903, 66.8, 1311050527, 'India', 2015],
        [36162, 83.5, 126573481, 'Japan', 2015],
        [1390, 71.4, 25155317, 'North Korea', 2015],
        [34644, 80.7, 50293439, 'South Korea', 2015],
        [34186, 80.6, 4528526, 'New Zealand', 2015],
        [64304, 81.6, 5210967, 'Norway', 2015],
        [24787, 77.3, 38611794, 'Poland', 2015],
        [23038, 73.13, 143456918, 'Russia', 2015],
        [19360, 76.5, 78665830, 'Turkey', 2015],
        [38225, 81.4, 64715810, 'United Kingdom', 2015],
        [53354, 79.1, 321773631, 'United States', 2015]
      ]
    },
    {
      transform: {
        type: 'filter',
        config: { dimension: 4, eq: 1990 }
      }
    },
    {
      transform: {
        type: 'filter',
        config: { dimension: 4, eq: 2015 }
      }
    },
    {
      transform: {
        type: 'ecStat:regression',
        config: {
          method: 'logarithmic'
        }
      }
    }
  ],
  title: {
    text: '1990 and 2015 per capita life expectancy and GDP',
    subtext: 'By ecStat.regression',
    sublink: 'https://github.com/ecomfe/echarts-stat',
    left: 'center'
  },
  legend: {
    data: ['1990', '2015'],
    bottom: 10
  },
  tooltip: {
    trigger: 'axis',
    axisPointer: {
      type: 'cross'
    }
  },
  xAxis: {
    type: 'value',
    splitLine: {
      lineStyle: {
        type: 'dashed'
      }
    }
  },
  yAxis: {
    type: 'value',
    splitLine: {
      lineStyle: {
        type: 'dashed'
      }
    }
  },
  visualMap: {
    show: false,
    dimension: 2,
    min: 20000,
    max: 1500000000,
    seriesIndex: [0, 1],
    inRange: {
      symbolSize: [10, 70]
    }
  },
  series: [
    {
      name: '1990',
      type: 'scatter',
      datasetIndex: 1
    },
    {
      name: '2015',
      type: 'scatter',
      datasetIndex: 2
    },
    {
      name: 'line',
      type: 'line',
      smooth: true,
      datasetIndex: 3,
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
            "dataset": [
                // [0] the raw 5-dim source: [gdp, lifeExpectancy, population, country, year].
                ["source": scatterLogarithmicRegressionData] as [String: Any],
                // [1] / [2] the two built-in `filter` transforms splitting dim 4 (year) into the two
                // scatter series. Both read dataset[0] (no `fromDatasetIndex` => default index 0).
                [
                    "transform": [
                        "type": "filter",
                        "config": ["dimension": 4.0, "eq": 1990.0] as [String: Any]
                    ] as [String: Any]
                ] as [String: Any],
                [
                    "transform": [
                        "type": "filter",
                        "config": ["dimension": 4.0, "eq": 2015.0] as [String: Any]
                    ] as [String: Any]
                ] as [String: Any],
                // [3] the ecStat logarithmic fit — y = a·ln(x) + b. Also defaults to dataset[0], so it is
                // fitted over all 38 points (both years pooled), not just the 2015 subset. ecStat's
                // `formulaOn` default ('end') puts the formula string in dim 2 of the LAST fitted point.
                // This is the transform type EChartsKit does not register — see nativeSupported above.
                [
                    "transform": [
                        "type": "ecStat:regression",
                        "config": ["method": "logarithmic"] as [String: Any]
                    ] as [String: Any]
                ] as [String: Any]
            ],
            "title": [
                "text": "1990 and 2015 per capita life expectancy and GDP",
                "subtext": "By ecStat.regression",
                "sublink": "https://github.com/ecomfe/echarts-stat",
                "left": "center"
            ] as [String: Any],
            "legend": [
                "data": ["1990", "2015"],
                "bottom": 10.0
            ] as [String: Any],
            "tooltip": [
                "trigger": "axis",
                "axisPointer": ["type": "cross"] as [String: Any]
            ] as [String: Any],
            "xAxis": [
                "type": "value",
                "splitLine": [
                    "lineStyle": ["type": "dashed"] as [String: Any]
                ] as [String: Any]
            ] as [String: Any],
            "yAxis": [
                "type": "value",
                "splitLine": [
                    "lineStyle": ["type": "dashed"] as [String: Any]
                ] as [String: Any]
            ] as [String: Any],
            // Sizes the scatter symbols by dim 2 (population) across [10, 70]. `seriesIndex: [0, 1]` keeps
            // it off the regression line. Plain values throughout — no symbolSize closure to omit.
            "visualMap": [
                "show": false,
                "dimension": 2.0,
                "min": 20000.0,
                "max": 1500000000.0,
                "seriesIndex": [0.0, 1.0],
                "inRange": [
                    "symbolSize": [10.0, 70.0]
                ] as [String: Any]
            ] as [String: Any],
            "series": [
                [
                    "name": "1990",
                    "type": "scatter",
                    "datasetIndex": 1.0
                ] as [String: Any],
                [
                    "name": "2015",
                    "type": "scatter",
                    "datasetIndex": 2.0
                ] as [String: Any],
                [
                    "name": "line",
                    "type": "line",
                    "smooth": true,
                    "datasetIndex": 3.0,
                    // A number upstream (not a symbolSize closure) — the fitted curve is drawn with its
                    // symbols effectively invisible.
                    "symbolSize": 0.1,
                    "symbol": "circle",
                    "label": ["show": true, "fontSize": 16.0] as [String: Any],
                    "labelLayout": ["dx": -20.0] as [String: Any],
                    // dim 2 = the regression formula text the transform appends; dim 1 = y, for the tooltip.
                    "encode": ["label": 2.0, "tooltip": 1.0] as [String: Any]
                ] as [String: Any]
            ]
        ])
}
