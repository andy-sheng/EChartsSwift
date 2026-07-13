// official-data-transform-sort-bar — replica of https://echarts.apache.org/examples/zh/editor.html?c=data-transform-sort-bar
// title: Sort Data in Bar Chart / titleCN: 柱状图排序
// A 9-row inline table (name/age/profession/score/date) run through the built-in `sort` transform
// (`dimension: 'score', order: 'desc'`); a single `bar` series reads the DERIVED dataset
// (`datasetIndex: 1`) and encodes x=name, y=score — so the bars come out ordered by score without the
// source rows being pre-sorted by hand. One row ('Adrian Groß') has `'-'` for its score: it is
// incomparable, and `desc` parks it at the tail (SortOrderComparator's `incomparable: 'min'` default).
//
// DEVIATIONS from the official source:
//   - None of substance. The example is a single static `option` literal — no data fetch, no timers, no
//     closures — so both panes carry it verbatim; only the trailing `export {}` is dropped (a bare export
//     is a SyntaxError in the reference pane's classic script).
//   - Native pane: the source rows are hoisted to a file-scope `[[Any]]` (Swift's type-checker chokes on a
//     large heterogeneous literal inline) and every number is a Swift `Double` — `util.isNumber` is
//     `value is Double`, so an `Int` score would miss SortOrderComparator's numeric path and be treated as
//     incomparable. `series` stays a single object, not an array, exactly as upstream: OptionManager
//     normalizes it (`model.normalizeToArray(ro["series"])`).
extension EChartsDemoRegistry {
    static let official_data_transform_sort_bar = EChartsDemo(
        name: "official-data-transform-sort-bar", category: "dataset",
        summary: "柱状图排序 — Sort Data in Bar Chart",
        width: 640, height: 420,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
option = {
  dataset: [
    {
      dimensions: ['name', 'age', 'profession', 'score', 'date'],
      source: [
        ['Hannah Krause', 41, 'Engineer', 314, '2011-02-12'],
        ['Zhao Qian', 20, 'Teacher', 351, '2011-03-01'],
        ['Jasmin Krause ', 52, 'Musician', 287, '2011-02-14'],
        ['Li Lei', 37, 'Teacher', 219, '2011-02-18'],
        ['Karle Neumann', 25, 'Engineer', 253, '2011-04-02'],
        ['Adrian Groß', 19, 'Teacher', '-', '2011-01-16'],
        ['Mia Neumann', 71, 'Engineer', 165, '2011-03-19'],
        ['Böhm Fuchs', 36, 'Musician', 318, '2011-02-24'],
        ['Han Meimei', 67, 'Engineer', 366, '2011-03-12']
      ]
    },
    {
      transform: {
        type: 'sort',
        config: { dimension: 'score', order: 'desc' }
      }
    }
  ],
  xAxis: {
    type: 'category',
    axisLabel: { interval: 0, rotate: 30 }
  },
  yAxis: {},
  series: {
    type: 'bar',
    encode: { x: 'name', y: 'score' },
    datasetIndex: 1
  }
};
"""#,
        option: [
            "dataset": [
                [
                    "dimensions": ["name", "age", "profession", "score", "date"],
                    "source": sortBarSource
                ] as [String: Any],
                [
                    "transform": [
                        "type": "sort",
                        "config": ["dimension": "score", "order": "desc"] as [String: Any]
                    ] as [String: Any]
                ] as [String: Any]
            ],
            "xAxis": [
                "type": "category",
                "axisLabel": ["interval": 0.0, "rotate": 30.0] as [String: Any]
            ] as [String: Any],
            "yAxis": [:] as [String: Any],
            // Upstream declares `series` as a single object (not an array); kept as-is.
            "series": [
                "type": "bar",
                "encode": ["x": "name", "y": "score"] as [String: Any],
                "datasetIndex": 1.0
            ] as [String: Any]
        ])
}

// [name, age, profession, score, date] — the raw, UNSORTED table; the `sort` transform orders it.
// Numbers are `Double` (see the header note on util.isNumber); 'Adrian Groß' keeps its `'-'` score.
private let sortBarSource: [[Any]] = [
    ["Hannah Krause", 41.0, "Engineer", 314.0, "2011-02-12"],
    ["Zhao Qian", 20.0, "Teacher", 351.0, "2011-03-01"],
    ["Jasmin Krause ", 52.0, "Musician", 287.0, "2011-02-14"],
    ["Li Lei", 37.0, "Teacher", 219.0, "2011-02-18"],
    ["Karle Neumann", 25.0, "Engineer", 253.0, "2011-04-02"],
    ["Adrian Groß", 19.0, "Teacher", "-", "2011-01-16"],
    ["Mia Neumann", 71.0, "Engineer", 165.0, "2011-03-19"],
    ["Böhm Fuchs", 36.0, "Musician", 318.0, "2011-02-24"],
    ["Han Meimei", 67.0, "Engineer", 366.0, "2011-03-12"]
]
