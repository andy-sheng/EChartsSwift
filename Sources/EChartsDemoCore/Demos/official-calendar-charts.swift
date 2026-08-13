// official-calendar-charts — replica of https://echarts.apache.org/examples/zh/editor.html?c=calendar-charts
// title: Calendar Charts / titleCN: 日历图
// Four vertical-orient calendar coordinate systems (2017-01 … 2017-04, cellSize 40), each carrying a
// DIFFERENT series type to show what a calendar coord sys can host: a directed `graph` (arrow edges walking
// Feb 1 → Feb 27) and a `heatmap` on calendar 0, an `effectScatter` on calendar 1, a `scatter` on calendar 2,
// a second `heatmap` on calendar 3. Two `visualMap`s split the series between them — a `calculable` one for
// series [2,3,4], a grey/opacity one for series [1].
//
// DEVIATIONS from the official source:
//   - DATA: upstream fills four of the five series with `getVirtualData('2017')`, which walks every day of
//     2017 (echarts.time.parse / echarts.time.format) assigning `Math.floor(Math.random() * 1000)` — and it
//     calls it FOUR SEPARATE TIMES, so each series gets its own fresh random array. That is
//     NONDETERMINISTIC: the two panes would never agree, nor would two renders of the same pane, so the
//     reference↔port diff would be meaningless. The 4 × 365 [date, value] rows are instead generated ONCE in
//     Swift by a seeded LCG (same shape: '{yyyy}-{MM}-{dd}' × 0…999, four arrays drawn in upstream's call
//     order from one stream) and the SAME arrays feed BOTH panes — spliced into webOptionJS as JSON
//     literals, and used verbatim as the native `series[].data`. `graphData` / `links` are already literal
//     upstream and stay verbatim.
//   - The effectScatter/scatter `symbolSize` functions use the typed native callback seam. The native
//     option also pins the default calendar locale to Chinese for January/March, matching the zh official
//     example page (February already specifies `nameMap: 'cn'`; April explicitly uses English weekdays).
//   - `export {};` and the TS type annotations are dropped (a bare export is a SyntaxError in the reference
//     page's classic script).
//
// CANVAS SIZE (a gallery knob, not part of the option): the calendars are hard-positioned by the option —
// the right column sits at `left: 460` (+ 7 day-columns × 40 = 740px right edge) and the bottom row at
// `top: 350` (+ 5 week-rows × 40 = 550px bottom edge), with both visualMaps at `bottom: 20` under that. The
// pane is therefore 900×600 (upstream's own shot is 1000 wide): at the default 460 height the bottom two
// calendars and both visualMaps would be off-canvas / overlapping in BOTH panes.
import Foundation
import EChartsKit

// The four random arrays upstream's four `getVirtualData('2017')` calls would have produced, made
// deterministic: a fixed-seed LCG stands in for Math.random(), drawn in upstream's call order (heatmap,
// effectScatter, scatter, heatmap). Row shape is the upstream `[string, number]` pair.
private let calendarChartsVirtualData: [[[Any]]] = {
    var seed: UInt64 = 2017_01_01
    func nextUnit() -> Double {          // deterministic stand-in for Math.random() → [0, 1)
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        return Double((seed >> 33) % 1_000_000) / 1_000_000.0
    }
    let monthDays = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]   // 2017 is not a leap year
    var sets: [[[Any]]] = []
    for _ in 0..<4 {                     // one array per getVirtualData('2017') call
        var rows: [[Any]] = []
        for (i, days) in monthDays.enumerated() {
            for day in 1...days {
                let date = String(format: "2017-%02d-%02d", i + 1, day)
                rows.append([date, (nextUnit() * 1000).rounded(.down)])
            }
        }
        sets.append(rows)
    }
    return sets
}()

private let calendarChartsHeatmap0Data: [[Any]] = calendarChartsVirtualData[0]        // series 1, calendar 0
private let calendarChartsEffectScatterData: [[Any]] = calendarChartsVirtualData[1]   // series 2, calendar 1
private let calendarChartsScatterData: [[Any]] = calendarChartsVirtualData[2]         // series 3, calendar 2
private let calendarChartsHeatmap3Data: [[Any]] = calendarChartsVirtualData[3]        // series 4, calendar 3

// The graph series' 7 nodes (upstream literal) and the 6 edges chaining them (upstream's
// `graphData.map(...)` + `links.pop()` — node i → node i+1, minus the dangling last one).
private let calendarChartsGraphData: [[Any]] = [
    ["2017-02-01", 260.0],
    ["2017-02-04", 200.0],
    ["2017-02-09", 279.0],
    ["2017-02-13", 847.0],
    ["2017-02-18", 241.0],
    ["2017-02-23", 411.0],
    ["2017-02-27", 985.0]
]
private let calendarChartsLinks: [[String: Any]] =
    (0..<(calendarChartsGraphData.count - 1)).map { ["source": Double($0), "target": Double($0 + 1)] }

// The arrays as JSON literals, spliced into the reference pane's JS (see \#( ... ) below).
private func calendarChartsJSON(_ value: Any) -> String {
    guard let data = try? JSONSerialization.data(withJSONObject: value, options: []),
          let json = String(data: data, encoding: .utf8) else { return "[]" }
    return json
}
private let calendarChartsHeatmap0JSON: String = calendarChartsJSON(calendarChartsHeatmap0Data)
private let calendarChartsEffectScatterJSON: String = calendarChartsJSON(calendarChartsEffectScatterData)
private let calendarChartsScatterJSON: String = calendarChartsJSON(calendarChartsScatterData)
private let calendarChartsHeatmap3JSON: String = calendarChartsJSON(calendarChartsHeatmap3Data)

private let calendarChartsEffectSymbolSize: SymbolSizeCallback<CallbackDataParams> = { rawValue, _ in
    let row = rawValue as? [Any] ?? []
    let value = (row.count > 1 ? row[1] : nil)
        .flatMap { ($0 as? Double) ?? ($0 as? Int).map(Double.init) } ?? 0
    return value / 40
}

private let calendarChartsScatterSymbolSize: SymbolSizeCallback<CallbackDataParams> = { rawValue, _ in
    let row = rawValue as? [Any] ?? []
    let value = (row.count > 1 ? row[1] : nil)
        .flatMap { ($0 as? Double) ?? ($0 as? Int).map(Double.init) } ?? 0
    return value / 60
}

extension EChartsDemoRegistry {
    static let official_calendar_charts = EChartsDemo(
        name: "official-calendar-charts", category: "calendar",
        summary: "日历图 — Calendar Charts",
        width: 900, height: 600,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
// Upstream calls getVirtualData('2017') four times (Math.floor(Math.random() * 1000) per day of 2017, a
// fresh array each call); the identical deterministic arrays the native pane uses are inlined here
// instead, so the two panes are diffable.
const virtualData1 = \#(calendarChartsHeatmap0JSON);
const virtualData2 = \#(calendarChartsEffectScatterJSON);
const virtualData3 = \#(calendarChartsScatterJSON);
const virtualData4 = \#(calendarChartsHeatmap3JSON);

const graphData = [
  ['2017-02-01', 260],
  ['2017-02-04', 200],
  ['2017-02-09', 279],
  ['2017-02-13', 847],
  ['2017-02-18', 241],
  ['2017-02-23', 411],
  ['2017-02-27', 985]
];

const links = graphData.map(function (item, idx) {
  return {
    source: idx,
    target: idx + 1
  };
});
links.pop();

option = {
  tooltip: {
    position: 'top'
  },

  visualMap: [
    {
      min: 0,
      max: 1000,
      calculable: true,
      seriesIndex: [2, 3, 4],
      orient: 'horizontal',
      left: '55%',
      bottom: 20
    },
    {
      min: 0,
      max: 1000,
      inRange: {
        color: ['grey'],
        opacity: [0, 0.3]
      },
      controller: {
        inRange: {
          opacity: [0.3, 0.6]
        },
        outOfRange: {
          color: '#ccc'
        }
      },
      seriesIndex: [1],
      orient: 'horizontal',
      left: '10%',
      bottom: 20
    }
  ],

  calendar: [
    {
      orient: 'vertical',
      yearLabel: {
        margin: 40
      },
      monthLabel: {
        nameMap: 'cn',
        margin: 20
      },
      dayLabel: {
        firstDay: 1,
        nameMap: 'cn'
      },
      cellSize: 40,
      range: '2017-02'
    },
    {
      orient: 'vertical',
      yearLabel: {
        margin: 40
      },
      monthLabel: {
        margin: 20
      },
      cellSize: 40,
      left: 460,
      range: '2017-01'
    },
    {
      orient: 'vertical',
      yearLabel: {
        margin: 40
      },
      monthLabel: {
        margin: 20
      },
      cellSize: 40,
      top: 350,
      range: '2017-03'
    },
    {
      orient: 'vertical',
      yearLabel: {
        margin: 40
      },
      dayLabel: {
        firstDay: 1,
        nameMap: ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat']
      },
      monthLabel: {
        nameMap: 'cn',
        margin: 20
      },
      cellSize: 40,
      top: 350,
      left: 460,
      range: '2017-04'
    }
  ],

  series: [
    {
      type: 'graph',
      edgeSymbol: ['none', 'arrow'],
      coordinateSystem: 'calendar',
      links: links,
      symbolSize: 10,
      calendarIndex: 0,
      data: graphData
    },
    {
      type: 'heatmap',
      coordinateSystem: 'calendar',
      data: virtualData1
    },
    {
      type: 'effectScatter',
      coordinateSystem: 'calendar',
      calendarIndex: 1,
      symbolSize: function (val) {
        return val[1] / 40;
      },
      data: virtualData2
    },
    {
      type: 'scatter',
      coordinateSystem: 'calendar',
      calendarIndex: 2,
      symbolSize: function (val) {
        return val[1] / 60;
      },
      data: virtualData3
    },
    {
      type: 'heatmap',
      coordinateSystem: 'calendar',
      calendarIndex: 3,
      data: virtualData4
    }
  ]
};
"""#,
        option: [
            "tooltip": [
                "position": "top"
            ] as [String: Any],
            "visualMap": [
                [
                    "min": 0.0,
                    "max": 1000.0,
                    "calculable": true,
                    "seriesIndex": [2.0, 3.0, 4.0],
                    "orient": "horizontal",
                    "left": "55%",
                    "bottom": 20.0
                ] as [String: Any],
                [
                    "min": 0.0,
                    "max": 1000.0,
                    "inRange": [
                        "color": ["grey"],
                        "opacity": [0.0, 0.3]
                    ] as [String: Any],
                    "controller": [
                        "inRange": [
                            "opacity": [0.3, 0.6]
                        ] as [String: Any],
                        "outOfRange": [
                            "color": "#ccc"
                        ] as [String: Any]
                    ] as [String: Any],
                    "seriesIndex": [1.0],
                    "orient": "horizontal",
                    "left": "10%",
                    "bottom": 20.0
                ] as [String: Any]
            ],
            "calendar": [
                [
                    "orient": "vertical",
                    "yearLabel": [
                        "margin": 40.0
                    ] as [String: Any],
                    "monthLabel": [
                        "nameMap": "ZH",
                        "margin": 20.0
                    ] as [String: Any],
                    "dayLabel": [
                        "firstDay": 1.0,
                        "nameMap": "ZH"
                    ] as [String: Any],
                    "cellSize": 40.0,
                    "range": "2017-02"
                ] as [String: Any],
                [
                    "orient": "vertical",
                    "yearLabel": [
                        "margin": 40.0
                    ] as [String: Any],
                    "monthLabel": [
                        "nameMap": "ZH",
                        "margin": 20.0
                    ] as [String: Any],
                    "dayLabel": [
                        "nameMap": "ZH"
                    ] as [String: Any],
                    "cellSize": 40.0,
                    "left": 460.0,
                    "range": "2017-01"
                ] as [String: Any],
                [
                    "orient": "vertical",
                    "yearLabel": [
                        "margin": 40.0
                    ] as [String: Any],
                    "monthLabel": [
                        "nameMap": "ZH",
                        "margin": 20.0
                    ] as [String: Any],
                    "dayLabel": [
                        "nameMap": "ZH"
                    ] as [String: Any],
                    "cellSize": 40.0,
                    "top": 350.0,
                    "range": "2017-03"
                ] as [String: Any],
                [
                    "orient": "vertical",
                    "yearLabel": [
                        "margin": 40.0
                    ] as [String: Any],
                    "dayLabel": [
                        "firstDay": 1.0,
                        "nameMap": ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
                    ] as [String: Any],
                    "monthLabel": [
                        "nameMap": "ZH",
                        "margin": 20.0
                    ] as [String: Any],
                    "cellSize": 40.0,
                    "top": 350.0,
                    "left": 460.0,
                    "range": "2017-04"
                ] as [String: Any]
            ],
            "series": [
                [
                    "type": "graph",
                    "edgeSymbol": ["none", "arrow"],
                    "coordinateSystem": "calendar",
                    "links": calendarChartsLinks,
                    "symbolSize": 10.0,
                    "calendarIndex": 0.0,
                    "data": calendarChartsGraphData
                ] as [String: Any],
                [
                    "type": "heatmap",
                    "coordinateSystem": "calendar",
                    "data": calendarChartsHeatmap0Data
                ] as [String: Any],
                [
                    "type": "effectScatter",
                    "coordinateSystem": "calendar",
                    "calendarIndex": 1.0,
                    "symbolSize": calendarChartsEffectSymbolSize,
                    "data": calendarChartsEffectScatterData
                ] as [String: Any],
                [
                    "type": "scatter",
                    "coordinateSystem": "calendar",
                    "calendarIndex": 2.0,
                    "symbolSize": calendarChartsScatterSymbolSize,
                    "data": calendarChartsScatterData
                ] as [String: Any],
                [
                    "type": "heatmap",
                    "coordinateSystem": "calendar",
                    "calendarIndex": 3.0,
                    "data": calendarChartsHeatmap3Data
                ] as [String: Any]
            ]
        ])
}
