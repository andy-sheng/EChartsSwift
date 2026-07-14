// official-gauge-temperature — replica of https://echarts.apache.org/examples/zh/editor.html?c=gauge-temperature
// title: Temperature Gauge chart / titleCN: 气温仪表盘
// Two stacked `gauge` series sharing one center/arc (200° → -20°, 0…60): a fat 30px peach progress arc
// carrying the ticks/labels and the `{value} °C` detail readout, and a thin 8px orange progress arc drawn
// on top of it. Both are pointer-less and anchor-less; the reading is the detail text, not a needle.
//
// THE 2s RANDOM-TEMPERATURE TIMER IS PORTED, on both panes. The web pane runs the example's own
// `setInterval(function () { ... myChart.setOption({ series: [...] }) }, 2000)` verbatim (a MERGE
// setOption — it re-supplies only `series[].data`); the native pane replays the same timeline through
// `drive` (see EChartsDemoChart). The still-frame PNG paths never call `drive` and neuter the web pane's
// setInterval, so both snapshot the first frame — value 20 on both gauges.
//
// DEVIATIONS from the official source:
//   - The TS type argument on `myChart.setOption<echarts.EChartsOption>({...})` is dropped: a classic
//     script cannot parse it. The trailing `export {};` is dropped (a bare export is a SyntaxError that
//     would kill the whole page).
//   - INHERENTLY UNSYNCHRONISED, by the example's own design: each pane draws its own random value
//     (`+(Math.random() * 60).toFixed(2)` in JS, the same expression over Swift's RNG natively), so at
//     any instant the two panes show DIFFERENT temperatures. Upstream's `Math.random()` is not
//     reproducible across engines, and seeding it would be a bigger deviation than the divergence. Diff
//     the two panes on the gauge's GEOMETRY (arc sweep for the value shown, tick/label placement, detail
//     typography), not on the number.
//   - No keys omitted: `detail.formatter` is the STRING `'{value} °C'`, not a closure, so it ports.
import Foundation

extension EChartsDemoRegistry {
    static let official_gauge_temperature = EChartsDemo(
        name: "official-gauge-temperature", category: "gauge",
        summary: "气温仪表盘 — Temperature Gauge chart",
        width: 640, height: 420,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
option = {
  series: [
    {
      type: 'gauge',
      center: ['50%', '60%'],
      startAngle: 200,
      endAngle: -20,
      min: 0,
      max: 60,
      splitNumber: 12,
      itemStyle: {
        color: '#FFAB91'
      },
      progress: {
        show: true,
        width: 30
      },

      pointer: {
        show: false
      },
      axisLine: {
        lineStyle: {
          width: 30
        }
      },
      axisTick: {
        distance: -45,
        splitNumber: 5,
        lineStyle: {
          width: 2,
          color: '#999'
        }
      },
      splitLine: {
        distance: -52,
        length: 14,
        lineStyle: {
          width: 3,
          color: '#999'
        }
      },
      axisLabel: {
        distance: -20,
        color: '#999',
        fontSize: 20
      },
      anchor: {
        show: false
      },
      title: {
        show: false
      },
      detail: {
        valueAnimation: true,
        width: '60%',
        lineHeight: 40,
        borderRadius: 8,
        offsetCenter: [0, '-15%'],
        fontSize: 60,
        fontWeight: 'bolder',
        formatter: '{value} °C',
        color: 'inherit'
      },
      data: [
        {
          value: 20
        }
      ]
    },

    {
      type: 'gauge',
      center: ['50%', '60%'],
      startAngle: 200,
      endAngle: -20,
      min: 0,
      max: 60,
      itemStyle: {
        color: '#FD7347'
      },
      progress: {
        show: true,
        width: 8
      },

      pointer: {
        show: false
      },
      axisLine: {
        show: false
      },
      axisTick: {
        show: false
      },
      splitLine: {
        show: false
      },
      axisLabel: {
        show: false
      },
      detail: {
        show: false
      },
      data: [
        {
          value: 20
        }
      ]
    }
  ]
};

setInterval(function () {
  const random = +(Math.random() * 60).toFixed(2);
  myChart.setOption({
    series: [
      {
        data: [
          {
            value: random
          }
        ]
      },
      {
        data: [
          {
            value: random
          }
        ]
      }
    ]
  });
}, 2000);
"""#,
        // The native pane's half of the same timeline: every 2s, push ONE random value into both series.
        // A MERGE setOption (notMerge: false) — upstream passes no `true`, and the partial option carries
        // nothing but `series[].data`; replacing would drop every gauge setting above.
        drive: { chart in
            chart.every(2) {
                // `+(Math.random() * 60).toFixed(2)` — a 0…60 reading, 2 decimals.
                let random = (Double.random(in: 0..<60) * 100).rounded() / 100
                chart.setOption(officialGaugeTemperatureUpdate(random), notMerge: false)
            }
        },
        option: [
            "series": [
                // The fat 30px arc: axis line, ticks, split lines, labels and the °C readout.
                [
                    "type": "gauge",
                    "center": ["50%", "60%"],
                    "startAngle": 200.0,
                    "endAngle": -20.0,
                    "min": 0.0,
                    "max": 60.0,
                    "splitNumber": 12.0,
                    "itemStyle": [
                        "color": "#FFAB91"
                    ] as [String: Any],
                    "progress": [
                        "show": true,
                        "width": 30.0
                    ] as [String: Any],
                    "pointer": [
                        "show": false
                    ] as [String: Any],
                    "axisLine": [
                        "lineStyle": [
                            "width": 30.0
                        ] as [String: Any]
                    ] as [String: Any],
                    "axisTick": [
                        "distance": -45.0,
                        "splitNumber": 5.0,
                        "lineStyle": [
                            "width": 2.0,
                            "color": "#999"
                        ] as [String: Any]
                    ] as [String: Any],
                    "splitLine": [
                        "distance": -52.0,
                        "length": 14.0,
                        "lineStyle": [
                            "width": 3.0,
                            "color": "#999"
                        ] as [String: Any]
                    ] as [String: Any],
                    "axisLabel": [
                        "distance": -20.0,
                        "color": "#999",
                        "fontSize": 20.0
                    ] as [String: Any],
                    "anchor": [
                        "show": false
                    ] as [String: Any],
                    "title": [
                        "show": false
                    ] as [String: Any],
                    "detail": [
                        "valueAnimation": true,
                        "width": "60%",
                        "lineHeight": 40.0,
                        "borderRadius": 8.0,
                        "offsetCenter": [0.0, "-15%"] as [Any],
                        "fontSize": 60.0,
                        "fontWeight": "bolder",
                        "formatter": "{value} °C",
                        "color": "inherit"
                    ] as [String: Any],
                    "data": [
                        ["value": 20.0] as [String: Any]
                    ] as [Any]
                ] as [String: Any],
                // The thin 8px arc laid over it: progress only, everything else switched off.
                [
                    "type": "gauge",
                    "center": ["50%", "60%"],
                    "startAngle": 200.0,
                    "endAngle": -20.0,
                    "min": 0.0,
                    "max": 60.0,
                    "itemStyle": [
                        "color": "#FD7347"
                    ] as [String: Any],
                    "progress": [
                        "show": true,
                        "width": 8.0
                    ] as [String: Any],
                    "pointer": [
                        "show": false
                    ] as [String: Any],
                    "axisLine": [
                        "show": false
                    ] as [String: Any],
                    "axisTick": [
                        "show": false
                    ] as [String: Any],
                    "splitLine": [
                        "show": false
                    ] as [String: Any],
                    "axisLabel": [
                        "show": false
                    ] as [String: Any],
                    "detail": [
                        "show": false
                    ] as [String: Any],
                    "data": [
                        ["value": 20.0] as [String: Any]
                    ] as [Any]
                ] as [String: Any]
            ] as [Any]
        ])
}

// The example's timer payload: the SAME reading on both gauges, as `series[].data` and nothing else.
private func officialGaugeTemperatureUpdate(_ value: Double) -> [String: Any] {
    let datum = ["data": [["value": value] as [String: Any]] as [Any]] as [String: Any]
    return ["series": [datum, datum] as [Any]]
}
