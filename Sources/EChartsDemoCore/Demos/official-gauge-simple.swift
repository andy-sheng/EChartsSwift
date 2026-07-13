// official-gauge-simple — replica of https://echarts.apache.org/examples/zh/editor.html?c=gauge-simple
// title: Simple Gauge / titleCN: 带标签数字动画的基础仪表盘
// A single gauge (default 225°->-45° span) with the `progress` arc shown and a `detail` readout of the
// value; `detail.valueAnimation` rolls the number up from 0 on load.
//
// DEVIATIONS from the official source:
//   - none in the option itself: the example's JS is verbatim. Both `formatter`s are STRING templates
//     ('{a} <br/>{b} : {c}%' and '{value}'), not JS closures, so both panes carry them as-is.
//   - the gallery renders ONE static frame with animation disabled, so `detail.valueAnimation`'s
//     number roll-up is not observable — both panes show the settled value (50).
//   - tooltip is hover-only and therefore never visible in a static snapshot; kept for fidelity.
extension EChartsDemoRegistry {
    static let official_gauge_simple = EChartsDemo(
        name: "official-gauge-simple", category: "gauge",
        summary: "带标签数字动画的基础仪表盘 — Simple Gauge",
        width: 640, height: 420,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
option = {
  tooltip: {
    formatter: '{a} <br/>{b} : {c}%'
  },
  series: [
    {
      name: 'Pressure',
      type: 'gauge',
      progress: {
        show: true
      },
      detail: {
        valueAnimation: true,
        formatter: '{value}'
      },
      data: [
        {
          value: 50,
          name: 'SCORE'
        }
      ]
    }
  ]
};
"""#,
        option: [
            "tooltip": [
                "formatter": "{a} <br/>{b} : {c}%"
            ] as [String: Any],
            "series": [
                [
                    "name": "Pressure",
                    "type": "gauge",
                    "progress": [
                        "show": true
                    ] as [String: Any],
                    "detail": [
                        "valueAnimation": true,
                        "formatter": "{value}"
                    ] as [String: Any],
                    "data": [
                        [
                            "value": 50.0,
                            "name": "SCORE"
                        ] as [String: Any]
                    ]
                ] as [String: Any]
            ]
        ])
}
