// official-line-polar2 — replica of https://echarts.apache.org/examples/zh/editor.html?c=line-polar2
// title: Two Value-Axes in Polar / titleCN: 极坐标双数值轴
// A line series on a polar coordinate system whose BOTH axes are numeric: angleAxis is
// `type: 'value'` (startAngle 0) and radiusAxis is a value axis clamped to `min: 0`. The 361 data
// points are [radius, angle] pairs of r = sin(2t)·cos(2t) sampled at every whole degree, which draws
// the four-petal rose (the negative half of r is clipped away by `radiusAxis.min: 0`).
// DEVIATIONS:
//   - The official source builds `data` with a `for` loop. The web pane keeps that loop VERBATIM
//     (minus the TS type annotation on `const data`, which is a SyntaxError in a classic script);
//     the native pane computes the identical 361 points in `linePolar2Data`.
//   - `export {};` dropped (bare export kills a classic script).
//   - `animationDuration: 2000` is carried in both panes but is inert: the gallery renders one
//     static frame and the web page force-disables animation.

import Foundation   // sin/cos for the generated rose data

extension EChartsDemoRegistry {
    static let official_line_polar2 = EChartsDemo(
        name: "official-line-polar2", category: "line",
        summary: "极坐标双数值轴 — Two Value-Axes in Polar",
        width: 640, height: 420,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
const data = [];

for (let i = 0; i <= 360; i++) {
  let t = (i / 180) * Math.PI;
  let r = Math.sin(2 * t) * Math.cos(2 * t);
  data.push([r, i]);
}

option = {
  title: {
    text: 'Two Value-Axes in Polar'
  },
  legend: {
    data: ['line']
  },
  polar: {
    center: ['50%', '54%']
  },
  tooltip: {
    trigger: 'axis',
    axisPointer: {
      type: 'cross'
    }
  },
  angleAxis: {
    type: 'value',
    startAngle: 0
  },
  radiusAxis: {
    min: 0
  },
  series: [
    {
      coordinateSystem: 'polar',
      name: 'line',
      type: 'line',
      showSymbol: false,
      data: data
    }
  ],
  animationDuration: 2000
};
"""#,
        option: [
            "title": [
                "text": "Two Value-Axes in Polar"
            ] as [String: Any],
            "legend": [
                "data": ["line"]
            ] as [String: Any],
            "polar": [
                "center": ["50%", "54%"]
            ] as [String: Any],
            "tooltip": [
                "trigger": "axis",
                "axisPointer": [
                    "type": "cross"
                ] as [String: Any]
            ] as [String: Any],
            "angleAxis": [
                "type": "value",
                "startAngle": 0.0
            ] as [String: Any],
            "radiusAxis": [
                "min": 0.0
            ] as [String: Any],
            "series": [
                [
                    "coordinateSystem": "polar",
                    "name": "line",
                    "type": "line",
                    "showSymbol": false,
                    "data": linePolar2Data
                ] as [String: Any]
            ],
            "animationDuration": 2000.0
        ])
}

// [radius, angle] for every whole degree in 0...360, r = sin(2t)·cos(2t) with t = i/180·π —
// the same loop the official source runs in JS.
private let linePolar2Data: [[Double]] = (0...360).map { i -> [Double] in
    let t = (Double(i) / 180.0) * Double.pi
    let r = sin(2 * t) * cos(2 * t)
    return [r, Double(i)]
}
