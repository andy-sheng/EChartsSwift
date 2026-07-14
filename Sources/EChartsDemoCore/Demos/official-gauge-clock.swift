// official-gauge-clock — replica of https://echarts.apache.org/examples/zh/editor.html?c=gauge-clock
// title: Clock / titleCN: 时钟仪表盘
// Three stacked `gauge` series (hour 0-12, minute 0-60, second 0-60) sharing a centre: a shadowed
// black dial with an SVG-path logo anchor, plus three SVG-path pointers of decreasing width and
// increasing length. Upstream a `setInterval(…, 1000)` re-`setOption`s the three series' data from
// `new Date()` every second, so the hands actually tell the time (the second hand's
// `animationEasingUpdate: 'bounceOut'` gives it a mechanical tick).
//
// THE 1s TICK IS PORTED, on both panes. The web pane runs the example's own `setInterval` verbatim;
// the native pane replays the same timeline through `drive` (see EChartsDemoChart), recomputing
// hour/minute/second from `Date()` and merging them into the three series each second. The headless
// still-frame paths ignore `drive` and neuter `setInterval`, so a snapshot deterministically shows
// the initial `value: 0` state — all three hands straight up at 12.
//
// DEVIATIONS from the official source:
//   - The TS type annotation on `myChart.setOption<echarts.EChartsOption>({...})` and the trailing
//     `export {};` are dropped from webOptionJS — a classic script cannot parse either.
//   - NATIVE PANE ONLY: `series[0].axisLabel.formatter` is a JS closure (blanks the "0" label so the
//     dial reads 1…12, not 0/12 twice) and cannot be expressed in a Swift option; the key is omitted,
//     so the native dial labels 0 where the web dial labels nothing. Marked with a PORT-NOTE below.
//   - NATIVE PANE ONLY: upstream's `option.animationDurationUpdate = 300;` inside the interval is
//     dead code (it mutates the already-consumed option literal; echarts has cloned it into its
//     models by then), so `drive` does not replicate it. It stays in webOptionJS verbatim.
import Foundation

// The hand shape, an SVG path — a rounded 5.2 x 120 bar. Upstream repeats this literal in all three
// `pointer.icon`s; it is the same string each time.
private let gaugeClockPointerIcon =
    "path://M2.9,0.7L2.9,0.7c1.4,0,2.6,1.2,2.6,2.6v115c0,1.4-1.2,2.6-2.6,2.6l0,0c-1.4,0-2.6-1.2-2.6-2.6V3.3C0.3,1.9,1.4,0.7,2.9,0.7z"

// The hour dial's anchor icon: the "ECHARTS" wordmark as an SVG path, drawn under the hands.
private let gaugeClockAnchorIcon =
    "path://M532.8,70.8C532.8,70.8,532.8,70.8,532.8,70.8L532.8,70.8C532.7,70.8,532.8,70.8,532.8,70.8z M456.1,49.6c-2.2-6.2-8.1-10.6-15-10.6h-37.5v10.6h37.5l0,0c2.9,0,5.3,2.4,5.3,5.3c0,2.9-2.4,5.3-5.3,5.3v0h-22.5c-1.5,0.1-3,0.4-4.3,0.9c-4.5,1.6-8.1,5.2-9.7,9.8c-0.6,1.7-0.9,3.4-0.9,5.3v16h10.6v-16l0,0l0,0c0-2.7,2.1-5,4.7-5.3h10.3l10.4,21.2h11.8l-10.4-21.2h0c6.9,0,12.8-4.4,15-10.6c0.6-1.7,0.9-3.5,0.9-5.3C457,53,456.7,51.2,456.1,49.6z M388.9,92.1h11.3L381,39h-3.6h-11.3L346.8,92v0h11.3l3.9-10.7h7.3h7.7l3.9-10.6h-7.7h-7.3l7.7-21.2v0L388.9,92.1z M301,38.9h-10.6v53.1H301V70.8h28.4l3.7-10.6H301V38.9zM333.2,38.9v10.6v10.7v31.9h10.6V38.9H333.2z M249.5,81.4L249.5,81.4L249.5,81.4c-2.9,0-5.3-2.4-5.3-5.3h0V54.9h0l0,0c0-2.9,2.4-5.3,5.3-5.3l0,0l0,0h33.6l3.9-10.6h-37.5c-1.9,0-3.6,0.3-5.3,0.9c-4.5,1.6-8.1,5.2-9.7,9.7c-0.6,1.7-0.9,3.5-0.9,5.3l0,0v21.3c0,1.9,0.3,3.6,0.9,5.3c1.6,4.5,5.2,8.1,9.7,9.7c1.7,0.6,3.5,0.9,5.3,0.9h33.6l3.9-10.6H249.5z M176.8,38.9v10.6h49.6l3.9-10.6H176.8z M192.7,81.4L192.7,81.4L192.7,81.4c-2.9,0-5.3-2.4-5.3-5.3l0,0v-5.3h38.9l3.9-10.6h-53.4v10.6v5.3l0,0c0,1.9,0.3,3.6,0.9,5.3c1.6,4.5,5.2,8.1,9.7,9.7c1.7,0.6,3.4,0.9,5.3,0.9h23.4h10.2l3.9-10.6l0,0H192.7z M460.1,38.9v10.6h21.4v42.5h10.6V49.6h17.5l3.8-10.6H460.1z M541.6,68.2c-0.2,0.1-0.4,0.3-0.7,0.4C541.1,68.4,541.4,68.3,541.6,68.2L541.6,68.2z M554.3,60.2h-21.6v0l0,0c-2.9,0-5.3-2.4-5.3-5.3c0-2.9,2.4-5.3,5.3-5.3l0,0l0,0h33.6l3.8-10.6h-37.5l0,0c-6.9,0-12.8,4.4-15,10.6c-0.6,1.7-0.9,3.5-0.9,5.3c0,1.9,0.3,3.7,0.9,5.3c2.2,6.2,8.1,10.6,15,10.6h21.6l0,0c2.9,0,5.3,2.4,5.3,5.3c0,2.9-2.4,5.3-5.3,5.3l0,0h-37.5v10.6h37.5c6.9,0,12.8-4.4,15-10.6c0.6-1.7,0.9-3.5,0.9-5.3c0-1.9-0.3-3.7-0.9-5.3C567.2,64.6,561.3,60.2,554.3,60.2z"

// `axisLine.lineStyle.color: [[1, 'rgba(0,0,0,0.7)']]` — one [stopRatio, color] band covering the
// whole dial. Heterogeneous, so it needs an explicit type.
private let gaugeClockAxisLineColor: [[Any]] = [[1.0, "rgba(0,0,0,0.7)"]]

// The three hands' shared drop shadow (`itemStyle` on every pointer).
private let gaugeClockPointerItemStyle: [String: Any] = [
    "color": "#C0911F",
    "shadowColor": "rgba(0, 0, 0, 0.3)",
    "shadowBlur": 8.0,
    "shadowOffsetX": 2.0,
    "shadowOffsetY": 4.0
]

extension EChartsDemoRegistry {
    static let official_gauge_clock = EChartsDemo(
        name: "official-gauge-clock", category: "gauge",
        summary: "时钟仪表盘 — Clock",
        width: 640, height: 420,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
option = {
  series: [
    {
      name: 'hour',
      type: 'gauge',
      startAngle: 90,
      endAngle: -270,
      min: 0,
      max: 12,
      splitNumber: 12,
      clockwise: true,
      axisLine: {
        lineStyle: {
          width: 15,
          color: [[1, 'rgba(0,0,0,0.7)']],
          shadowColor: 'rgba(0, 0, 0, 0.5)',
          shadowBlur: 15
        }
      },
      splitLine: {
        lineStyle: {
          shadowColor: 'rgba(0, 0, 0, 0.3)',
          shadowBlur: 3,
          shadowOffsetX: 1,
          shadowOffsetY: 2
        }
      },
      axisLabel: {
        fontSize: 50,
        distance: 25,
        formatter: function (value) {
          if (value === 0) {
            return '';
          }
          return value + '';
        }
      },
      anchor: {
        show: true,
        icon:
          'path://M532.8,70.8C532.8,70.8,532.8,70.8,532.8,70.8L532.8,70.8C532.7,70.8,532.8,70.8,532.8,70.8z M456.1,49.6c-2.2-6.2-8.1-10.6-15-10.6h-37.5v10.6h37.5l0,0c2.9,0,5.3,2.4,5.3,5.3c0,2.9-2.4,5.3-5.3,5.3v0h-22.5c-1.5,0.1-3,0.4-4.3,0.9c-4.5,1.6-8.1,5.2-9.7,9.8c-0.6,1.7-0.9,3.4-0.9,5.3v16h10.6v-16l0,0l0,0c0-2.7,2.1-5,4.7-5.3h10.3l10.4,21.2h11.8l-10.4-21.2h0c6.9,0,12.8-4.4,15-10.6c0.6-1.7,0.9-3.5,0.9-5.3C457,53,456.7,51.2,456.1,49.6z M388.9,92.1h11.3L381,39h-3.6h-11.3L346.8,92v0h11.3l3.9-10.7h7.3h7.7l3.9-10.6h-7.7h-7.3l7.7-21.2v0L388.9,92.1z M301,38.9h-10.6v53.1H301V70.8h28.4l3.7-10.6H301V38.9zM333.2,38.9v10.6v10.7v31.9h10.6V38.9H333.2z M249.5,81.4L249.5,81.4L249.5,81.4c-2.9,0-5.3-2.4-5.3-5.3h0V54.9h0l0,0c0-2.9,2.4-5.3,5.3-5.3l0,0l0,0h33.6l3.9-10.6h-37.5c-1.9,0-3.6,0.3-5.3,0.9c-4.5,1.6-8.1,5.2-9.7,9.7c-0.6,1.7-0.9,3.5-0.9,5.3l0,0v21.3c0,1.9,0.3,3.6,0.9,5.3c1.6,4.5,5.2,8.1,9.7,9.7c1.7,0.6,3.5,0.9,5.3,0.9h33.6l3.9-10.6H249.5z M176.8,38.9v10.6h49.6l3.9-10.6H176.8z M192.7,81.4L192.7,81.4L192.7,81.4c-2.9,0-5.3-2.4-5.3-5.3l0,0v-5.3h38.9l3.9-10.6h-53.4v10.6v5.3l0,0c0,1.9,0.3,3.6,0.9,5.3c1.6,4.5,5.2,8.1,9.7,9.7c1.7,0.6,3.4,0.9,5.3,0.9h23.4h10.2l3.9-10.6l0,0H192.7z M460.1,38.9v10.6h21.4v42.5h10.6V49.6h17.5l3.8-10.6H460.1z M541.6,68.2c-0.2,0.1-0.4,0.3-0.7,0.4C541.1,68.4,541.4,68.3,541.6,68.2L541.6,68.2z M554.3,60.2h-21.6v0l0,0c-2.9,0-5.3-2.4-5.3-5.3c0-2.9,2.4-5.3,5.3-5.3l0,0l0,0h33.6l3.8-10.6h-37.5l0,0c-6.9,0-12.8,4.4-15,10.6c-0.6,1.7-0.9,3.5-0.9,5.3c0,1.9,0.3,3.7,0.9,5.3c2.2,6.2,8.1,10.6,15,10.6h21.6l0,0c2.9,0,5.3,2.4,5.3,5.3c0,2.9-2.4,5.3-5.3,5.3l0,0h-37.5v10.6h37.5c6.9,0,12.8-4.4,15-10.6c0.6-1.7,0.9-3.5,0.9-5.3c0-1.9-0.3-3.7-0.9-5.3C567.2,64.6,561.3,60.2,554.3,60.2z',
        showAbove: false,
        offsetCenter: [0, '-35%'],
        size: 120,
        keepAspect: true,
        itemStyle: {
          color: '#707177'
        }
      },
      pointer: {
        icon:
          'path://M2.9,0.7L2.9,0.7c1.4,0,2.6,1.2,2.6,2.6v115c0,1.4-1.2,2.6-2.6,2.6l0,0c-1.4,0-2.6-1.2-2.6-2.6V3.3C0.3,1.9,1.4,0.7,2.9,0.7z',
        width: 12,
        length: '55%',
        offsetCenter: [0, '8%'],
        itemStyle: {
          color: '#C0911F',
          shadowColor: 'rgba(0, 0, 0, 0.3)',
          shadowBlur: 8,
          shadowOffsetX: 2,
          shadowOffsetY: 4
        }
      },
      detail: {
        show: false
      },
      title: {
        offsetCenter: [0, '30%']
      },
      data: [
        {
          value: 0
        }
      ]
    },
    {
      name: 'minute',
      type: 'gauge',
      startAngle: 90,
      endAngle: -270,
      min: 0,
      max: 60,
      clockwise: true,
      axisLine: {
        show: false
      },
      splitLine: {
        show: false
      },
      axisTick: {
        show: false
      },
      axisLabel: {
        show: false
      },
      pointer: {
        icon:
          'path://M2.9,0.7L2.9,0.7c1.4,0,2.6,1.2,2.6,2.6v115c0,1.4-1.2,2.6-2.6,2.6l0,0c-1.4,0-2.6-1.2-2.6-2.6V3.3C0.3,1.9,1.4,0.7,2.9,0.7z',
        width: 8,
        length: '70%',
        offsetCenter: [0, '8%'],
        itemStyle: {
          color: '#C0911F',
          shadowColor: 'rgba(0, 0, 0, 0.3)',
          shadowBlur: 8,
          shadowOffsetX: 2,
          shadowOffsetY: 4
        }
      },
      anchor: {
        show: true,
        size: 20,
        showAbove: false,
        itemStyle: {
          borderWidth: 15,
          borderColor: '#C0911F',
          shadowColor: 'rgba(0, 0, 0, 0.3)',
          shadowBlur: 8,
          shadowOffsetX: 2,
          shadowOffsetY: 4
        }
      },
      detail: {
        show: false
      },
      title: {
        offsetCenter: ['0%', '-40%']
      },
      data: [
        {
          value: 0
        }
      ]
    },
    {
      name: 'second',
      type: 'gauge',
      startAngle: 90,
      endAngle: -270,
      min: 0,
      max: 60,
      animationEasingUpdate: 'bounceOut',
      clockwise: true,
      axisLine: {
        show: false
      },
      splitLine: {
        show: false
      },
      axisTick: {
        show: false
      },
      axisLabel: {
        show: false
      },
      pointer: {
        icon:
          'path://M2.9,0.7L2.9,0.7c1.4,0,2.6,1.2,2.6,2.6v115c0,1.4-1.2,2.6-2.6,2.6l0,0c-1.4,0-2.6-1.2-2.6-2.6V3.3C0.3,1.9,1.4,0.7,2.9,0.7z',
        width: 4,
        length: '85%',
        offsetCenter: [0, '8%'],
        itemStyle: {
          color: '#C0911F',
          shadowColor: 'rgba(0, 0, 0, 0.3)',
          shadowBlur: 8,
          shadowOffsetX: 2,
          shadowOffsetY: 4
        }
      },
      anchor: {
        show: true,
        size: 15,
        showAbove: true,
        itemStyle: {
          color: '#C0911F',
          shadowColor: 'rgba(0, 0, 0, 0.3)',
          shadowBlur: 8,
          shadowOffsetX: 2,
          shadowOffsetY: 4
        }
      },
      detail: {
        show: false
      },
      title: {
        offsetCenter: ['0%', '-40%']
      },
      data: [
        {
          value: 0
        }
      ]
    }
  ]
};

setInterval(function () {
  var date = new Date();
  var second = date.getSeconds();
  var minute = date.getMinutes() + second / 60;
  var hour = (date.getHours() % 12) + minute / 60;

  option.animationDurationUpdate = 300;
  myChart.setOption({
    series: [
      {
        name: 'hour',
        animation: hour !== 0,
        data: [{ value: hour }]
      },
      {
        name: 'minute',
        animation: minute !== 0,
        data: [{ value: minute }]
      },
      {
        animation: second !== 0,
        name: 'second',
        data: [{ value: second }]
      }
    ]
  });
}, 1000);
"""#,
        // The native pane's half of the same timeline: the example's `setInterval(fn, 1000)`, which
        // re-reads the wall clock and MERGES the three hands' new values into the live chart (upstream
        // passes no second argument to setOption, so this is a merge, not a replace — a notMerge here
        // would throw away the dial, the anchors and the pointers every second).
        drive: { chart in
            chart.every(1) {
                let c = Calendar.current.dateComponents([.hour, .minute, .second], from: Date())
                let second = Double(c.second ?? 0)
                let minute = Double(c.minute ?? 0) + second / 60
                let hour = Double((c.hour ?? 0) % 12) + minute / 60
                chart.setOption(gaugeClockTickOption(hour: hour, minute: minute, second: second),
                                notMerge: false)
            }
        },
        option: [
            "series": [gaugeClockHourSeries, gaugeClockMinuteSeries, gaugeClockSecondSeries]
        ])
}

// One tick of the example's interval body: the three hands' new values, merged into the live chart.
// `animation: <hand> !== 0` — upstream suppresses the tween on the wrap-around tick, so a hand going
// 59 → 0 snaps back instead of sweeping the long way round the dial.
private func gaugeClockTickOption(hour: Double, minute: Double, second: Double) -> [String: Any] {
    let hourSeries: [String: Any] = [
        "name": "hour",
        "animation": hour != 0,
        "data": [["value": hour] as [String: Any]]
    ]
    let minuteSeries: [String: Any] = [
        "name": "minute",
        "animation": minute != 0,
        "data": [["value": minute] as [String: Any]]
    ]
    let secondSeries: [String: Any] = [
        "animation": second != 0,
        "name": "second",
        "data": [["value": second] as [String: Any]]
    ]
    return ["series": [hourSeries, minuteSeries, secondSeries]]
}

// The three series, hoisted and explicitly typed — the option nests six levels deep and the
// type-checker gives up on it as one literal.

// hour — the only series that draws the dial itself (axisLine / splitLine / axisLabel).
private let gaugeClockHourSeries: [String: Any] = [
    "name": "hour",
    "type": "gauge",
    "startAngle": 90.0,
    "endAngle": -270.0,
    "min": 0.0,
    "max": 12.0,
    "splitNumber": 12.0,
    "clockwise": true,
    "axisLine": [
        "lineStyle": [
            "width": 15.0,
            "color": gaugeClockAxisLineColor,
            "shadowColor": "rgba(0, 0, 0, 0.5)",
            "shadowBlur": 15.0
        ] as [String: Any]
    ] as [String: Any],
    "splitLine": [
        "lineStyle": [
            "shadowColor": "rgba(0, 0, 0, 0.3)",
            "shadowBlur": 3.0,
            "shadowOffsetX": 1.0,
            "shadowOffsetY": 2.0
        ] as [String: Any]
    ] as [String: Any],
    "axisLabel": [
        "fontSize": 50.0,
        "distance": 25.0
        // PORT-NOTE: axisLabel.formatter omitted — the JS closure returned '' for value 0 (so the dial
        // reads 1…12 with nothing at the top) and `value + ''` otherwise. Without it the native dial
        // prints a "0" at 12 o'clock.
    ] as [String: Any],
    "anchor": [
        "show": true,
        "icon": gaugeClockAnchorIcon,
        "showAbove": false,
        "offsetCenter": [0.0, "-35%"] as [Any],
        "size": 120.0,
        "keepAspect": true,
        "itemStyle": ["color": "#707177"] as [String: Any]
    ] as [String: Any],
    "pointer": [
        "icon": gaugeClockPointerIcon,
        "width": 12.0,
        "length": "55%",
        "offsetCenter": [0.0, "8%"] as [Any],
        "itemStyle": gaugeClockPointerItemStyle
    ] as [String: Any],
    "detail": ["show": false] as [String: Any],
    "title": ["offsetCenter": [0.0, "30%"] as [Any]] as [String: Any],
    "data": [["value": 0.0] as [String: Any]]
]

// minute — bare pointer plus a ring anchor; no dial of its own.
private let gaugeClockMinuteSeries: [String: Any] = [
    "name": "minute",
    "type": "gauge",
    "startAngle": 90.0,
    "endAngle": -270.0,
    "min": 0.0,
    "max": 60.0,
    "clockwise": true,
    "axisLine": ["show": false] as [String: Any],
    "splitLine": ["show": false] as [String: Any],
    "axisTick": ["show": false] as [String: Any],
    "axisLabel": ["show": false] as [String: Any],
    "pointer": [
        "icon": gaugeClockPointerIcon,
        "width": 8.0,
        "length": "70%",
        "offsetCenter": [0.0, "8%"] as [Any],
        "itemStyle": gaugeClockPointerItemStyle
    ] as [String: Any],
    "anchor": [
        "show": true,
        "size": 20.0,
        "showAbove": false,
        "itemStyle": [
            "borderWidth": 15.0,
            "borderColor": "#C0911F",
            "shadowColor": "rgba(0, 0, 0, 0.3)",
            "shadowBlur": 8.0,
            "shadowOffsetX": 2.0,
            "shadowOffsetY": 4.0
        ] as [String: Any]
    ] as [String: Any],
    "detail": ["show": false] as [String: Any],
    "title": ["offsetCenter": ["0%", "-40%"]] as [String: Any],
    "data": [["value": 0.0] as [String: Any]]
]

// second — thinnest, longest hand; its 'bounceOut' update easing is the mechanical tick.
private let gaugeClockSecondSeries: [String: Any] = [
    "name": "second",
    "type": "gauge",
    "startAngle": 90.0,
    "endAngle": -270.0,
    "min": 0.0,
    "max": 60.0,
    "animationEasingUpdate": "bounceOut",
    "clockwise": true,
    "axisLine": ["show": false] as [String: Any],
    "splitLine": ["show": false] as [String: Any],
    "axisTick": ["show": false] as [String: Any],
    "axisLabel": ["show": false] as [String: Any],
    "pointer": [
        "icon": gaugeClockPointerIcon,
        "width": 4.0,
        "length": "85%",
        "offsetCenter": [0.0, "8%"] as [Any],
        "itemStyle": gaugeClockPointerItemStyle
    ] as [String: Any],
    "anchor": [
        "show": true,
        "size": 15.0,
        "showAbove": true,
        "itemStyle": [
            "color": "#C0911F",
            "shadowColor": "rgba(0, 0, 0, 0.3)",
            "shadowBlur": 8.0,
            "shadowOffsetX": 2.0,
            "shadowOffsetY": 4.0
        ] as [String: Any]
    ] as [String: Any],
    "detail": ["show": false] as [String: Any],
    "title": ["offsetCenter": ["0%", "-40%"]] as [String: Any],
    "data": [["value": 0.0] as [String: Any]]
]
