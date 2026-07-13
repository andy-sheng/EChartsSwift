// official-bar-polar-stack-radial — replica of https://echarts.apache.org/examples/zh/editor.html?c=bar-polar-stack-radial
// title: Stacked Bar Chart on Polar(Radial) / titleCN: 极坐标系下的堆叠柱状图
// Three bar series stacked on the same `stack: 'a'` group, drawn on a polar coord system in RADIAL
// mode (angleAxis is the category axis, radiusAxis the value axis), so each weekday is a spoke and
// the stack grows outward. `emphasis.focus: 'series'` fades the other series on hover; a legend
// toggles A/B/C.
// DEVIATIONS: none — the official source is a single static `option` literal: no data fetch, no
// closures, no timers. Both panes carry it verbatim (the source's trailing `export {};` is dropped
// from webOptionJS: a bare export is a SyntaxError in the reference pane's classic script).
extension EChartsDemoRegistry {
    static let official_bar_polar_stack_radial = EChartsDemo(
        name: "official-bar-polar-stack-radial", category: "bar",
        summary: "极坐标系下的堆叠柱状图 — Stacked Bar Chart on Polar(Radial)",
        width: 640, height: 420,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
option = {
  angleAxis: {
    type: 'category',
    data: ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']
  },
  radiusAxis: {},
  polar: {},
  series: [
    {
      type: 'bar',
      data: [1, 2, 3, 4, 3, 5, 1],
      coordinateSystem: 'polar',
      name: 'A',
      stack: 'a',
      emphasis: {
        focus: 'series'
      }
    },
    {
      type: 'bar',
      data: [2, 4, 6, 1, 3, 2, 1],
      coordinateSystem: 'polar',
      name: 'B',
      stack: 'a',
      emphasis: {
        focus: 'series'
      }
    },
    {
      type: 'bar',
      data: [1, 2, 3, 4, 1, 2, 5],
      coordinateSystem: 'polar',
      name: 'C',
      stack: 'a',
      emphasis: {
        focus: 'series'
      }
    }
  ],
  legend: {
    show: true,
    data: ['A', 'B', 'C']
  }
};
"""#,
        option: [
            "angleAxis": [
                "type": "category",
                "data": ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
            ] as [String: Any],
            "radiusAxis": [:] as [String: Any],
            "polar": [:] as [String: Any],
            "series": [
                [
                    "type": "bar",
                    "data": barPolarStackRadialA,
                    "coordinateSystem": "polar",
                    "name": "A",
                    "stack": "a",
                    "emphasis": ["focus": "series"] as [String: Any]
                ] as [String: Any],
                [
                    "type": "bar",
                    "data": barPolarStackRadialB,
                    "coordinateSystem": "polar",
                    "name": "B",
                    "stack": "a",
                    "emphasis": ["focus": "series"] as [String: Any]
                ] as [String: Any],
                [
                    "type": "bar",
                    "data": barPolarStackRadialC,
                    "coordinateSystem": "polar",
                    "name": "C",
                    "stack": "a",
                    "emphasis": ["focus": "series"] as [String: Any]
                ] as [String: Any]
            ],
            "legend": [
                "show": true,
                "data": ["A", "B", "C"]
            ] as [String: Any]
        ])
}

// One value per weekday (Mon…Sun); the three series share `stack: 'a'`.
private let barPolarStackRadialA: [Double] = [1, 2, 3, 4, 3, 5, 1]
private let barPolarStackRadialB: [Double] = [2, 4, 6, 1, 3, 2, 1]
private let barPolarStackRadialC: [Double] = [1, 2, 3, 4, 1, 2, 5]
