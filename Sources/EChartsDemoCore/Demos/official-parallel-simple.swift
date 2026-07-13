// official-parallel-simple — replica of https://echarts.apache.org/examples/zh/editor.html?c=parallel-simple
// title: Basic Parallel / titleCN: 基础平行坐标
// Four parallel axes (three value, one category 'Score') with three 4-dimension data lines.
// The example is static: no assets, no closures, no JS-function-valued keys — so nothing is dropped
// from the native `option`, and webOptionJS is the upstream source verbatim (`series` stays an OBJECT
// there, exactly as upstream writes it — real echarts array-normalizes it in `backwardCompat`).
//
// DEVIATION (native pane only): the Swift `option` wraps `series` in a ONE-ELEMENT ARRAY. Upstream's
//   `compat/backwardCompat.ts` preprocessor runs `option.series = normalizeToArray(option.series)`
//   BEFORE `parallelPreprocessor`, so by the time the latter runs, `series` is always an array
//   (verified against echarts 6.1.0: a late-registered preprocessor already sees `series` as an array
//   and `parallel: [{}]`). EChartsKit does NOT port backwardCompat, and its `parallelPreprocessor`
//   reads `option["series"] as? [Any]` — a dict-valued `series` casts to nil, so `hasParallelSeries`
//   stays false, `option.parallel` is never auto-created, `parallelCreator` builds no coordinate
//   system, and ParallelView bails out (blank native pane). Passing the already-normalized array is
//   exactly what echarts does internally; the option is semantically identical either way.
extension EChartsDemoRegistry {
    static let official_parallel_simple = EChartsDemo(
        name: "official-parallel-simple", category: "parallel",
        summary: "基础平行坐标 — Basic Parallel",
        width: 640, height: 420,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
option = {
  parallelAxis: [
    { dim: 0, name: 'Price' },
    { dim: 1, name: 'Net Weight' },
    { dim: 2, name: 'Amount' },
    {
      dim: 3,
      name: 'Score',
      type: 'category',
      data: ['Excellent', 'Good', 'OK', 'Bad']
    }
  ],
  series: {
    type: 'parallel',
    lineStyle: {
      width: 4
    },
    data: [
      [12.99, 100, 82, 'Good'],
      [9.99, 80, 77, 'OK'],
      [20, 120, 60, 'Excellent']
    ]
  }
};
"""#,
        option: [
            "parallelAxis": [
                ["dim": 0, "name": "Price"] as [String: Any],
                ["dim": 1, "name": "Net Weight"] as [String: Any],
                ["dim": 2, "name": "Amount"] as [String: Any],
                [
                    "dim": 3,
                    "name": "Score",
                    "type": "category",
                    "data": ["Excellent", "Good", "OK", "Bad"]
                ] as [String: Any]
            ],
            // PORT-NOTE: array-wrapped (see the DEVIATION note in the file header); upstream's
            //   backwardCompat preprocessor does the same normalization before any parallel code runs.
            "series": [
                [
                    "type": "parallel",
                    "lineStyle": ["width": 4.0] as [String: Any],
                    "data": parallelSimpleData
                ] as [String: Any]
            ]
        ])
}

// Mixed value/category rows (the 4th dim is an ordinal string), so the element type is [Any].
private let parallelSimpleData: [[Any]] = [
    [12.99, 100.0, 82.0, "Good"],
    [9.99, 80.0, 77.0, "OK"],
    [20.0, 120.0, 60.0, "Excellent"]
]
