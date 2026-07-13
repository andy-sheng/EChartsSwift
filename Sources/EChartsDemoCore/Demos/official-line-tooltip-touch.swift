// official-line-tooltip-touch — replica of https://echarts.apache.org/examples/zh/editor.html?c=line-tooltip-touch
// title: Tooltip and DataZoom on Mobile / titleCN: 移动端上的 dataZoom 和 tooltip
// The mobile touch pattern: two stacked smooth area lines on a `time` xAxis, an always-on xAxis
// `axisPointer` parked at 2016-10-7 with a draggable handle (`handle.show`), a `triggerOn: 'none'`
// tooltip driven only by that handle, inside-dataZoom + a dataZoom/restore toolbox, and inside-drawn
// axis labels/ticks so the grid can run edge-to-edge.
//
// DEVIATIONS from the official source:
//   - DATA FROZEN / DETERMINISTIC. Upstream builds both 9-point series at load time from `Math.random()`
//     (start `Math.random() * 300` / `* 50`, then a ±10 walk per day off `+new Date(2016, 9, 3)`). That is
//     NONDETERMINISTIC — the two panes would never agree and no two renders of one pane would agree, so the
//     reference↔port diff would be meaningless. The identical loop was run ONCE with a fixed-seed LCG standing
//     in for Math.random(), and the SAME frozen rows feed BOTH panes: spliced into webOptionJS as a JSON
//     literal, and used verbatim as the native `series.data`. Row count (9), date strings and shape
//     ([dayStr, value]) are unchanged.
//   - `tooltip.position` is a JS closure and is dropped from the native option (see PORT-NOTE); with
//     `triggerOn: 'none'` the tooltip only ever appears via the axisPointer handle, which a static
//     snapshot never shows. The reference pane keeps it.
//   - `xAxis.axisPointer.label.formatter` is a JS closure (`echarts.format.formatTime`) and is dropped from
//     the native option (see PORT-NOTE); the label still shows, with echarts' default time formatting.
//   - `new echarts.graphic.LinearGradient(0, 0, 0, 1, [...])` is kept verbatim in the reference pane and
//     spelled as the equivalent plain object (`{type:'linear', x:0, y:0, x2:0, y2:1, colorStops:[...]}`) in
//     the native option — echarts accepts both.
//   - `legend.data: ['Intention']` matches no series (both are named 'Fake Data'); kept verbatim, upstream
//     renders the same dangling legend entry.
//   - the official source is TypeScript: the `params: any` annotation on the axisPointer label formatter and
//     the trailing `export {};` are stripped (both are SyntaxErrors in the reference pane's classic script).
//   - the rest of the option is verbatim.
import Foundation

// The two 9-row [dayStr, value] series upstream's loop would have produced, made deterministic (see the
// file header). Values are integers because upstream `Math.round`s each step.
private let lineTooltipTouchData: [[Any]] = [
    ["2016-10-4", 137.0], ["2016-10-5", 131.0], ["2016-10-6", 129.0],
    ["2016-10-7", 124.0], ["2016-10-8", 124.0], ["2016-10-9", 117.0],
    ["2016-10-10", 124.0], ["2016-10-11", 124.0], ["2016-10-12", 132.0]
]

private let lineTooltipTouchData2: [[Any]] = [
    ["2016-10-4", 39.0], ["2016-10-5", 32.0], ["2016-10-6", 39.0],
    ["2016-10-7", 31.0], ["2016-10-8", 22.0], ["2016-10-9", 22.0],
    ["2016-10-10", 24.0], ["2016-10-11", 29.0], ["2016-10-12", 28.0]
]

// The same rows as JSON literals, spliced into the reference pane's JS (see \#( ... ) below).
private func lineTooltipTouchJSON(_ rows: [[Any]]) -> String {
    guard let data = try? JSONSerialization.data(withJSONObject: rows, options: []),
          let json = String(data: data, encoding: .utf8) else { return "[]" }
    return json
}
private let lineTooltipTouchDataJSON: String = lineTooltipTouchJSON(lineTooltipTouchData)
private let lineTooltipTouchData2JSON: String = lineTooltipTouchJSON(lineTooltipTouchData2)

extension EChartsDemoRegistry {
    static let official_line_tooltip_touch = EChartsDemo(
        name: "official-line-tooltip-touch", category: "line",
        summary: "移动端上的 dataZoom 和 tooltip — Tooltip and DataZoom on Mobile",
        width: 640, height: 420,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
// Upstream walks 9 days off `+new Date(2016, 9, 3)` with Math.random(); the identical deterministic
// rows the native pane uses are inlined here instead, so the two panes are diffable.
let data = \#(lineTooltipTouchDataJSON);
let data2 = \#(lineTooltipTouchData2JSON);

option = {
  title: {
    left: 'center',
    text: 'Tootip and dataZoom on Mobile Device'
  },
  legend: {
    top: 'bottom',
    data: ['Intention']
  },
  tooltip: {
    triggerOn: 'none',
    position: function (pt) {
      return [pt[0], 130];
    }
  },
  toolbox: {
    left: 'center',
    itemSize: 25,
    top: 55,
    feature: {
      dataZoom: {
        yAxisIndex: 'none'
      },
      restore: {}
    }
  },
  xAxis: {
    type: 'time',
    axisPointer: {
      value: '2016-10-7',
      snap: true,
      lineStyle: {
        color: '#7581BD',
        width: 2
      },
      label: {
        show: true,
        formatter: function (params) {
          return echarts.format.formatTime('yyyy-MM-dd', params.value);
        },
        backgroundColor: '#7581BD'
      },
      handle: {
        show: true,
        color: '#7581BD'
      }
    },
    splitLine: {
      show: false
    }
  },
  yAxis: {
    type: 'value',
    axisTick: {
      inside: true
    },
    splitLine: {
      show: false
    },
    axisLabel: {
      inside: true,
      formatter: '{value}\n'
    },
    z: 10
  },
  grid: {
    top: 110,
    left: 15,
    right: 15,
    height: 160
  },
  dataZoom: [
    {
      type: 'inside',
      throttle: 50
    }
  ],
  series: [
    {
      name: 'Fake Data',
      type: 'line',
      smooth: true,
      symbol: 'circle',
      symbolSize: 5,
      sampling: 'average',
      itemStyle: {
        color: '#0770FF'
      },
      stack: 'a',
      areaStyle: {
        color: new echarts.graphic.LinearGradient(0, 0, 0, 1, [
          {
            offset: 0,
            color: 'rgba(58,77,233,0.8)'
          },
          {
            offset: 1,
            color: 'rgba(58,77,233,0.3)'
          }
        ])
      },
      data: data
    },
    {
      name: 'Fake Data',
      type: 'line',
      smooth: true,
      stack: 'a',
      symbol: 'circle',
      symbolSize: 5,
      sampling: 'average',
      itemStyle: {
        color: '#F2597F'
      },
      areaStyle: {
        color: new echarts.graphic.LinearGradient(0, 0, 0, 1, [
          {
            offset: 0,
            color: 'rgba(213,72,120,0.8)'
          },
          {
            offset: 1,
            color: 'rgba(213,72,120,0.3)'
          }
        ])
      },
      data: data2
    }
  ]
};
"""#,
        option: [
            "title": [
                "left": "center",
                "text": "Tootip and dataZoom on Mobile Device"
            ] as [String: Any],
            "legend": [
                "top": "bottom",
                "data": ["Intention"]
            ] as [String: Any],
            "tooltip": [
                "triggerOn": "none"
                // PORT-NOTE: tooltip.position omitted — JS closure `function (pt) { return [pt[0], 130]; }`,
                // which pins the tooltip box to the axisPointer handle's x and a fixed y of 130px.
            ] as [String: Any],
            "toolbox": [
                "left": "center",
                "itemSize": 25.0,
                "top": 55.0,
                "feature": [
                    "dataZoom": [
                        "yAxisIndex": "none"
                    ] as [String: Any],
                    "restore": [:] as [String: Any]
                ] as [String: Any]
            ] as [String: Any],
            "xAxis": [
                "type": "time",
                "axisPointer": [
                    "value": "2016-10-7",
                    "snap": true,
                    "lineStyle": [
                        "color": "#7581BD",
                        "width": 2.0
                    ] as [String: Any],
                    "label": [
                        "show": true,
                        // PORT-NOTE: label.formatter omitted — JS closure
                        // `echarts.format.formatTime('yyyy-MM-dd', params.value)`, which renders the pointer's
                        // timestamp as e.g. `2016-10-07`. Without it the default time label formatting applies.
                        "backgroundColor": "#7581BD"
                    ] as [String: Any],
                    "handle": [
                        "show": true,
                        "color": "#7581BD"
                    ] as [String: Any]
                ] as [String: Any],
                "splitLine": [
                    "show": false
                ] as [String: Any]
            ] as [String: Any],
            "yAxis": [
                "type": "value",
                "axisTick": [
                    "inside": true
                ] as [String: Any],
                "splitLine": [
                    "show": false
                ] as [String: Any],
                "axisLabel": [
                    "inside": true,
                    "formatter": "{value}\n"
                ] as [String: Any],
                "z": 10.0
            ] as [String: Any],
            "grid": [
                "top": 110.0,
                "left": 15.0,
                "right": 15.0,
                "height": 160.0
            ] as [String: Any],
            "dataZoom": [
                [
                    "type": "inside",
                    "throttle": 50.0
                ] as [String: Any]
            ],
            "series": [
                [
                    "name": "Fake Data",
                    "type": "line",
                    "smooth": true,
                    "symbol": "circle",
                    "symbolSize": 5.0,
                    "sampling": "average",
                    "itemStyle": [
                        "color": "#0770FF"
                    ] as [String: Any],
                    "stack": "a",
                    "areaStyle": [
                        "color": [
                            "type": "linear",
                            "x": 0.0, "y": 0.0, "x2": 0.0, "y2": 1.0,
                            "colorStops": [
                                ["offset": 0.0, "color": "rgba(58,77,233,0.8)"] as [String: Any],
                                ["offset": 1.0, "color": "rgba(58,77,233,0.3)"] as [String: Any]
                            ] as [Any]
                        ] as [String: Any]
                    ] as [String: Any],
                    "data": lineTooltipTouchData
                ] as [String: Any],
                [
                    "name": "Fake Data",
                    "type": "line",
                    "smooth": true,
                    "stack": "a",
                    "symbol": "circle",
                    "symbolSize": 5.0,
                    "sampling": "average",
                    "itemStyle": [
                        "color": "#F2597F"
                    ] as [String: Any],
                    "areaStyle": [
                        "color": [
                            "type": "linear",
                            "x": 0.0, "y": 0.0, "x2": 0.0, "y2": 1.0,
                            "colorStops": [
                                ["offset": 0.0, "color": "rgba(213,72,120,0.8)"] as [String: Any],
                                ["offset": 1.0, "color": "rgba(213,72,120,0.3)"] as [String: Any]
                            ] as [Any]
                        ] as [String: Any]
                    ] as [String: Any],
                    "data": lineTooltipTouchData2
                ] as [String: Any]
            ]
        ])
}
