// official-boxplot-light-velocity2 — replica of
// https://echarts.apache.org/examples/zh/editor.html?c=boxplot-light-velocity2
// title: Boxplot Light Velocity2 / titleCN: 垂直方向盒须图
//
// The Michelson-Morley experiment again (5 runs × 20 light-speed measurements, km/s minus 299,000), but laid
// out with the CATEGORY axis on y and the VALUE axis on x — i.e. the boxes lie horizontally. Same shape as
// `official-boxplot-light-velocity`: a raw `dataset` reduced by the built-in `boxplot` dataset transform into
// (a) the five boxes and (b) a second transform result holding the outliers, drawn as a `scatter` series.
// Because the axes are swapped, the outlier scatter carries an explicit `encode: { x: 1, y: 0 }`.
//
// DEVIATIONS from the official source:
//   - webOptionJS: the upstream file is TypeScript — its `function (params: any)` type annotation is stripped
//     (a `: any` in a classic <script> is a SyntaxError), and the trailing `export {};` is dropped. The 5×20
//     sample matrix is already inline upstream, so nothing had to be fetched or spliced in. Otherwise verbatim;
//     the example is static (no setInterval / re-setOption), so the single rendered frame IS the example.
//   - option (native): the JS `itemNameFormatter(params)` callback is represented by the native boxplot
//     transform callback `(Double) -> String`; both produce the same `expr <index>` item names.
//
// nativeSupported: TRUE — same wiring as `official-boxplot-light-velocity`: the `boxplot` SERIES
// (BoxplotSeriesModel + BoxplotView + boxplotLayout + registerBoxplotAxisHandlers, all wired in
// `ECharts.installOnce()`), the `dataset` TRANSFORM PIPELINE (sourceManager reads
// `fromDatasetIndex`/`fromTransformResult`; `data/helper/transform.swift` is the `applyDataTransform`
// engine), and the `boxplot` transform TYPE itself — `chart/boxplot/boxplotTransform.swift`, the thin
// `ExternalDataTransform` wrapper around the ported `prepareBoxplotData.swift`, registered by
// `registerExternalTransform(boxplotTransform)` in `component/transform/transformInstall.swift:69`.
// The `option` below is a 1:1 transcription — modulo the item names noted at the drop site.

// The raw sample matrix (upstream `dataset[0].source`): 5 experiment runs, 20 measurements each.
// Hoisted out of the option literal with an explicit type — a 100-element untyped nested literal is
// exactly the shape that times out Swift's type-checker.
private let lightVelocity2Source: [[Double]] = [
    [850, 740, 900, 1070, 930, 850, 950, 980, 980, 880, 1000, 980, 930, 650, 760, 810, 1000, 1000, 960, 960],
    [960, 940, 960, 940, 880, 800, 850, 880, 900, 840, 830, 790, 810, 880, 880, 830, 800, 790, 760, 800],
    [880, 880, 880, 860, 720, 720, 620, 860, 970, 950, 880, 910, 850, 870, 840, 840, 850, 840, 840, 840],
    [890, 810, 810, 820, 800, 770, 760, 740, 750, 760, 910, 920, 890, 860, 880, 720, 840, 850, 850, 780],
    [890, 840, 780, 810, 760, 810, 790, 810, 820, 850, 870, 870, 810, 740, 810, 940, 950, 800, 810, 870]
]

private let lightVelocity2ItemNameFormatter: (Double) -> String = { value in
    "expr \(Int(value))"
}

extension EChartsDemoRegistry {
    static let official_boxplot_light_velocity2 = EChartsDemo(
        name: "official-boxplot-light-velocity2", category: "boxplot",
        summary: "垂直方向盒须图 — Boxplot Light Velocity2",
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
        fontSize: 14
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
        config: {
          itemNameFormatter: function (params) {
            return 'expr ' + params.value;
          }
        }
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
  yAxis: {
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
  xAxis: {
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
      encode: { x: 1, y: 0 },
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
                        "fontSize": 14.0
                    ] as [String: Any],
                    "left": "10%",
                    "top": "90%"
                ] as [String: Any]
            ],
            "dataset": [
                // [0] the raw 5×20 sample matrix.
                ["source": lightVelocity2Source] as [String: Any],
                // [1] the built-in boxplot transform: result 0 = the boxes, result 1 = the outliers.
                [
                    "transform": [
                        "type": "boxplot",
                        "config": [
                            "itemNameFormatter": lightVelocity2ItemNameFormatter as (Double) -> String
                        ] as [String: Any]
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
            // Axes are SWAPPED relative to light-velocity: category on y, value on x.
            "yAxis": [
                "type": "category",
                "boundaryGap": true,
                "nameGap": 30.0,
                "splitArea": ["show": false] as [String: Any],
                "splitLine": ["show": false] as [String: Any]
            ] as [String: Any],
            "xAxis": [
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
                    // dim 1 = the outlier value -> x, dim 0 = the box's item name -> y (category).
                    "encode": ["x": 1.0, "y": 0.0] as [String: Any],
                    "datasetIndex": 2.0
                ] as [String: Any]
            ]
        ])
}
