// official-gauge-progress — replica of https://echarts.apache.org/examples/zh/editor.html?c=gauge-progress
// title: Progress Gauge / titleCN: 进度仪表盘
// A single gauge whose `progress` arc (width 18) overlays an equally thick `axisLine`, ticks hidden,
// short grey splitLines, a shown-above `anchor` at the pivot, no `title`, and a big (fontSize 80)
// `detail` readout pushed below centre (offsetCenter [0, '70%']). Value 70.
//
// DEVIATIONS from the official source:
//   - `export {};` dropped (a bare ES-module export is a SyntaxError in the page's classic script);
//     the option itself is verbatim in both panes. There are no closures, no data fetch and no timers,
//     so no key is omitted from the Swift option and no `drive` timeline is needed.
//   - the gallery's still-frame render disables animation, so `detail.valueAnimation`'s number roll-up
//     from 0 is not observable there — both panes show the settled value (70). The live gallery pane
//     runs the example as the website does.
extension EChartsDemoRegistry {
    static let official_gauge_progress = EChartsDemo(
        name: "official-gauge-progress", category: "gauge",
        summary: "进度仪表盘 — Progress Gauge",
        width: 640, height: 420,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
option = {
  series: [
    {
      type: 'gauge',
      progress: {
        show: true,
        width: 18
      },
      axisLine: {
        lineStyle: {
          width: 18
        }
      },
      axisTick: {
        show: false
      },
      splitLine: {
        length: 15,
        lineStyle: {
          width: 2,
          color: '#999'
        }
      },
      axisLabel: {
        distance: 25,
        color: '#999',
        fontSize: 20
      },
      anchor: {
        show: true,
        showAbove: true,
        size: 25,
        itemStyle: {
          borderWidth: 10
        }
      },
      title: {
        show: false
      },
      detail: {
        valueAnimation: true,
        fontSize: 80,
        offsetCenter: [0, '70%']
      },
      data: [
        {
          value: 70
        }
      ]
    }
  ]
};
"""#,
        option: [
            "series": [
                [
                    "type": "gauge",
                    "progress": [
                        "show": true,
                        "width": 18.0
                    ] as [String: Any],
                    "axisLine": [
                        "lineStyle": [
                            "width": 18.0
                        ] as [String: Any]
                    ] as [String: Any],
                    "axisTick": [
                        "show": false
                    ] as [String: Any],
                    "splitLine": [
                        "length": 15.0,
                        "lineStyle": [
                            "width": 2.0,
                            "color": "#999"
                        ] as [String: Any]
                    ] as [String: Any],
                    "axisLabel": [
                        "distance": 25.0,
                        "color": "#999",
                        "fontSize": 20.0
                    ] as [String: Any],
                    "anchor": [
                        "show": true,
                        "showAbove": true,
                        "size": 25.0,
                        "itemStyle": [
                            "borderWidth": 10.0
                        ] as [String: Any]
                    ] as [String: Any],
                    "title": [
                        "show": false
                    ] as [String: Any],
                    "detail": [
                        "valueAnimation": true,
                        "fontSize": 80.0,
                        "offsetCenter": [0.0, "70%"] as [Any]
                    ] as [String: Any],
                    "data": [
                        [
                            "value": 70.0
                        ] as [String: Any]
                    ]
                ] as [String: Any]
            ]
        ])
}
