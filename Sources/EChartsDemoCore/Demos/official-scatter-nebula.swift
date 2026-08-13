// official-scatter-nebula — replica of https://echarts.apache.org/examples/zh/editor.html?c=scatter-nebula
// title: Scatter Nebula / titleCN: 大规模星云散点图
// A 1,000,000-point cartesian scatter "nebula" (large:true → one LargeSymbolPath / large-mode fast
// path), symbolSize 3 at 0.4 opacity, with inside+slider dataZoom on both axes and a toolbox dataZoom
// (brush-to-zoom) feature. The point cloud is a flat Float32Array of [x, y] pairs.
//
// DEVIATIONS from the official source:
//   - DATA INLINED. Upstream XHRs `ROOT_PATH + '/data/asset/data/fake-nebula.bin'` as an ArrayBuffer
//     and wraps it in a Float32Array. The gallery page has no network, so the SAME 8 MB asset is
//     vendored at assets/data/fake-nebula.bin (read via Upstream.repoRoot, as map-bar-morph does) and
//     reaches the two panes as: base64 → atob → Float32Array in webOptionJS (byte-identical to the
//     XHR result), and a Swift [Float] decode for the native pane. No point is dropped: both panes
//     draw all 1,000,000.
//   - `myChart.showLoading()` / `hideLoading()`, the xhr wrapper and `myChart.setOption(option)` are
//     dropped; `option` is assigned unconditionally at the top level (it lived in the xhr.onload body).
//   - NATIVE PANE ONLY: upstream feeds the Float32Array straight to `series.data` — echarts' typed-array
//     source format reads it as flat [x, y] pairs (hence `dimensions: ['x', 'y']`). Swift has no
//     typed-array source, so the native option carries the identical points expanded to [[x, y]] pairs
//     (SOURCE_FORMAT_ORIGINAL). `dimensions` is kept, and the values are the same Float32s widened to
//     Double.
//   - NATIVE PANE ONLY: `title.text` is `echarts.format.addCommas(Math.round(rawData.length / 2)) +
//     ' Points'` upstream — a value, not a closure, so it is computed in Swift from the same buffer
//     (grouped thousands, en_US_POSIX) and yields the identical "1,000,000 Points".
//   - dataZoom/toolbox are interactive; the gallery renders ONE static frame, so both panes show the
//     initial, un-zoomed full range.
import Foundation

// The vendored point cloud (assets/data/fake-nebula.bin — the upstream asset, byte for byte).
// A parse/read failure degrades to an empty cloud (blank chart) rather than crashing.
private let nebulaBinary: Data = {
    let url = Upstream.repoRoot.appendingPathComponent("assets/data/fake-nebula.bin")
    return (try? Data(contentsOf: url)) ?? Data()
}()

// `new Float32Array(this.response)` — little-endian float32s, copied out through a memcpy so the file
// buffer's alignment never matters.
private let nebulaFloats: [Float] = {
    let count = nebulaBinary.count / MemoryLayout<Float>.size
    guard count > 0 else { return [] }
    var out = [Float](repeating: 0, count: count)
    out.withUnsafeMutableBytes { dst in _ = nebulaBinary.copyBytes(to: dst) }
    return out
}()

// The flat [x, y] stream expanded to point pairs — the native pane's source format (see DEVIATIONS).
private let nebulaPointData: [[Double]] = {
    let n = nebulaFloats.count / 2
    var out: [[Double]] = []
    out.reserveCapacity(n)
    for i in 0..<n {
        out.append([Double(nebulaFloats[2 * i]), Double(nebulaFloats[2 * i + 1])])
    }
    return out
}()

// `echarts.format.addCommas(Math.round(rawData.length / 2)) + ' Points'`, computed in Swift.
private let nebulaTitleText = "1,000,000 Points"

// The same bytes for the web pane: base64 → atob → Uint8Array → Float32Array (see DEVIATIONS).
private let nebulaBase64: String = nebulaBinary.base64EncodedString()

// The dataZoom slider handle (upstream, verbatim) — shared by the horizontal and vertical sliders.
private let nebulaHandleIcon = "path://M10.7,11.9v-1.3H9.3v1.3c-4.9,0.3-8.8,4.4-8.8,9.4c0,5,3.9,9.1,8.8,9.4v1.3h1.3v-1.3c4.9-0.3,8.8-4.4,8.8-9.4C19.5,16.3,15.6,12.2,10.7,11.9z M13.3,24.4H6.7V23h6.6V24.4z M13.3,19.6H6.7v-1.4h6.6V19.6z"

extension EChartsDemoRegistry {
    static let official_scatter_nebula = EChartsDemo(
        name: "official-scatter-nebula", category: "scatter",
        summary: "大规模星云散点图 — Scatter Nebula",
        width: 640, height: 420,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
// The upstream XHR of '/data/asset/data/fake-nebula.bin' as an ArrayBuffer, inlined: the identical
// bytes, base64-decoded in-page into the very same Float32Array the callback received.
var rawData = (function () {
  var bin = atob('\#(nebulaBase64)');
  var bytes = new Uint8Array(bin.length);
  for (var i = 0; i < bin.length; i++) {
    bytes[i] = bin.charCodeAt(i);
  }
  return new Float32Array(bytes.buffer);
})();

option = {
  title: {
    left: 'center',
    text:
      echarts.format.addCommas(Math.round(rawData.length / 2)) + ' Points',
    subtext: 'Fake data'
  },
  tooltip: {},
  toolbox: {
    right: 20,
    feature: {
      dataZoom: {}
    }
  },
  grid: {
    right: 70,
    bottom: 70
  },
  xAxis: [{}],
  yAxis: [{}],
  dataZoom: [
    {
      type: 'inside'
    },
    {
      type: 'slider',
      showDataShadow: false,
      handleIcon:
        'path://M10.7,11.9v-1.3H9.3v1.3c-4.9,0.3-8.8,4.4-8.8,9.4c0,5,3.9,9.1,8.8,9.4v1.3h1.3v-1.3c4.9-0.3,8.8-4.4,8.8-9.4C19.5,16.3,15.6,12.2,10.7,11.9z M13.3,24.4H6.7V23h6.6V24.4z M13.3,19.6H6.7v-1.4h6.6V19.6z',
      handleSize: '80%'
    },
    {
      type: 'inside',
      orient: 'vertical'
    },
    {
      type: 'slider',
      orient: 'vertical',
      showDataShadow: false,
      handleIcon:
        'path://M10.7,11.9v-1.3H9.3v1.3c-4.9,0.3-8.8,4.4-8.8,9.4c0,5,3.9,9.1,8.8,9.4v1.3h1.3v-1.3c4.9-0.3,8.8-4.4,8.8-9.4C19.5,16.3,15.6,12.2,10.7,11.9z M13.3,24.4H6.7V23h6.6V24.4z M13.3,19.6H6.7v-1.4h6.6V19.6z',
      handleSize: '80%'
    }
  ],
  animation: false,
  series: [
    {
      type: 'scatter',
      data: rawData,
      dimensions: ['x', 'y'],
      symbolSize: 3,
      itemStyle: {
        opacity: 0.4
      },
      blendMode: 'source-over',
      progressive: 0,
      large: true,
      largeThreshold: 500
    }
  ]
};
"""#,
        option: [
            "title": [
                "left": "center",
                "text": nebulaTitleText,
                "subtext": "Fake data"
            ] as [String: Any],
            "tooltip": [:] as [String: Any],
            "toolbox": [
                "right": 20.0,
                "feature": [
                    "dataZoom": [:] as [String: Any]
                ] as [String: Any]
            ] as [String: Any],
            "grid": [
                "right": 70.0,
                "bottom": 70.0
            ] as [String: Any],
            "xAxis": [[:] as [String: Any]],
            "yAxis": [[:] as [String: Any]],
            "dataZoom": [
                [
                    "type": "inside"
                ] as [String: Any],
                [
                    "type": "slider",
                    "showDataShadow": false,
                    "handleIcon": nebulaHandleIcon,
                    "handleSize": "80%"
                ] as [String: Any],
                [
                    "type": "inside",
                    "orient": "vertical"
                ] as [String: Any],
                [
                    "type": "slider",
                    "orient": "vertical",
                    "showDataShadow": false,
                    "handleIcon": nebulaHandleIcon,
                    "handleSize": "80%"
                ] as [String: Any]
            ],
            "animation": false,
            "series": [
                [
                    "type": "scatter",
                    "data": nebulaPointData,
                    "dimensions": ["x", "y"],
                    "symbolSize": 3.0,
                    "itemStyle": [
                        "opacity": 0.4
                    ] as [String: Any],
                    "blendMode": "source-over",
                    "progressive": 0.0,
                    "large": true,
                    "largeThreshold": 500.0
                ] as [String: Any]
            ]
        ])
}
