// official-bar-tick-align — replica of https://echarts.apache.org/examples/zh/editor.html?c=bar-tick-align
// title: Axis Align with Tick / titleCN: 坐标轴刻度与标签对齐
// A single bar series on a category x-axis with `axisTick.alignWithLabel: true` — ticks sit under the
// label/bar center instead of on the band boundary. Also exercises grid.containLabel and a shadow axisPointer.
// DEVIATIONS: none — the official source is a single static `option` literal: no data fetch, no
// closures, no timers. Both panes carry it verbatim.
extension EChartsDemoRegistry {
    static let official_bar_tick_align = EChartsDemo(
        name: "official-bar-tick-align", category: "bar",
        summary: "坐标轴刻度与标签对齐 — Axis Align with Tick",
        width: 640, height: 420,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
option = {
  tooltip: {
    trigger: 'axis',
    axisPointer: {
      type: 'shadow'
    }
  },
  grid: {
    left: '3%',
    right: '4%',
    bottom: '3%',
    containLabel: true
  },
  xAxis: [
    {
      type: 'category',
      data: ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'],
      axisTick: {
        alignWithLabel: true
      }
    }
  ],
  yAxis: [
    {
      type: 'value'
    }
  ],
  series: [
    {
      name: 'Direct',
      type: 'bar',
      barWidth: '60%',
      data: [10, 52, 200, 334, 390, 330, 220]
    }
  ]
};
"""#,
        option: [
            "tooltip": [
                "trigger": "axis",
                "axisPointer": [
                    "type": "shadow"
                ] as [String: Any]
            ] as [String: Any],
            "grid": [
                "left": "3%",
                "right": "4%",
                "bottom": "3%",
                "containLabel": true
            ] as [String: Any],
            "xAxis": [
                [
                    "type": "category",
                    "data": ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"],
                    "axisTick": [
                        "alignWithLabel": true
                    ] as [String: Any]
                ] as [String: Any]
            ],
            "yAxis": [
                [
                    "type": "value"
                ] as [String: Any]
            ],
            "series": [
                [
                    "name": "Direct",
                    "type": "bar",
                    "barWidth": "60%",
                    "data": [10.0, 52.0, 200.0, 334.0, 390.0, 330.0, 220.0]
                ] as [String: Any]
            ]
        ])
}
