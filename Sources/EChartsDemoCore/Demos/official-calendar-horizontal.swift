// official-calendar-horizontal — replica of https://echarts.apache.org/examples/zh/editor.html?c=calendar-horizontal
// title: Calendar Heatmap Horizontal / titleCN: 横向日历图
// THREE horizontally-oriented calendar coordinate systems stacked down the canvas (2017 at the default
// `top`, 2016 at `top: 260`, 2015 at `top: 450`), each carrying its own `heatmap` series bound to it by
// `calendarIndex`. One shared continuous `visualMap` (0…1000, calculable, horizontal, centred at the top)
// colours all three. `cellSize: ['auto', 20]` fixes the row height at 20px and lets the week-columns
// stretch to the pane width.
//
// DEVIATIONS from the official source:
//   - DATA: upstream fills each year with `getVirtualData(year)`, which walks every day of the year
//     (echarts.time.parse / echarts.time.format) and assigns `Math.floor(Math.random() * 1000)`. That is
//     NONDETERMINISTIC — the two panes would never agree, and no two renders of the SAME pane would agree
//     either, so the reference↔port diff would be meaningless. The 365 / 366 / 365 [date, value] rows are
//     instead generated ONCE in Swift by a seeded LCG (same shape: '{yyyy}-{MM}-{dd}' × 0…999, 2016 leap-
//     aware) and the SAME arrays are inlined into BOTH panes — spliced into webOptionJS as JSON literals
//     and used verbatim as the native `series[].data`. Follows official-calendar-simple. Everything else
//     (tooltip, visualMap, all three calendars, all three series) is verbatim.
//   - no PORT-NOTE below: the option has NO function-valued key (no formatter / label callback), so the
//     Swift `option` mirrors the JS one key-for-key with NOTHING dropped. `visualMap.type` is left
//     unspelled because the official leaves it unspelled — visualMap's typeDefaulter resolves min/max to
//     `continuous`, and writing it out would be an embellishment.
//   - STATIC: no timers, no myChart calls upstream → no `drive`.
//
// CANVAS SIZE (a gallery knob, not part of the option): 900×620. Width 900 is the example's own
// `shotWidth`; it gives the 'auto' cells ~14px each across the 53 week-columns. The height is set by the
// option itself: the third calendar sits at `top: 450` and is 7 day-rows × 20px = 140px tall, so its
// bottom edge is at 590. A shorter pane crops that last calendar (identically in both panes, so the diff
// would stay honest — but the cropped strip would simply never be compared, which is the whole point of
// the demo's third coordinate system). 620 puts all three calendars fully on-canvas. Both galleries
// aspect-fit the pane, so a taller canvas costs nothing.
import Foundation

// The rows `getVirtualData(year)` would have produced, made deterministic: a fixed-seed LCG stands in for
// Math.random(). Element shape is the upstream `[string, number]` pair.
private func calendarHorizontalYearData(_ year: Int, seed: UInt64) -> [[Any]] {
    var state = seed
    func nextUnit() -> Double {          // deterministic stand-in for Math.random() → [0, 1)
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Double((state >> 33) % 1_000_000) / 1_000_000.0
    }
    var monthDays = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
    if (year % 4 == 0 && year % 100 != 0) || year % 400 == 0 { monthDays[1] = 29 }   // 2016 is a leap year
    var rows: [[Any]] = []
    for (i, days) in monthDays.enumerated() {
        for day in 1...days {
            let date = String(format: "%04d-%02d-%02d", year, i + 1, day)
            rows.append([date, (nextUnit() * 1000).rounded(.down)])
        }
    }
    return rows
}

private let calendarHorizontal2017Data: [[Any]] = calendarHorizontalYearData(2017, seed: 2017_01_01)
private let calendarHorizontal2016Data: [[Any]] = calendarHorizontalYearData(2016, seed: 2016_01_01)
private let calendarHorizontal2015Data: [[Any]] = calendarHorizontalYearData(2015, seed: 2015_01_01)

// The same rows as JSON literals, spliced into the reference pane's JS (see \#( ... ) below).
private func calendarHorizontalJSON(_ rows: [[Any]]) -> String {
    guard let data = try? JSONSerialization.data(withJSONObject: rows, options: []),
          let json = String(data: data, encoding: .utf8) else { return "[]" }
    return json
}
private let calendarHorizontal2017JSON = calendarHorizontalJSON(calendarHorizontal2017Data)
private let calendarHorizontal2016JSON = calendarHorizontalJSON(calendarHorizontal2016Data)
private let calendarHorizontal2015JSON = calendarHorizontalJSON(calendarHorizontal2015Data)

extension EChartsDemoRegistry {
    static let official_calendar_horizontal = EChartsDemo(
        name: "official-calendar-horizontal", category: "calendar",
        summary: "横向日历图 — Calendar Heatmap Horizontal",
        width: 900, height: 620,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
// Upstream builds these with getVirtualData('2017'|'2016'|'2015') (Math.random per day); the identical
// deterministic arrays the native pane uses are inlined here instead, so the two panes are diffable.
var data2017 = \#(calendarHorizontal2017JSON);
var data2016 = \#(calendarHorizontal2016JSON);
var data2015 = \#(calendarHorizontal2015JSON);

option = {
  tooltip: {
    position: 'top'
  },
  visualMap: {
    min: 0,
    max: 1000,
    calculable: true,
    orient: 'horizontal',
    left: 'center',
    top: 'top'
  },

  calendar: [
    {
      range: '2017',
      cellSize: ['auto', 20]
    },
    {
      top: 260,
      range: '2016',
      cellSize: ['auto', 20]
    },
    {
      top: 450,
      range: '2015',
      cellSize: ['auto', 20],
      right: 5
    }
  ],

  series: [
    {
      type: 'heatmap',
      coordinateSystem: 'calendar',
      calendarIndex: 0,
      data: data2017
    },
    {
      type: 'heatmap',
      coordinateSystem: 'calendar',
      calendarIndex: 1,
      data: data2016
    },
    {
      type: 'heatmap',
      coordinateSystem: 'calendar',
      calendarIndex: 2,
      data: data2015
    }
  ]
};
"""#,
        option: [
            "tooltip": [
                "position": "top"
            ] as [String: Any],
            "visualMap": [
                "min": 0.0,
                "max": 1000.0,
                "calculable": true,
                "orient": "horizontal",
                "left": "center",
                "top": "top"
            ] as [String: Any],
            "calendar": [
                [
                    "range": "2017",
                    "cellSize": ["auto", 20.0] as [Any],
                    "monthLabel": ["nameMap": "ZH"] as [String: Any],
                    "dayLabel": ["nameMap": "ZH"] as [String: Any]
                ] as [String: Any],
                [
                    "top": 260.0,
                    "range": "2016",
                    "cellSize": ["auto", 20.0] as [Any],
                    "monthLabel": ["nameMap": "ZH"] as [String: Any],
                    "dayLabel": ["nameMap": "ZH"] as [String: Any]
                ] as [String: Any],
                [
                    "top": 450.0,
                    "range": "2015",
                    "cellSize": ["auto", 20.0] as [Any],
                    "right": 5.0,
                    "monthLabel": ["nameMap": "ZH"] as [String: Any],
                    "dayLabel": ["nameMap": "ZH"] as [String: Any]
                ] as [String: Any]
            ],
            "series": [
                [
                    "type": "heatmap",
                    "coordinateSystem": "calendar",
                    "calendarIndex": 0.0,
                    "data": calendarHorizontal2017Data
                ] as [String: Any],
                [
                    "type": "heatmap",
                    "coordinateSystem": "calendar",
                    "calendarIndex": 1.0,
                    "data": calendarHorizontal2016Data
                ] as [String: Any],
                [
                    "type": "heatmap",
                    "coordinateSystem": "calendar",
                    "calendarIndex": 2.0,
                    "data": calendarHorizontal2015Data
                ] as [String: Any]
            ]
        ])
}
