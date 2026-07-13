// official-line-polar — replica of https://echarts.apache.org/examples/zh/editor.html?c=line-polar
// title: Two Value-Axes in Polar / titleCN: 极坐标双数值轴
// A cardioid (r = 5·(1 + sin θ)) drawn as a `line` series on a polar coord system whose angleAxis AND
// radiusAxis are both `value` axes; the data points are [radius, angle] pairs. Cross axisPointer.
// DEVIATIONS from the official source:
//   - The source is TypeScript; webOptionJS drops the `const data: number[][]` type annotation and the
//     trailing `export {};` (a bare export is a SyntaxError in the gallery's classic script tag). The
//     generating for-loop itself is verbatim, so the reference pane computes the same 101 points.
//   - The native pane cannot run that loop inside a Swift option literal, so `linePolarData` computes
//     the identical points in Swift (same formula, same order). No values were hand-copied.
//   - No closures, no data fetch, no timers in the original — nothing else omitted.
import Foundation

extension EChartsDemoRegistry {
    static let official_line_polar = EChartsDemo(
        name: "official-line-polar", category: "line",
        summary: "极坐标双数值轴 — Two Value-Axes in Polar",
        width: 640, height: 420,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
const data = [];

for (let i = 0; i <= 100; i++) {
  let theta = (i / 100) * 360;
  let r = 5 * (1 + Math.sin((theta / 180) * Math.PI));
  data.push([r, theta]);
}

option = {
  title: {
    text: 'Two Value-Axes in Polar'
  },
  legend: {
    data: ['line']
  },
  polar: {},
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
  radiusAxis: {},
  series: [
    {
      coordinateSystem: 'polar',
      name: 'line',
      type: 'line',
      data: data
    }
  ]
};
"""#,
        option: [
            "title": [
                "text": "Two Value-Axes in Polar"
            ] as [String: Any],
            "legend": [
                "data": ["line"]
            ] as [String: Any],
            "polar": [:] as [String: Any],
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
            "radiusAxis": [:] as [String: Any],
            "series": [
                [
                    "coordinateSystem": "polar",
                    "name": "line",
                    "type": "line",
                    "data": linePolarData
                ] as [String: Any]
            ]
        ])
}

// The official example's generating loop, in Swift: 101 samples of the cardioid r = 5·(1 + sin θ),
// θ sweeping 0…360°, emitted as [radius, angle] pairs (the order a polar `line` series expects).
private let linePolarData: [[Double]] = (0...100).map { i -> [Double] in
    let theta = (Double(i) / 100.0) * 360.0
    let r = 5.0 * (1.0 + sin((theta / 180.0) * Double.pi))
    return [r, theta]
}
