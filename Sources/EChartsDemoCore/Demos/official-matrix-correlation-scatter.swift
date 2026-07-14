// official-matrix-correlation-scatter — replica of https://echarts.apache.org/examples/zh/editor.html?c=matrix-correlation-scatter
// title: Correlation Matrix (Scatter) / titleCN: 相关矩阵（散点图） (since echarts 6.0.0)
//
// A 10x6 correlation matrix drawn as a `scatter` series on the `matrix` coordinate system: each cell
// holds one bubble whose COLOUR and RADIUS both come from a continuous `visualMap` over the datum's
// 3rd dimension (dimension: 2, a correlation in [-1, 1]) — `inRange.color` is the 11-stop
// RdYlBu-reversed ramp and `inRange.symbolSize` maps the same value onto [15, 40]px.
//
// DEVIATIONS from the official source:
//   - Math.random() -> a seeded LCG (`rnd()` in each pane: top-level in webOptionJS, local to the
//     `matrixCorrelationScatterData` initializer in Swift). The official example re-rolls its 60 cells
//     on every load; the two panes here must render the SAME chart to be diffable, so both run the
//     identical generation loop over the identical 32-bit LCG stream (seed 1,
//     x = x*1664525 + 1013904223 mod 2^32) in the same call order — i-major, one draw per cell.
//     Everything else in the data loop (the `Math.random() * 2 - 1` mapping onto [-1, 1], the
//     'X'+i / 'Y'+j locators) is verbatim. Same substitution official-matrix-covariance makes.
//   - series.label.formatter is a JS closure: kept verbatim in the web pane, omitted in the native
//     option (see PORT-NOTE below).
//   - The official source writes `series` as a bare object; the Swift option uses the one-element array
//     echarts itself normalizes it to (webOptionJS keeps the object form verbatim). Not a semantic change.
//   - NATIVE PANE IS PARTIAL — the same gap official-matrix-simple / official-matrix-covariance carry,
//     and nothing about this option causes it. EChartsKit registers the matrix coord + MatrixView, so
//     the native pane draws the table backdrop (the X1..X10 / Y1..Y6 headers, the dividers, the border)
//     and the visualMap bar — but NOT the 60 bubbles: `ScatterView.render` builds its `pointAt`
//     placement closure only for cartesian2d / polar / geo, and a matrix coordSys falls into the final
//     `else` (an early `return` → nothing drawn). Kept `nativeSupported: true` on purpose: this diff IS
//     the gap the gallery exists to surface. The web pane is fully correct. Lights up when ScatterView
//     grows a matrix branch (`ScatterSeries.dependencies` already lists 'matrix').
// No other option key is dropped: the visualMap (including inRange.symbolSize) and the matrix headers
// are plain data and port across unchanged.
extension EChartsDemoRegistry {
    static let official_matrix_correlation_scatter = EChartsDemo(
        name: "official-matrix-correlation-scatter", category: "matrix",
        summary: "相关矩阵（散点图） — Correlation Matrix (Scatter)",
        width: 720, height: 460,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
// Seeded LCG standing in for Math.random(), so this pane and the native pane draw the same matrix.
let rndState = 1;
function rnd() {
  rndState = (rndState * 1664525 + 1013904223) >>> 0;
  return rndState / 4294967296;
}

const xCnt = 10;
const yCnt = 6;
const xData = [];
const yData = [];
for (let i = 0; i < xCnt; ++i) {
  xData.push({
    value: 'X' + (i + 1)
  });
}

for (let i = 0; i < yCnt; ++i) {
  yData.push({
    value: 'Y' + (i + 1)
  });
}

const data = [];
for (let i = 1; i <= xCnt; ++i) {
  for (let j = 1; j <= yCnt; ++j) {
    data.push(['X' + i, 'Y' + j, rnd() * 2 - 1]);
  }
}

option = {
  matrix: {
    x: {
      data: xData
    },
    y: {
      data: yData
    },
    top: 80
  },
  visualMap: {
    type: 'continuous',
    min: -1,
    max: 1,
    dimension: 2,
    calculable: true,
    orient: 'horizontal',
    top: 5,
    left: 'center',
    inRange: {
      color: [
        '#313695',
        '#4575b4',
        '#74add1',
        '#abd9e9',
        '#e0f3f8',
        '#ffffbf',
        '#fee090',
        '#fdae61',
        '#f46d43',
        '#d73027',
        '#a50026'
      ],
      symbolSize: [15, 40]
    }
  },
  series: {
    type: 'scatter',
    coordinateSystem: 'matrix',
    data,
    itemStyle: {
      opacity: 1
    },
    label: {
      show: true,
      formatter: (params) => params.value[2].toFixed(2)
    }
  }
};
"""#,
        option: [
            "matrix": [
                "x": ["data": matrixCorrelationScatterXData] as [String: Any],
                "y": ["data": matrixCorrelationScatterYData] as [String: Any],
                "top": 80.0
            ] as [String: Any],
            "visualMap": [
                "type": "continuous",
                "min": -1.0,
                "max": 1.0,
                // The mapped dimension: index 2 of each datum, i.e. the correlation in [x, y, value].
                "dimension": 2.0,
                "calculable": true,
                "orient": "horizontal",
                "top": 5.0,
                "left": "center",
                "inRange": [
                    "color": matrixCorrelationScatterColors,
                    // The visualMap drives the bubble RADIUS as well as its colour.
                    "symbolSize": [15.0, 40.0]
                ] as [String: Any]
            ] as [String: Any],
            "series": [
                // PORT-NOTE: rendered as the matrix BACKDROP only today — ScatterView.render has no matrix
                // branch (cartesian2d / polar / geo only), so these 60 bubbles draw nothing on the native
                // pane. Option is complete and correct; it lights up when that branch lands. See header.
                [
                    "type": "scatter",
                    "coordinateSystem": "matrix",
                    "data": matrixCorrelationScatterData,
                    "itemStyle": ["opacity": 1.0] as [String: Any],
                    "label": [
                        "show": true
                        // PORT-NOTE: label.formatter omitted — `(params) => params.value[2].toFixed(2)`,
                        // which prints each bubble's correlation on it, fixed to 2 decimals ("-0.42").
                        // Without it the native label would fall back to the datum's name.
                    ] as [String: Any]
                ] as [String: Any]
            ]
        ])
}

// MARK: - generated data (mirrors the example's preamble; see DEVIATIONS above)

private let matrixCorrelationScatterXCnt = 10
private let matrixCorrelationScatterYCnt = 6

private let matrixCorrelationScatterColors: [String] = [
    "#313695", "#4575b4", "#74add1", "#abd9e9", "#e0f3f8", "#ffffbf",
    "#fee090", "#fdae61", "#f46d43", "#d73027", "#a50026"
]

/// The matrix headers, verbatim from the source: flat `{ value: 'X1' }` … `{ value: 'X10' }` /
/// `{ value: 'Y1' }` … `{ value: 'Y6' }` cells (no `children` — this matrix is single-level).
private let matrixCorrelationScatterXData: [[String: Any]] =
    (0..<matrixCorrelationScatterXCnt).map { ["value": "X\($0 + 1)"] as [String: Any] }

private let matrixCorrelationScatterYData: [[String: Any]] =
    (0..<matrixCorrelationScatterYCnt).map { ["value": "Y\($0 + 1)"] as [String: Any] }

/// [xCell, yCell, correlation] triples for all 10x6 cells, correlation in [-1, 1].
/// The LCG below must stay bit-identical to `rnd()` in webOptionJS (same seed, same multiplier /
/// increment, same modulus, same call order — i-major, one draw per cell) or the two panes drift apart.
private let matrixCorrelationScatterData: [[Any]] = {
    var rndState: UInt32 = 1
    func rnd() -> Double {
        rndState = rndState &* 1664525 &+ 1013904223
        return Double(rndState) / 4294967296.0
    }

    var data: [[Any]] = []
    for i in 1...matrixCorrelationScatterXCnt {
        for j in 1...matrixCorrelationScatterYCnt {
            data.append(["X\(i)", "Y\(j)", rnd() * 2 - 1])
        }
    }
    return data
}()
