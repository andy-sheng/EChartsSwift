// official-gauge-ring — replica of https://echarts.apache.org/examples/zh/editor.html?c=gauge-ring
// title: Ring Gauge / titleCN: 得分环
// One full-circle gauge (startAngle 90 → endAngle -270, no pointer) carrying THREE data items, each
// drawn as a round-capped, non-overlapping `progress` arc on the same 40px-wide axisLine, with its own
// stacked title + `{value}%` detail pill.
//
// THE 2s RANDOMIZE IS PORTED, on both panes. The web pane runs the example's own
// `setInterval(function () { gaugeData[i].value = +(Math.random() * 100).toFixed(2); myChart.setOption({...}) }, 2000)`
// verbatim (a MERGE setOption, so only series[0].data changes and `detail.valueAnimation` tweens the
// numbers); the native pane replays the same timeline through `drive` (see EChartsDemoChart). The
// still-frame PNG paths capture the first frame — values 20/40/60 — and neuter the timer, so a
// snapshot stays deterministic.
//
// DEVIATIONS from the official source:
//   - The TS type annotation on `myChart.setOption<echarts.EChartsOption>({...})` is dropped (a classic
//     script cannot parse it), as is the trailing `export {}` (a bare export is a SyntaxError that would
//     kill the whole page). The call itself, and the interval around it, run verbatim.
//   - The two panes randomize independently (each pane has its own RNG), so their three arcs will not
//     show the same values at the same instant — the example's point is the ring/pill/valueAnimation
//     rendering, not the numbers.
//   - No option key is omitted: `detail.formatter: '{value}%'` is a STRING template, not a JS closure,
//     so it crosses into the Swift option intact.
import Foundation

// The example's `gaugeData` — three items sharing one gauge, each with its own title/detail offsets.
// A function, not a `let`: the 2s interval rewrites the three `value`s in place, so the native pane
// rebuilds the array from a fresh triple each tick (upstream mutates `gaugeData[i].value`).
private func officialGaugeRingData(_ values: [Double]) -> [[String: Any]] {
    [
        [
            "value": values[0],
            "name": "Perfect",
            "title": ["offsetCenter": ["0%", "-30%"]] as [String: Any],
            "detail": ["valueAnimation": true, "offsetCenter": ["0%", "-20%"]] as [String: Any]
        ] as [String: Any],
        [
            "value": values[1],
            "name": "Good",
            "title": ["offsetCenter": ["0%", "0%"]] as [String: Any],
            "detail": ["valueAnimation": true, "offsetCenter": ["0%", "10%"]] as [String: Any]
        ] as [String: Any],
        [
            "value": values[2],
            "name": "Commonly",
            "title": ["offsetCenter": ["0%", "30%"]] as [String: Any],
            "detail": ["valueAnimation": true, "offsetCenter": ["0%", "40%"]] as [String: Any]
        ] as [String: Any]
    ]
}

// Upstream's `+(Math.random() * 100).toFixed(2)` — a value in [0, 100), two decimal places.
private func officialGaugeRingRandomValue() -> Double {
    (Double.random(in: 0..<100) * 100).rounded() / 100
}

// The example's `option` — one gauge series, parameterised by the three values so the initial frame
// (20/40/60) and any later frame are built the same way. The interval does NOT re-send this: upstream
// merges only `{ series: [{ data, pointer }] }`, so the rest of the series survives untouched.
private func officialGaugeRingOption(_ values: [Double]) -> [String: Any] {
    [
        "series": [
            [
                "type": "gauge",
                "startAngle": 90.0,
                "endAngle": -270.0,
                "pointer": ["show": false] as [String: Any],
                "progress": [
                    "show": true,
                    "overlap": false,
                    "roundCap": true,
                    "clip": false,
                    "itemStyle": [
                        "borderWidth": 1.0,
                        "borderColor": "#464646"
                    ] as [String: Any]
                ] as [String: Any],
                "axisLine": [
                    "lineStyle": ["width": 40.0] as [String: Any]
                ] as [String: Any],
                "splitLine": [
                    "show": false,
                    "distance": 0.0,
                    "length": 10.0
                ] as [String: Any],
                "axisTick": ["show": false] as [String: Any],
                "axisLabel": [
                    "show": false,
                    "distance": 50.0
                ] as [String: Any],
                "data": officialGaugeRingData(values) as [Any],
                "title": ["fontSize": 14.0] as [String: Any],
                "detail": [
                    "width": 50.0,
                    "height": 14.0,
                    "fontSize": 14.0,
                    "color": "inherit",
                    "borderColor": "inherit",
                    "borderRadius": 20.0,
                    "borderWidth": 1.0,
                    "formatter": "{value}%"
                ] as [String: Any]
            ] as [String: Any]
        ]
    ]
}

extension EChartsDemoRegistry {
    static let official_gauge_ring = EChartsDemo(
        name: "official-gauge-ring", category: "gauge",
        summary: "得分环 — Ring Gauge",
        width: 640, height: 420,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
const gaugeData = [
  {
    value: 20,
    name: 'Perfect',
    title: {
      offsetCenter: ['0%', '-30%']
    },
    detail: {
      valueAnimation: true,
      offsetCenter: ['0%', '-20%']
    }
  },
  {
    value: 40,
    name: 'Good',
    title: {
      offsetCenter: ['0%', '0%']
    },
    detail: {
      valueAnimation: true,
      offsetCenter: ['0%', '10%']
    }
  },
  {
    value: 60,
    name: 'Commonly',
    title: {
      offsetCenter: ['0%', '30%']
    },
    detail: {
      valueAnimation: true,
      offsetCenter: ['0%', '40%']
    }
  }
];

option = {
  series: [
    {
      type: 'gauge',
      startAngle: 90,
      endAngle: -270,
      pointer: {
        show: false
      },
      progress: {
        show: true,
        overlap: false,
        roundCap: true,
        clip: false,
        itemStyle: {
          borderWidth: 1,
          borderColor: '#464646'
        }
      },
      axisLine: {
        lineStyle: {
          width: 40
        }
      },
      splitLine: {
        show: false,
        distance: 0,
        length: 10
      },
      axisTick: {
        show: false
      },
      axisLabel: {
        show: false,
        distance: 50
      },
      data: gaugeData,
      title: {
        fontSize: 14
      },
      detail: {
        width: 50,
        height: 14,
        fontSize: 14,
        color: 'inherit',
        borderColor: 'inherit',
        borderRadius: 20,
        borderWidth: 1,
        formatter: '{value}%'
      }
    }
  ]
};

setInterval(function () {
  gaugeData[0].value = +(Math.random() * 100).toFixed(2);
  gaugeData[1].value = +(Math.random() * 100).toFixed(2);
  gaugeData[2].value = +(Math.random() * 100).toFixed(2);
  myChart.setOption({
    series: [
      {
        data: gaugeData,
        pointer: {
          show: false
        }
      }
    ]
  });
}, 2000);
"""#,
        // The native pane's half of the same timeline: every 2s, re-roll the three values and MERGE
        // them in (upstream's `myChart.setOption({ series: [{ data: gaugeData, pointer: {...} }] })` —
        // no `true`, so the rest of the series is preserved and `detail.valueAnimation` tweens).
        drive: { chart in
            chart.every(2) {
                let values = [officialGaugeRingRandomValue(),
                              officialGaugeRingRandomValue(),
                              officialGaugeRingRandomValue()]
                chart.setOption([
                    "series": [
                        [
                            "data": officialGaugeRingData(values) as [Any],
                            "pointer": ["show": false] as [String: Any]
                        ] as [String: Any]
                    ]
                ], notMerge: false)
            }
        },
        // The example's first frame: the literal 20 / 40 / 60 of `gaugeData`.
        option: officialGaugeRingOption([20, 40, 60]))
}
