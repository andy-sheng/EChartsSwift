// official-heatmap-large — replica of https://echarts.apache.org/examples/zh/editor.html?c=heatmap-large
// title: Heatmap - 20K data / titleCN: 热力图 - 2w 数据
// A 201 x 101 cartesian heatmap (20,301 cells) over two category axes, coloured by a `calculable`
// visualMap through the 11-stop RdYlBu-ish ramp. The cell values are a 2-D Perlin-noise field
// (noisejs, inlined by the upstream example itself) sampled at (i/40, j/20) and biased by +0.5.
// The series runs `progressive: 1000` + `animation: false`.
//
// DEVIATIONS from the official source:
//   1. webOptionJS is the example verbatim except: the TypeScript annotations are stripped
//      (`let xData: number[]`, `function generateData(theta: number, …)`, the `class Grad` field
//      declarations, `function seed(seed: number)`, …) — the reference pane runs a classic script,
//      not TS — and the trailing `export {};` is dropped (a bare export is a SyntaxError in a
//      classic script and would blank the whole page). Both `data.push` comment-outs and the unused
//      `theta/min/max` params are kept as-is.
//   2. THE SEED IS FIXED. Upstream calls `noise.seed(Math.random())`, so the field is different on
//      every load and the two panes could never show the same chart. Everything downstream of the
//      seed is deterministic, so both panes here seed with the same constant (0.42) — which turns
//      this demo from "not comparable by construction" into a genuine pixel-for-pixel diff.
//   3. The noisejs helper (`Grad`, the 256-entry permutation table, `seed`, `fade`, `lerp`,
//      `perlin2`) is ported to Swift below for the native pane. It reproduces the JS EXACTLY: for
//      seed 0.42, ALL 20,301 values were compared against node as raw IEEE-754 bit patterns
//      (`Double.bitPattern` vs `DataView.getFloat64`) and every one is identical — not a rounding
//      match, the same doubles. So `data` is the SAME 20,301 triples in both panes, and any visual
//      difference between them is the renderer's, never the data's.
//      To re-verify: run this file's `webOptionJS` under node and dump `series[0].data[k][2]` bit
//      patterns; do the same for `heatmapLargeData`; diff. (The two `perlin2`s agree because JS `|`
//      `<<` `>>` `&` are int32 ops — hence the Int32 coercion in `seed` — and `Math.floor`/`%`/the
//      float arithmetic map 1:1 onto `.rounded(.down)`/`%`/Double.)
//   4. Upstream quirk, preserved verbatim: `data` is built for j in 0…100 (101 rows) but `yData`
//      only gets j in 0…99 (100 categories), so the top row of cells has no category and echarts
//      drops it. Both panes carry the same off-by-one.
//   5. `tooltip: {}` is interactive; the gallery snapshots ONE static frame, so it never shows.
//
// No PORT-NOTE below: this option has NO function-valued key (no formatter/renderItem/label callback),
// so NOTHING had to be dropped from the Swift `option` — it mirrors the JS one key-for-key. The only
// shape difference is that `xData`/`yData`/`data` are pre-computed into file-scope `private let`s
// rather than built by a `generateData` call, because the Swift option is data, not code.
// `visualMap.type` is left unspelled because the official leaves it unspelled: visualMap's
// typeDefaulter resolves min/max + calculable to `continuous`, and stating it would be an
// unfaithful embellishment. `progressive: 1000` is honored on BOTH panes — natively it routes
// through HeatmapView.incrementalPrepareRender/incrementalRender (the cartesian branch is ported).
import Foundation

// MARK: - the upstream noisejs helper (https://github.com/josephg/noisejs), ported

private struct HeatmapLargeGrad {
    let x: Double, y: Double, z: Double
    func dot2(_ x: Double, _ y: Double) -> Double { self.x * x + self.y * y }
    // `dot3` exists upstream but `perlin2` never calls it — omitted.
}

private let heatmapLargeGrad3: [HeatmapLargeGrad] = [
    HeatmapLargeGrad(x: 1, y: 1, z: 0), HeatmapLargeGrad(x: -1, y: 1, z: 0),
    HeatmapLargeGrad(x: 1, y: -1, z: 0), HeatmapLargeGrad(x: -1, y: -1, z: 0),
    HeatmapLargeGrad(x: 1, y: 0, z: 1), HeatmapLargeGrad(x: -1, y: 0, z: 1),
    HeatmapLargeGrad(x: 1, y: 0, z: -1), HeatmapLargeGrad(x: -1, y: 0, z: -1),
    HeatmapLargeGrad(x: 0, y: 1, z: 1), HeatmapLargeGrad(x: 0, y: -1, z: 1),
    HeatmapLargeGrad(x: 0, y: 1, z: -1), HeatmapLargeGrad(x: 0, y: -1, z: -1)
]

/// Ken Perlin's 256-entry permutation table, verbatim from the example's `p`.
private let heatmapLargePermutation: [Int] = [
    151, 160, 137, 91, 90, 15, 131, 13, 201, 95, 96, 53, 194, 233, 7, 225, 140,
    36, 103, 30, 69, 142, 8, 99, 37, 240, 21, 10, 23, 190, 6, 148, 247, 120,
    234, 75, 0, 26, 197, 62, 94, 252, 219, 203, 117, 35, 11, 32, 57, 177, 33,
    88, 237, 149, 56, 87, 174, 20, 125, 136, 171, 168, 68, 175, 74, 165, 71,
    134, 139, 48, 27, 166, 77, 146, 158, 231, 83, 111, 229, 122, 60, 211, 133,
    230, 220, 105, 92, 41, 55, 46, 245, 40, 244, 102, 143, 54, 65, 25, 63, 161,
    1, 216, 80, 73, 209, 76, 132, 187, 208, 89, 18, 169, 200, 196, 135, 130,
    116, 188, 159, 86, 164, 100, 109, 198, 173, 186, 3, 64, 52, 217, 226, 250,
    124, 123, 5, 202, 38, 147, 118, 126, 255, 82, 85, 212, 207, 206, 59, 227,
    47, 16, 58, 17, 182, 189, 28, 42, 223, 183, 170, 213, 119, 248, 152, 2, 44,
    154, 163, 70, 221, 153, 101, 155, 167, 43, 172, 9, 129, 22, 39, 253, 19, 98,
    108, 110, 79, 113, 224, 232, 178, 185, 112, 104, 218, 246, 97, 228, 251, 34,
    242, 193, 238, 210, 144, 12, 191, 179, 162, 241, 81, 51, 145, 235, 249, 14,
    239, 107, 49, 192, 214, 31, 181, 199, 106, 157, 184, 84, 204, 176, 115, 121,
    50, 45, 127, 4, 150, 254, 138, 236, 205, 93, 222, 114, 67, 29, 24, 72, 243,
    141, 128, 195, 78, 66, 215, 61, 156, 180
]

private struct HeatmapLargeNoise {
    /// The permutation table doubled to 512 so `perlin2` never has to wrap its indices.
    private var perm = [Int](repeating: 0, count: 512)
    private var gradP = [HeatmapLargeGrad](repeating: heatmapLargeGrad3[0], count: 512)

    init(seed s: Double) { self.seed(s) }

    /// Upstream `seed(seed)`. Supports 2^16 distinct seeds; a fractional seed is scaled out.
    /// The `|`/`>>`/`&` below are JS bitwise ops — i.e. int32 — hence the Int32 coercion.
    /// (Safe here: the only caller passes the literal `heatmapLargeSeed`.)
    mutating func seed(_ s: Double) {
        var scaled = s
        if scaled > 0 && scaled < 1 { scaled *= 65536 }   // scale the seed out
        var value = Int32(scaled.rounded(.down))
        if value < 256 { value |= value << 8 }
        for i in 0..<256 {
            let v = (i & 1) != 0
                ? heatmapLargePermutation[i] ^ (Int(value) & 255)
                : heatmapLargePermutation[i] ^ ((Int(value) >> 8) & 255)
            perm[i] = v
            perm[i + 256] = v
            gradP[i] = heatmapLargeGrad3[v % 12]
            gradP[i + 256] = heatmapLargeGrad3[v % 12]
        }
    }

    private func fade(_ t: Double) -> Double { t * t * t * (t * (t * 6 - 15) + 10) }
    private func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { (1 - t) * a + t * b }

    /// Upstream `perlin2(x, y)`: 2-D Perlin noise, roughly in [-0.7, 0.7].
    func perlin2(_ px: Double, _ py: Double) -> Double {
        // Unit grid cell containing the point, then the point's offset within that cell.
        var X = Int(px.rounded(.down))
        var Y = Int(py.rounded(.down))
        let x = px - Double(X)
        let y = py - Double(Y)
        X = X & 255   // wrap the integer cells at 255
        Y = Y & 255
        // Noise contributions from the cell's four corners.
        let n00 = gradP[X + perm[Y]].dot2(x, y)
        let n01 = gradP[X + perm[Y + 1]].dot2(x, y - 1)
        let n10 = gradP[X + 1 + perm[Y]].dot2(x - 1, y)
        let n11 = gradP[X + 1 + perm[Y + 1]].dot2(x - 1, y - 1)
        let u = fade(x)
        return lerp(lerp(n00, n10, u), lerp(n01, n11, u), fade(y))
    }
}

// MARK: - the upstream `generateData(2, -5, 5)`, ported

/// Upstream seeds with `Math.random()`; both panes here use this constant instead (DEVIATION 2).
private let heatmapLargeSeed = 0.42

/// `data` (20,301 `[i, j, value]` triples) plus the two category axes, built in one pass.
/// `theta` / `min` / `max` are dead upstream — the normal-distribution variant is commented out —
/// so the port drops them and keeps only the perlin branch that actually runs.
private let heatmapLargeGenerated: (data: [[Double]], xData: [Double], yData: [Double]) = {
    let noise = HeatmapLargeNoise(seed: heatmapLargeSeed)
    var data: [[Double]] = []
    var xData: [Double] = []
    var yData: [Double] = []
    data.reserveCapacity(201 * 101)
    xData.reserveCapacity(201)
    yData.reserveCapacity(100)

    for i in 0...200 {
        for j in 0...100 {
            data.append([Double(i), Double(j),
                         noise.perlin2(Double(i) / 40, Double(j) / 20) + 0.5])
        }
        xData.append(Double(i))
    }
    // NOTE: 0..<100, not 0...100 — the upstream off-by-one against `data`'s j loop (DEVIATION 4).
    for j in 0..<100 { yData.append(Double(j)) }

    return (data, xData, yData)
}()

private let heatmapLargeData: [[Double]] = heatmapLargeGenerated.data
private let heatmapLargeXData: [Double] = heatmapLargeGenerated.xData
private let heatmapLargeYData: [Double] = heatmapLargeGenerated.yData

/// The visualMap's 11-stop colour ramp.
private let heatmapLargeColors: [String] = [
    "#313695", "#4575b4", "#74add1", "#abd9e9", "#e0f3f8", "#ffffbf",
    "#fee090", "#fdae61", "#f46d43", "#d73027", "#a50026"
]

// MARK: - demo

extension EChartsDemoRegistry {
    static let official_heatmap_large = EChartsDemo(
        name: "official-heatmap-large", category: "heatmap",
        summary: "热力图 - 2w 数据 — Heatmap - 20K data",
        width: 640, height: 420,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
let noise = getNoiseHelper();
let xData = [];
let yData = [];
// Upstream: noise.seed(Math.random()) — pinned so both panes render the same field.
noise.seed(0.42);
function generateData(theta, min, max) {
  let data = [];
  for (let i = 0; i <= 200; i++) {
    for (let j = 0; j <= 100; j++) {
      // let x = (max - min) * i / 200 + min;
      // let y = (max - min) * j / 100 + min;
      data.push([i, j, noise.perlin2(i / 40, j / 20) + 0.5]);
      // data.push([i, j, normalDist(theta, x) * normalDist(theta, y)]);
    }
    xData.push(i);
  }
  for (let j = 0; j < 100; j++) {
    yData.push(j);
  }
  return data;
}
let data = generateData(2, -5, 5);

option = {
  tooltip: {},
  xAxis: {
    type: 'category',
    data: xData
  },
  yAxis: {
    type: 'category',
    data: yData
  },
  visualMap: {
    min: 0,
    max: 1,
    calculable: true,
    realtime: false,
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
  series: [
    {
      name: 'Gaussian',
      type: 'heatmap',
      data: data,
      emphasis: {
        itemStyle: {
          borderColor: '#333',
          borderWidth: 1
        }
      },
      progressive: 1000,
      animation: false
    }
  ]
};
///////////////////////////////////////////////////////////////////////////
// perlin noise helper from https://github.com/josephg/noisejs
///////////////////////////////////////////////////////////////////////////
function getNoiseHelper() {
  class Grad {
    constructor(x, y, z) {
      this.x = x;
      this.y = y;
      this.z = z;
    }

    dot2(x, y) {
      return this.x * x + this.y * y;
    }

    dot3(x, y, z) {
      return this.x * x + this.y * y + this.z * z;
    }
  }

  const grad3 = [
    new Grad(1, 1, 0),
    new Grad(-1, 1, 0),
    new Grad(1, -1, 0),
    new Grad(-1, -1, 0),
    new Grad(1, 0, 1),
    new Grad(-1, 0, 1),
    new Grad(1, 0, -1),
    new Grad(-1, 0, -1),
    new Grad(0, 1, 1),
    new Grad(0, -1, 1),
    new Grad(0, 1, -1),
    new Grad(0, -1, -1)
  ];
  const p = [
    151, 160, 137, 91, 90, 15, 131, 13, 201, 95, 96, 53, 194, 233, 7, 225, 140,
    36, 103, 30, 69, 142, 8, 99, 37, 240, 21, 10, 23, 190, 6, 148, 247, 120,
    234, 75, 0, 26, 197, 62, 94, 252, 219, 203, 117, 35, 11, 32, 57, 177, 33,
    88, 237, 149, 56, 87, 174, 20, 125, 136, 171, 168, 68, 175, 74, 165, 71,
    134, 139, 48, 27, 166, 77, 146, 158, 231, 83, 111, 229, 122, 60, 211, 133,
    230, 220, 105, 92, 41, 55, 46, 245, 40, 244, 102, 143, 54, 65, 25, 63, 161,
    1, 216, 80, 73, 209, 76, 132, 187, 208, 89, 18, 169, 200, 196, 135, 130,
    116, 188, 159, 86, 164, 100, 109, 198, 173, 186, 3, 64, 52, 217, 226, 250,
    124, 123, 5, 202, 38, 147, 118, 126, 255, 82, 85, 212, 207, 206, 59, 227,
    47, 16, 58, 17, 182, 189, 28, 42, 223, 183, 170, 213, 119, 248, 152, 2, 44,
    154, 163, 70, 221, 153, 101, 155, 167, 43, 172, 9, 129, 22, 39, 253, 19, 98,
    108, 110, 79, 113, 224, 232, 178, 185, 112, 104, 218, 246, 97, 228, 251, 34,
    242, 193, 238, 210, 144, 12, 191, 179, 162, 241, 81, 51, 145, 235, 249, 14,
    239, 107, 49, 192, 214, 31, 181, 199, 106, 157, 184, 84, 204, 176, 115, 121,
    50, 45, 127, 4, 150, 254, 138, 236, 205, 93, 222, 114, 67, 29, 24, 72, 243,
    141, 128, 195, 78, 66, 215, 61, 156, 180
  ];
  // To remove the need for index wrapping, double the permutation table length
  let perm = new Array(512);
  let gradP = new Array(512);
  // This isn't a very good seeding function, but it works ok. It supports 2^16
  // different seed values. Write something better if you need more seeds.
  function seed(seed) {
    if (seed > 0 && seed < 1) {
      // Scale the seed out
      seed *= 65536;
    }
    seed = Math.floor(seed);
    if (seed < 256) {
      seed |= seed << 8;
    }
    for (let i = 0; i < 256; i++) {
      let v;
      if (i & 1) {
        v = p[i] ^ (seed & 255);
      } else {
        v = p[i] ^ ((seed >> 8) & 255);
      }
      perm[i] = perm[i + 256] = v;
      gradP[i] = gradP[i + 256] = grad3[v % 12];
    }
  }
  seed(0);
  // ##### Perlin noise stuff
  function fade(t) {
    return t * t * t * (t * (t * 6 - 15) + 10);
  }
  function lerp(a, b, t) {
    return (1 - t) * a + t * b;
  }
  // 2D Perlin Noise
  function perlin2(x, y) {
    // Find unit grid cell containing point
    let X = Math.floor(x),
      Y = Math.floor(y);
    // Get relative xy coordinates of point within that cell
    x = x - X;
    y = y - Y;
    // Wrap the integer cells at 255 (smaller integer period can be introduced here)
    X = X & 255;
    Y = Y & 255;
    // Calculate noise contributions from each of the four corners
    let n00 = gradP[X + perm[Y]].dot2(x, y);
    let n01 = gradP[X + perm[Y + 1]].dot2(x, y - 1);
    let n10 = gradP[X + 1 + perm[Y]].dot2(x - 1, y);
    let n11 = gradP[X + 1 + perm[Y + 1]].dot2(x - 1, y - 1);
    // Compute the fade curve value for x
    let u = fade(x);
    // Interpolate the four results
    return lerp(lerp(n00, n10, u), lerp(n01, n11, u), fade(y));
  }

  return {
    seed,
    perlin2
  };
}
"""#,
        option: [
            "tooltip": [:] as [String: Any],
            "xAxis": [
                "type": "category",
                "data": heatmapLargeXData
            ] as [String: Any],
            "yAxis": [
                "type": "category",
                "data": heatmapLargeYData
            ] as [String: Any],
            "visualMap": [
                "min": 0.0,
                "max": 1.0,
                "calculable": true,
                "realtime": false,
                "inRange": [
                    "color": heatmapLargeColors
                ] as [String: Any]
            ] as [String: Any],
            "series": [
                [
                    "name": "Gaussian",
                    "type": "heatmap",
                    "data": heatmapLargeData,
                    "emphasis": [
                        "itemStyle": [
                            "borderColor": "#333",
                            "borderWidth": 1.0
                        ] as [String: Any]
                    ] as [String: Any],
                    "progressive": 1000.0,
                    "animation": false
                ] as [String: Any]
            ]
        ])
}
