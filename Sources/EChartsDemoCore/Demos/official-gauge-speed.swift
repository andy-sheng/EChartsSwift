// official-gauge-speed — replica of https://echarts.apache.org/examples/zh/editor.html?c=gauge-speed
// title: Speed Gauge / titleCN: 速度仪表盘
// A 180°→0° gauge (0..240 km/h, value 100): rounded-cap progress arc + axisLine, a custom SVG
// `path://` pointer, grey ticks/splitLines/labels, and a boxed `detail` readout whose rich text
// splits the number from its "km/h" unit.
// DEVIATIONS:
//   - web pane: the official source VERBATIM (formatter closure and all), minus the trailing
//     `export {};` (a bare export is a SyntaxError in a classic script).
//   - native pane: `series[0].detail.formatter` is a JS function and is omitted (see PORT-NOTE) —
//     but NOT because the option bag cannot hold one. `option` is [String: Any] and util.isFunction
//     duck-types Swift closures (ZRenderKit/Core/util.swift), so a closure would arrive intact. It is
//     the gauge's own label path that drops it: GaugeView.formatLabel (EChartsKit/chart/gauge/
//     GaugeView.swift:88-106) MATCHES the isFunction branch and deliberately does not call it
//     ("PORT-NOTE (deferred): requires the formatter-callback seam"), keeping the raw numeric label.
//     Carrying the closure here would therefore be an invisible no-op; natively only a '{value}'
//     STRING template is honoured. The `detail.rich` styles the formatter addressed stay in the
//     option, but with no formatter emitting `{value|...}{unit|...}` markup they are never applied:
//     the native detail falls back to the plain value, so it will read "100" (unstyled, no "km/h")
//     where the web pane reads "100km/h" in 50px bold + a 20px grey unit. That divergence is the
//     point — it is a real framework gap, not a simplification of the example.
//   - static example: no timers, no data fetch, no map — hence no `drive` closure and no assets.
extension EChartsDemoRegistry {
    static let official_gauge_speed = EChartsDemo(
        name: "official-gauge-speed", category: "gauge",
        summary: "速度仪表盘 — Speed Gauge",
        width: 640, height: 420,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
option = {
  series: [
    {
      type: 'gauge',
      startAngle: 180,
      endAngle: 0,
      min: 0,
      max: 240,
      splitNumber: 12,
      itemStyle: {
        color: '#58D9F9',
        shadowColor: 'rgba(0,138,255,0.45)',
        shadowBlur: 10,
        shadowOffsetX: 2,
        shadowOffsetY: 2
      },
      progress: {
        show: true,
        roundCap: true,
        width: 18
      },
      pointer: {
        icon: 'path://M2090.36389,615.30999 L2090.36389,615.30999 C2091.48372,615.30999 2092.40383,616.194028 2092.44859,617.312956 L2096.90698,728.755929 C2097.05155,732.369577 2094.2393,735.416212 2090.62566,735.56078 C2090.53845,735.564269 2090.45117,735.566014 2090.36389,735.566014 L2090.36389,735.566014 C2086.74736,735.566014 2083.81557,732.63423 2083.81557,729.017692 C2083.81557,728.930412 2083.81732,728.84314 2083.82081,728.755929 L2088.2792,617.312956 C2088.32396,616.194028 2089.24407,615.30999 2090.36389,615.30999 Z',
        length: '75%',
        width: 16,
        offsetCenter: [0, '5%']
      },
      axisLine: {
        roundCap: true,
        lineStyle: {
          width: 18
        }
      },
      axisTick: {
        splitNumber: 2,
        lineStyle: {
          width: 2,
          color: '#999'
        }
      },
      splitLine: {
        length: 12,
        lineStyle: {
          width: 3,
          color: '#999'
        }
      },
      axisLabel: {
        distance: 30,
        color: '#999',
        fontSize: 20
      },
      title: {
        show: false
      },
      detail: {
        backgroundColor: '#fff',
        borderColor: '#999',
        borderWidth: 2,
        width: '60%',
        lineHeight: 40,
        height: 40,
        borderRadius: 8,
        offsetCenter: [0, '35%'],
        valueAnimation: true,
        formatter: function (value) {
          return '{value|' + value.toFixed(0) + '}{unit|km/h}';
        },
        rich: {
          value: {
            fontSize: 50,
            fontWeight: 'bolder',
            color: '#777'
          },
          unit: {
            fontSize: 20,
            color: '#999',
            padding: [0, 0, -20, 10]
          }
        }
      },
      data: [
        {
          value: 100
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
                    "startAngle": 180.0,
                    "endAngle": 0.0,
                    "min": 0.0,
                    "max": 240.0,
                    "splitNumber": 12.0,
                    "itemStyle": [
                        "color": "#58D9F9",
                        "shadowColor": "rgba(0,138,255,0.45)",
                        "shadowBlur": 10.0,
                        "shadowOffsetX": 2.0,
                        "shadowOffsetY": 2.0
                    ] as [String: Any],
                    "progress": [
                        "show": true,
                        "roundCap": true,
                        "width": 18.0
                    ] as [String: Any],
                    "pointer": [
                        "icon": gaugeSpeedPointerIcon,
                        "length": "75%",
                        "width": 16.0,
                        "offsetCenter": [0.0, "5%"] as [Any]
                    ] as [String: Any],
                    "axisLine": [
                        "roundCap": true,
                        "lineStyle": [
                            "width": 18.0
                        ] as [String: Any]
                    ] as [String: Any],
                    "axisTick": [
                        "splitNumber": 2.0,
                        "lineStyle": [
                            "width": 2.0,
                            "color": "#999"
                        ] as [String: Any]
                    ] as [String: Any],
                    "splitLine": [
                        "length": 12.0,
                        "lineStyle": [
                            "width": 3.0,
                            "color": "#999"
                        ] as [String: Any]
                    ] as [String: Any],
                    "axisLabel": [
                        "distance": 30.0,
                        "color": "#999",
                        "fontSize": 20.0
                    ] as [String: Any],
                    "title": [
                        "show": false
                    ] as [String: Any],
                    "detail": [
                        "backgroundColor": "#fff",
                        "borderColor": "#999",
                        "borderWidth": 2.0,
                        "width": "60%",
                        "lineHeight": 40.0,
                        "height": 40.0,
                        "borderRadius": 8.0,
                        "offsetCenter": [0.0, "35%"] as [Any],
                        "valueAnimation": true,
                        // PORT-NOTE: detail.formatter omitted — the JS closure returned
                        // `'{value|' + value.toFixed(0) + '}{unit|km/h}'`, i.e. the rounded value tagged
                        // for the `value` rich style followed by a literal "km/h" tagged for `unit`.
                        // A Swift closure WOULD fit in this [String: Any] bag (util.isFunction duck-types
                        // one), but GaugeView.formatLabel deliberately does not invoke a function
                        // formatter — the formatter-callback seam is unported — so carrying it here would
                        // be a silent no-op. Native therefore renders the raw value and the `rich` styles
                        // below go unused. Closing this gap means porting that seam, not substituting a
                        // '{value}' string template the official example does not use.
                        "rich": [
                            "value": [
                                "fontSize": 50.0,
                                "fontWeight": "bolder",
                                "color": "#777"
                            ] as [String: Any],
                            "unit": [
                                "fontSize": 20.0,
                                "color": "#999",
                                "padding": [0.0, 0.0, -20.0, 10.0]
                            ] as [String: Any]
                        ] as [String: Any]
                    ] as [String: Any],
                    "data": [
                        ["value": 100.0] as [String: Any]
                    ]
                ] as [String: Any]
            ]
        ])
}

// The pointer's custom needle, an SVG path in echarts' `path://` form (verbatim from the example).
private let gaugeSpeedPointerIcon = "path://M2090.36389,615.30999 L2090.36389,615.30999 C2091.48372,615.30999 2092.40383,616.194028 2092.44859,617.312956 L2096.90698,728.755929 C2097.05155,732.369577 2094.2393,735.416212 2090.62566,735.56078 C2090.53845,735.564269 2090.45117,735.566014 2090.36389,735.566014 L2090.36389,735.566014 C2086.74736,735.566014 2083.81557,732.63423 2083.81557,729.017692 C2083.81557,728.930412 2083.81732,728.84314 2083.82081,728.755929 L2088.2792,617.312956 C2088.32396,616.194028 2089.24407,615.30999 2090.36389,615.30999 Z"
