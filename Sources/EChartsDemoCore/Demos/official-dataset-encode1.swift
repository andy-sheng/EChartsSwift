// official-dataset-encode1 — replica of
// https://echarts.apache.org/examples/zh/editor.html?c=dataset-encode1
// title: Encode and Matrix / titleCN: 指定数据到坐标轴的映射
//
// One `dataset` (the 1540-row life-expectancy table, dimensions Income / Life Expectancy /
// Population / Country / Year-as-ordinal) feeding FOUR scatter series at once. Each series lives on
// its own grid of a 2x2 matrix (`grid[i]` + `xAxisIndex`/`yAxisIndex`) and picks its columns purely
// through `encode` — the same source plotted four different ways, which is the whole point of the
// example. A `toolbox.feature.dataZoom` and a shared `legend`/`tooltip` sit on top.
//
// DEVIATIONS from the official source:
//   1. DATA: the example wraps everything in
//      `$.get(ROOT_PATH + '/data/asset/data/life-expectancy-table.json', function (data) { ... })`.
//      The gallery page has no network, so the asset is mirrored into the repo
//      (assets/data/life-expectancy-table.json, verbatim from the official asset tree) and read via
//      Upstream.repoRoot. The web pane gets the raw JSON text spliced in at the top level in place of
//      the fetch; the native pane parses the same file. The rows — INCLUDING the leading header row
//      `["Income","Life Expectancy","Population","Country","Year"]`, which echarts' `sourceHeader`
//      auto-detection is expected to strip — are handed to `dataset.source` untouched on both panes.
//   2. TypeScript-only bits dropped: the `myChart.setOption<echarts.EChartsOption>(option)` type
//      argument (kept as a plain `myChart.setOption(option)`) and the trailing `export {};`, which a
//      classic script cannot parse.
//   3. Canvas is 900x560, not the gallery default 640x420: four grids at 43% x 43% plus four axis
//      names and 50°-rotated, `interval: 0` axis labels are illegible at 640x420.
// No option value is a JS closure (symbolSize is the number 2.5, no formatters), so the native option
// is a complete port — nothing omitted.
import Foundation

// The raw asset text, spliced verbatim into the web pane (which cannot read the filesystem).
private let datasetEncode1RawJSON: String = {
    let url = Upstream.repoRoot.appendingPathComponent("assets/data/life-expectancy-table.json")
    return (try? String(contentsOf: url, encoding: .utf8)) ?? "[]"
}()

// The same table for the native pane: a header row + 1539 data rows of
// [Income, Life Expectancy, Population, Country, Year]. A parse failure degrades to an empty source
// (the pane renders empty grids rather than crashing).
//
// NOTE: the rows are used EXACTLY as JSONSerialization produces them (NSNumber), deliberately NOT
// normalized to Swift `Double`. `Year` is declared `type: 'ordinal'` and reaches the tooltip through
// `encode.tooltip`, and Ordinal.getLabel stringifies a category by interpolation — an NSNumber
// holding 1950 interpolates as "1950" (JS-like), whereas a Swift `Double` would render "1950.0".
// NSNumber still bridges to Double for the numeric dimensions (Income / Life Expectancy /
// Population), so the scatter geometry is unaffected.
private let datasetEncode1Source: [[Any]] = {
    guard let data = datasetEncode1RawJSON.data(using: .utf8),
          let rows = (try? JSONSerialization.jsonObject(with: data)) as? [[Any]] else { return [] }
    return rows
}()

// upstream `var sizeValue = '57%'` — each grid is inset 57% from the far side, leaving a 43% cell.
private let datasetEncode1SizeValue = "57%"
// upstream `var symbolSize = 2.5`.
private let datasetEncode1SymbolSize = 2.5

// The four grids of the matrix (upstream `grid: [...]`), in order: bottom-right, bottom-left,
// top-right, top-left.
private let datasetEncode1Grids: [[String: Any]] = [
    ["right": datasetEncode1SizeValue, "bottom": datasetEncode1SizeValue],
    ["left": datasetEncode1SizeValue, "bottom": datasetEncode1SizeValue],
    ["right": datasetEncode1SizeValue, "top": datasetEncode1SizeValue],
    ["left": datasetEncode1SizeValue, "top": datasetEncode1SizeValue]
]

private let datasetEncode1XAxis: [[String: Any]] = [
    [
        "type": "value", "gridIndex": 0.0, "name": "Income",
        "axisLabel": ["rotate": 50.0, "interval": 0.0] as [String: Any]
    ],
    [
        "type": "category", "gridIndex": 1.0, "name": "Country", "boundaryGap": false,
        "axisLabel": ["rotate": 50.0, "interval": 0.0] as [String: Any]
    ],
    [
        "type": "value", "gridIndex": 2.0, "name": "Income",
        "axisLabel": ["rotate": 50.0, "interval": 0.0] as [String: Any]
    ],
    [
        "type": "value", "gridIndex": 3.0, "name": "Life Expectancy",
        "axisLabel": ["rotate": 50.0, "interval": 0.0] as [String: Any]
    ]
]

private let datasetEncode1YAxis: [[String: Any]] = [
    ["type": "value", "gridIndex": 0.0, "name": "Life Expectancy"],
    ["type": "value", "gridIndex": 1.0, "name": "Income"],
    ["type": "value", "gridIndex": 2.0, "name": "Population"],
    ["type": "value", "gridIndex": 3.0, "name": "Population"]
]

// Every series is the same scatter over the same dataset; only the grid it sits on and the
// dimensions `encode` picks differ. `tooltip: [0,1,2,3,4]` = show all five dimensions on hover.
private let datasetEncode1Series: [[String: Any]] = [
    [
        "type": "scatter", "symbolSize": datasetEncode1SymbolSize,
        "xAxisIndex": 0.0, "yAxisIndex": 0.0,
        "encode": [
            "x": "Income", "y": "Life Expectancy", "tooltip": [0.0, 1.0, 2.0, 3.0, 4.0]
        ] as [String: Any]
    ],
    [
        "type": "scatter", "symbolSize": datasetEncode1SymbolSize,
        "xAxisIndex": 1.0, "yAxisIndex": 1.0,
        "encode": [
            "x": "Country", "y": "Income", "tooltip": [0.0, 1.0, 2.0, 3.0, 4.0]
        ] as [String: Any]
    ],
    [
        "type": "scatter", "symbolSize": datasetEncode1SymbolSize,
        "xAxisIndex": 2.0, "yAxisIndex": 2.0,
        "encode": [
            "x": "Income", "y": "Population", "tooltip": [0.0, 1.0, 2.0, 3.0, 4.0]
        ] as [String: Any]
    ],
    [
        "type": "scatter", "symbolSize": datasetEncode1SymbolSize,
        "xAxisIndex": 3.0, "yAxisIndex": 3.0,
        "encode": [
            "x": "Life Expectancy", "y": "Population", "tooltip": [0.0, 1.0, 2.0, 3.0, 4.0]
        ] as [String: Any]
    ]
]

extension EChartsDemoRegistry {
    static let official_dataset_encode1 = EChartsDemo(
        name: "official-dataset-encode1", category: "dataset",
        summary: "指定数据到坐标轴的映射 — Encode and Matrix",
        width: 900, height: 560,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
var data = \#(datasetEncode1RawJSON);

var sizeValue = '57%';
var symbolSize = 2.5;
option = {
  legend: {},
  tooltip: {},
  toolbox: {
    left: 'center',
    feature: {
      dataZoom: {}
    }
  },
  grid: [
    { right: sizeValue, bottom: sizeValue },
    { left: sizeValue, bottom: sizeValue },
    { right: sizeValue, top: sizeValue },
    { left: sizeValue, top: sizeValue }
  ],
  xAxis: [
    {
      type: 'value',
      gridIndex: 0,
      name: 'Income',
      axisLabel: { rotate: 50, interval: 0 }
    },
    {
      type: 'category',
      gridIndex: 1,
      name: 'Country',
      boundaryGap: false,
      axisLabel: { rotate: 50, interval: 0 }
    },
    {
      type: 'value',
      gridIndex: 2,
      name: 'Income',
      axisLabel: { rotate: 50, interval: 0 }
    },
    {
      type: 'value',
      gridIndex: 3,
      name: 'Life Expectancy',
      axisLabel: { rotate: 50, interval: 0 }
    }
  ],
  yAxis: [
    { type: 'value', gridIndex: 0, name: 'Life Expectancy' },
    { type: 'value', gridIndex: 1, name: 'Income' },
    { type: 'value', gridIndex: 2, name: 'Population' },
    { type: 'value', gridIndex: 3, name: 'Population' }
  ],
  dataset: {
    dimensions: [
      'Income',
      'Life Expectancy',
      'Population',
      'Country',
      { name: 'Year', type: 'ordinal' }
    ],
    source: data
  },
  series: [
    {
      type: 'scatter',
      symbolSize: symbolSize,
      xAxisIndex: 0,
      yAxisIndex: 0,
      encode: {
        x: 'Income',
        y: 'Life Expectancy',
        tooltip: [0, 1, 2, 3, 4]
      }
    },
    {
      type: 'scatter',
      symbolSize: symbolSize,
      xAxisIndex: 1,
      yAxisIndex: 1,
      encode: {
        x: 'Country',
        y: 'Income',
        tooltip: [0, 1, 2, 3, 4]
      }
    },
    {
      type: 'scatter',
      symbolSize: symbolSize,
      xAxisIndex: 2,
      yAxisIndex: 2,
      encode: {
        x: 'Income',
        y: 'Population',
        tooltip: [0, 1, 2, 3, 4]
      }
    },
    {
      type: 'scatter',
      symbolSize: symbolSize,
      xAxisIndex: 3,
      yAxisIndex: 3,
      encode: {
        x: 'Life Expectancy',
        y: 'Population',
        tooltip: [0, 1, 2, 3, 4]
      }
    }
  ]
};

myChart.setOption(option);
"""#,
        option: [
            "legend": [:] as [String: Any],
            "tooltip": [:] as [String: Any],
            "toolbox": [
                "left": "center",
                "feature": [
                    "dataZoom": [:] as [String: Any]
                ] as [String: Any]
            ] as [String: Any],
            "grid": datasetEncode1Grids,
            "xAxis": datasetEncode1XAxis,
            "yAxis": datasetEncode1YAxis,
            "dataset": [
                "dimensions": [
                    "Income",
                    "Life Expectancy",
                    "Population",
                    "Country",
                    ["name": "Year", "type": "ordinal"] as [String: Any]
                ] as [Any],
                "source": datasetEncode1Source
            ] as [String: Any],
            "series": datasetEncode1Series
        ])
}
