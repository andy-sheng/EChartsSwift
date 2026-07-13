// official-data-transform-filter — replica of https://echarts.apache.org/examples/zh/editor.html?c=data-transform-filter
// title: Data Transform Filter / titleCN: 数据过滤
// One raw dataset (the 1540-row life-expectancy table) fanned out into two derived datasets by the
// built-in `filter` transform — `Year >= 1950 AND Country = Germany|France` — each feeding a `line`
// series through `datasetId` + `encode`. The point of the example is that no data is pre-sliced by
// hand: the two lines come out of ONE source via `dataset.transform`.
//
// DEVIATIONS from the official source:
//   - Data inlined. Upstream fetches the table with
//     `$.get(ROOT_PATH + '/data/asset/data/life-expectancy-table.json', function (_rawData) { run(_rawData); })`.
//     The page has no network, so the asset is vendored at assets/data/life-expectancy-table.json and read at
//     demo time via Upstream.repoRoot (the same #filePath-relative repo read WebPage.swift uses for the
//     echarts dist): spliced verbatim into webOptionJS as the `_rawData` JS literal, and parsed into the
//     Swift `option`. The `run(_rawData)` wrapper, `myChart.setOption` and the trailing `export {}` are
//     dropped so `option` is assigned unconditionally at the top level; the option literal itself is verbatim.
//   - Nothing omitted from the native pane: the example is fully declarative (no formatter / renderItem /
//     symbolSize closures), and EChartsKit ports the whole path it exercises — the `filter` transform
//     (component/transform/filterTransform.swift, auto-registered), `and` / `gte` / the `'='`→`eq` operator
//     alias (util/conditionalExpression.swift), `fromDatasetId`, `datasetId` and `encode`. Both panes carry
//     the same option.
import Foundation

// The raw asset, as TEXT — spliced straight into webOptionJS as a JS array literal (it is already valid JS).
// An unreadable asset degrades to `[]`: both panes then render blank rather than crashing.
private let lifeExpectancyRawJSON: String = {
    let url = Upstream.repoRoot.appendingPathComponent("assets/data/life-expectancy-table.json")
    return (try? String(contentsOf: url, encoding: .utf8)) ?? "[]"
}()

// The SAME asset, parsed, for the native pane: a header row
// (`['Income', 'Life Expectancy', 'Population', 'Country', 'Year']`) + 1539 data rows.
//
// NOTE: the rows are used EXACTLY as JSONSerialization produces them (NSNumber), deliberately NOT
// normalized to Swift `Double`. `Year` is the category dimension, and Ordinal.getLabel stringifies a
// category by interpolation — an NSNumber holding 1950 interpolates as "1950" (JS-like), whereas a Swift
// `Double` would interpolate as "1950.0" and every x-axis label would be wrong. NSNumber still bridges to
// Double for the numeric dimensions (`Income`) and for the filter's `isNumber`/`as! Double` fast path.
private let lifeExpectancyRows: [[Any]] = {
    guard let data = lifeExpectancyRawJSON.data(using: .utf8),
          let rows = (try? JSONSerialization.jsonObject(with: data)) as? [[Any]] else { return [] }
    return rows
}()

// The two `filter` transforms differ only by country — `Year >= 1950 AND Country = <name>`.
// NOTE: `gte` MUST be a Swift `Double`. FilterOrderComparator gates its rvalue on `util.isNumber`
// (`value is Double`), which an `Int` fails — and filterTransform parses the config with `try!`.
private func lifeExpectancySince1950(_ country: String) -> [String: Any] {
    return [
        "type": "filter",
        "config": [
            "and": [
                ["dimension": "Year", "gte": 1950.0] as [String: Any],
                ["dimension": "Country", "=": country] as [String: Any]
            ]
        ] as [String: Any]
    ]
}

// Both series are identical but for the dataset they read from.
private func lifeExpectancyIncomeLine(_ datasetId: String) -> [String: Any] {
    return [
        "type": "line",
        "datasetId": datasetId,
        "showSymbol": false,
        "encode": [
            "x": "Year",
            "y": "Income",
            "itemName": "Year",
            "tooltip": ["Income"]
        ] as [String: Any]
    ]
}

extension EChartsDemoRegistry {
    static let official_data_transform_filter = EChartsDemo(
        name: "official-data-transform-filter", category: "line",
        summary: "数据过滤 — Data Transform Filter",
        width: 640, height: 420,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
var _rawData = \#(lifeExpectancyRawJSON);

option = {
  dataset: [
    {
      id: 'dataset_raw',
      source: _rawData
    },
    {
      id: 'dataset_since_1950_of_germany',
      fromDatasetId: 'dataset_raw',
      transform: {
        type: 'filter',
        config: {
          and: [
            { dimension: 'Year', gte: 1950 },
            { dimension: 'Country', '=': 'Germany' }
          ]
        }
      }
    },
    {
      id: 'dataset_since_1950_of_france',
      fromDatasetId: 'dataset_raw',
      transform: {
        type: 'filter',
        config: {
          and: [
            { dimension: 'Year', gte: 1950 },
            { dimension: 'Country', '=': 'France' }
          ]
        }
      }
    }
  ],
  title: {
    text: 'Income of Germany and France since 1950'
  },
  tooltip: {
    trigger: 'axis'
  },
  xAxis: {
    type: 'category',
    nameLocation: 'middle'
  },
  yAxis: {
    name: 'Income'
  },
  series: [
    {
      type: 'line',
      datasetId: 'dataset_since_1950_of_germany',
      showSymbol: false,
      encode: {
        x: 'Year',
        y: 'Income',
        itemName: 'Year',
        tooltip: ['Income']
      }
    },
    {
      type: 'line',
      datasetId: 'dataset_since_1950_of_france',
      showSymbol: false,
      encode: {
        x: 'Year',
        y: 'Income',
        itemName: 'Year',
        tooltip: ['Income']
      }
    }
  ]
};
"""#,
        option: [
            "dataset": [
                [
                    "id": "dataset_raw",
                    "source": lifeExpectancyRows
                ] as [String: Any],
                [
                    "id": "dataset_since_1950_of_germany",
                    "fromDatasetId": "dataset_raw",
                    "transform": lifeExpectancySince1950("Germany")
                ] as [String: Any],
                [
                    "id": "dataset_since_1950_of_france",
                    "fromDatasetId": "dataset_raw",
                    "transform": lifeExpectancySince1950("France")
                ] as [String: Any]
            ],
            "title": [
                "text": "Income of Germany and France since 1950"
            ] as [String: Any],
            "tooltip": [
                "trigger": "axis"
            ] as [String: Any],
            "xAxis": [
                "type": "category",
                "nameLocation": "middle"
            ] as [String: Any],
            "yAxis": [
                "name": "Income"
            ] as [String: Any],
            "series": [
                lifeExpectancyIncomeLine("dataset_since_1950_of_germany"),
                lifeExpectancyIncomeLine("dataset_since_1950_of_france")
            ]
        ])
}
