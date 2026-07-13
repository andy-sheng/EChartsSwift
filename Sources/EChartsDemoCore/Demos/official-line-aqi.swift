// official-line-aqi — replica of https://echarts.apache.org/examples/zh/editor.html?c=line-aqi
// title: Beijing AQI / titleCN: 北京 AQI 可视化
// A 4928-point daily AQI line (2000-06-05 … 2015-02-24) coloured by a piecewise `visualMap` (the six
// official AQI bands), with `markLine`s at the band thresholds, a `dataZoom` window opening at
// 2014-06-01, and the dataZoom/restore/saveAsImage toolbox.
//
// DEVIATIONS from the official source:
//   - DATA INLINED. Upstream fetches the series with `$.get(ROOT_PATH + '/data/asset/data/aqi-beijing.json',
//     function (data) { ... })`. The gallery page has no network, so the asset is vendored at
//     assets/data/aqi-beijing.json and read at demo time via Upstream.repoRoot (the same #filePath-relative
//     repo read WebPage.swift uses for the echarts dist). The web pane gets the raw JSON text spliced in as
//     `var data = [...]` and then runs the callback body VERBATIM — including both `data.map(...)` closures —
//     so `option` is assigned unconditionally at the top level. The native pane derives the same two arrays
//     (dates, values) in Swift.
//   - The TypeScript parameter annotations (`item: string[]` / `item: number[]`) are dropped from the web
//     pane's closures: the page is a classic script, and an annotation there is a SyntaxError.
//   - Upstream writes `series` as a bare object; the native pane uses the equivalent single-element array
//     (echarts normalizes the two to the same thing).
// No timers, no animated re-setOption: the official example is a single static frame already.
import Foundation

// The vendored asset, raw, for the web pane: spliced in as `var data = ...` so the official callback body
// can run untouched. An unreadable file degrades to `[]` (the pane renders an empty chart, not a broken one).
private let aqiBeijingRawJSON: String = {
    let url = Upstream.repoRoot.appendingPathComponent("assets/data/aqi-beijing.json")
    return (try? String(contentsOf: url, encoding: .utf8)) ?? "[]"
}()

// The same asset, parsed, for the native pane: 4928 `["YYYY-MM-DD", aqi]` rows. Rows are split into the two
// arrays upstream's `data.map` closures produce, in one pass, so dates and values can never desync.
private let aqiBeijingSeries: (dates: [String], values: [Double]) = {
    let url = Upstream.repoRoot.appendingPathComponent("assets/data/aqi-beijing.json")
    guard let data = try? Data(contentsOf: url),
          let rows = (try? JSONSerialization.jsonObject(with: data)) as? [[Any]] else { return ([], []) }
    var dates: [String] = []
    var values: [Double] = []
    for row in rows {
        guard row.count >= 2, let date = row[0] as? String, let aqi = row[1] as? NSNumber else { continue }
        dates.append(date)
        values.append(aqi.doubleValue)
    }
    return (dates, values)
}()

// The six official AQI bands (good → hazardous) plus the out-of-range grey.
private let aqiBeijingPieces: [[String: Any]] = [
    ["gt": 0.0, "lte": 50.0, "color": "#93CE07"],
    ["gt": 50.0, "lte": 100.0, "color": "#FBDB0F"],
    ["gt": 100.0, "lte": 150.0, "color": "#FC7D02"],
    ["gt": 150.0, "lte": 200.0, "color": "#FD0100"],
    ["gt": 200.0, "lte": 300.0, "color": "#AA069F"],
    ["gt": 300.0, "color": "#AC3B2A"]
]

// A horizontal rule at each band threshold.
private let aqiBeijingMarkLineData: [[String: Any]] = [
    ["yAxis": 50.0], ["yAxis": 100.0], ["yAxis": 150.0], ["yAxis": 200.0], ["yAxis": 300.0]
]

extension EChartsDemoRegistry {
    static let official_line_aqi = EChartsDemo(
        name: "official-line-aqi", category: "line",
        summary: "北京 AQI 可视化 — Beijing AQI",
        width: 640, height: 420,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
var data = \#(aqiBeijingRawJSON);

option = {
  title: {
    text: 'Beijing AQI',
    left: '1%'
  },
  tooltip: {
    trigger: 'axis'
  },
  grid: {
    left: '5%',
    right: '15%',
    bottom: '10%'
  },
  xAxis: {
    data: data.map(function (item) {
      return item[0];
    })
  },
  yAxis: {},
  toolbox: {
    right: 10,
    feature: {
      dataZoom: {
        yAxisIndex: 'none'
      },
      restore: {},
      saveAsImage: {}
    }
  },
  dataZoom: [
    {
      startValue: '2014-06-01'
    },
    {
      type: 'inside'
    }
  ],
  visualMap: {
    top: 50,
    right: 10,
    pieces: [
      {
        gt: 0,
        lte: 50,
        color: '#93CE07'
      },
      {
        gt: 50,
        lte: 100,
        color: '#FBDB0F'
      },
      {
        gt: 100,
        lte: 150,
        color: '#FC7D02'
      },
      {
        gt: 150,
        lte: 200,
        color: '#FD0100'
      },
      {
        gt: 200,
        lte: 300,
        color: '#AA069F'
      },
      {
        gt: 300,
        color: '#AC3B2A'
      }
    ],
    outOfRange: {
      color: '#999'
    }
  },
  series: {
    name: 'Beijing AQI',
    type: 'line',
    data: data.map(function (item) {
      return item[1];
    }),
    markLine: {
      silent: true,
      lineStyle: {
        color: '#333'
      },
      data: [
        {
          yAxis: 50
        },
        {
          yAxis: 100
        },
        {
          yAxis: 150
        },
        {
          yAxis: 200
        },
        {
          yAxis: 300
        }
      ]
    }
  }
};
"""#,
        option: [
            "title": [
                "text": "Beijing AQI",
                "left": "1%"
            ] as [String: Any],
            "tooltip": [
                "trigger": "axis"
            ] as [String: Any],
            "grid": [
                "left": "5%",
                "right": "15%",
                "bottom": "10%"
            ] as [String: Any],
            "xAxis": [
                "data": aqiBeijingSeries.dates
            ] as [String: Any],
            "yAxis": [:] as [String: Any],
            "toolbox": [
                "right": 10.0,
                "feature": [
                    "dataZoom": ["yAxisIndex": "none"] as [String: Any],
                    "restore": [:] as [String: Any],
                    "saveAsImage": [:] as [String: Any]
                ] as [String: Any]
            ] as [String: Any],
            "dataZoom": [
                ["startValue": "2014-06-01"] as [String: Any],
                ["type": "inside"] as [String: Any]
            ],
            "visualMap": [
                "top": 50.0,
                "right": 10.0,
                "pieces": aqiBeijingPieces,
                "outOfRange": ["color": "#999"] as [String: Any]
            ] as [String: Any],
            "series": [
                [
                    "name": "Beijing AQI",
                    "type": "line",
                    "data": aqiBeijingSeries.values,
                    "markLine": [
                        "silent": true,
                        "lineStyle": ["color": "#333"] as [String: Any],
                        "data": aqiBeijingMarkLineData
                    ] as [String: Any]
                ] as [String: Any]
            ]
        ])
}
