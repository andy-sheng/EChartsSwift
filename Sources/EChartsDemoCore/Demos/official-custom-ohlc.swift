// official-custom-ohlc — replica of https://echarts.apache.org/examples/zh/editor.html?c=custom-ohlc
// title: OHLC Chart / titleCN: OHLC 图（使用自定义系列）
// Dow-Jones daily bars drawn as OHLC sticks (high–low line + left open tick + right close tick) by a
// `custom` series whose renderItem builds three `line` elements per datum; category x-axis, `scale`
// y-axis, inside+slider dataZoom windowed to the last 2% of the series, cross axisPointer, brush/dataZoom
// toolbox.
//
// DEVIATIONS from the official source:
//   - DATA INLINED: the example does `$.get(ROOT_PATH + '/data/asset/data/stock-DJI.json', ...)`. The
//     page has no network, so the asset is vendored at assets/data/stock-DJI.json and read at demo time
//     via Upstream.repoRoot (the same #filePath-relative repo read WebPage.swift uses for the echarts
//     dist). The web pane gets the raw JSON text spliced in as `rawData`; the `$.get` wrapper is dropped
//     and its callback body kept verbatim, so `option` is assigned unconditionally at the top level.
//     `myChart.setOption(option, true)` is likewise dropped (the gallery page does the setOption).
//   - NATIVE PANE UNSUPPORTED: the chart IS the renderItem closure — every mark on screen is produced by
//     JS (`api.coord` / `api.size` / `api.style`), and a Swift `[String: Any]` option cannot carry a
//     function. Without it the `custom` series has nothing to draw, so nativeSupported is false. The
//     Swift option below still mirrors every other key (see the PORT-NOTEs for the two JS closures).
import Foundation
import EChartsKit

// Numeric coercion for the renderItem api values (ParsedValue is `Any`; api.value may box Int or Double).
private func customOHLCNum(_ v: Any?) -> Double {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let n = v as? NSNumber { return n.doubleValue }
    return .nan
}

// The official `renderItem`, ported statement-for-statement. Typed EXACTLY CustomSeriesRenderItem so
//   CustomView's `get("renderItem") as? CustomSeriesRenderItem` cast holds. Draws each datum as a group
//   of three lines: the low→high stick, a left tick at the open, a right tick at the close.
private let customOHLCRenderItem: CustomSeriesRenderItem = { _, api in
    let xValue = customOHLCNum(api.value(0.0, nil))
    let openPoint = api.coord([xValue, customOHLCNum(api.value(1.0, nil))], nil)
    let closePoint = api.coord([xValue, customOHLCNum(api.value(2.0, nil))], nil)
    let lowPoint = api.coord([xValue, customOHLCNum(api.value(3.0, nil))], nil)
    let highPoint = api.coord([xValue, customOHLCNum(api.value(4.0, nil))], nil)
    guard openPoint.count >= 2, closePoint.count >= 2, lowPoint.count >= 2, highPoint.count >= 2 else { return nil }
    let halfWidth = ((api.size([1.0, 0.0], nil) as? [Double])?.first ?? 0) * 0.35
    let style = api.style(["stroke": api.visual("color", nil) as Any], nil)
    return [
        "type": "group",
        "children": [
            ["type": "line",
             "shape": ["x1": lowPoint[0], "y1": lowPoint[1], "x2": highPoint[0], "y2": highPoint[1]] as [String: Any],
             "style": style] as [String: Any],
            ["type": "line",
             "shape": ["x1": openPoint[0], "y1": openPoint[1], "x2": openPoint[0] - halfWidth, "y2": openPoint[1]] as [String: Any],
             "style": style] as [String: Any],
            ["type": "line",
             "shape": ["x1": closePoint[0], "y1": closePoint[1], "x2": closePoint[0] + halfWidth, "y2": closePoint[1]] as [String: Any],
             "style": style] as [String: Any]
        ]
    ] as [String: Any]
}

// The upstream asset: rows of [date, open, close, lowest, highest, volume]. Read ONCE from the repo;
// a read/parse failure degrades to empty data (the pane renders an empty grid rather than crashing).
private let customOHLCRawURL = Upstream.repoRoot.appendingPathComponent("assets/data/stock-DJI.json")

// Raw JSON TEXT, spliced straight into the web pane as `rawData` (its `splitData` then runs verbatim).
private let customOHLCRawJSON: String = {
    guard let s = try? String(contentsOf: customOHLCRawURL, encoding: .utf8) else { return "[]" }
    return s.trimmingCharacters(in: .whitespacesAndNewlines)
}()

// The Swift half of upstream `splitData`: category = the date column, values = the row with its date
// replaced by the row index (volume, the unnamed 6th column, is carried along exactly as upstream does).
private let customOHLCSplit: (categoryData: [String], values: [[Double]]) = {
    guard let data = try? Data(contentsOf: customOHLCRawURL),
          let rows = (try? JSONSerialization.jsonObject(with: data)) as? [[Any]] else {
        return ([], [])
    }
    var categoryData: [String] = []
    var values: [[Double]] = []
    categoryData.reserveCapacity(rows.count)
    values.reserveCapacity(rows.count)
    for (i, row) in rows.enumerated() {
        guard let date = row.first as? String else { continue }
        categoryData.append(date)
        var v: [Double] = [Double(i)]
        for cell in row.dropFirst() { v.append((cell as? NSNumber)?.doubleValue ?? 0) }
        values.append(v)
    }
    return (categoryData, values)
}()

extension EChartsDemoRegistry {
    static let official_custom_ohlc = EChartsDemo(
        name: "official-custom-ohlc", category: "candlestick",
        summary: "OHLC 图（使用自定义系列） — OHLC Chart",
        width: 640, height: 420,
        nativeSupported: true,   // renderItem ported to Swift (customOHLCRenderItem) — see header
        collection: .official,
        webOptionJS: #"""
var rawData = \#(customOHLCRawJSON);

function splitData(rawData) {
  const categoryData = [];
  const values = [];
  for (var i = 0; i < rawData.length; i++) {
    categoryData.push(rawData[i][0]);
    rawData[i][0] = i;
    values.push(rawData[i]);
  }
  return {
    categoryData: categoryData,
    values: values
  };
}

function renderItem(params, api) {
  var xValue = api.value(0);
  var openPoint = api.coord([xValue, api.value(1)]);
  var closePoint = api.coord([xValue, api.value(2)]);
  var lowPoint = api.coord([xValue, api.value(3)]);
  var highPoint = api.coord([xValue, api.value(4)]);
  var halfWidth = api.size([1, 0])[0] * 0.35;
  var style = api.style({
    stroke: api.visual('color')
  });

  return {
    type: 'group',
    children: [
      {
        type: 'line',
        shape: {
          x1: lowPoint[0],
          y1: lowPoint[1],
          x2: highPoint[0],
          y2: highPoint[1]
        },
        style: style
      },
      {
        type: 'line',
        shape: {
          x1: openPoint[0],
          y1: openPoint[1],
          x2: openPoint[0] - halfWidth,
          y2: openPoint[1]
        },
        style: style
      },
      {
        type: 'line',
        shape: {
          x1: closePoint[0],
          y1: closePoint[1],
          x2: closePoint[0] + halfWidth,
          y2: closePoint[1]
        },
        style: style
      }
    ]
  };
}

var data = splitData(rawData);

option = {
  animation: false,
  legend: {
    bottom: 10,
    left: 'center',
    data: ['Dow-Jones index']
  },
  tooltip: {
    trigger: 'axis',
    axisPointer: {
      type: 'cross'
    },
    position: function (pos, params, el, elRect, size) {
      var obj = { top: 10 };
      obj[['left', 'right'][+(pos[0] < size.viewSize[0] / 2)]] = 30;
      return obj;
    }
  },
  axisPointer: {
    link: [{ xAxisIndex: 'all' }]
  },
  toolbox: {
    feature: {
      dataZoom: {
        yAxisIndex: false
      },
      brush: {
        type: ['lineX', 'clear']
      }
    }
  },
  grid: [
    {
      left: '10%',
      right: '8%',
      bottom: 150
    }
  ],
  xAxis: [
    {
      type: 'category',
      data: data.categoryData,
      boundaryGap: false,
      axisLine: { onZero: false },
      splitLine: { show: false },
      min: 'dataMin',
      max: 'dataMax',
      axisPointer: {
        z: 100
      }
    }
  ],
  yAxis: [
    {
      scale: true,
      splitArea: {
        show: true
      }
    }
  ],
  dataZoom: [
    {
      type: 'inside',
      start: 98,
      end: 100,
      minValueSpan: 10
    },
    {
      show: true,
      type: 'slider',
      bottom: 60,
      start: 98,
      end: 100,
      minValueSpan: 10
    }
  ],
  series: [
    {
      name: 'Dow-Jones index',
      type: 'custom',
      renderItem: renderItem,
      dimensions: ['-', 'open', 'close', 'lowest', 'highest'],
      encode: {
        x: 0,
        y: [1, 2, 3, 4],
        tooltip: [1, 2, 3, 4]
      },
      data: data.values
    }
  ]
};
"""#,
        option: [
            "animation": false,
            "legend": [
                "bottom": 10.0,
                "left": "center",
                "data": ["Dow-Jones index"]
            ] as [String: Any],
            "tooltip": [
                "trigger": "axis",
                "axisPointer": [
                    "type": "cross"
                ] as [String: Any]
                // PORT-NOTE: tooltip.position omitted — JS closure pinning the tooltip to top:10 and to
                // whichever side (left/right, inset 30) is opposite the cursor's half of the viewport.
            ] as [String: Any],
            "axisPointer": [
                "link": [["xAxisIndex": "all"] as [String: Any]]
            ] as [String: Any],
            "toolbox": [
                "feature": [
                    "dataZoom": [
                        "yAxisIndex": false
                    ] as [String: Any],
                    "brush": [
                        "type": ["lineX", "clear"]
                    ] as [String: Any]
                ] as [String: Any]
            ] as [String: Any],
            "grid": [
                [
                    "left": "10%",
                    "right": "8%",
                    "bottom": 150.0
                ] as [String: Any]
            ],
            "xAxis": [
                [
                    "type": "category",
                    "data": customOHLCSplit.categoryData,
                    "boundaryGap": false,
                    "axisLine": ["onZero": false] as [String: Any],
                    "splitLine": ["show": false] as [String: Any],
                    "min": "dataMin",
                    "max": "dataMax",
                    "axisPointer": [
                        "z": 100.0
                    ] as [String: Any]
                ] as [String: Any]
            ],
            "yAxis": [
                [
                    "scale": true,
                    "splitArea": [
                        "show": true
                    ] as [String: Any]
                ] as [String: Any]
            ],
            "dataZoom": [
                [
                    "type": "inside",
                    "start": 98.0,
                    "end": 100.0,
                    "minValueSpan": 10.0
                ] as [String: Any],
                [
                    "show": true,
                    "type": "slider",
                    "bottom": 60.0,
                    "start": 98.0,
                    "end": 100.0,
                    "minValueSpan": 10.0
                ] as [String: Any]
            ],
            "series": [
                [
                    "name": "Dow-Jones index",
                    // renderItem ported to Swift (customOHLCRenderItem, top of file): each datum is a group
                    // of three lines — the low→high stick, a left tick at the open, a right tick at the
                    // close, each half-tick 0.35 * api.size([1,0])[0] wide, stroked with the visual color.
                    "type": "custom",
                    "renderItem": customOHLCRenderItem,
                    "dimensions": ["-", "open", "close", "lowest", "highest"],
                    "encode": [
                        "x": 0.0,
                        "y": [1.0, 2.0, 3.0, 4.0],
                        "tooltip": [1.0, 2.0, 3.0, 4.0]
                    ] as [String: Any],
                    "data": customOHLCSplit.values
                ] as [String: Any]
            ]
        ])
}
