// official-scatter-large — replica of https://echarts.apache.org/examples/zh/editor.html?c=scatter-large
// title: Large Scatter / titleCN: 大规模散点图
// Two `large: true` scatter series over a cartesian grid — a randomly generated sin(x) cloud, one series
// offset +1 in y — with a vertical legend, `dataZoom` (inside + slider), a toolbox dataZoom feature and
// `animation: false`. The point is the LARGE fast path (LargeSymbolDraw: one path for every point).
//
// DEVIATIONS:
//   - webOptionJS is the official source VERBATIM, minus the TS type annotations on `genData` and the
//     trailing `export {};` (a bare export is a SyntaxError in the page's classic script). It keeps the
//     real 5e5 + 5e5 points, the Float32Array flat data, and `echarts.format.addCommas` in the title.
//   - The NATIVE pane cannot carry `genData` (a JS closure) or a Float32Array, so the data is
//     regenerated in Swift by `scatterLargeGenData`, a line-for-line mirror of `genData` with a
//     deterministic LCG standing in for `Math.random()`. The two panes' clouds are therefore
//     statistically identical but never point-identical — the upstream example is random, so no port of
//     it can be pixel-comparable.
//   - The native point count is reduced 5e5 -> 2e4 PER SERIES (still far past `largeThreshold` 2000, so
//     the large path is what renders). 1e6 boxed points through the Swift option/model path costs
//     minutes in the headless render sweep for no extra signal; the sin-band cloud reads the same.
//     The title text follows the reduced count ("40,000 Points") rather than "1,000,000 Points".
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
function genData(len, offset) {
  let arr = new Float32Array(len * 2);
  let off = 0;

  for (let i = 0; i < len; i++) {
    let x = +Math.random() * 10;
    let y =
      +Math.sin(x) -
      x * (len % 2 ? 0.1 : -0.1) * Math.random() +
      (offset || 0) / 10;
    arr[off++] = x;
    arr[off++] = y;
  }
  return arr;
}

const data1 = genData(5e5);
const data2 = genData(5e5, 10);

option = {
  title: {
    text:
      echarts.format.addCommas(data1.length / 2 + data2.length / 2) + ' Points'
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
                    "large": true
                ] as [String: Any],
                [
                    "name": "B",
                    "type": "scatter",
                    "data": scatterLargeData2,
                    "dimensions": ["x", "y"],
                    "symbolSize": 3.0,
                    "itemStyle": ["opacity": 0.4] as [String: Any],
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
