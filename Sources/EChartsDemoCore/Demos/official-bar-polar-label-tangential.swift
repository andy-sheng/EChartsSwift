// official-bar-polar-label-tangential — replica of
// https://echarts.apache.org/examples/zh/editor.html?c=bar-polar-label-tangential
// title: Tangential Polar Bar Label Position / titleCN: 极坐标柱状图标签
// Four bars on a polar coordinate system (category radiusAxis, value angleAxis capped at max 4,
// startAngle 75), each labelled in the middle of its bar via the '{b}: {c}' template — the label
// rides tangentially along the bar.
// DEVIATIONS from the official source:
//   - None of substance. The example is a single static `option` literal — no data fetch, no timers,
//     no closures — so both panes carry it verbatim; only the trailing `export {}` is dropped (a bare
//     export is a SyntaxError in the reference pane's classic script).
//   - `label.formatter` is a STRING template ('{b}: {c}'), not a JS function, so the native pane
//     carries it as-is; nothing is omitted. `series` stays a single object, not an array, exactly as
//     upstream: GlobalModel normalizes a lone option bag (`normalizeToComponentOptionList`).
extension EChartsDemoRegistry {
    static let official_bar_polar_label_tangential = EChartsDemo(
        name: "official-bar-polar-label-tangential", category: "bar",
        summary: "极坐标柱状图标签 — Tangential Polar Bar Label Position",
        width: 640, height: 420,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
option = {
  title: [
    {
      text: 'Tangential Polar Bar Label Position (middle)'
    }
  ],
  polar: {
    radius: [30, '80%']
  },
  angleAxis: {
    max: 4,
    startAngle: 75
  },
  radiusAxis: {
    type: 'category',
    data: ['a', 'b', 'c', 'd']
  },
  tooltip: {},
  series: {
    type: 'bar',
    data: [2, 1.2, 2.4, 3.6],
    coordinateSystem: 'polar',
    label: {
      show: true,
      position: 'middle', // or 'start', 'insideStart', 'end', 'insideEnd'
      formatter: '{b}: {c}'
    }
  }
};
"""#,
        option: [
            "title": [
                [
                    "text": "Tangential Polar Bar Label Position (middle)"
                ] as [String: Any]
            ],
            "polar": [
                "radius": [30.0, "80%"] as [Any]
            ] as [String: Any],
            "angleAxis": [
                "max": 4.0,
                "startAngle": 75.0
            ] as [String: Any],
            "radiusAxis": [
                "type": "category",
                "data": ["a", "b", "c", "d"]
            ] as [String: Any],
            "tooltip": [:] as [String: Any],
            "series": [
                "type": "bar",
                "data": [2.0, 1.2, 2.4, 3.6],
                "coordinateSystem": "polar",
                "label": [
                    "show": true,
                    // or 'start', 'insideStart', 'end', 'insideEnd'
                    "position": "middle",
                    "formatter": "{b}: {c}"
                ] as [String: Any]
            ] as [String: Any]
        ])
}
