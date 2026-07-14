// official-gauge-barometer — replica of https://echarts.apache.org/examples/zh/editor.html?c=gauge-barometer
// title: Gauge Barometer chart / titleCN: 气压表
// An aneroid barometer built from TWO gauge series drawn on top of each other: an outer RED dial
// (min 0, max 100, splitNumber 10) whose ticks/labels are pulled INSIDE its 3px axisLine by negative
// `distance`s, and an inner BLACK dial (min 0, max 60, splitNumber 6) with `pointer.show: false` that
// contributes only its scale and a second anchor. The single needle belongs to the red series and is a
// custom `pointer.icon` ('path://…', a long tapered barometer hand) at `length: '115%'`, so it
// overshoots its own dial and reads against both scales at once; `detail.valueAnimation` + `precision: 1`
// roll the readout to one decimal.
//
// THE 2s setInterval IS PORTED, on both panes. The example is not a static option: every 2s it merges a
// fresh `+(Math.random() * 100).toFixed(2)` into the first gauge's data, so the needle sweeps and the
// detail number rolls. The web pane runs that interval verbatim; the native pane replays the same
// timeline through `drive` (see EChartsDemoChart) with the same 2-decimal rounding. The still-frame PNG
// paths capture the initial frame (value 58.46) and neuter the timer, so a snapshot stays deterministic
// — and because both panes then draw their own random numbers, the two are NOT expected to agree
// digit-for-digit while live; what must agree is the two-dial geometry, the inset ticks/labels and the
// custom needle.
//
// DEVIATIONS from the official source:
//   - the TypeScript type argument in `myChart.setOption<echarts.EChartsOption>({...})` is dropped — a
//     classic script parses `<` / `>` as comparison operators and the whole page dies on it. The call
//     itself, and its argument, are verbatim. The trailing `export {};` is dropped for the same reason.
//   - nothing in this example is a JS closure (there is no formatter at all), so the Swift option
//     carries every key of the original.
extension EChartsDemoRegistry {
    static let official_gauge_barometer = EChartsDemo(
        name: "official-gauge-barometer", category: "gauge",
        summary: "气压表 — Gauge Barometer chart",
        width: 640, height: 420,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
option = {
  series: [
    {
      type: 'gauge',
      min: 0,
      max: 100,
      splitNumber: 10,
      radius: '80%',
      axisLine: {
        lineStyle: {
          color: [[1, '#f00']],
          width: 3
        }
      },
      splitLine: {
        distance: -18,
        length: 18,
        lineStyle: {
          color: '#f00'
        }
      },
      axisTick: {
        distance: -12,
        length: 10,
        lineStyle: {
          color: '#f00'
        }
      },
      axisLabel: {
        distance: -50,
        color: '#f00',
        fontSize: 25
      },
      anchor: {
        show: true,
        size: 20,
        itemStyle: {
          borderColor: '#000',
          borderWidth: 2
        }
      },
      pointer: {
        offsetCenter: [0, '10%'],
        icon:
          'path://M2090.36389,615.30999 L2090.36389,615.30999 C2091.48372,615.30999 2092.40383,616.194028 2092.44859,617.312956 L2096.90698,728.755929 C2097.05155,732.369577 2094.2393,735.416212 2090.62566,735.56078 C2090.53845,735.564269 2090.45117,735.566014 2090.36389,735.566014 L2090.36389,735.566014 C2086.74736,735.566014 2083.81557,732.63423 2083.81557,729.017692 C2083.81557,728.930412 2083.81732,728.84314 2083.82081,728.755929 L2088.2792,617.312956 C2088.32396,616.194028 2089.24407,615.30999 2090.36389,615.30999 Z',
        length: '115%',
        itemStyle: {
          color: '#000'
        }
      },
      detail: {
        valueAnimation: true,
        precision: 1
      },
      title: {
        offsetCenter: [0, '-50%']
      },
      data: [
        {
          value: 58.46,
          name: 'PLP'
        }
      ]
    },
    {
      type: 'gauge',
      min: 0,
      max: 60,
      splitNumber: 6,
      axisLine: {
        lineStyle: {
          color: [[1, '#000']],
          width: 3
        }
      },
      splitLine: {
        distance: -3,
        length: 18,
        lineStyle: {
          color: '#000'
        }
      },
      axisTick: {
        distance: 0,
        length: 10,
        lineStyle: {
          color: '#000'
        }
      },
      axisLabel: {
        distance: 10,
        fontSize: 25,
        color: '#000'
      },
      pointer: {
        show: false
      },
      title: {
        show: false
      },
      anchor: {
        show: true,
        size: 14,
        itemStyle: {
          color: '#000'
        }
      }
    }
  ]
};
setInterval(function () {
  myChart.setOption({
    series: [
      {
        type: 'gauge',
        data: [
          {
            value: +(Math.random() * 100).toFixed(2),
            name: 'PLP'
          }
        ]
      }
    ]
  });
}, 2000);
"""#,
        // The native pane's half of the same timeline: the example's `setInterval(fn, 2000)`, merging a
        // new random pressure into the FIRST gauge. `notMerge: false` is upstream's bare `setOption(opt)`
        // — the partial option carries only `series[0].data` (merged by index, so the black inner dial at
        // series[1] is untouched); a replace would drop both dials' styling and the custom needle with it.
        drive: { chart in
            chart.every(2) {
                // `+(Math.random() * 100).toFixed(2)` — a pressure in [0, 100), rounded to 2 decimals.
                // Kept in the example's two steps so it cannot be misread as a double scaling:
                // `Math.random() * 100` first, then `.toFixed(2)` (which is `(x * 100).rounded() / 100`).
                let pressure = Double.random(in: 0..<1) * 100
                let value = (pressure * 100).rounded() / 100
                chart.setOption([
                    "series": [
                        [
                            "type": "gauge",
                            "data": [
                                ["value": value, "name": "PLP"] as [String: Any]
                            ]
                        ] as [String: Any]
                    ]
                ], notMerge: false)
            }
        },
        option: [
            "series": [
                // The outer RED dial: 0…100 in 10 divisions, and the series that owns the needle.
                [
                    "type": "gauge",
                    "min": 0.0,
                    "max": 100.0,
                    "splitNumber": 10.0,
                    "radius": "80%",
                    "axisLine": [
                        "lineStyle": [
                            "color": gaugeBarometerRedBand,
                            "width": 3.0
                        ] as [String: Any]
                    ] as [String: Any],
                    "splitLine": [
                        "distance": -18.0,   // negative: pull the split lines inside the arc
                        "length": 18.0,
                        "lineStyle": [
                            "color": "#f00"
                        ] as [String: Any]
                    ] as [String: Any],
                    "axisTick": [
                        "distance": -12.0,
                        "length": 10.0,
                        "lineStyle": [
                            "color": "#f00"
                        ] as [String: Any]
                    ] as [String: Any],
                    "axisLabel": [
                        "distance": -50.0,   // labels sit well inside the red arc
                        "color": "#f00",
                        "fontSize": 25.0
                    ] as [String: Any],
                    "anchor": [
                        "show": true,
                        "size": 20.0,
                        "itemStyle": [
                            "borderColor": "#000",
                            "borderWidth": 2.0
                        ] as [String: Any]
                    ] as [String: Any],
                    "pointer": [
                        "offsetCenter": [0.0, "10%"] as [Any],
                        // The barometer hand, as an SVG path (a long tapered needle).
                        "icon": gaugeBarometerPointerIcon,
                        "length": "115%",    // >100%: the needle overshoots its own dial
                        "itemStyle": [
                            "color": "#000"
                        ] as [String: Any]
                    ] as [String: Any],
                    "detail": [
                        "valueAnimation": true,
                        "precision": 1.0
                    ] as [String: Any],
                    "title": [
                        "offsetCenter": [0.0, "-50%"] as [Any]
                    ] as [String: Any],
                    "data": [
                        [
                            "value": 58.46,
                            "name": "PLP"
                        ] as [String: Any]
                    ]
                ] as [String: Any],
                // The inner BLACK dial: 0…60 in 6 divisions, no needle and no title — a second scale
                // (and a second, smaller anchor cap) the shared needle is read against.
                [
                    "type": "gauge",
                    "min": 0.0,
                    "max": 60.0,
                    "splitNumber": 6.0,
                    "axisLine": [
                        "lineStyle": [
                            "color": gaugeBarometerBlackBand,
                            "width": 3.0
                        ] as [String: Any]
                    ] as [String: Any],
                    "splitLine": [
                        "distance": -3.0,
                        "length": 18.0,
                        "lineStyle": [
                            "color": "#000"
                        ] as [String: Any]
                    ] as [String: Any],
                    "axisTick": [
                        "distance": 0.0,
                        "length": 10.0,
                        "lineStyle": [
                            "color": "#000"
                        ] as [String: Any]
                    ] as [String: Any],
                    "axisLabel": [
                        "distance": 10.0,
                        "fontSize": 25.0,
                        "color": "#000"
                    ] as [String: Any],
                    "pointer": [
                        "show": false
                    ] as [String: Any],
                    "title": [
                        "show": false
                    ] as [String: Any],
                    "anchor": [
                        "show": true,
                        "size": 14.0,
                        "itemStyle": [
                            "color": "#000"
                        ] as [String: Any]
                    ] as [String: Any]
                ] as [String: Any]
            ]
        ])
}

// `axisLine.lineStyle.color` — [stop, colour] pairs, the stop being the band's upper bound as a fraction
// of the axis range. A single band spanning the whole dial in each case. Heterogeneous, so both need the
// explicit [[Any]] to keep the type-checker honest.
private let gaugeBarometerRedBand: [[Any]] = [[1.0, "#f00"]]
private let gaugeBarometerBlackBand: [[Any]] = [[1.0, "#000"]]

// `pointer.icon` — the needle, verbatim from the official source.
private let gaugeBarometerPointerIcon = "path://M2090.36389,615.30999 L2090.36389,615.30999 C2091.48372,615.30999 2092.40383,616.194028 2092.44859,617.312956 L2096.90698,728.755929 C2097.05155,732.369577 2094.2393,735.416212 2090.62566,735.56078 C2090.53845,735.564269 2090.45117,735.566014 2090.36389,735.566014 L2090.36389,735.566014 C2086.74736,735.566014 2083.81557,732.63423 2083.81557,729.017692 C2083.81557,728.930412 2083.81732,728.84314 2083.82081,728.755929 L2088.2792,617.312956 C2088.32396,616.194028 2089.24407,615.30999 2090.36389,615.30999 Z"
