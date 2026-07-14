// official-calendar-vertical — replica of https://echarts.apache.org/examples/zh/editor.html?c=calendar-vertical
// title: Calendar Heatmap Vertical / titleCN: 纵向日历图
// THREE vertical calendar coordinate systems side by side (2015, 2016, 2017), each carrying its own
// `heatmap` series (calendarIndex 0/1/2), with one continuous+calculable vertical visualMap (0…1000)
// parked at the right. The point of the example is the contrast between a FIXED cell height (calendars
// 0 and 1 leave `cellSize` at its default 20, so their 53-week columns run to ~1060px tall) and an AUTO
// one (calendar 2 asks for `cellSize: [20, 'auto']` + `bottom: 10`, so its weeks stretch to fit the pane).
//
// DEVIATIONS from the official source:
//   - DATA: the example builds each year with `getVirtualData(year)`, which walks every day of that year
//     (echarts.time.parse / echarts.time.format) and assigns `Math.floor(Math.random() * 1000)`. That is
//     NONDETERMINISTIC — the two panes would never agree, and no two renders of the same pane would agree
//     either, so the reference↔port diff would be meaningless. The 365 / 366 / 365 [date, value] rows
//     (2016 IS a leap year) are instead generated ONCE in Swift by a seeded LCG (same shape:
//     '{yyyy}-{MM}-{dd}' × 0…999) and the SAME arrays are inlined into BOTH panes — spliced into
//     webOptionJS as JSON literals, and used verbatim as the native `series[].data`. The rest of the
//     option is verbatim.
//     (Upstream also formats its timestamps with `useUTC = false` while parsing them as UTC, so
//     west-of-UTC viewers actually get the year shifted a day; our rows are the clean
//     one-per-calendar-day set.)
//   - `export {};` and the TS type annotations are dropped (a bare export is a SyntaxError in the
//     reference page's classic script).
//   - see the PORT-NOTE below: `tooltip.formatter` is a JS closure, so the native option cannot carry it.
//
// CANVAS SIZE (a gallery knob, not part of the option): 900×560, the example's own `shotWidth: 900`.
// Calendars 0 and 1 are ~1060px tall at their default 20px cells and are therefore CROPPED at the bottom
// — as they are on the official page at any normal chart height, and identically in BOTH panes here, so
// the diff stays honest for the visible part. Width 900 is what the option demands: the visualMap sits at
// `left: '670'` and needs its bar + labels to the right of that.
import Foundation

// The rows that `getVirtualData(year)` would have produced, made deterministic: a fixed-seed LCG stands in
// for Math.random(). Element shape is the upstream `[string, number]` pair.
private func calendarVerticalRows(year: Int, leap: Bool, seed initialSeed: UInt64) -> [[Any]] {
    var seed = initialSeed
    func nextUnit() -> Double {          // deterministic stand-in for Math.random() → [0, 1)
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        return Double((seed >> 33) % 1_000_000) / 1_000_000.0
    }
    let monthDays = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
    var rows: [[Any]] = []
    for (i, days) in monthDays.enumerated() {
        for day in 1...days {
            let date = String(format: "%04d-%02d-%02d", year, i + 1, day)
            rows.append([date, (nextUnit() * 1000).rounded(.down)])
        }
    }
    return rows
}

private let calendarVertical2015: [[Any]] = calendarVerticalRows(year: 2015, leap: false, seed: 2015_01_01)
private let calendarVertical2016: [[Any]] = calendarVerticalRows(year: 2016, leap: true, seed: 2016_01_01)
private let calendarVertical2017: [[Any]] = calendarVerticalRows(year: 2017, leap: false, seed: 2017_01_01)

// The same rows as JSON literals, spliced into the reference pane's JS (see \#( ... ) below).
private func calendarVerticalJSON(_ rows: [[Any]]) -> String {
    guard let data = try? JSONSerialization.data(withJSONObject: rows, options: []),
          let json = String(data: data, encoding: .utf8) else { return "[]" }
    return json
}
private let calendarVertical2015JSON = calendarVerticalJSON(calendarVertical2015)
private let calendarVertical2016JSON = calendarVerticalJSON(calendarVertical2016)
private let calendarVertical2017JSON = calendarVerticalJSON(calendarVertical2017)

extension EChartsDemoRegistry {
    static let official_calendar_vertical = EChartsDemo(
        name: "official-calendar-vertical", category: "calendar",
        summary: "纵向日历图 — Calendar Heatmap Vertical",
        width: 900, height: 560,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
// Upstream builds these three with getVirtualData('2015'|'2016'|'2017') (Math.random per day); the
// identical deterministic arrays the native pane uses are inlined here instead, so the panes are diffable.
var data2015 = \#(calendarVertical2015JSON);
var data2016 = \#(calendarVertical2016JSON);
var data2017 = \#(calendarVertical2017JSON);

option = {
  tooltip: {
    position: 'top',
    formatter: function (p) {
      const format = echarts.time.format(p.data[0], '{yyyy}-{MM}-{dd}', false);
      return format + ': ' + p.data[1];
    }
  },
  visualMap: {
    min: 0,
    max: 1000,
    calculable: true,
    orient: 'vertical',
    left: '670',
    top: 'center'
  },

  calendar: [
    {
      orient: 'vertical',
      range: '2015'
    },
    {
      left: 300,
      orient: 'vertical',
      range: '2016'
    },
    {
      left: 520,
      cellSize: [20, 'auto'],
      bottom: 10,
      orient: 'vertical',
      range: '2017',
      dayLabel: {
        margin: 5
      }
    }
  ],

  series: [
    {
      type: 'heatmap',
      coordinateSystem: 'calendar',
      calendarIndex: 0,
      data: data2015
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
      data: data2017
    }
  ]
};
"""#,
        option: [
            "tooltip": [
                "position": "top"
                // PORT-NOTE: tooltip.formatter omitted — a JS closure that re-formatted the row's date
                // through `echarts.time.format(p.data[0], '{yyyy}-{MM}-{dd}', false)` and returned
                // "<date>: <value>". Tooltips are not rendered in the static snapshot anyway.
            ] as [String: Any],
            "visualMap": [
                "min": 0.0,
                "max": 1000.0,
                "calculable": true,
                "orient": "vertical",
                "left": "670",
                "top": "center"
            ] as [String: Any],
            "calendar": [
                [
                    "orient": "vertical",
                    "range": "2015"
                ] as [String: Any],
                [
                    "left": 300.0,
                    "orient": "vertical",
                    "range": "2016"
                ] as [String: Any],
                [
                    "left": 520.0,
                    "cellSize": [20.0, "auto"] as [Any],
                    "bottom": 10.0,
                    "orient": "vertical",
                    "range": "2017",
                    "dayLabel": [
                        "margin": 5.0
                    ] as [String: Any]
                ] as [String: Any]
            ],
            "series": [
                [
                    "type": "heatmap",
                    "coordinateSystem": "calendar",
                    "calendarIndex": 0.0,
                    "data": calendarVertical2015
                ] as [String: Any],
                [
                    "type": "heatmap",
                    "coordinateSystem": "calendar",
                    "calendarIndex": 1.0,
                    "data": calendarVertical2016
                ] as [String: Any],
                [
                    "type": "heatmap",
                    "coordinateSystem": "calendar",
                    "calendarIndex": 2.0,
                    "data": calendarVertical2017
                ] as [String: Any]
            ]
        ])
}
