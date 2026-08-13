// official-data-transform-aggregate — replica of
// https://echarts.apache.org/examples/zh/editor.html?c=data-transform-aggregate
// title: Data Transform Simple Aggregate / titleCN: 简单的数据聚合
//
// A three-stage dataset PIPELINE over the 1540-row life-expectancy table: `raw` → `since_year`
// (built-in `filter`, Year >= 1950) → `income_aggregate`, which runs the THIRD-PARTY
// `ecSimpleTransform:aggregate` transform to reduce each country's Income column to its five-number
// summary (min / Q1 / median / Q3 / max), then `sort`s the groups by Q3. The aggregate rows feed a
// horizontal `boxplot` series; the *unaggregated* `since_year` rows are overlaid as a red `scatter`
// series (one dot per country-year), so each box sits behind the raw points it summarises.
//
// DEVIATIONS from the official source:
//   - Data inlined. Upstream fetches the table inside a `$.when($.get(ROOT_PATH +
//     '/data/asset/data/life-expectancy-table.json'), $.getScript(CDN_PATH + 'echarts-simple-transform/...'))
//     .done(function (res) { run(res[0]); })` wrapper. The page has no network, so the asset is vendored at
//     assets/data/life-expectancy-table.json and read at demo time via Upstream.repoRoot (the same
//     #filePath-relative repo read WebPage.swift uses for the echarts dist): spliced verbatim into
//     webOptionJS as the `_rawData` JS literal, and parsed into the Swift `option`. The fetch wrapper and
//     the `run()` function are dropped so its BODY runs at the top level; everything inside it — the
//     `echarts.registerTransform(...)` call, the option literal and `myChart.setOption(option)` — is verbatim.
//   - ecSimpleTransform inlined. `$.getScript(CDN_PATH + 'echarts-simple-transform/dist/ecSimpleTransform.min.js')`
//     needs an `ecSimpleTransform` global that our offline pane cannot fetch, so the VENDORED UMD bundle is
//     spliced into webOptionJS ahead of the example's JS: upstream/echarts/test/lib/ecSimpleTransform.js —
//     the same library, the unminified build upstream's own test/data-transform-aggregate.html loads
//     (`'ecSimpleTransform': 'lib/ecSimpleTransform'` in test/lib/config.js). With no module system present
//     the UMD takes its global branch and assigns `window.ecSimpleTransform`, so the example's JS then runs
//     unchanged. (Same treatment official-scatter-linear-regression gives ecStat.)
//   - Nothing else: the option is static (no timers, no re-setOption) and carries no closures — every value
//     is declarative — so nothing had to be omitted from the native option either. Both panes carry the
//     same option, byte for byte in structure.
//
// nativeSupported: FALSE — and the gap is the TRANSFORM TYPE, not a closure, and not the boxplot series.
// EChartsKit already has (a) the `boxplot` series (BoxplotSeriesModel + BoxplotView + boxplotLayout, all
// wired in `ECharts.installOnce()`), (b) the whole dataset-transform pipeline (sourceManager resolving
// `fromDatasetId` / `fromTransformResult`; `data/helper/transform.swift` = `applyDataTransform` +
// the public `registerExternalTransform`), and (c) the `filter` and `sort` built-ins this example chains
// (component/transform/transformInstall.swift registers exactly those two, and nothing else).
// `ecSimpleTransform:aggregate` belongs to echarts-simple-transform — a separate JS plugin outside the
// echarts source tree, with no Swift port and no registration — so `applyDataTransform` throws
// `Can not find transform on type "ecSimpleTransform:aggregate".` while building `dataset[2]`, which kills
// the render before EITHER series is laid out (not just the boxplot). Exactly the shape of gap
// official-boxplot-light-velocity and official-scatter-linear-regression document: the fix is a thin
// `ExternalDataTransform` (group by a dimension, then min/Q1/median/Q3/max per group) plus one
// `registerExternalTransform` call. The `option` below is a 1:1 transcription of the official one, so this
// demo lights up for free the moment that lands.
import Foundation

// The echarts-simple-transform UMD, spliced into the reference page — see DEVIATIONS above. A read failure
// degrades to "" (the pane then errors on `ecSimpleTransform is not defined` rather than silently drawing a
// chart with its aggregation missing, which is the honest failure for a reference pane).
private let ecSimpleTransformUMDJS: String = {
    let url = Upstream.repoRoot.appendingPathComponent("upstream/echarts/test/lib/ecSimpleTransform.js")
    return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
}()

// The raw asset, as TEXT — spliced straight into webOptionJS as the `_rawData` JS array literal (it is
// already valid JS). An unreadable asset degrades to `[]`: both panes then render blank rather than crashing.
private let dtAggregateRawJSON: String = {
    let url = Upstream.repoRoot.appendingPathComponent("assets/data/life-expectancy-table.json")
    return (try? String(contentsOf: url, encoding: .utf8)) ?? "[]"
}()

// The SAME asset, parsed, for the native pane: a header row
// (`['Income', 'Life Expectancy', 'Population', 'Country', 'Year']`) + 1539 data rows. Normalize JSON
// numbers to the port's canonical `Double` representation so the built-in numeric filter takes the same
// fast path as JavaScript (`Year >= 1950`) before aggregation.
private let dtAggregateRows: [[Any]] = {
    guard let data = dtAggregateRawJSON.data(using: .utf8),
          let rows = (try? JSONSerialization.jsonObject(with: data)) as? [[Any]] else { return [] }
    return rows.map { row in
        row.map { value in
            if let number = value as? NSNumber { return number.doubleValue }
            return value
        }
    }
}()

// `income_aggregate`'s first transform: the five-number summary of `Income` per `Country`.
// One dict per result dimension; the `Country` dim is the groupBy dim, so it carries NO `method`.
private let dtAggregateResultDimensions: [[String: Any]] = [
    ["name": "min", "from": "Income", "method": "min"],
    ["name": "Q1", "from": "Income", "method": "Q1"],
    ["name": "median", "from": "Income", "method": "median"],
    ["name": "Q3", "from": "Income", "method": "Q3"],
    ["name": "max", "from": "Income", "method": "max"],
    ["name": "Country", "from": "Country"]
]

extension EChartsDemoRegistry {
    static let official_data_transform_aggregate = EChartsDemo(
        name: "official-data-transform-aggregate", category: "boxplot",
        summary: "简单的数据聚合 — Data Transform Simple Aggregate",
        width: 720, height: 560,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
// --- vendored echarts-simple-transform UMD (upstream/echarts/test/lib/ecSimpleTransform.js);
// --- assigns window.ecSimpleTransform, standing in for the example's $.getScript(CDN_PATH + ...).
\#(ecSimpleTransformUMDJS)
// --- end ecSimpleTransform; the official example's JS runs verbatim from here ---

var _rawData = \#(dtAggregateRawJSON);

echarts.registerTransform(ecSimpleTransform.aggregate);

option = {
  dataset: [
    {
      id: 'raw',
      source: _rawData
    },
    {
      id: 'since_year',
      fromDatasetId: 'raw',
      transform: [
        {
          type: 'filter',
          config: {
            dimension: 'Year',
            gte: 1950
          }
        }
      ]
    },
    {
      id: 'income_aggregate',
      fromDatasetId: 'since_year',
      transform: [
        {
          type: 'ecSimpleTransform:aggregate',
          config: {
            resultDimensions: [
              { name: 'min', from: 'Income', method: 'min' },
              { name: 'Q1', from: 'Income', method: 'Q1' },
              { name: 'median', from: 'Income', method: 'median' },
              { name: 'Q3', from: 'Income', method: 'Q3' },
              { name: 'max', from: 'Income', method: 'max' },
              { name: 'Country', from: 'Country' }
            ],
            groupBy: 'Country'
          }
        },
        {
          type: 'sort',
          config: {
            dimension: 'Q3',
            order: 'asc'
          }
        }
      ]
    }
  ],
  title: {
    text: 'Income since 1950'
  },
  tooltip: {
    trigger: 'axis',
    confine: true
  },
  xAxis: {
    name: 'Income',
    nameLocation: 'middle',
    nameGap: 30,
    scale: true
  },
  yAxis: {
    type: 'category'
  },
  grid: {
    bottom: 140
  },
  legend: {
    selected: { detail: false }
  },
  dataZoom: [
    {
      type: 'inside'
    },
    {
      type: 'slider',
      height: 20,
      bottom: 60
    }
  ],
  series: [
    {
      name: 'boxplot',
      type: 'boxplot',
      datasetId: 'income_aggregate',
      itemStyle: {
        color: '#b8c5f2'
      },
      encode: {
        x: ['min', 'Q1', 'median', 'Q3', 'max'],
        y: 'Country',
        itemName: ['Country'],
        tooltip: ['min', 'Q1', 'median', 'Q3', 'max']
      }
    },
    {
      name: 'detail',
      type: 'scatter',
      datasetId: 'since_year',
      symbolSize: 6,
      tooltip: {
        trigger: 'item'
      },
      label: {
        show: true,
        position: 'top',
        align: 'left',
        verticalAlign: 'middle',
        rotate: 90,
        fontSize: 12
      },
      itemStyle: {
        color: '#d00000'
      },
      encode: {
        x: 'Income',
        y: 'Country',
        label: 'Year',
        itemName: 'Year',
        tooltip: ['Country', 'Year', 'Income']
      }
    }
  ]
};

myChart.setOption(option);
"""#,
        option: [
            "dataset": [
                [
                    "id": "raw",
                    "source": dtAggregateRows
                ] as [String: Any],
                [
                    // Year >= 1950. NOTE: `gte` MUST be a Swift `Double` — FilterOrderComparator gates its
                    // rvalue on `util.isNumber` (`value is Double`), which an `Int` fails, and
                    // filterTransform parses the config with `try!`.
                    "id": "since_year",
                    "fromDatasetId": "raw",
                    "transform": [
                        [
                            "type": "filter",
                            "config": [
                                "dimension": "Year",
                                "gte": 1950.0
                            ] as [String: Any]
                        ] as [String: Any]
                    ]
                ] as [String: Any],
                [
                    "id": "income_aggregate",
                    "fromDatasetId": "since_year",
                    "transform": [
                        [
                            "type": "ecSimpleTransform:aggregate",
                            "config": [
                                "resultDimensions": dtAggregateResultDimensions,
                                "groupBy": "Country"
                            ] as [String: Any]
                        ] as [String: Any],
                        [
                            "type": "sort",
                            "config": [
                                "dimension": "Q3",
                                "order": "asc"
                            ] as [String: Any]
                        ] as [String: Any]
                    ]
                ] as [String: Any]
            ],
            "title": [
                "text": "Income since 1950"
            ] as [String: Any],
            "tooltip": [
                "trigger": "axis",
                "confine": true
            ] as [String: Any],
            "xAxis": [
                "name": "Income",
                "nameLocation": "middle",
                "nameGap": 30.0,
                "scale": true
            ] as [String: Any],
            "yAxis": [
                "type": "category"
            ] as [String: Any],
            "grid": [
                "bottom": 140.0
            ] as [String: Any],
            "legend": [
                // The `detail` (scatter) series starts unselected; `boxplot` stays on.
                "selected": ["detail": false] as [String: Any]
            ] as [String: Any],
            "dataZoom": [
                [
                    "type": "inside"
                ] as [String: Any],
                [
                    "type": "slider",
                    "height": 20.0,
                    "bottom": 60.0
                ] as [String: Any]
            ],
            "series": [
                [
                    // The five-number summary per country, drawn horizontally (`encode.x` is the 5 box dims).
                    "name": "boxplot",
                    "type": "boxplot",
                    "datasetId": "income_aggregate",
                    "itemStyle": [
                        "color": "#b8c5f2"
                    ] as [String: Any],
                    "encode": [
                        "x": ["min", "Q1", "median", "Q3", "max"],
                        "y": "Country",
                        "itemName": ["Country"],
                        "tooltip": ["min", "Q1", "median", "Q3", "max"]
                    ] as [String: Any]
                ] as [String: Any],
                [
                    // The raw (unaggregated) country-year points behind the boxes, labelled with the Year.
                    "name": "detail",
                    "type": "scatter",
                    "datasetId": "since_year",
                    "symbolSize": 6.0,
                    "tooltip": [
                        "trigger": "item"
                    ] as [String: Any],
                    "label": [
                        "show": true,
                        "position": "top",
                        "align": "left",
                        "verticalAlign": "middle",
                        "rotate": 90.0,
                        "fontSize": 12.0
                    ] as [String: Any],
                    "itemStyle": [
                        "color": "#d00000"
                    ] as [String: Any],
                    "encode": [
                        "x": "Income",
                        "y": "Country",
                        "label": "Year",
                        "itemName": "Year",
                        "tooltip": ["Country", "Year", "Income"]
                    ] as [String: Any]
                ] as [String: Any]
            ]
        ])
}
