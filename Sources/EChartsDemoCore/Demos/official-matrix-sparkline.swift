// official-matrix-sparkline — replica of https://echarts.apache.org/examples/zh/editor.html?c=matrix-sparkline
// title: Mini Line Charts (Sparkline) in Matrix / titleCN: 矩阵中的微型折线图 (since echarts 6.0.0)
//
// A 5x6 `matrix` (weekday x two-hour slot) whose cells each HOST A CARTESIAN GRID: one `grid` +
// `xAxis` + `yAxis` + `line` series per cell, the grid placed by `coordinateSystem: 'matrix'` +
// `coord: [xval, yval]`. The '12:00~14:00' row is not a chart at all — a merged `matrix.body` cell
// labelled 'Break' spans it. Two dataZooms (slider + inside) drive all 25 x-axes at once.
//
// DEVIATIONS from the official source:
//   - THE DATA IS RANDOM UPSTREAM. `generateFakeSeriesData` walks a random walk off `Math.random()`,
//     so independently loading the two panes would make visual comparison meaningless. Both panes
//     therefore use the same per-cell seeded xorshift64* stream. The walk itself is unchanged: 365
//     weekly points, ±50 delta, sign-flipping turn points and the same date labels.
//   - JS `Math.round` / `Number.toFixed(0)` tie-breaking (toward +inf) is not reproduced exactly;
//     `.rounded()` (ties away from zero) is used. Noise-level on random data.
//   - The source builds `grid`/`xAxis`/`yAxis`/`series` by pushing inside `eachMatrixCell(...)`; the
//     Swift option holds the same arrays, materialized once at file scope (`matrixSparklineParts`).
//     Same values, same order (row-major over y then x, break row skipped). Not a semantic change.
// No option key is a JS closure, so nothing is dropped from the Swift port.
//
// Each cell grid is placed into its matrix cell by the BOX COORDINATE SYSTEM branch of
// `layout.createBoxLayoutReference` (`model.boxCoordinateSystem` -> `CoordinateSystem.dataToLayout(coord)`
// -> the cell rect). That branch — and Matrix's `CoordinateSystem` conformance that lets
// `simpleCoordSysInjectionProvider` inject the matrix into each grid's `boxCoordinateSystem` — are now
// ported, so the 30 cell sparklines land in their own cells instead of stacking over the full viewport.
// This gallery surfaced that gap.

import Foundation

// ---------------------------------------------------------------------------------------------
// Source's `_matrixDimensionData` / `_yBreakTimeIndex` / `_seriesFakeDataLength`.
// ---------------------------------------------------------------------------------------------

private let matrixSparklineXDim: [String] = ["Mon", "Tue", "Wed", "Thu", "Fri"]

// The '12:00~14:00' slot carries an explicit `size: 55` (a shorter row — it holds no chart).
private let matrixSparklineYDim: [[String: Any]] = [
    ["value": "8:00\n~\n10:00"],
    ["value": "10:00\n~\n12:00"],
    ["value": "12:00\n~\n14:00", "size": 55.0],
    ["value": "14:00\n~\n16:00"],
    ["value": "16:00\n~\n18:00"],
    ["value": "18:00\n~\n20:00"]
]

private let matrixSparklineBreakIndex = 2      // '12:00 ~ 14:00'
private let matrixSparklineDataLength = 365

// matrix.body's merged 'Break' cell: `coord: [null, 2]` — null = "the entire row" (with coordClamp).
// NSNull is the JS `null`; MatrixDim.getCell routes it to OrdinalScale.parse -> NaN -> clamp.
private let matrixSparklineBreakCoord: [Any] = [NSNull(), Double(matrixSparklineBreakIndex)]

// ---------------------------------------------------------------------------------------------
// The port of `generateFakeSeriesData`. Deterministic stand-in for Math.random() (see DEVIATIONS).
// ---------------------------------------------------------------------------------------------

/// xorshift64* — a Math.random() replacement with a per-cell seed, so the native pane is stable.
private struct MatrixSparklineRNG {
    private var state: UInt64
    init(seed: UInt64) { self.state = seed | 1 }
    /// Uniform in [0, 1), like `Math.random()`.
    mutating func next() -> Double {
        state ^= state >> 12
        state ^= state << 25
        state ^= state >> 27
        let v = state &* 2_685_821_657_736_338_717
        return Double(v >> 11) / Double(1 << 53)
    }
}

private let matrixSparklineDayFormatter: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = TimeZone(identifier: "UTC")
    f.dateFormat = "yyyy-MM-dd"    // the source's echarts.time.format(t, '{yyyy}-{MM}-{dd}')
    return f
}()

/// `generateFakeSeriesData(dayCount, xidx, yidx)`: a `dayCount`-step random walk, one point per week,
/// starting on the weekday `xidx` of the week of 2025-05-05 (a Monday). Returns `[[dateString, value]]`.
private func matrixSparklineCellData(_ dayCount: Int, _ xidx: Int, _ yidx: Int) -> [[Any]] {
    var rng = MatrixSparklineRNG(seed: UInt64(1_234_567 &+ xidx &* 977 &+ yidx &* 31))
    // new Date('2025-05-05T00:00:00.000Z'); dayStart.setDate(xidx + 5)  ->  Mon..Fri of that week.
    let weekStart = Date(timeIntervalSince1970: 1_746_403_200)   // 2025-05-05T00:00:00Z
    let timeStart = weekStart.timeIntervalSince1970 + Double(xidx) * 86_400
    let sevenDay: Double = 7 * 24 * 3600

    var cellData: [[Any]] = []
    cellData.reserveCapacity(dayCount)
    var lastVal = (rng.next() * 300).rounded()
    var turnCount: Int?
    var sign: Double = -1

    for idx in 0..<dayCount {
        if turnCount == nil || idx >= turnCount! {
            turnCount = idx + Int(((Double(dayCount) / 4) * ((rng.next() - 0.5) * 0.1)).rounded())
            sign = -sign
        }
        let deltaMag: Double = 50
        let delta = (rng.next() * deltaMag - deltaMag / 2 + (sign * deltaMag) / 3).rounded()
        lastVal += delta
        let val = max(0, lastVal)
        let xTime = timeStart + Double(idx) * sevenDay
        let dataXVal = matrixSparklineDayFormatter.string(from: Date(timeIntervalSince1970: xTime))
        cellData.append([dataXVal, val])
    }
    return cellData
}

// ---------------------------------------------------------------------------------------------
// The port of the `eachMatrixCell(...)` push loop: one grid + xAxis + yAxis + line series per cell.
// Materialized once (25 cells x 365 points) — an inline literal would blow up the type-checker.
// ---------------------------------------------------------------------------------------------

private struct MatrixSparklineParts {
    let grid: [[String: Any]]
    let xAxis: [[String: Any]]
    let yAxis: [[String: Any]]
    let series: [[String: Any]]
}

private let matrixSparklineParts: MatrixSparklineParts = {
    var grid: [[String: Any]] = []
    var xAxis: [[String: Any]] = []
    var yAxis: [[String: Any]] = []
    var series: [[String: Any]] = []

    for (yidx, yItem) in matrixSparklineYDim.enumerated() {
        if yidx == matrixSparklineBreakIndex { continue }          // the merged 'Break' row: no chart
        let yval = yItem["value"] as? String ?? ""
        for (xidx, xval) in matrixSparklineXDim.enumerated() {
            let id = "\(xidx)|\(yidx)"                              // makeId(xidx, yidx)
            grid.append([
                "id": id,
                "coordinateSystem": "matrix",
                "coord": [xval, yval],                             // the matrix cell this grid lives in
                "top": 10.0,
                "bottom": 10.0,
                "left": "center",
                "width": "90%",
                "containLabel": true
            ] as [String: Any])
            xAxis.append([
                "type": "category",
                "id": id,
                "gridId": id,
                "scale": true,
                "axisTick": ["show": false] as [String: Any],
                "axisLabel": ["show": false] as [String: Any],
                "axisLine": ["show": false] as [String: Any],
                "splitLine": ["show": false] as [String: Any]
            ] as [String: Any])
            yAxis.append([
                "id": id,
                "gridId": id,
                // Number.MAX_SAFE_INTEGER — an interval so large only the min/max labels survive.
                "interval": 9_007_199_254_740_991.0,
                "scale": true,
                "axisLabel": [
                    "showMaxLabel": true,
                    "fontSize": 9.0
                ] as [String: Any],
                "axisLine": ["show": false] as [String: Any],
                "axisTick": ["show": false] as [String: Any]
            ] as [String: Any])
            series.append([
                "xAxisId": id,
                "yAxisId": id,
                "type": "line",
                "symbol": "none",
                "lineStyle": ["lineWidth": 1.0] as [String: Any],
                "data": matrixSparklineCellData(matrixSparklineDataLength, xidx, yidx)
            ] as [String: Any])
        }
    }
    return MatrixSparklineParts(grid: grid, xAxis: xAxis, yAxis: yAxis, series: series)
}()

extension EChartsDemoRegistry {
    static let official_matrix_sparkline = EChartsDemo(
        name: "official-matrix-sparkline", category: "matrix",
        summary: "矩阵中的微型折线图 — Mini Line Charts (Sparkline) in Matrix",
        width: 900, height: 560,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
const _matrixDimensionData = {
  x: ['Mon', 'Tue', 'Wed', 'Thu', 'Fri'],
  y: [
    { value: '8:00\n~\n10:00' },
    { value: '10:00\n~\n12:00' },
    { value: '12:00\n~\n14:00', size: 55 },
    { value: '14:00\n~\n16:00' },
    { value: '16:00\n~\n18:00' },
    { value: '18:00\n~\n20:00' }
  ]
};
const _yBreakTimeIndex = 2; // '12:00 - 14:00',
const _seriesFakeDataLength = 365;
option = {
  matrix: {
    x: {
      data: _matrixDimensionData.x,
      levelSize: 40,
      label: {
        fontSize: 16,
        color: '#555'
      }
    },
    y: {
      data: _matrixDimensionData.y,
      levelSize: 70,
      label: {
        fontSize: 14,
        color: '#777'
      }
    },
    corner: {
      data: [
        {
          coord: [-1, -1],
          value: 'Time'
        }
      ],
      label: {
        fontSize: 16,
        color: '#777'
      }
    },
    body: {
      data: [
        {
          coord: [null, _yBreakTimeIndex],
          coordClamp: true,
          mergeCells: true,
          value: 'Break',
          label: {
            color: '#999',
            fontSize: 16
          }
        }
      ]
    },
    top: 30,
    bottom: 80,
    width: '90%',
    left: 'center'
  },
  tooltip: {
    trigger: 'axis'
  },
  dataZoom: [{
    type: 'slider',
    xAxisIndex: 'all',
    left: '10%',
    right: '10%',
    bottom: 30,
    height: 30,
    throttle: 120
  }, {
    type: 'inside',
    xAxisIndex: 'all',
    throttle: 120
  }],
  grid: [],
  xAxis: [],
  yAxis: [],
  series: []
};
eachMatrixCell((xval, yval, xidx, yidx) => {
  const id = makeId(xidx, yidx);
  option.grid.push({
    id: id,
    coordinateSystem: 'matrix',
    coord: [xval, yval],
    top: 10,
    bottom: 10,
    left: 'center',
    width: '90%',
    containLabel: true
  });
  option.xAxis.push({
    type: 'category',
    id: id,
    gridId: id,
    scale: true,
    axisTick: { show: false },
    axisLabel: { show: false },
    axisLine: { show: false },
    splitLine: { show: false }
  });
  option.yAxis.push({
    id: id,
    gridId: id,
    interval: Number.MAX_SAFE_INTEGER,
    scale: true,
    axisLabel: {
      showMaxLabel: true,
      fontSize: 9
    },
    axisLine: { show: false },
    axisTick: { show: false }
  });
  option.series.push({
    xAxisId: id,
    yAxisId: id,
    type: 'line',
    symbol: 'none',
    lineStyle: {
      lineWidth: 1
    },
    data: generateFakeSeriesData(_seriesFakeDataLength, xidx, yidx)
  });
});
// ------ Helpers Start ------
function makeId(xidx, yidx) {
  return `${xidx}|${yidx}`;
}
function eachMatrixCell(cb) {
  _matrixDimensionData.y.forEach((yvalItem, yidx) => {
    const yval = yvalItem.value;
    if (yidx === _yBreakTimeIndex) {
      return;
    }
    _matrixDimensionData.x.forEach((xval, xidx) => {
      cb(xval, yval, xidx, yidx);
    });
  });
}
function generateFakeSeriesData(dayCount, xidx, yidx) {
  // Match MatrixSparklineRNG exactly. BigInt.asUintN reproduces UInt64 overflow after every step.
  let rngState = BigInt(1234567 + xidx * 977 + yidx * 31) | 1n;
  function seededRandom() {
    rngState = BigInt.asUintN(64, rngState ^ (rngState >> 12n));
    rngState = BigInt.asUintN(64, rngState ^ (rngState << 25n));
    rngState = BigInt.asUintN(64, rngState ^ (rngState >> 27n));
    const value = BigInt.asUintN(64, rngState * 2685821657736338717n);
    return Number(value >> 11n) / 9007199254740992;
  }
  const dayStart = new Date('2025-05-05T00:00:00.000Z'); // Monday
  dayStart.setDate(xidx + 5);
  const timeStart = dayStart.getTime();
  const sevenDay = 7 * 1000 * 3600 * 24;
  const cellData = [];
  let lastVal = +(seededRandom() * 300).toFixed(0);
  let turnCount = null;
  let sign = -1;
  for (let idx = 0; idx < dayCount; idx++) {
    if (turnCount == null || idx >= turnCount) {
      turnCount =
        idx + Math.round((dayCount / 4) * ((seededRandom() - 0.5) * 0.1));
      sign = -sign;
    }
    const deltaMag = 50;
    const delta = +(
      seededRandom() * deltaMag -
      deltaMag / 2 +
      (sign * deltaMag) / 3
    ).toFixed(0);
    const val = Math.max(0, (lastVal += delta));
    const xTime = timeStart + idx * sevenDay;
    const dataXVal = echarts.time.format(xTime, '{yyyy}-{MM}-{dd}');
    cellData.push([dataXVal, val]);
  }
  return cellData;
}
"""#,
        option: [
            "matrix": [
                "x": [
                    "data": matrixSparklineXDim,
                    "levelSize": 40.0,
                    "label": [
                        "fontSize": 16.0,
                        "color": "#555"
                    ] as [String: Any]
                ] as [String: Any],
                "y": [
                    "data": matrixSparklineYDim,
                    "levelSize": 70.0,
                    "label": [
                        "fontSize": 14.0,
                        "color": "#777"
                    ] as [String: Any]
                ] as [String: Any],
                "corner": [
                    // coord [-1, -1]: the corner area (negative locators address the header block).
                    "data": [
                        [
                            "coord": [-1.0, -1.0],
                            "value": "Time"
                        ] as [String: Any]
                    ],
                    "label": [
                        "fontSize": 16.0,
                        "color": "#777"
                    ] as [String: Any]
                ] as [String: Any],
                "body": [
                    "data": [
                        [
                            "coord": matrixSparklineBreakCoord,
                            "coordClamp": true,
                            "mergeCells": true,
                            "value": "Break",
                            "label": [
                                "color": "#999",
                                "fontSize": 16.0
                            ] as [String: Any]
                        ] as [String: Any]
                    ]
                ] as [String: Any],
                "top": 30.0,
                "bottom": 80.0,
                "width": "90%",
                "left": "center"
            ] as [String: Any],
            "tooltip": [
                "trigger": "axis"
            ] as [String: Any],
            "dataZoom": [
                [
                    "type": "slider",
                    "xAxisIndex": "all",
                    "left": "10%",
                    "right": "10%",
                    "bottom": 30.0,
                    "height": 30.0,
                    "throttle": 120.0
                ] as [String: Any],
                [
                    "type": "inside",
                    "xAxisIndex": "all",
                    "throttle": 120.0
                ] as [String: Any]
            ],
            "grid": matrixSparklineParts.grid,
            "xAxis": matrixSparklineParts.xAxis,
            "yAxis": matrixSparklineParts.yAxis,
            "series": matrixSparklineParts.series
        ])
}
