// official-candlestick-large — replica of https://echarts.apache.org/examples/zh/editor.html?c=candlestick-large
// title: Large Scale Candlestick / titleCN: 大数据量K线图
// A procedurally generated OHLC+volume stream (one bar per minute from 2011-01-01) fed through a
// `dataset.source` and split across two grids: the candlestick on grid 0, a `large: true` volume bar
// series on grid 1, tied together by an inside + slider `dataZoom` pair (start 10%) and colored by a
// hidden `visualMap` that maps the row's sign dimension (6) to the up/down colors.
//
// DEVIATIONS from the official source:
//   1. webOptionJS is the example VERBATIM except: the TypeScript is stripped (the `type DataItem`
//      alias and every `: number` / `: DataItem[]` annotation — the reference pane runs a classic
//      script, not TS) and the trailing `export {};` is dropped (a bare export is a SyntaxError in a
//      classic script and would blank the whole page). `echarts.format.addCommas` and
//      `echarts.format.formatTime` stay: both are real echarts API, still exported by the 6.1.0 dist
//      the pane loads.
//   2. The upstream data is RANDOM (`Math.random()`, regenerated on every load), which makes a
//      reference↔native visual comparison meaningless. Both panes therefore run the same seeded
//      xorshift64* stream and the same OHLC recurrence.
//   3. The row count in BOTH panes is reduced 2e5 -> 2e4 (still ~33x past the candlestick `largeThreshold`
//      of 600, so the large path is what renders). 200k rows x 7 boxed dimensions through the Swift
//      option/SourceManager path costs minutes in the headless render sweep for no extra signal — the
//      dense band reads the same. `title.text` follows the reduced count ("Data Amount: 20,000").
//   4. Upstream's generator calls `boxVals.sort()` with no comparator. Both panes use numeric sort,
//      which is what the OHLC example intends (boxVals[0] = lowest, boxVals[3] = highest).
//   5. `toolbox` and `dataZoom` are interactive; the gallery snapshots ONE static frame, so both panes
//      show them in their initial state (the dataZoom window at start: 10, end: 100).
//   6. Canvas bumped to 800x560 (from the gallery default 640x420): the example hard-codes
//      `grid[0].bottom: 200`, which at 420px tall leaves the candlestick grid barely 150px of height.
import Foundation

// MARK: - the upstream `generateOHLC(2e5)`, ported

/// Native row count (upstream: 2e5). See DEVIATION 3.
private let candlestickLargeCount = 20_000

/// Upstream drives everything off `Math.random()`; a gallery frame must be reproducible, so the native
/// pane runs the identical recurrence on a seeded xorshift64* stream (see DEVIATION 2).
private struct CandlestickLargeRandom {
    private var state: UInt64
    init(seed: UInt64) { self.state = seed }
    /// The `Math.random()` contract: a Double in [0, 1).
    mutating func next01() -> Double {
        state ^= state >> 12
        state ^= state << 25
        state ^= state >> 27
        let x = state &* 2_685_821_657_736_338_717
        return Double(x >> 11) * (1.0 / 9_007_199_254_740_992.0)   // 53-bit mantissa, like V8
    }
}

/// One row per minute: `[time, open, highest, lowest, close, volumn, sign]` — exactly the upstream
/// `DataItem`, which `series[0].encode.y = [1, 4, 3, 2]` re-reads as [open, close, lowest, highest]
/// and `visualMap.dimension = 6` reads as the up(+1)/down(-1) sign of the volume bar.
private let candlestickLargeSource: [[Any]] = {
    var rng = CandlestickLargeRandom(seed: 0x9E37_79B9_7F4A_7C15)
    var baseValue = rng.next01() * 12000
    let dayRange = 12.0

    // JS `(+x.toFixed(2))` / `(+x.toFixed(0))` on positive values.
    func round2(_ v: Double) -> Double { (v * 100).rounded() / 100 }
    func pad2(_ v: Int) -> String { v < 10 ? "0\(v)" : "\(v)" }
    /// What `echarts.format.formatTime('yyyy-MM-dd\nhh:mm:ss', +new Date(2011, 0, 1) + m * 60000)`
    /// yields: padded LOCAL wall-clock fields, `hh` being the 24-hour one. Upstream advances the clock
    /// BEFORE formatting (`xValue += minute` inside the call), so row i carries minute i + 1. 20,000
    /// minutes is 13d 21h 20m — the range stays inside 2011-01-01 … 2011-01-14, no month boundary is
    /// crossed, which lets this be integer arithmetic instead of 20k Calendar round-trips.
    func stamp(_ minutes: Int) -> String {
        let day = 1 + minutes / 1440
        let rem = minutes % 1440
        return "2011-01-\(pad2(day))\n\(pad2(rem / 60)):\(pad2(rem % 60)):00"
    }

    var rows: [[Any]] = []
    rows.reserveCapacity(candlestickLargeCount)
    var boxVals = [Double](repeating: 0, count: 4)
    var prevClose = 0.0   // upstream re-reads `data[i - 1][4]`, i.e. the ROUNDED previous close.

    for i in 0..<candlestickLargeCount {
        baseValue = baseValue + rng.next01() * 20 - 10

        for j in 0..<4 { boxVals[j] = (rng.next01() - 0.5) * dayRange + baseValue }
        boxVals.sort()   // upstream: `boxVals.sort()` — see DEVIATION 4.

        // JS `Math.round` is floor(x + 0.5) (half-up, not half-away-from-zero).
        let openIdx = Int((rng.next01() * 3 + 0.5).rounded(.down))
        var closeIdx = Int((rng.next01() * 2 + 0.5).rounded(.down))
        if closeIdx == openIdx { closeIdx += 1 }
        let volumn = boxVals[3] * (1000 + rng.next01() * 500)

        // upstream `getSign(data, i, +boxVals[openIdx], +boxVals[closeIdx], 4)` — the UNROUNDED
        // open/close decide the sign; only the tie-break compares against the stored previous close.
        let openVal = boxVals[openIdx]
        let closeVal = boxVals[closeIdx]
        let sign: Double
        if openVal > closeVal {
            sign = -1
        } else if openVal < closeVal {
            sign = 1
        } else {
            sign = i > 0 ? (prevClose <= closeVal ? 1 : -1) : 1
        }

        let close = round2(closeVal)
        rows.append([
            stamp(i + 1),          // 0: time
            round2(openVal),       // 1: open
            round2(boxVals[3]),    // 2: highest
            round2(boxVals[0]),    // 3: lowest
            close,                 // 4: close
            volumn.rounded(),      // 5: volumn
            sign                   // 6: sign
        ])
        prevClose = close
    }
    return rows
}()

/// `'Data Amount: ' + echarts.format.addCommas(dataCount)`, pre-computed for the native row count.
private let candlestickLargeTitleText = "Data Amount: 20,000"

// MARK: - demo

extension EChartsDemoRegistry {
    static let official_candlestick_large = EChartsDemo(
        name: "official-candlestick-large", category: "candlestick",
        summary: "大数据量K线图 — Large Scale Candlestick",
        width: 800, height: 560,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
const upColor = '#ec0000';
const upBorderColor = '#8A0000';
const downColor = '#00da3c';
const downBorderColor = '#008F28';

const dataCount = 2e4;
const data = generateOHLC(dataCount);

option = {
  dataset: {
    source: data
  },
  title: {
    text: 'Data Amount: ' + echarts.format.addCommas(dataCount)
  },
  tooltip: {
    trigger: 'axis',
    axisPointer: {
      type: 'line'
    }
  },
  toolbox: {
    feature: {
      dataZoom: {
        yAxisIndex: false
      }
    }
  },
  grid: [
    {
      left: '10%',
      right: '10%',
      bottom: 200
    },
    {
      left: '10%',
      right: '10%',
      height: 80,
      bottom: 80
    }
  ],
  xAxis: [
    {
      type: 'category',
      boundaryGap: false,
      // inverse: true,
      axisLine: { onZero: false },
      splitLine: { show: false },
      min: 'dataMin',
      max: 'dataMax'
    },
    {
      type: 'category',
      gridIndex: 1,
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
      start: 10,
      end: 100
    },
    {
      show: true,
      xAxisIndex: [0, 1],
      type: 'slider',
      bottom: 10,
      start: 10,
      end: 100
    }
  ],
  visualMap: {
    show: false,
    seriesIndex: 1,
    dimension: 6,
    pieces: [
      {
        value: 1,
        color: upColor
      },
      {
        value: -1,
        color: downColor
      }
    ]
  },
  series: [
    {
      type: 'candlestick',
      itemStyle: {
        color: upColor,
        color0: downColor,
        borderColor: upBorderColor,
        borderColor0: downBorderColor
      },
      encode: {
        x: 0,
        y: [1, 4, 3, 2]
      }
    },
    {
      name: 'Volumn',
      type: 'bar',
      xAxisIndex: 1,
      yAxisIndex: 1,
      itemStyle: {
        color: '#7fbe9e'
      },
      large: true,
      encode: {
        x: 0,
        y: 5
      }
    }
  ]
};

function generateOHLC(count) {
  let data = [];

  // Deterministic counterpart of `CandlestickLargeRandom` in the Native option.
  let randomState = 0x9E3779B97F4A7C15n;
  const uint64Mask = (1n << 64n) - 1n;
  function random01() {
    randomState ^= randomState >> 12n;
    randomState &= uint64Mask;
    randomState ^= (randomState << 25n) & uint64Mask;
    randomState &= uint64Mask;
    randomState ^= randomState >> 27n;
    randomState &= uint64Mask;
    const x = (randomState * 2685821657736338717n) & uint64Mask;
    return Number(x >> 11n) / 9007199254740992;
  }

  let xValue = +new Date(2011, 0, 1);
  let minute = 60 * 1000;
  let baseValue = random01() * 12000;
  let boxVals = new Array(4);
  let dayRange = 12;

  for (let i = 0; i < count; i++) {
    baseValue = baseValue + random01() * 20 - 10;

    for (let j = 0; j < 4; j++) {
      boxVals[j] = (random01() - 0.5) * dayRange + baseValue;
    }
    boxVals.sort((a, b) => a - b);

    let openIdx = Math.round(random01() * 3);
    let closeIdx = Math.round(random01() * 2);
    if (closeIdx === openIdx) {
      closeIdx++;
    }
    let volumn = boxVals[3] * (1000 + random01() * 500);

    // ['open', 'close', 'lowest', 'highest', 'volumn']
    // [1, 4, 3, 2]
    data[i] = [
      echarts.format.formatTime('yyyy-MM-dd\nhh:mm:ss', (xValue += minute)),
      +boxVals[openIdx].toFixed(2), // open
      +boxVals[3].toFixed(2), // highest
      +boxVals[0].toFixed(2), // lowest
      +boxVals[closeIdx].toFixed(2), // close
      +volumn.toFixed(0),
      getSign(data, i, +boxVals[openIdx], +boxVals[closeIdx], 4) // sign
    ];
  }

  return data;

  function getSign(data, dataIndex, openVal, closeVal, closeDimIdx) {
    var sign;
    if (openVal > closeVal) {
      sign = -1;
    } else if (openVal < closeVal) {
      sign = 1;
    } else {
      sign =
        dataIndex > 0
          ? // If close === open, compare with close of last record
            data[dataIndex - 1][closeDimIdx] <= closeVal
            ? 1
            : -1
          : // No record of previous, set to be positive
            1;
    }

    return sign;
  }
}
"""#,
        option: [
            "dataset": [
                "source": candlestickLargeSource
            ] as [String: Any],
            "title": [
                // upstream: 'Data Amount: ' + echarts.format.addCommas(dataCount) — a helper called
                // while BUILDING the option, not a closure in it, so the native pane pre-computes it.
                "text": candlestickLargeTitleText
            ] as [String: Any],
            "tooltip": [
                "trigger": "axis",
                "axisPointer": [
                    "type": "line"
                ] as [String: Any]
            ] as [String: Any],
            "toolbox": [
                "feature": [
                    "dataZoom": [
                        "yAxisIndex": false
                    ] as [String: Any]
                ] as [String: Any]
            ] as [String: Any],
            "grid": [
                [
                    "left": "10%",
                    "right": "10%",
                    "bottom": 200.0
                ] as [String: Any],
                [
                    "left": "10%",
                    "right": "10%",
                    "height": 80.0,
                    "bottom": 80.0
                ] as [String: Any]
            ],
            "xAxis": [
                [
                    "type": "category",
                    "boundaryGap": false,
                    // inverse: true,
                    "axisLine": ["onZero": false] as [String: Any],
                    "splitLine": ["show": false] as [String: Any],
                    "min": "dataMin",
                    "max": "dataMax"
                ] as [String: Any],
                [
                    "type": "category",
                    "gridIndex": 1.0,
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
                    "splitArea": [
                        "show": true
                    ] as [String: Any]
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
                    "start": 10.0,
                    "end": 100.0
                ] as [String: Any],
                [
                    "show": true,
                    "xAxisIndex": [0.0, 1.0],
                    "type": "slider",
                    "bottom": 10.0,
                    "start": 10.0,
                    "end": 100.0
                ] as [String: Any]
            ],
            "visualMap": [
                "show": false,
                "seriesIndex": 1.0,
                "dimension": 6.0,
                "pieces": [
                    [
                        "value": 1.0,
                        "color": candlestickLargeUpColor
                    ] as [String: Any],
                    [
                        "value": -1.0,
                        "color": candlestickLargeDownColor
                    ] as [String: Any]
                ]
            ] as [String: Any],
            "series": [
                [
                    "type": "candlestick",
                    "itemStyle": [
                        "color": candlestickLargeUpColor,
                        "color0": candlestickLargeDownColor,
                        "borderColor": candlestickLargeUpBorderColor,
                        "borderColor0": candlestickLargeDownBorderColor
                    ] as [String: Any],
                    "encode": [
                        "x": 0.0,
                        "y": [1.0, 4.0, 3.0, 2.0]
                    ] as [String: Any]
                ] as [String: Any],
                [
                    "name": "Volumn",
                    "type": "bar",
                    "xAxisIndex": 1.0,
                    "yAxisIndex": 1.0,
                    "itemStyle": [
                        "color": "#7fbe9e"
                    ] as [String: Any],
                    "large": true,
                    "encode": [
                        "x": 0.0,
                        "y": 5.0
                    ] as [String: Any]
                ] as [String: Any]
            ]
        ])
}

private let candlestickLargeUpColor = "#ec0000"
private let candlestickLargeUpBorderColor = "#8A0000"
private let candlestickLargeDownColor = "#00da3c"
private let candlestickLargeDownBorderColor = "#008F28"
