// official-scatter-large — replica of https://echarts.apache.org/examples/zh/editor.html?c=scatter-large
// title: Large Scatter / titleCN: 大规模散点图
// Two `large: true` scatter series over a cartesian grid — a randomly generated sin(x) cloud, one series
// offset +1 in y — with a vertical legend, `dataZoom` (inside + slider), a toolbox dataZoom feature and
// `animation: false`. The point is the LARGE fast path (LargeSymbolDraw: one path for every point).
//
// DEVIATIONS:
//   - Both panes use the same deterministic 64-bit LCG instead of `Math.random()`, making the random
//     example screenshot-comparable.
//   - The point count is reduced 5e5 -> 2e4 PER SERIES (still far past `largeThreshold` 2000, so
//     the large path is what renders). 1e6 boxed points through the Swift option/model path costs
//     minutes in the headless render sweep for no extra signal; the sin-band cloud reads the same.
//     Both panes' title follows the reduced count ("40,000 Points").
//   - toolbox/dataZoom are interactive; the gallery snapshots one static frame of their initial state.
import Foundation

extension EChartsDemoRegistry {
    static let official_scatter_large = EChartsDemo(
        name: "official-scatter-large", category: "scatter",
        summary: "大规模散点图 — Large Scatter",
        width: 640, height: 420,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
function genData(len, offset, seed) {
  const mask64 = (1n << 64n) - 1n;
  let state = seed;
  function random() {
    state = (state * 6364136223846793005n + 1442695040888963407n) & mask64;
    return Number(state >> 11n) / 9007199254740992;
  }
  let arr = [];

  for (let i = 0; i < len; i++) {
    let x = random() * 10;
    let y =
      +Math.sin(x) -
      x * (len % 2 ? 0.1 : -0.1) * random() +
      (offset || 0) / 10;
    arr.push([x, y]);
  }
  return arr;
}

const data1 = genData(2e4, 0, 0x9E3779B97F4A7C15n);
const data2 = genData(2e4, 10, 0xD1B54A32D192ED03n);

option = {
  title: {
    text:
      echarts.format.addCommas(data1.length + data2.length) + ' Points'
  },
  tooltip: {},
  toolbox: {
    left: 'center',
    feature: {
      dataZoom: {}
    }
  },
  legend: {
    orient: 'vertical',
    right: 10
  },
  xAxis: [{}],
  yAxis: [{}],
  dataZoom: [
    {
      type: 'inside'
    },
    {
      type: 'slider'
    }
  ],
  animation: false,
  series: [
    {
      name: 'A',
      type: 'scatter',
      data: data1,
      dimensions: ['x', 'y'],
      symbolSize: 3,
      itemStyle: {
        opacity: 0.4
      },
      progressive: 0,
      large: true
    },
    {
      name: 'B',
      type: 'scatter',
      data: data2,
      dimensions: ['x', 'y'],
      symbolSize: 3,
      itemStyle: {
        opacity: 0.4
      },
      progressive: 0,
      large: true
    }
  ]
};
"""#,
        option: [
            "title": [
                // PORT-NOTE: upstream computes this as
                //   echarts.format.addCommas(data1.length / 2 + data2.length / 2) + ' Points'
                // — a JS call over the live data. Inlined here for the native (reduced) point count.
                "text": "40,000 Points"
            ] as [String: Any],
            "tooltip": [:] as [String: Any],
            "toolbox": [
                "left": "center",
                "feature": [
                    "dataZoom": [:] as [String: Any]
                ] as [String: Any]
            ] as [String: Any],
            "legend": [
                "orient": "vertical",
                "right": 10.0
            ] as [String: Any],
            "xAxis": [[:] as [String: Any]],
            "yAxis": [[:] as [String: Any]],
            "dataZoom": [
                ["type": "inside"] as [String: Any],
                ["type": "slider"] as [String: Any]
            ],
            "animation": false,
            "series": [
                [
                    "name": "A",
                    "type": "scatter",
                    "data": scatterLargeData1,
                    "dimensions": ["x", "y"],
                    "symbolSize": 3.0,
                    "itemStyle": ["opacity": 0.4] as [String: Any],
                    "progressive": 0.0,
                    "large": true
                ] as [String: Any],
                [
                    "name": "B",
                    "type": "scatter",
                    "data": scatterLargeData2,
                    "dimensions": ["x", "y"],
                    "symbolSize": 3.0,
                    "itemStyle": ["opacity": 0.4] as [String: Any],
                    "progressive": 0.0,
                    "large": true
                ] as [String: Any]
            ]
        ])
}

// Native point count per series (upstream: 5e5). See the DEVIATIONS note in the header.
private let scatterLargePointCount = 20_000

/// Mirror of the example's `genData(len, offset)`. Upstream draws from `Math.random()`; Swift has no
/// seedable stdlib RNG, so a plain 64-bit LCG stands in — the cloud is the same distribution, and it is
/// deterministic, so the native snapshot is stable across runs.
/// Upstream returns a flat `Float32Array` of x/y pairs; the Swift option carries the same pairs as
/// `[[x, y]]`, which is what the ported SourceManager understands.
private func scatterLargeGenData(_ len: Int, _ offset: Double = 0, seed: UInt64) -> [[Double]] {
    var state = seed
    func random() -> Double {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Double(state >> 11) / Double(1 << 53)   // [0, 1)
    }
    var arr: [[Double]] = []
    arr.reserveCapacity(len)
    for _ in 0..<len {
        // upstream: let x = +Math.random() * 10;
        let x = random() * 10
        // upstream: let y = +Math.sin(x) - x * (len % 2 ? 0.1 : -0.1) * Math.random() + (offset || 0) / 10;
        let y = sin(x) - x * (len % 2 != 0 ? 0.1 : -0.1) * random() + offset / 10
        arr.append([x, y])
    }
    return arr
}

// upstream: const data1 = genData(5e5);
private let scatterLargeData1: [[Double]] = scatterLargeGenData(scatterLargePointCount, seed: 0x9E37_79B9_7F4A_7C15)
// upstream: const data2 = genData(5e5, 10);   (offset 10 -> the whole cloud shifted +1 in y)
private let scatterLargeData2: [[Double]] = scatterLargeGenData(scatterLargePointCount, 10, seed: 0xD1B5_4A32_D192_ED03)
