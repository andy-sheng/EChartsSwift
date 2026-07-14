// official-gauge-stage — replica of https://echarts.apache.org/examples/zh/editor.html?c=gauge-stage
// title: Stage Speed Gauge / titleCN: 阶段速度仪表盘
// A speedometer whose axisLine is banded into three stages (0-30 cyan, 30-70 blue, 70-100 red); the
// pointer, the axis labels and the `{value} km/h` detail readout all take `color: 'auto'/'inherit'`,
// so they recolour to whichever band the needle sits in. Ticks and split lines are pushed INSIDE the
// 30px-wide band (`distance: -30`) and drawn white, so they read as notches cut out of the arc.
//
// THE 2s setInterval IS PORTED, on both panes. The example is not a static option: every 2s it merges
// a fresh `+(Math.random() * 100).toFixed(2)` into the series data, and `detail.valueAnimation: true`
// makes the readout roll from the old number to the new one while the needle sweeps across the bands.
// The web pane runs that interval verbatim; the native pane replays the same timeline through `drive`
// (see EChartsDemoChart) with the same 2-decimal rounding. The still-frame PNG paths capture the
// initial frame (value 70) and neuter the timer, so a snapshot stays deterministic — and because both
// panes then pick their own random numbers, the two are NOT expected to agree digit-for-digit while
// live; what must agree is the banding, the needle geometry and the auto/inherit colour behaviour.
//
// DEVIATIONS from the official source:
//   - the TypeScript type argument in `myChart.setOption<echarts.EChartsOption>({...})` is dropped —
//     a classic script parses `<` / `>` as comparison operators and the whole page dies on it. The
//     call itself, and its argument, are verbatim.
//   - `detail.formatter` ('{value} km/h') is a STRING template, not a JS closure, so it survives into
//     the Swift option unchanged; nothing else in this example is a function.
extension EChartsDemoRegistry {
    static let official_gauge_stage = EChartsDemo(
        name: "official-gauge-stage", category: "gauge",
        summary: "阶段速度仪表盘 — Stage Speed Gauge",
        width: 640, height: 420,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
option = {
  series: [
    {
      type: 'gauge',
      axisLine: {
        lineStyle: {
          width: 30,
          color: [
            [0.3, '#67e0e3'],
            [0.7, '#37a2da'],
            [1, '#fd666d']
          ]
        }
      },
      pointer: {
        itemStyle: {
          color: 'auto'
        }
      },
      axisTick: {
        distance: -30,
        length: 8,
        lineStyle: {
          color: '#fff',
          width: 2
        }
      },
      splitLine: {
        distance: -30,
        length: 30,
        lineStyle: {
          color: '#fff',
          width: 4
        }
      },
      axisLabel: {
        color: 'inherit',
        distance: 40,
        fontSize: 20
      },
      detail: {
        valueAnimation: true,
        formatter: '{value} km/h',
        color: 'inherit'
      },
      data: [
        {
          value: 70
        }
      ]
    }
  ]
};

setInterval(function () {
  myChart.setOption({
    series: [
      {
        data: [
          {
            value: +(Math.random() * 100).toFixed(2)
          }
        ]
      }
    ]
  });
}, 2000);
"""#,
        // The native pane's half of the same timeline: the example's `setInterval(fn, 2000)`, merging a
        // new random speed into the series. `notMerge: false` is upstream's bare `setOption(opt)` — the
        // partial option carries only `series[0].data`, and a replace would drop the axisLine bands,
        // the ticks and the detail formatter with it.
        drive: { chart in
            chart.every(2) {
                // `+(Math.random() * 100).toFixed(2)` — a speed in [0, 100), rounded to 2 decimals.
                // Kept in the example's two steps so it cannot be misread as a double scaling:
                // `Math.random() * 100` first, then `.toFixed(2)` (which is `(x * 100).rounded() / 100`).
                let speed = Double.random(in: 0..<1) * 100
                let value = (speed * 100).rounded() / 100
                chart.setOption([
                    "series": [
                        [
                            "data": [
                                ["value": value] as [String: Any]
                            ]
                        ] as [String: Any]
                    ]
                ], notMerge: false)
            }
        },
        option: [
            "series": [
                [
                    "type": "gauge",
                    "axisLine": [
                        "lineStyle": [
                            "width": 30.0,
                            // Stage bands: [upper bound as a fraction of the axis, colour].
                            "color": gaugeStageBands
                        ] as [String: Any]
                    ] as [String: Any],
                    "pointer": [
                        "itemStyle": [
                            "color": "auto"   // take the band colour the needle currently points at
                        ] as [String: Any]
                    ] as [String: Any],
                    "axisTick": [
                        "distance": -30.0,    // negative: inside the 30px band
                        "length": 8.0,
                        "lineStyle": [
                            "color": "#fff",
                            "width": 2.0
                        ] as [String: Any]
                    ] as [String: Any],
                    "splitLine": [
                        "distance": -30.0,
                        "length": 30.0,
                        "lineStyle": [
                            "color": "#fff",
                            "width": 4.0
                        ] as [String: Any]
                    ] as [String: Any],
                    "axisLabel": [
                        "color": "inherit",
                        "distance": 40.0,
                        "fontSize": 20.0
                    ] as [String: Any],
                    "detail": [
                        "valueAnimation": true,
                        "formatter": "{value} km/h",
                        "color": "inherit"
                    ] as [String: Any],
                    "data": [
                        ["value": 70.0] as [String: Any]
                    ]
                ] as [String: Any]
            ]
        ])
}

// `axisLine.lineStyle.color` — [stop, colour] pairs, each stop the band's upper bound as a fraction of
// the axis range. Heterogeneous, so it needs the explicit [[Any]] to keep the type-checker honest.
private let gaugeStageBands: [[Any]] = [
    [0.3, "#67e0e3"],
    [0.7, "#37a2da"],
    [1.0, "#fd666d"]
]
