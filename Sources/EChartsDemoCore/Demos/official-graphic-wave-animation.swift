// official-graphic-wave-animation — replica of
// https://echarts.apache.org/examples/zh/editor.html?c=graphic-wave-animation
// title: Wave Animation / titleCN: 波浪动画
//
// A chart with no series or axes: a 40-point-spaced field of circles fills the canvas. Each circle
// loops through a 4s `keyframeAnimation`, shrinking from radius 22 to the equivalent of radius 5 and
// fading from black to white before expanding back to black. A 2-D Perlin-noise field supplies each
// circle's negative delay, so the phase offset travels across the grid like a wave.
//
// DEVIATIONS from the official source:
//   - The official `noise.seed(Math.random())` is pinned to 0.42 in both panes. Independent random
//     seeds would give Native and Web different phase fields, making a visual comparison meaningless.
//   - The trailing `export {}` is removed from `webOptionJS`; the gallery runs a classic script, where
//     a bare module export is a syntax error.
//   - The editor-only `app.config` controls are kept in the Web source but have no controls in this
//     gallery. The native option therefore carries their initial values (frequency 500, offsets
//     0/100, sizes 5/22, duration 4000, black on white).
//   - The native pane builds the grid from this demo's fixed 640x420 logical canvas, matching the
//     values returned by `myChart.getWidth()` / `getHeight()` in the Web pane.

import Foundation

private let graphicWaveWidth = 640.0
private let graphicWaveHeight = 420.0
private let graphicWaveSeed = 0.42

private struct GraphicWaveGrad {
    let x: Double
    let y: Double

    func dot2(_ x: Double, _ y: Double) -> Double {
        self.x * x + self.y * y
    }
}

private let graphicWaveGrad3: [GraphicWaveGrad] = [
    GraphicWaveGrad(x: 1, y: 1), GraphicWaveGrad(x: -1, y: 1),
    GraphicWaveGrad(x: 1, y: -1), GraphicWaveGrad(x: -1, y: -1),
    GraphicWaveGrad(x: 1, y: 0), GraphicWaveGrad(x: -1, y: 0),
    GraphicWaveGrad(x: 1, y: 0), GraphicWaveGrad(x: -1, y: 0),
    GraphicWaveGrad(x: 0, y: 1), GraphicWaveGrad(x: 0, y: -1),
    GraphicWaveGrad(x: 0, y: 1), GraphicWaveGrad(x: 0, y: -1)
]

private let graphicWavePermutation: [Int] = [
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

private struct GraphicWaveNoise {
    private var perm = [Int](repeating: 0, count: 512)
    private var gradP = [GraphicWaveGrad](repeating: graphicWaveGrad3[0], count: 512)

    init(seed: Double) {
        var scaled = seed
        if scaled > 0 && scaled < 1 { scaled *= 65_536 }
        var value = Int32(scaled.rounded(.down))
        if value < 256 { value |= value << 8 }

        for i in 0..<256 {
            let v = (i & 1) != 0
                ? graphicWavePermutation[i] ^ (Int(value) & 255)
                : graphicWavePermutation[i] ^ ((Int(value) >> 8) & 255)
            perm[i] = v
            perm[i + 256] = v
            gradP[i] = graphicWaveGrad3[v % 12]
            gradP[i + 256] = graphicWaveGrad3[v % 12]
        }
    }

    private func fade(_ t: Double) -> Double {
        t * t * t * (t * (t * 6 - 15) + 10)
    }

    private func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
        (1 - t) * a + t * b
    }

    func perlin2(_ px: Double, _ py: Double) -> Double {
        var xCell = Int(px.rounded(.down))
        var yCell = Int(py.rounded(.down))
        let x = px - Double(xCell)
        let y = py - Double(yCell)
        xCell &= 255
        yCell &= 255

        let n00 = gradP[xCell + perm[yCell]].dot2(x, y)
        let n01 = gradP[xCell + perm[yCell + 1]].dot2(x, y - 1)
        let n10 = gradP[xCell + 1 + perm[yCell]].dot2(x - 1, y)
        let n11 = gradP[xCell + 1 + perm[yCell + 1]].dot2(x - 1, y - 1)
        let u = fade(x)
        return lerp(lerp(n00, n10, u), lerp(n01, n11, u), fade(y))
    }
}

private let graphicWaveElements: [[String: Any]] = {
    let noise = GraphicWaveNoise(seed: graphicWaveSeed)
    var elements: [[String: Any]] = []

    var x = 20.0
    while x < graphicWaveWidth {
        var y = 20.0
        while y < graphicWaveHeight {
            let randomPhase = noise.perlin2(x / 500.0, y / 500.0 + 100.0)
            elements.append([
                "type": "circle",
                "x": x,
                "y": y,
                "style": ["fill": "#000"] as [String: Any],
                "shape": ["r": 22.0] as [String: Any],
                "keyframeAnimation": [
                    "duration": 4_000.0,
                    "loop": true,
                    "delay": (randomPhase - 1) * 4_000.0,
                    "keyframes": [
                        [
                            "percent": 0.5,
                            "easing": "sinusoidalInOut",
                            "style": ["fill": "#fff"] as [String: Any],
                            "scaleX": 5.0 / 22.0,
                            "scaleY": 5.0 / 22.0
                        ] as [String: Any],
                        [
                            "percent": 1.0,
                            "easing": "sinusoidalInOut",
                            "style": ["fill": "#000"] as [String: Any],
                            "scaleX": 1.0,
                            "scaleY": 1.0
                        ] as [String: Any]
                    ]
                ] as [String: Any]
            ])
            y += 40
        }
        x += 40
    }

    return elements
}()

extension EChartsDemoRegistry {
    static let official_graphic_wave_animation = EChartsDemo(
        name: "official-graphic-wave-animation", category: "graphic",
        summary: "波浪动画 — Wave Animation",
        width: graphicWaveWidth, height: graphicWaveHeight,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
let noise = getNoiseHelper();

let config = (app.config = {
  frequency: 500,
  offsetX: 0,
  offsetY: 100,

  minSize: 5,
  maxSize: 22,

  duration: 4000,

  color0: '#fff',
  color1: '#000',
  backgroundColor: '#fff',

  onChange() {
    myChart.setOption({
      backgroundColor: config.backgroundColor,
      graphic: {
        elements: createElements()
      }
    });
  }
});

// Upstream: noise.seed(Math.random()) — pinned for deterministic Native/Web parity.
noise.seed(0.42);

function createElements() {
  const elements = [];
  for (let x = 20; x < myChart.getWidth(); x += 40) {
    for (let y = 20; y < myChart.getHeight(); y += 40) {
      const rand = noise.perlin2(
        x / config.frequency + config.offsetX,
        y / config.frequency + config.offsetY
      );
      elements.push({
        type: 'circle',
        x,
        y,
        style: {
          fill: config.color1
        },
        shape: {
          r: config.maxSize
        },
        keyframeAnimation: {
          duration: config.duration,
          loop: true,
          delay: (rand - 1) * 4000,
          keyframes: [
            {
              percent: 0.5,
              easing: 'sinusoidalInOut',
              style: {
                fill: config.color0
              },
              scaleX: config.minSize / config.maxSize,
              scaleY: config.minSize / config.maxSize
            },
            {
              percent: 1,
              easing: 'sinusoidalInOut',
              style: {
                fill: config.color1
              },
              scaleX: 1,
              scaleY: 1
            }
          ]
        }
      });
    }
  }
  return elements;
}

option = {
  backgroundColor: config.backgroundColor,
  graphic: {
    elements: createElements()
  }
};

app.configParameters = {
  frequency: { min: 10, max: 1000 },
  offsetX: { min: 0, max: 1000 },
  offsetY: { min: 0, max: 1000 },
  minSize: { min: 0, max: 100 },
  maxSize: { min: 0, max: 100 },
  duration: { min: 100, max: 100000 }
};

///////////////////////////////////////////////////////////////////////////
// Simplex and perlin noise helper from https://github.com/josephg/noisejs
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
  let perm = new Array(512);
  let gradP = new Array(512);

  function seed(seed) {
    if (seed > 0 && seed < 1) {
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

  function fade(t) {
    return t * t * t * (t * (t * 6 - 15) + 10);
  }

  function lerp(a, b, t) {
    return (1 - t) * a + t * b;
  }

  function perlin2(x, y) {
    let X = Math.floor(x),
      Y = Math.floor(y);
    x = x - X;
    y = y - Y;
    X = X & 255;
    Y = Y & 255;
    let n00 = gradP[X + perm[Y]].dot2(x, y);
    let n01 = gradP[X + perm[Y + 1]].dot2(x, y - 1);
    let n10 = gradP[X + 1 + perm[Y]].dot2(x - 1, y);
    let n11 = gradP[X + 1 + perm[Y + 1]].dot2(x - 1, y - 1);
    let u = fade(x);
    return lerp(lerp(n00, n10, u), lerp(n01, n11, u), fade(y));
  }

  return {
    seed,
    perlin2
  };
}
"""#,
        option: [
            "backgroundColor": "#fff",
            "graphic": [
                "elements": graphicWaveElements
            ] as [String: Any]
        ]
    )
}
