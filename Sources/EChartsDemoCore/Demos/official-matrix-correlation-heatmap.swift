// official-matrix-correlation-heatmap — replica of https://echarts.apache.org/examples/zh/editor.html?c=matrix-correlation-heatmap
// title: Correlation Matrix (Heatmap) / titleCN: 相关矩阵（热力图）
// An 8x8 lower-triangular correlation heatmap on a `matrix` coordinate system: single-level x/y
// dimensions ('X1'..'X8' / 'Y1'..'Y8'), only the cells with i >= j are emitted (36 of 64), the
// diagonal is pinned to 1, and the off-diagonal cells are random correlations in [-1, 1] colored by
// a horizontal `calculable` continuous visualMap on dimension 2. Each cell is labeled with its
// value to 2 decimals.
//
// DEVIATIONS from the official source:
//   - Math.random() -> a seeded LCG (`rnd()` in each pane: top-level in webOptionJS, local to the
//     `matrixCorrelationHeatmapData` initializer in Swift). The official example re-rolls its 28
//     off-diagonal cells on every load; the two panes here must render the SAME chart to be
//     diffable, so both run the identical generation loop over the identical 32-bit LCG stream
//     (seed 1, x = x*1664525 + 1013904223 mod 2^32) in the SAME call order — including the fact
//     that the `i === j ? 1 : ...` ternary short-circuits, so no random is drawn on the 8 diagonal
//     cells. Everything else in the data loop (the i >= j filter, the value expression) is verbatim.
//   - series.label.formatter is a JS closure: kept verbatim in the web pane, omitted in the native
//     option (see note). The native pane therefore labels the cells with echarts' default
//     (the raw value) rather than `toFixed(2)`.
//   - NATIVE PANE IS PARTIAL — the same gap official-matrix-simple / official-matrix-covariance
//     carry, and nothing about this option causes it. EChartsKit registers the matrix coord +
//     MatrixView, so the native pane draws the table backdrop (the X/Y headers, dividers, border)
//     and the visualMap bar — but NOT the 36 heatmap cells: `HeatmapView.render` only wires the
//     cartesian2d / calendar / geo branches and a matrix coordSys falls into the `else`
//     (group.removeAll() → nothing drawn). Kept `nativeSupported: true` on purpose: this diff IS
//     the gap the gallery exists to surface. The web pane is fully correct. Lights up when
//     HeatmapView's `_renderOnGridLike` matrix branch lands.
extension EChartsDemoRegistry {
    static let official_matrix_correlation_heatmap = EChartsDemo(
        name: "official-matrix-correlation-heatmap", category: "matrix",
        summary: "相关矩阵（热力图） — Correlation Matrix (Heatmap)",
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

const xCnt = 8;
const yCnt = xCnt;
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
    if (i >= j) {
      data.push([
        'X' + i,
        'Y' + j,
        i === j ? 1 : rnd() * 2 - 1
      ]);
    }
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
    left: 'center'
  },
  series: {
    type: 'heatmap',
    coordinateSystem: 'matrix',
    data,
    label: {
      show: true,
      formatter: params => params.value[2].toFixed(2)
    }
  }
};
"""#,
        option: [
            "matrix": [
                "x": [
                    "data": matrixCorrelationHeatmapXData
                ] as [String: Any],
                "y": [
                    "data": matrixCorrelationHeatmapYData
                ] as [String: Any],
                "top": 80.0
            ] as [String: Any],
            "visualMap": [
                "type": "continuous",
                "min": -1.0,
                "max": 1.0,
                "dimension": 2.0,
                "calculable": true,
                "orient": "horizontal",
                "top": 5.0,
                "left": "center"
            ] as [String: Any],
            // draws the matrix BACKDROP ONLY today — HeatmapView.render has no matrix branch
            // (cartesian2d / calendar / geo only), so these 36 cells render nothing on the native pane.
            // The option is complete and correct; it lights up when that branch lands. See header.
            "series": [
                "type": "heatmap",
                "coordinateSystem": "matrix",
                "data": matrixCorrelationHeatmapData,
                "label": [
                    "show": true
                    // label.formatter omitted — `params => params.value[2].toFixed(2)`,
                    // which prints the cell's correlation (data dim 2) rounded to 2 decimals.
                ] as [String: Any]
            ] as [String: Any]
        ])
}

// MARK: - generated data (mirrors the example's preamble; see DEVIATIONS above)

private let matrixCorrelationHeatmapCnt = 8

/// Single-level matrix dimensions: 'X1'..'X8' and 'Y1'..'Y8', the names the heatmap data indexes by.
private func matrixCorrelationHeatmapDim(_ prefix: String) -> [[String: Any]] {
    (0..<matrixCorrelationHeatmapCnt).map { i in
        ["value": "\(prefix)\(i + 1)"] as [String: Any]
    }
}

private let matrixCorrelationHeatmapXData: [[String: Any]] = matrixCorrelationHeatmapDim("X")
private let matrixCorrelationHeatmapYData: [[String: Any]] = matrixCorrelationHeatmapDim("Y")

/// `[xCell, yCell, correlation]` triples for the lower triangle (i >= j) — 36 of the 64 cells.
/// The LCG below must stay bit-identical to `rnd()` in webOptionJS (same seed, same multiplier /
/// increment, same modulus, same call order — note it is NOT called on the diagonal, where the JS
/// ternary short-circuits to the literal 1) or the two panes drift apart.
private let matrixCorrelationHeatmapData: [[Any]] = {
    var rndState: UInt32 = 1
    func rnd() -> Double {
        rndState = rndState &* 1664525 &+ 1013904223
        return Double(rndState) / 4294967296.0
    }

    let xCnt = matrixCorrelationHeatmapCnt
    let yCnt = xCnt
    var data: [[Any]] = []
    for i in 1...xCnt {
        for j in 1...yCnt where i >= j {
            let value: Double = (i == j) ? 1 : rnd() * 2 - 1
            data.append(["X\(i)", "Y\(j)", value])
        }
    }
    return data
}()
