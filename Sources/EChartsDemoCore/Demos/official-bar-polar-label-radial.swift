// official-bar-polar-label-radial — replica of https://echarts.apache.org/examples/zh/editor.html?c=bar-polar-label-radial
// title: Radial Polar Bar Label Position / titleCN: 极坐标柱状图标签
// Four bars on a polar coord system (category angleAxis, startAngle 75, radiusAxis max 4, ring radius
// [30, '80%']), each labelled in the MIDDLE of its bar via the string template '{b}: {c}'.
// DEVIATIONS from the official source:
//   - webOptionJS drops only the trailing `export {};` (a bare export is a SyntaxError in the
//     gallery's classic script tag). Everything else — including the inline comment listing the other
//     label positions — is verbatim.
//   - The native option writes `series` as a one-element ARRAY; the source uses the bare-object
//     shorthand, which echarts normalizes to exactly that array. Same for the already-array `title`.
//   - The label formatter is the STRING template '{b}: {c}', not a closure, so the native pane carries
//     it as-is. No data fetch, no timers, nothing omitted.
extension EChartsDemoRegistry {
    static let official_bar_polar_label_radial = EChartsDemo(
        name: "official-bar-polar-label-radial", category: "bar",
        summary: "极坐标柱状图标签 — Radial Polar Bar Label Position",
        width: 640, height: 420,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
option = {
  title: [
    {
      text: 'Radial Polar Bar Label Position (middle)'
    }
  ],
  polar: {
    radius: [30, '80%']
  },
  radiusAxis: {
    max: 4
  },
  angleAxis: {
    type: 'category',
    data: ['a', 'b', 'c', 'd'],
    startAngle: 75
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
  },
  animation: false
};
"""#,
        option: [
            "title": [
                [
                    "text": "Radial Polar Bar Label Position (middle)"
                ] as [String: Any]
            ],
            "polar": [
                "radius": [30.0, "80%"] as [Any]
            ] as [String: Any],
            "radiusAxis": [
                "max": 4.0
            ] as [String: Any],
            "angleAxis": [
                "type": "category",
                "data": ["a", "b", "c", "d"],
                "startAngle": 75.0
            ] as [String: Any],
            "tooltip": [:] as [String: Any],
            "series": [
                [
                    "type": "bar",
                    "data": [2.0, 1.2, 2.4, 3.6],
                    "coordinateSystem": "polar",
                    "label": [
                        "show": true,
                        // 'middle' — or 'start', 'insideStart', 'end', 'insideEnd'.
                        "position": "middle",
                        "formatter": "{b}: {c}"
                    ] as [String: Any]
                ] as [String: Any]
            ],
            "animation": false
        ])
}
