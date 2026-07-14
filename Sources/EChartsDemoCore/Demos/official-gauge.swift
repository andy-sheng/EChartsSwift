// official-gauge — replica of https://echarts.apache.org/examples/zh/editor.html?c=gauge
// title: Gauge Basic chart / titleCN: 基础仪表盘
// A single default-styled gauge (one datum, value 50, name 'SCORE'). Everything drawn comes from the
// gauge series defaults: the flat axisLine band ([[1, '#e8ebf0']], width 10), split lines, axis ticks
// and labels, the pointer needle, the 'SCORE' title below centre and the detail readout below that.
// NOT a progress arc — `progress.show` defaults to false (GaugeSeries.swift), and this option never
// turns it on.
// DEVIATIONS: none of substance — the official source is one static `option` literal with no data
// fetch and no timers. Its two formatters are STRING templates ('{a} <br/>{b} : {c}%' for the
// tooltip, '{value}' for the detail), not JS closures, so the Swift option carries them verbatim
// rather than dropping them: native GaugeView resolves `detail.formatter` through `formatLabel`.
// `tooltip` is hover-only, so it changes neither pane's static snapshot — it is kept for fidelity.
// Only the trailing `export {};` is dropped (a bare export is a SyntaxError in a classic script).
extension EChartsDemoRegistry {
    static let official_gauge = EChartsDemo(
        name: "official-gauge", category: "gauge",
        summary: "基础仪表盘 — Gauge Basic chart",
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
      detail: {
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
                    "detail": [
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
