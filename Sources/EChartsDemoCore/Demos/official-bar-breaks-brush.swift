// official-bar-breaks-brush — replica of https://echarts.apache.org/examples/zh/editor.html?c=bar-breaks-brush
// title: Bar Chart with Axis Breaks (Brush-enabled) / titleCN: 断轴上的柱状图（可刷选）
// Four bar series whose values straddle two clusters (~1k–4k and ~100k–107k); a y-axis `break`
// (5000 → 100000, collapsed to a 2% gap) elides the empty middle so both clusters stay readable.
// The break band is drawn by `breakArea` (zigzag edges).
//
// DEVIATIONS from the official source:
//   - The `initAxisBreakInteraction()` harness (and its `setTimeout(..., 0)` bootstrap) is DROPPED
//     from both panes. It is the example's interactive half: a zr mousedown/mousemove/
//     document-mouseup brush that converts the dragged pixel span to a data range, merges it into
//     `_currentAxisBreaks`, and re-`setOption`s twice (once at full gap, once at '2%' on a
//     setTimeout) to animate the collapse; plus an `axisbreakchanged` handler that drops breaks the
//     user expanded by clicking. The gallery snapshots ONE static frame, so only the INITIAL state
//     is ported: the single pre-seeded 5000→100000 break. Nothing in `option` depended on it — the
//     official source itself brackets the block with "You can ignore this part if you do not need it."
//     Consequence: the "Brush to create..." subtext is (faithfully) rendered but inert here.
//   - Its TypeScript-only bits (`type AxisBreakItem = ...`, the `: AxisBreakItem[]` annotation) and
//     the trailing `export {};` are removed — neither is valid in the page's classic script.
//   - Canvas is 640x520, not the 420-tall default: `grid` hard-codes a 120px top + 80px bottom for
//     the two-line title, which would leave a ~220px plot at 420.
// Everything else (title/subtext, tooltip, legend, grid, the breaks + breakArea config and all four
// series) is verbatim. No option key is a JS closure, so the native option carries the example whole.
extension EChartsDemoRegistry {
    static let official_bar_breaks_brush = EChartsDemo(
        name: "official-bar-breaks-brush", category: "bar",
        summary: "断轴上的柱状图（可刷选） — Bar Chart with Axis Breaks (Brush-enabled)",
        width: 640, height: 520,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
var GRID_TOP = 120;
var GRID_BOTTOM = 80;

var _currentAxisBreaks = [{
  start: 5000,
  end: 100000,
  gap: '2%'
}];

option = {
  title: {
    text: 'Bar Chart with Axis Break (Brush-enabled)',
    subtext: 'Brush to create a new axis break.\nClick on the break area to reset.',
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
    top: GRID_TOP,
    bottom: GRID_BOTTOM
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
      zigzagMaxSpan: 15,
      zigzagAmplitude: 2,
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
      data: [106212, 102118, 102643, 104631, 106679, 100130, 107022],
      emphasis: {
        focus: 'series'
      },
    }
  ]
};
"""#,
        option: [
            "title": [
                "text": "Bar Chart with Axis Break (Brush-enabled)",
                "subtext": "Brush to create a new axis break.\nClick on the break area to reset.",
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
                "top": barBreaksBrushGridTop,
                "bottom": barBreaksBrushGridBottom
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
                    "breaks": barBreaksBrushCurrentAxisBreaks,
                    "breakArea": [
                        "itemStyle": [
                            "opacity": 1.0
                        ] as [String: Any],
                        "zigzagMaxSpan": 15.0,
                        "zigzagAmplitude": 2.0,
                        "zigzagZ": 200.0
                    ] as [String: Any]
                ] as [String: Any]
            ],
            "series": [
                [
                    "name": "Data A",
                    "type": "bar",
                    "emphasis": ["focus": "series"] as [String: Any],
                    "data": barBreaksBrushDataA
                ] as [String: Any],
                [
                    "name": "Data B",
                    "type": "bar",
                    "emphasis": ["focus": "series"] as [String: Any],
                    "data": barBreaksBrushDataB
                ] as [String: Any],
                [
                    "name": "Data C",
                    "type": "bar",
                    "emphasis": ["focus": "series"] as [String: Any],
                    "data": barBreaksBrushDataC
                ] as [String: Any],
                [
                    "name": "Data D",
                    "type": "bar",
                    "data": barBreaksBrushDataD,
                    "emphasis": ["focus": "series"] as [String: Any]
                ] as [String: Any]
            ]
        ])
}

// The example's GRID_TOP / GRID_BOTTOM consts (the title needs the extra headroom).
private let barBreaksBrushGridTop: Double = 120
private let barBreaksBrushGridBottom: Double = 80

// The pre-seeded break, i.e. `_currentAxisBreaks` before any brushing: the 5000→100000 void is
// collapsed to a 2%-of-axis gap.
private let barBreaksBrushCurrentAxisBreaks: [[String: Any]] = [
    [
        "start": 5000.0,
        "end": 100000.0,
        "gap": "2%"
    ] as [String: Any]
]

private let barBreaksBrushDataA: [Double] = [1500, 2032, 2001, 3154, 2190, 4330, 2410]
private let barBreaksBrushDataB: [Double] = [1200, 1320, 1010, 1340, 900, 2300, 2100]
private let barBreaksBrushDataC: [Double] = [103200, 100320, 103010, 102340, 103900, 103300, 103200]
private let barBreaksBrushDataD: [Double] = [106212, 102118, 102643, 104631, 106679, 100130, 107022]
