// official-matrix-covariance — replica of https://echarts.apache.org/examples/zh/editor.html?c=matrix-covariance
// title: Covariance Matrix / titleCN: 协方差矩阵
// A 25x25 heatmap on a `matrix` coordinate system: the x/y dimensions are two-level (5 groups
// X1..X5 / Y1..Y5, each with 5 leaf cells '1'..'25'), the cells are colored by a continuous
// visualMap, and the values are symmetric across the diagonal.
//
// DEVIATIONS from the official source:
//   - Math.random() -> a seeded LCG (`rnd()` in each pane: top-level in webOptionJS, local to the
//     `matrixCovarianceData` initializer in Swift). The official example
//     re-rolls its 625 cells on every load; the two panes here must render the SAME chart to be
//     diffable, so both run the identical generation loop over the identical 32-bit LCG stream
//     (seed 1, x = x*1664525 + 1013904223 mod 2^32) in the same call order. Everything else in the
//     data loop — the base/group/diagonal terms, the i>j symmetry lookup — is verbatim.
//   - matrix.left: `(window.innerWidth - 500) / 2` -> the constant 110. The official example centers
//     its fixed 500px matrix in the BROWSER WINDOW; there is no window in the native pane, and on
//     macOS the reference pane's window is the WKWebView (wider than the demo canvas), which would
//     push the matrix off-canvas. 110 = (720 - 500) / 2, i.e. the same centering against this demo's
//     720x560 canvas. Canvas height is 560 (not the gallery default) so the 500px-tall matrix fits
//     under its default `top: '10%'`.
//   - tooltip.valueFormatter is a JS closure: kept verbatim in the web pane, omitted in the native
//     option (see PORT-NOTE). Tooltips do not appear in the static render either way.
//   - NATIVE PANE IS PARTIAL — the same gap official-matrix-simple carries, and nothing about this
//     option causes it. EChartsKit registers the matrix coord + MatrixView, so the native pane draws
//     the table backdrop (the two-level headers, dividers, border) and the visualMap bar — but NOT the
//     625 heatmap cells: `HeatmapView.render` only wires the cartesian2d / calendar / geo branches, and
//     a matrix coordSys falls into the `else` (group.removeAll() → nothing drawn). Kept
//     `nativeSupported: true` on purpose: this diff IS the gap the gallery exists to surface. The web
//     pane is fully correct. Lights up when HeatmapView's `_renderOnGridLike` matrix branch lands.
extension EChartsDemoRegistry {
    static let official_matrix_covariance = EChartsDemo(
        name: "official-matrix-covariance", category: "matrix",
        summary: "协方差矩阵 — Covariance Matrix",
        width: 720, height: 560,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
// Seeded LCG standing in for Math.random(), so this pane and the native pane draw the same matrix.
let rndState = 1;
function rnd() {
  rndState = (rndState * 1664525 + 1013904223) >>> 0;
  return rndState / 4294967296;
}

const xData = [];
const yData = [];
for (let i = 0; i < 5; ++i) {
  const children = [];
  for (let j = 0; j < 5; ++j) {
    children.push(i * 5 + j + 1 + '');
  }
  xData.push({
    value: 'X' + (i + 1),
    children
  });
  yData.push({
    value: 'Y' + (i + 1),
    children
  });
}

const data = [];
const size = 25;
let temp = {};

for (let i = 1; i <= size; ++i) {
  for (let j = 1; j <= size; ++j) {
    let base = i === j ? 100 : 20;
    const iGroup = Math.ceil(i / 5);
    const jGroup = Math.ceil(j / 5);
    base += (3 - Math.abs(iGroup - jGroup)) * 35;
    if (i % 5 === j % 5) {
      base += 20;
    }
    if (rnd() > 0.9) {
      base += rnd() * 40;
    }

    if (i > j) {
      // Use the previously calculated value to ensure symmetry
      data.push([
        i + '',
        j + '',
        temp[j + '_' + i]
      ]);
    } else {
      // Calculate a new value and save it for future use
      let value = (rnd() * 0.5 + 0.5) * base;
      data.push([
        i + '',
        j + '',
        value
      ]);
      temp[i + '_' + j] = value;
    }
  }
}

option = {
  matrix: {
    x: {
      data: xData,
      show: false
    },
    y: {
      data: yData,
      show: false
    },
    width: 500,
    height: 500,
    left: 110
  },
  tooltip: {
    show: true,
    valueFormatter: value => Math.round(value)
  },
  visualMap: {
    type: 'continuous',
    min: 15,
    max: 120,
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
      ]
    }
  },
  series: {
    type: 'heatmap',
    coordinateSystem: 'matrix',
    data
  }
};
"""#,
        option: [
            "matrix": [
                "x": [
                    "data": matrixCovarianceXData,
                    "show": false
                ] as [String: Any],
                "y": [
                    "data": matrixCovarianceYData,
                    "show": false
                ] as [String: Any],
                "width": 500.0,
                "height": 500.0,
                "left": 110.0
            ] as [String: Any],
            "tooltip": [
                "show": true
                // PORT-NOTE: tooltip.valueFormatter omitted — `value => Math.round(value)`, which
                // rounds the raw covariance to an integer in the tooltip body.
            ] as [String: Any],
            "visualMap": [
                "type": "continuous",
                "min": 15.0,
                "max": 120.0,
                "dimension": 2.0,
                "calculable": true,
                "orient": "horizontal",
                "top": 5.0,
                "left": "center",
                "inRange": [
                    "color": matrixCovarianceColors
                ] as [String: Any]
            ] as [String: Any],
            // PORT-NOTE: draws the matrix BACKDROP ONLY today — HeatmapView.render has no matrix branch
            // (cartesian2d / calendar / geo only), so these 625 cells render nothing on the native pane.
            // The option is complete and correct; it lights up when that branch lands. See header.
            "series": [
                "type": "heatmap",
                "coordinateSystem": "matrix",
                "data": matrixCovarianceData
            ] as [String: Any]
        ])
}

// MARK: - generated data (mirrors the example's preamble; see DEVIATIONS above)

private let matrixCovarianceColors: [String] = [
    "#313695", "#4575b4", "#74add1", "#abd9e9", "#e0f3f8", "#ffffbf",
    "#fee090", "#fdae61", "#f46d43", "#d73027", "#a50026"
]

/// Two-level matrix dimension: 5 groups (`X1`..`X5` / `Y1`..`Y5`), each holding leaf cells
/// '1'..'25' — the same leaf names the heatmap data indexes by.
private func matrixCovarianceDim(_ prefix: String) -> [[String: Any]] {
    (0..<5).map { i in
        [
            "value": "\(prefix)\(i + 1)",
            "children": (0..<5).map { j in "\(i * 5 + j + 1)" }
        ] as [String: Any]
    }
}

private let matrixCovarianceXData: [[String: Any]] = matrixCovarianceDim("X")
private let matrixCovarianceYData: [[String: Any]] = matrixCovarianceDim("Y")

/// [xCell, yCell, value] triples for all 25x25 cells, symmetric across the diagonal.
/// The LCG below must stay bit-identical to `rnd()` in webOptionJS (same seed, same multiplier /
/// increment, same modulus, same call order) or the two panes drift apart.
private let matrixCovarianceData: [[Any]] = {
    var rndState: UInt32 = 1
    func rnd() -> Double {
        rndState = rndState &* 1664525 &+ 1013904223
        return Double(rndState) / 4294967296.0
    }

    var data: [[Any]] = []
    let size = 25
    var temp: [String: Double] = [:]

    for i in 1...size {
        for j in 1...size {
            var base: Double = (i == j) ? 100 : 20
            let iGroup = (i + 4) / 5     // ceil(i / 5)
            let jGroup = (j + 4) / 5     // ceil(j / 5)
            base += Double(3 - abs(iGroup - jGroup)) * 35
            if i % 5 == j % 5 {
                base += 20
            }
            if rnd() > 0.9 {
                base += rnd() * 40
            }

            if i > j {
                // Use the previously calculated value to ensure symmetry.
                // Typed `let` on purpose: inline, `temp[...] ?? 0` would be type-checked against the
                // literal's `Any` element type, where `??` can bind T := Any and default `0` to an Int.
                // The lookup always hits (the i<j pass wrote it), so the fallback is unreachable.
                let mirrored: Double = temp["\(j)_\(i)"] ?? 0
                data.append(["\(i)", "\(j)", mirrored])
            } else {
                // Calculate a new value and save it for future use
                let value = (rnd() * 0.5 + 0.5) * base
                data.append(["\(i)", "\(j)", value])
                temp["\(i)_\(j)"] = value
            }
        }
    }
    return data
}()
