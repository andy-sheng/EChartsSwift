// official-bar-histogram — replica of https://echarts.apache.org/examples/zh/editor.html?c=bar-histogram
// title: Histogram with Custom Series / titleCN: 直方图（自定义系列）
//
// Three panels over ONE dataset chain: 31 raw (x, y) samples as a `scatter` in the lower-left grid, and
// two histograms of them binned by the third-party `ecStat:histogram` dataset transform — dataset[1] bins
// dimension 0 (drawn as a vertical `bar` above the scatter, `barWidth: '99.3%'` so the bins touch) and
// dataset[2] bins dimension 1 (`config: { dimensions: [1] }`, drawn as a horizontal `bar` to the right of
// the scatter via `encode: { x: 1, y: 0 }`). The three grids interlock (`grid[0]` top 50%/right 50%, etc.)
// so each histogram sits along the axis it summarises. Each bar is labelled with the bin's interval string,
// which the transform returns as dimension 4 (`encode: { itemName: 4 }`).
// NOTE ON THE NAME: despite the official title, this example contains NO `custom` series — it is `scatter` +
// two `bar` series; the title is upstream's (it is filed under the `custom` category). We keep both verbatim.
//
// DEVIATIONS from the official source:
//   - ECSTAT IS INLINED. The example's first statement is
//     `echarts.registerTransform(ecStat.transform.histogram)`. `ecStat` is the third-party echarts-stat
//     plugin (https://github.com/ecomfe/echarts-stat), which the official editor page loads from a CDN;
//     our reference page is offline and self-contained (no network, no ROOT_PATH), so `ecStat` would be a
//     ReferenceError that blanks the whole pane. The ecStat UMD bundle vendored with upstream echarts
//     (upstream/echarts/test/lib/ecStat.min.js — the exact build upstream's own test/data-transform-ecStat.html
//     loads) is therefore read via Upstream.repoRoot (the same #filePath-relative repo read WebPage.swift uses
//     for the echarts dist, so it resolves on macOS and in the iOS simulator alike) and spliced into
//     webOptionJS ABOVE the example. It is a UMD with no module system present in a classic script, so it
//     assigns the global `ecStat` exactly as the CDN <script> would. From `echarts.registerTransform(...)`
//     down, webOptionJS is the official source VERBATIM.
//   - The leading `/* title: ... */` metadata block comment (the examples repo's front-matter, not code) is
//     dropped; its contents are reproduced in this header. There is no trailing `export {};` to drop.
//   - Nothing else: the option is static (no timers, no myChart driving) and contains no closures — not one
//     formatter — so the native `option` below is a 1:1 transcription, dataset transforms included.
//
// nativeSupported: TRUE — the former gap was the TRANSFORM TYPE, not a closure. EChartsKit has the full
// dataset-transform pipeline (data/helper/transform.swift: `applyDataTransform` + the public
// `registerExternalTransform`; sourceManager.swift resolving `datasetIndex` / `fromTransformResult`), but
// for a long time the only types ever registered were the two BUILT-INS, `filter` and `sort`
// (component/transform/transformInstall.swift). `ecStat:histogram` is a JS function object handed to
// `echarts.registerTransform` by a plugin that lives outside the echarts source tree, so nothing registered
// that type: the lookup in `applySingleDataTransform` missed and it threw
// `Can not find transform on type "ecStat:histogram".` while building dataset[1] — i.e. the bins, i.e. the
// point of the example. FIXED by `ecStatHistogramTransform.swift` — a faithful port of echarts-stat's
// `histogram()` (squareRoot/scott/freedmanDiaconis/sturges bin-count choosers, the d3-tickStep-style "nice"
// step, and the bisect-based bin assignment; see that file's header for the full derivation) registered
// under its own `ecStat:histogram` type in `transformInstall.swift`. (Registering it from THIS file was
// rejected on purpose, exactly as official-scatter-polynomial-regression records: `externalTransformMap` is
// global and keyed by type string, so per-demo registration would have the sibling ecStat demos racing to
// overwrite each other.) The option below needed no change.
import Foundation

// The ecStat UMD (echarts-stat), spliced into the reference page — see DEVIATIONS. A read failure degrades to
// "" so the pane fails loudly (`ecStat is not defined`) rather than quietly rendering a chart with no bins.
private let barHistogramEcStatUMD: String = {
    let url = Upstream.repoRoot.appendingPathComponent("upstream/echarts/test/lib/ecStat.min.js")
    return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
}()

// The 31 raw (x, y) samples — upstream's `dataset[0].source`, verbatim. Hoisted out of the option literal
// with an explicit type: a 31-row untyped nested literal is what times out Swift's type-checker.
private let barHistogramSource: [[Double]] = [
    [8.3, 143],
    [8.6, 214],
    [8.8, 251],
    [10.5, 26],
    [10.7, 86],
    [10.8, 93],
    [11.0, 176],
    [11.0, 39],
    [11.1, 221],
    [11.2, 188],
    [11.3, 57],
    [11.4, 91],
    [11.4, 191],
    [11.7, 8],
    [12.0, 196],
    [12.9, 177],
    [12.9, 153],
    [13.3, 201],
    [13.7, 199],
    [13.8, 47],
    [14.0, 81],
    [14.2, 98],
    [14.5, 121],
    [16.0, 37],
    [16.3, 12],
    [17.3, 105],
    [17.5, 168],
    [17.9, 84],
    [18.0, 197],
    [18.0, 155],
    [20.6, 125]
]

extension EChartsDemoRegistry {
    static let official_bar_histogram = EChartsDemo(
        name: "official-bar-histogram", category: "custom",
        summary: "直方图（自定义系列） — Histogram with Custom Series",
        width: 720, height: 460,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
// --- echarts-stat (ecStat) UMD, inlined: the gallery page has no network and no CDN. Everything below the
// --- next banner is the official example source, verbatim.
\#(barHistogramEcStatUMD)
// --- official source ---------------------------------------------------------------------------------
// See https://github.com/ecomfe/echarts-stat
echarts.registerTransform(ecStat.transform.histogram);

option = {
  dataset: [
    {
      source: [
        [8.3, 143],
        [8.6, 214],
        [8.8, 251],
        [10.5, 26],
        [10.7, 86],
        [10.8, 93],
        [11.0, 176],
        [11.0, 39],
        [11.1, 221],
        [11.2, 188],
        [11.3, 57],
        [11.4, 91],
        [11.4, 191],
        [11.7, 8],
        [12.0, 196],
        [12.9, 177],
        [12.9, 153],
        [13.3, 201],
        [13.7, 199],
        [13.8, 47],
        [14.0, 81],
        [14.2, 98],
        [14.5, 121],
        [16.0, 37],
        [16.3, 12],
        [17.3, 105],
        [17.5, 168],
        [17.9, 84],
        [18.0, 197],
        [18.0, 155],
        [20.6, 125]
      ]
    },
    {
      transform: {
        type: 'ecStat:histogram',
        config: {}
      }
    },
    {
      transform: {
        type: 'ecStat:histogram',
        // print: true,
        config: { dimensions: [1] }
      }
    }
  ],
  tooltip: {},
  grid: [
    {
      top: '50%',
      right: '50%'
    },
    {
      bottom: '52%',
      right: '50%'
    },
    {
      top: '50%',
      left: '52%'
    }
  ],
  xAxis: [
    {
      scale: true,
      gridIndex: 0
    },
    {
      type: 'category',
      scale: true,
      axisTick: { show: false },
      axisLabel: { show: false },
      axisLine: { show: false },
      gridIndex: 1
    },
    {
      scale: true,
      gridIndex: 2
    }
  ],
  yAxis: [
    {
      gridIndex: 0
    },
    {
      gridIndex: 1
    },
    {
      type: 'category',
      axisTick: { show: false },
      axisLabel: { show: false },
      axisLine: { show: false },
      gridIndex: 2
    }
  ],
  series: [
    {
      name: 'origianl scatter',
      type: 'scatter',
      xAxisIndex: 0,
      yAxisIndex: 0,
      encode: { tooltip: [0, 1] },
      datasetIndex: 0
    },
    {
      name: 'histogram',
      type: 'bar',
      xAxisIndex: 1,
      yAxisIndex: 1,
      barWidth: '99.3%',
      label: {
        show: true,
        position: 'top'
      },
      encode: { x: 0, y: 1, itemName: 4 },
      datasetIndex: 1
    },
    {
      name: 'histogram',
      type: 'bar',
      xAxisIndex: 2,
      yAxisIndex: 2,
      barWidth: '99.3%',
      label: {
        show: true,
        position: 'right'
      },
      encode: { x: 1, y: 0, itemName: 4 },
      datasetIndex: 2
    }
  ]
};
"""#,
        option: [
            // PORT-NOTE: the two `ecStat:histogram` transforms are DECLARED here exactly as upstream; their
            // implementation now lives in `ecStatHistogramTransform.swift` (registered as `ecStat:histogram`
            // in transformInstall.swift) — see the header.
            "dataset": [
                // [0] the raw samples, consumed by the scatter series.
                ["source": barHistogramSource] as [String: Any],
                // [1] bins of dimension 0 (ecStat's default) — the vertical histogram.
                [
                    "transform": [
                        "type": "ecStat:histogram",
                        "config": [:] as [String: Any]
                    ] as [String: Any]
                ] as [String: Any],
                // [2] bins of dimension 1 — the horizontal histogram.
                [
                    "transform": [
                        "type": "ecStat:histogram",
                        "config": ["dimensions": [1.0]] as [String: Any]
                    ] as [String: Any]
                ] as [String: Any]
            ],
            "tooltip": [:] as [String: Any],
            // Three interlocking grids: [0] scatter (lower-left), [1] x-histogram (above it),
            // [2] y-histogram (right of it).
            "grid": [
                ["top": "50%", "right": "50%"] as [String: Any],
                ["bottom": "52%", "right": "50%"] as [String: Any],
                ["top": "50%", "left": "52%"] as [String: Any]
            ],
            "xAxis": [
                ["scale": true, "gridIndex": 0.0] as [String: Any],
                // The vertical histogram's bin axis: categories (the interval strings), chrome hidden so it
                // reads as a continuation of the scatter's x-axis below it.
                [
                    "type": "category",
                    "scale": true,
                    "axisTick": ["show": false] as [String: Any],
                    "axisLabel": ["show": false] as [String: Any],
                    "axisLine": ["show": false] as [String: Any],
                    "gridIndex": 1.0
                ] as [String: Any],
                ["scale": true, "gridIndex": 2.0] as [String: Any]
            ],
            "yAxis": [
                ["gridIndex": 0.0] as [String: Any],
                ["gridIndex": 1.0] as [String: Any],
                // The horizontal histogram's bin axis — same trick, on y.
                [
                    "type": "category",
                    "axisTick": ["show": false] as [String: Any],
                    "axisLabel": ["show": false] as [String: Any],
                    "axisLine": ["show": false] as [String: Any],
                    "gridIndex": 2.0
                ] as [String: Any]
            ],
            "series": [
                // The raw points (upstream's typo `origianl` kept verbatim — it shows in the tooltip).
                [
                    "name": "origianl scatter",
                    "type": "scatter",
                    "xAxisIndex": 0.0,
                    "yAxisIndex": 0.0,
                    "encode": ["tooltip": [0.0, 1.0]] as [String: Any],
                    "datasetIndex": 0.0
                ] as [String: Any],
                // Bins of x, drawn upward. dim 0 = bin centre, dim 1 = count, dim 4 = the interval string.
                [
                    "name": "histogram",
                    "type": "bar",
                    "xAxisIndex": 1.0,
                    "yAxisIndex": 1.0,
                    "barWidth": "99.3%",
                    "label": ["show": true, "position": "top"] as [String: Any],
                    "encode": ["x": 0.0, "y": 1.0, "itemName": 4.0] as [String: Any],
                    "datasetIndex": 1.0
                ] as [String: Any],
                // Bins of y, drawn rightward — the same result table read with x/y swapped.
                [
                    "name": "histogram",
                    "type": "bar",
                    "xAxisIndex": 2.0,
                    "yAxisIndex": 2.0,
                    "barWidth": "99.3%",
                    "label": ["show": true, "position": "right"] as [String: Any],
                    "encode": ["x": 1.0, "y": 0.0, "itemName": 4.0] as [String: Any],
                    "datasetIndex": 2.0
                ] as [String: Any]
            ]
        ])
}
