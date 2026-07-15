// official-boxplot-light-velocity — replica of
// https://echarts.apache.org/examples/zh/editor.html?c=boxplot-light-velocity
// title: Boxplot Light Velocity / titleCN: 基础盒须图
//
// The Michelson-Morley experiment: 5 runs × 20 light-speed measurements (km/s minus 299,000) fed as a raw
// `dataset` and reduced by the BUILT-IN `boxplot` dataset transform into (a) the five boxes and (b) a second
// transform result holding the outliers, drawn as a `scatter` series.
//
// DEVIATIONS from the official source: none in the option itself — the JS is verbatim (the raw 5×20 sample
// matrix is inline in the upstream example already, so nothing had to be fetched or spliced in), and the
// example is static (no setInterval / re-setOption). `itemNameFormatter: 'expr {value}'` is a template
// STRING upstream, not a closure, so nothing was dropped.
//
// nativeSupported: FALSE — but the gap is NARROWER than it looks, so don't let this note mislead the next
// reader. EChartsKit already has BOTH halves this example is usually assumed to be blocked on:
//   - the `boxplot` SERIES: `ComponentModel.registerClass(BoxplotSeriesModel.self)` + `BoxplotView` in the
//     view factory + `boxplotLayout(ecModel)` + `registerBoxplotAxisHandlers` are all wired in
//     `ECharts.installOnce()`.
//   - the `dataset` TRANSFORM PIPELINE: `sourceManager.swift` reads `fromDatasetIndex` /
//     `fromTransformResult`, `data/helper/transform.swift` is the `applyDataTransform` engine, and
//     `transformInstall` registers the `filter` + `sort` built-ins against it.
// The ONE missing piece is the `boxplot` transform TYPE itself: upstream `chart/boxplot/boxplotTransform.ts`
// is not ported, so nothing ever calls `registerExternalTransform` for it and `applyDataTransform` throws
// `Can not find transform on type "boxplot".` on `dataset[1]` — hence the native pane is off. The math it
// wraps (`prepareBoxplotData.swift`) IS already ported, so the remaining work is the thin
// `ExternalDataTransform` wrapper + one registration call. The `option` below is a 1:1 Swift transcription
// of the official option, so this demo lights up for free the moment that wrapper lands.

// The raw sample matrix (upstream `dataset[0].source`): 5 experiment runs, 20 measurements each.
// Hoisted out of the option literal with an explicit type — a 100-element untyped nested literal is
// exactly the shape that times out Swift's type-checker.
private let lightVelocitySource: [[Double]] = [
    [850, 740, 900, 1070, 930, 850, 950, 980, 980, 880, 1000, 980, 930, 650, 760, 810, 1000, 1000, 960, 960],
    [960, 940, 960, 940, 880, 800, 850, 880, 900, 840, 830, 790, 810, 880, 880, 830, 800, 790, 760, 800],
    [880, 880, 880, 860, 720, 720, 620, 860, 970, 950, 880, 910, 850, 870, 840, 840, 850, 840, 840, 840],
    [890, 810, 810, 820, 800, 770, 760, 740, 750, 760, 910, 920, 890, 860, 880, 720, 840, 850, 850, 780],
    [890, 840, 780, 810, 760, 810, 790, 810, 820, 850, 870, 870, 810, 740, 810, 940, 950, 800, 810, 870]
]

extension EChartsDemoRegistry {
    static let official_boxplot_light_velocity = EChartsDemo(
        name: "official-boxplot-light-velocity", category: "boxplot",
        summary: "基础盒须图 — Boxplot Light Velocity",
        width: 640, height: 420,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
option = {
  title: [
    {
      text: 'Michelson-Morley Experiment',
      left: 'center'
    },
    {
      text: 'upper: Q3 + 1.5 * IQR \nlower: Q1 - 1.5 * IQR',
      borderColor: '#999',
      borderWidth: 1,
      textStyle: {
        fontWeight: 'normal',
        fontSize: 14,
        lineHeight: 20
      },
      left: '10%',
      top: '90%'
    }
  ],
  dataset: [
    {
      // prettier-ignore
      source: [
        [850, 740, 900, 1070, 930, 850, 950, 980, 980, 880, 1000, 980, 930, 650, 760, 810, 1000, 1000, 960, 960],
        [960, 940, 960, 940, 880, 800, 850, 880, 900, 840, 830, 790, 810, 880, 880, 830, 800, 790, 760, 800],
        [880, 880, 880, 860, 720, 720, 620, 860, 970, 950, 880, 910, 850, 870, 840, 840, 850, 840, 840, 840],
        [890, 810, 810, 820, 800, 770, 760, 740, 750, 760, 910, 920, 890, 860, 880, 720, 840, 850, 850, 780],
        [890, 840, 780, 810, 760, 810, 790, 810, 820, 850, 870, 870, 810, 740, 810, 940, 950, 800, 810, 870]
      ]
    },
    {
      transform: {
        type: 'boxplot',
        config: { itemNameFormatter: 'expr {value}' }
      }
    },
    {
      fromDatasetIndex: 1,
      fromTransformResult: 1
    }
  ],
  tooltip: {
    trigger: 'item',
    axisPointer: {
      type: 'shadow'
    }
  },
  grid: {
    left: '10%',
    right: '10%',
    bottom: '15%'
  },
  xAxis: {
    type: 'category',
    boundaryGap: true,
    nameGap: 30,
    splitArea: {
      show: false
    },
    splitLine: {
      show: false
    }
  },
  yAxis: {
    type: 'value',
    name: 'km/s minus 299,000',
    splitArea: {
      show: true
    }
  },
  series: [
    {
      name: 'boxplot',
      type: 'boxplot',
      datasetIndex: 1
    },
    {
      name: 'outlier',
      type: 'scatter',
      datasetIndex: 2
    }
  ]
};
"""#,
        option: [
            "title": [
                [
                    "text": "Michelson-Morley Experiment",
                    "left": "center"
                ] as [String: Any],
                [
                    // JS `'upper: Q3 + 1.5 * IQR \nlower: Q1 - 1.5 * IQR'` — same embedded newline.
                    "text": "upper: Q3 + 1.5 * IQR \nlower: Q1 - 1.5 * IQR",
                    "borderColor": "#999",
                    "borderWidth": 1.0,
                    "textStyle": [
                        "fontWeight": "normal",
                        "fontSize": 14.0,
                        "lineHeight": 20.0
                    ] as [String: Any],
                    "left": "10%",
                    "top": "90%"
                ] as [String: Any]
            ],
            "dataset": [
                // [0] the raw 5×20 sample matrix.
                ["source": lightVelocitySource] as [String: Any],
                // [1] the built-in boxplot transform: result 0 = the boxes, result 1 = the outliers.
                [
                    "transform": [
                        "type": "boxplot",
                        // 'expr {value}' is a template STRING upstream (not a closure) — ports as-is.
                        "config": ["itemNameFormatter": "expr {value}"] as [String: Any]
                    ] as [String: Any]
                ] as [String: Any],
                // [2] the transform's SECOND result (the outliers), consumed by the scatter series.
                [
                    "fromDatasetIndex": 1.0,
                    "fromTransformResult": 1.0
                ] as [String: Any]
            ],
            "tooltip": [
                "trigger": "item",
                "axisPointer": ["type": "shadow"] as [String: Any]
            ] as [String: Any],
            "grid": [
                "left": "10%",
                "right": "10%",
                "bottom": "15%"
            ] as [String: Any],
            "xAxis": [
                "type": "category",
                "boundaryGap": true,
                "nameGap": 30.0,
                "splitArea": ["show": false] as [String: Any],
                "splitLine": ["show": false] as [String: Any]
            ] as [String: Any],
            "yAxis": [
                "type": "value",
                "name": "km/s minus 299,000",
                "splitArea": ["show": true] as [String: Any]
            ] as [String: Any],
            "series": [
                [
                    "name": "boxplot",
                    "type": "boxplot",
                    "datasetIndex": 1.0
                ] as [String: Any],
                [
                    "name": "outlier",
                    "type": "scatter",
                    "datasetIndex": 2.0
                ] as [String: Any]
            ]
        ])
}
