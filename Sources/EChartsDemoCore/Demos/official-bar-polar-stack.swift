// official-bar-polar-stack — replica of https://echarts.apache.org/examples/zh/editor.html?c=bar-polar-stack
// title: Stacked Bar Chart on Polar / titleCN: 极坐标系下的堆叠柱状图
// Three bar series (A/B/C) stacked on one `stack: 'a'` group, drawn on a polar coordinate system:
// a category radiusAxis (Mon–Thu) against a default value angleAxis, with `emphasis.focus: 'series'`
// and a legend.
// DEVIATIONS: the source's trailing `export {};` is dropped — a bare export is a SyntaxError in the
// reference pane's classic script. Nothing else: the official source is a single static `option`
// literal (no data fetch, no closures, no timers), so both panes carry it verbatim.
extension EChartsDemoRegistry {
    static let official_bar_polar_stack = EChartsDemo(
        name: "official-bar-polar-stack", category: "bar",
        summary: "极坐标系下的堆叠柱状图 — Stacked Bar Chart on Polar",
        width: 640, height: 420,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
option = {
  angleAxis: {},
  radiusAxis: {
    type: 'category',
    data: ['Mon', 'Tue', 'Wed', 'Thu'],
    z: 10
  },
  polar: {},
  series: [
    {
      type: 'bar',
      data: [1, 2, 3, 4],
      coordinateSystem: 'polar',
      name: 'A',
      stack: 'a',
      emphasis: {
        focus: 'series'
      }
    },
    {
      type: 'bar',
      data: [2, 4, 6, 8],
      coordinateSystem: 'polar',
      name: 'B',
      stack: 'a',
      emphasis: {
        focus: 'series'
      }
    },
    {
      type: 'bar',
      data: [1, 2, 3, 4],
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
            "angleAxis": [:] as [String: Any],
            "radiusAxis": [
                "type": "category",
                "data": ["Mon", "Tue", "Wed", "Thu"],
                "z": 10.0
            ] as [String: Any],
            "polar": [:] as [String: Any],
            "series": [
                [
                    "type": "bar",
                    "data": [1.0, 2.0, 3.0, 4.0],
                    "coordinateSystem": "polar",
                    "name": "A",
                    "stack": "a",
                    "emphasis": ["focus": "series"] as [String: Any]
                ] as [String: Any],
                [
                    "type": "bar",
                    "data": [2.0, 4.0, 6.0, 8.0],
                    "coordinateSystem": "polar",
                    "name": "B",
                    "stack": "a",
                    "emphasis": ["focus": "series"] as [String: Any]
                ] as [String: Any],
                [
                    "type": "bar",
                    "data": [1.0, 2.0, 3.0, 4.0],
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
