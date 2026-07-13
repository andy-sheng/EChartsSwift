// official-bar-breaks-simple — replica of https://echarts.apache.org/examples/zh/editor.html?c=bar-breaks-simple
// title: Bar Chart with Axis Breaks / titleCN: 断轴上的柱状图
// Four bar series whose magnitudes span three orders of magnitude (10^3, 10^5, 10^6); two `breaks`
// on the value axis collapse the empty ranges (5k–100k, 105k–3.1M) so all four stay readable.
//
// DEVIATIONS from the official source:
//   - The `initAxisBreakInteraction()` block (setTimeout-scheduled: an 'axisbreakchanged' + 'click'
//     handler pair that re-setOptions a `graphic` "Collapse Axis Breaks" button and dispatches
//     `collapseAxisBreak`) is DROPPED from both panes. The gallery renders one static frame, so the
//     button never appears (it is `ignore: true` until a break is expanded by a click) — and the
//     block is TypeScript, not JS: `params: echarts.AxisBreakChangedEvent` / `params as ...` are
//     type annotations that would be a SyntaxError in the reference pane's classic script.
//     Both panes therefore show the INITIAL state: both breaks collapsed.
//   - The trailing `export {};` is dropped (a bare export is a SyntaxError in a classic script).
//   - The reference pane keeps the `_currentAxisBreaks` var verbatim (still referenced by
//     `yAxis.breaks`); the native pane carries the same two breaks as `barBreaksSimpleBreaks`.
// Everything else — title/subtext styling, shadow axisPointer tooltip, legend, grid.top, breakArea,
// per-series `emphasis.focus: 'series'` — is verbatim.
extension EChartsDemoRegistry {
    static let official_bar_breaks_simple = EChartsDemo(
        name: "official-bar-breaks-simple", category: "bar",
        summary: "断轴上的柱状图 — Bar Chart with Axis Breaks",
        width: 640, height: 420,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
var _currentAxisBreaks = [{
  start: 5000,
  end: 100000,
  gap: '1.5%'
}, {
  // `start` and `end` are also used as the identifier for a certain axis break.
  start: 105000,
  end: 3100000,
  gap: '1.5%'
}];

option = {
  title: {
    text: 'Bar Chart with Axis Breaks',
    subtext: 'Click the break area to expand it',
    left: 'center',
    textStyle: {
      fontSize: 20
    },
    subtextStyle: {
      color: '#175ce5',
      fontSize: 15,
      fontWeight: 'bold'
    }
  },
  tooltip: {
    trigger: 'axis',
    axisPointer: {
      type: 'shadow'
    }
  },
  legend: {},
  grid: {
    top: 120,
  },
  xAxis: [{
    type: 'category',
    data: ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']
  }],
  yAxis: [{
    type: 'value',
    breaks: _currentAxisBreaks,
    breakArea: {
      itemStyle: {
        opacity: 1
      },
      zigzagZ: 200,
    }
  }],
  series: [
    {
      name: 'Data A',
      type: 'bar',
      emphasis: {
        focus: 'series'
      },
      data: [1500, 2032, 2001, 3154, 2190, 4330, 2410]
    },
    {
      name: 'Data B',
      type: 'bar',
      emphasis: {
        focus: 'series'
      },
      data: [1200, 1320, 1010, 1340, 900, 2300, 2100]
    },
    {
      name: 'Data C',
      type: 'bar',
      emphasis: {
        focus: 'series'
      },
      data: [103200, 100320, 103010, 102340, 103900, 103300, 103200]
    },
    {
      name: 'Data D',
      type: 'bar',
      data: [3106212, 3102118, 3102643, 3104631, 3106679, 3100130, 3107022],
      emphasis: {
        focus: 'series'
      },
    }
  ]
};
"""#,
        option: [
            "title": [
                "text": "Bar Chart with Axis Breaks",
                "subtext": "Click the break area to expand it",
                "left": "center",
                "textStyle": [
                    "fontSize": 20.0
                ] as [String: Any],
                "subtextStyle": [
                    "color": "#175ce5",
                    "fontSize": 15.0,
                    "fontWeight": "bold"
                ] as [String: Any]
            ] as [String: Any],
            "tooltip": [
                "trigger": "axis",
                "axisPointer": [
                    "type": "shadow"
                ] as [String: Any]
            ] as [String: Any],
            "legend": [:] as [String: Any],
            "grid": [
                "top": 120.0
            ] as [String: Any],
            "xAxis": [
                [
                    "type": "category",
                    "data": ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
                ] as [String: Any]
            ],
            "yAxis": [
                [
                    "type": "value",
                    "breaks": barBreaksSimpleBreaks,
                    "breakArea": [
                        "itemStyle": [
                            "opacity": 1.0
                        ] as [String: Any],
                        "zigzagZ": 200.0
                    ] as [String: Any]
                ] as [String: Any]
            ],
            "series": [
                [
                    "name": "Data A",
                    "type": "bar",
                    "emphasis": ["focus": "series"] as [String: Any],
                    "data": barBreaksSimpleDataA
                ] as [String: Any],
                [
                    "name": "Data B",
                    "type": "bar",
                    "emphasis": ["focus": "series"] as [String: Any],
                    "data": barBreaksSimpleDataB
                ] as [String: Any],
                [
                    "name": "Data C",
                    "type": "bar",
                    "emphasis": ["focus": "series"] as [String: Any],
                    "data": barBreaksSimpleDataC
                ] as [String: Any],
                [
                    "name": "Data D",
                    "type": "bar",
                    "data": barBreaksSimpleDataD,
                    "emphasis": ["focus": "series"] as [String: Any]
                ] as [String: Any]
            ]
        ])
}

// The two collapsed ranges on the value axis. `start`/`end` double as each break's identifier.
private let barBreaksSimpleBreaks: [[String: Any]] = [
    ["start": 5000.0, "end": 100000.0, "gap": "1.5%"],
    ["start": 105000.0, "end": 3100000.0, "gap": "1.5%"]
]

private let barBreaksSimpleDataA: [Double] = [1500, 2032, 2001, 3154, 2190, 4330, 2410]
private let barBreaksSimpleDataB: [Double] = [1200, 1320, 1010, 1340, 900, 2300, 2100]
private let barBreaksSimpleDataC: [Double] = [103200, 100320, 103010, 102340, 103900, 103300, 103200]
private let barBreaksSimpleDataD: [Double] = [3106212, 3102118, 3102643, 3104631, 3106679, 3100130, 3107022]
