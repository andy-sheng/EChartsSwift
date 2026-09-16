// official-candlestick-brush — replica of https://echarts.apache.org/examples/zh/editor.html?c=candlestick-brush
// title: Candlestick Brush / titleCN: K 线图刷选
// Dow-Jones OHLC candlesticks + MA5/10/20/30 lines on grid 0, a sign-coloured volume bar series on
// grid 1 (visualMap seriesIndex:5, dimension:2), linked axisPointers, a lineX `brush` (with the
// toolbox brush/dataZoom features) and inside+slider dataZoom windowed to the last 2% of the range.
//
// DEVIATIONS from the official source:
//   - DATA INLINED. Upstream wraps everything in `$.get(ROOT_PATH + '/data/asset/data/stock-DJI.json',
//     function (rawData) { ... })`. The asset is vendored at assets/data/stock-DJI.json (3141 rows of
//     [date, open, close, lowest, highest, volume]); the reference pane splices the raw JSON text in as
//     `var rawData = [...]` and keeps the callback body VERBATIM (splitData/calculateMA run as real JS),
//     the native pane re-implements splitData/calculateMA in Swift below.
//   - TRAILING `myChart.dispatchAction({ type: 'brush', areas: [...] })` DROPPED (it pre-selects
//     2016-06-02..2016-06-20 with a lineX brush). The gallery renders ONE static setOption frame and the
//     reference page has no `myChart` in scope while the option script runs, so BOTH panes show the chart
//     with the brush ARMED but nothing selected — i.e. the frame before the example's initial selection.
//   - TS type annotations (`rawData: number[][]`, `Record<string, number>`) stripped: the reference pane
//     is a classic script. `export {}` and the `myChart.setOption(option, true)` wrapper likewise removed.
//   - NATIVE PANE: `tooltip.position` is a JS closure — omitted (see note); `itemStyle.borderColor:
//     undefined` / `borderColor0: undefined` are dropped (JS `undefined` == key absent).
//   - Canvas bumped to 800x520: two stacked grids + bottom legend + dataZoom slider do not fit 640x420.
import Foundation

// MARK: - the vendored asset (upstream ROOT_PATH + '/data/asset/data/stock-DJI.json')

// Raw JSON text, spliced verbatim into webOptionJS. Empty array if the asset is missing (pane renders blank).
private let candlestickBrushRawJSON: String = {
    let url = Upstream.repoRoot.appendingPathComponent("assets/data/stock-DJI.json")
    return (try? String(contentsOf: url, encoding: .utf8)) ?? "[]"
}()

// MARK: - splitData / calculateMA, ported for the native pane

private struct CandlestickBrushSplit {
    let categoryData: [String]   // the date column
    let values: [[Double]]       // [open, close, lowest, highest, volume] per day
    let volumes: [[Double]]      // [index, volume, open > close ? 1 : -1]
}

private let candlestickBrushSplit: CandlestickBrushSplit = {
    guard let data = candlestickBrushRawJSON.data(using: .utf8),
          let rows = (try? JSONSerialization.jsonObject(with: data)) as? [[Any]] else {
        return CandlestickBrushSplit(categoryData: [], values: [], volumes: [])
    }
    var categoryData: [String] = []
    var values: [[Double]] = []
    var volumes: [[Double]] = []
    for row in rows {
        guard row.count >= 6, let date = row[0] as? String else { continue }
        let nums: [Double] = row.dropFirst().map { ($0 as? NSNumber)?.doubleValue ?? 0 }
        let i = Double(categoryData.count)
        categoryData.append(date)
        values.append(nums)                                            // rawData[i] after splice(0, 1)
        volumes.append([i, nums[4], nums[0] > nums[1] ? 1 : -1])
    }
    return CandlestickBrushSplit(categoryData: categoryData, values: values, volumes: volumes)
}()

/// `calculateMA` — mean of the last `dayCount` CLOSE prices (values[i][1]), '-' until enough days,
/// rounded to 3 decimals (JS `+(sum / dayCount).toFixed(3)`). Mixed String/Double, hence [Any].
private func candlestickBrushMA(_ dayCount: Int) -> [Any] {
    let values = candlestickBrushSplit.values
    var result: [Any] = []
    result.reserveCapacity(values.count)
    for i in 0..<values.count {
        if i < dayCount { result.append("-"); continue }
        var sum = 0.0
        for j in 0..<dayCount { sum += values[i - j][1] }
        result.append((sum / Double(dayCount) * 1000).rounded() / 1000)
    }
    return result
}

private let candlestickBrushMA5: [Any] = candlestickBrushMA(5)
private let candlestickBrushMA10: [Any] = candlestickBrushMA(10)
private let candlestickBrushMA20: [Any] = candlestickBrushMA(20)
private let candlestickBrushMA30: [Any] = candlestickBrushMA(30)

private let candlestickBrushUpColor = "#00da3c"
private let candlestickBrushDownColor = "#ec0000"

extension EChartsDemoRegistry {
    static let official_candlestick_brush = EChartsDemo(
        name: "official-candlestick-brush", category: "candlestick",
        summary: "K 线图刷选 — Candlestick Brush",
        width: 800, height: 520,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
const upColor = '#00da3c';
const downColor = '#ec0000';

function splitData(rawData) {
  let categoryData = [];
  let values = [];
  let volumes = [];
  for (let i = 0; i < rawData.length; i++) {
    categoryData.push(rawData[i].splice(0, 1)[0]);
    values.push(rawData[i]);
    volumes.push([i, rawData[i][4], rawData[i][0] > rawData[i][1] ? 1 : -1]);
  }

  return {
    categoryData: categoryData,
    values: values,
    volumes: volumes
  };
}

function calculateMA(dayCount, data) {
  var result = [];
  for (var i = 0, len = data.values.length; i < len; i++) {
    if (i < dayCount) {
      result.push('-');
      continue;
    }
    var sum = 0;
    for (var j = 0; j < dayCount; j++) {
      sum += data.values[i - j][1];
    }
    result.push(+(sum / dayCount).toFixed(3));
  }
  return result;
}

// upstream: $.get(ROOT_PATH + '/data/asset/data/stock-DJI.json', function (rawData) { ... })
var rawData = \#(candlestickBrushRawJSON);
var data = splitData(rawData);

option = {
  animation: false,
  legend: {
    bottom: 10,
    left: 'center',
    data: ['Dow-Jones index', 'MA5', 'MA10', 'MA20', 'MA30']
  },
  tooltip: {
    trigger: 'axis',
    axisPointer: {
      type: 'cross'
    },
    borderWidth: 1,
    borderColor: '#ccc',
    padding: 10,
    textStyle: {
      color: '#000'
    },
    position: function (pos, params, el, elRect, size) {
      const obj = {
        top: 10
      };
      obj[['left', 'right'][+(pos[0] < size.viewSize[0] / 2)]] = 30;
      return obj;
    }
    // extraCssText: 'width: 170px'
  },
  axisPointer: {
    link: [
      {
        xAxisIndex: 'all'
      }
    ],
    label: {
      backgroundColor: '#777'
    }
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
  brush: {
    xAxisIndex: 'all',
    brushLink: 'all',
    outOfBrush: {
      colorAlpha: 0.1
    }
  },
  visualMap: {
    show: false,
    seriesIndex: 5,
    dimension: 2,
    pieces: [
      {
        value: 1,
        color: downColor
      },
      {
        value: -1,
        color: upColor
      }
    ]
  },
  grid: [
    {
      left: '10%',
      right: '8%',
      height: '50%'
    },
    {
      left: '10%',
      right: '8%',
      top: '63%',
      height: '16%'
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
    },
    {
      type: 'category',
      gridIndex: 1,
      data: data.categoryData,
      boundaryGap: false,
      axisLine: { onZero: false },
      axisTick: { show: false },
      splitLine: { show: false },
      axisLabel: { show: false },
      min: 'dataMin',
      max: 'dataMax'
    }
  ],
  yAxis: [
    {
      scale: true,
      splitArea: {
        show: true
      }
    },
    {
      scale: true,
      gridIndex: 1,
      splitNumber: 2,
      axisLabel: { show: false },
      axisLine: { show: false },
      axisTick: { show: false },
      splitLine: { show: false }
    }
  ],
  dataZoom: [
    {
      type: 'inside',
      xAxisIndex: [0, 1],
      start: 98,
      end: 100
    },
    {
      show: true,
      xAxisIndex: [0, 1],
      type: 'slider',
      top: '85%',
      start: 98,
      end: 100
    }
  ],
  series: [
    {
      name: 'Dow-Jones index',
      type: 'candlestick',
      data: data.values,
      itemStyle: {
        color: upColor,
        color0: downColor,
        borderColor: undefined,
        borderColor0: undefined
      }
    },
    {
      name: 'MA5',
      type: 'line',
      data: calculateMA(5, data),
      smooth: true,
      lineStyle: {
        opacity: 0.5
      }
    },
    {
      name: 'MA10',
      type: 'line',
      data: calculateMA(10, data),
      smooth: true,
      lineStyle: {
        opacity: 0.5
      }
    },
    {
      name: 'MA20',
      type: 'line',
      data: calculateMA(20, data),
      smooth: true,
      lineStyle: {
        opacity: 0.5
      }
    },
    {
      name: 'MA30',
      type: 'line',
      data: calculateMA(30, data),
      smooth: true,
      lineStyle: {
        opacity: 0.5
      }
    },
    {
      name: 'Volume',
      type: 'bar',
      xAxisIndex: 1,
      yAxisIndex: 1,
      data: data.volumes
    }
  ]
};
"""#,
        option: [
            "animation": false,
            "legend": [
                "bottom": 10.0,
                "left": "center",
                "data": [
                    [
                        "name": "Dow-Jones index",
                        // The reference icon has no visible outline when the series border is
                        // explicitly undefined; suppress the inherited Native default border.
                        "itemStyle": ["borderWidth": 0.0] as [String: Any]
                    ] as [String: Any],
                    "MA5", "MA10", "MA20", "MA30"
                ] as [Any]
            ] as [String: Any],
            "tooltip": [
                "trigger": "axis",
                "axisPointer": [
                    "type": "cross"
                ] as [String: Any],
                "borderWidth": 1.0,
                "borderColor": "#ccc",
                "padding": 10.0,
                "textStyle": [
                    "color": "#000"
                ] as [String: Any]
                // tooltip.position omitted — a JS closure that pins the tooltip to top:10 and
                // parks it 30px from whichever side the cursor is NOT on (left when the pointer is in the
                // right half, right otherwise), so it never covers the candles under the cursor.
            ] as [String: Any],
            "axisPointer": [
                "link": [
                    ["xAxisIndex": "all"] as [String: Any]
                ],
                "label": [
                    "backgroundColor": "#777"
                ] as [String: Any]
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
            "brush": [
                "xAxisIndex": "all",
                "brushLink": "all",
                "outOfBrush": [
                    "colorAlpha": 0.1
                ] as [String: Any]
            ] as [String: Any],
            "visualMap": [
                "show": false,
                "seriesIndex": 5.0,
                "dimension": 2.0,
                "pieces": [
                    ["value": 1.0, "color": candlestickBrushDownColor] as [String: Any],
                    ["value": -1.0, "color": candlestickBrushUpColor] as [String: Any]
                ]
            ] as [String: Any],
            "grid": [
                [
                    "left": "10%",
                    "right": "8%",
                    "height": "50%"
                ] as [String: Any],
                [
                    "left": "10%",
                    "right": "8%",
                    "top": "63%",
                    "height": "16%"
                ] as [String: Any]
            ],
            "xAxis": [
                [
                    "type": "category",
                    "data": candlestickBrushSplit.categoryData,
                    "boundaryGap": false,
                    "axisLine": ["onZero": false] as [String: Any],
                    "splitLine": ["show": false] as [String: Any],
                    "min": "dataMin",
                    "max": "dataMax",
                    "axisPointer": ["z": 100.0] as [String: Any]
                ] as [String: Any],
                [
                    "type": "category",
                    "gridIndex": 1.0,
                    "data": candlestickBrushSplit.categoryData,
                    "boundaryGap": false,
                    "axisLine": ["onZero": false] as [String: Any],
                    "axisTick": ["show": false] as [String: Any],
                    "splitLine": ["show": false] as [String: Any],
                    "axisLabel": ["show": false] as [String: Any],
                    "min": "dataMin",
                    "max": "dataMax"
                ] as [String: Any]
            ],
            "yAxis": [
                [
                    "scale": true,
                    "splitArea": ["show": true] as [String: Any]
                ] as [String: Any],
                [
                    "scale": true,
                    "gridIndex": 1.0,
                    "splitNumber": 2.0,
                    "axisLabel": ["show": false] as [String: Any],
                    "axisLine": ["show": false] as [String: Any],
                    "axisTick": ["show": false] as [String: Any],
                    "splitLine": ["show": false] as [String: Any]
                ] as [String: Any]
            ],
            "dataZoom": [
                [
                    "type": "inside",
                    "xAxisIndex": [0.0, 1.0],
                    "start": 98.0,
                    "end": 100.0
                ] as [String: Any],
                [
                    "show": true,
                    "xAxisIndex": [0.0, 1.0],
                    "type": "slider",
                    "top": "85%",
                    "start": 98.0,
                    "end": 100.0
                ] as [String: Any]
            ],
            "series": [
                [
                    "name": "Dow-Jones index",
                    "type": "candlestick",
                    "data": candlestickBrushSplit.values,
                    // itemStyle.borderColor / borderColor0 are `undefined` upstream — i.e. absent,
                    // so the candlestick defaults apply. Omitted rather than mapped to NSNull.
                    "itemStyle": [
                        "color": candlestickBrushUpColor,
                        "color0": candlestickBrushDownColor
                    ] as [String: Any]
                ] as [String: Any],
                [
                    "name": "MA5",
                    "type": "line",
                    "data": candlestickBrushMA5,
                    "smooth": true,
                    "lineStyle": ["opacity": 0.5] as [String: Any]
                ] as [String: Any],
                [
                    "name": "MA10",
                    "type": "line",
                    "data": candlestickBrushMA10,
                    "smooth": true,
                    "lineStyle": ["opacity": 0.5] as [String: Any]
                ] as [String: Any],
                [
                    "name": "MA20",
                    "type": "line",
                    "data": candlestickBrushMA20,
                    "smooth": true,
                    "lineStyle": ["opacity": 0.5] as [String: Any]
                ] as [String: Any],
                [
                    "name": "MA30",
                    "type": "line",
                    "data": candlestickBrushMA30,
                    "smooth": true,
                    "lineStyle": ["opacity": 0.5] as [String: Any]
                ] as [String: Any],
                [
                    "name": "Volume",
                    "type": "bar",
                    "xAxisIndex": 1.0,
                    "yAxisIndex": 1.0,
                    "data": candlestickBrushSplit.volumes
                ] as [String: Any]
            ]
        ])
}
