// official-calendar-effectscatter — replica of https://echarts.apache.org/examples/zh/editor.html?c=calendar-effectscatter
// title: Calendar EffectScatter / titleCN: 热力特效散点图
// Two half-year 2016 calendars stacked vertically (Jan–Jun on top, Jul–Dec below) over a dark
// `#404a59` ground. Each carries a `scatter` of one dot per day (gold `#ddb926`), and a `Top 12`
// `effectScatter` (the 12 highest-value days of the whole year, rippling `#f4e925`) routed to its
// calendar via `calendarIndex`. Points outside a calendar's `range` are clipped, so the year splits
// across the two panels.
//
// DEVIATIONS from the official source:
//   - DATA: upstream builds `data` with `getVirtualData('2016')` — `Math.floor(Math.random() * 10000)`
//     per day — which is NONDETERMINISTIC (the two panes could never agree). The 366 `[date, value]`
//     rows of leap-year 2016 are instead generated ONCE in Swift by a fixed-seed LCG (same shape as
//     calendar-heatmap) and the SAME array is inlined into BOTH panes: spliced into webOptionJS as a
//     JSON literal, and used verbatim as the native `series.data`. The `Top 12` slice is computed the
//     same way upstream does — sort by value descending, take the first 12.
//   - PORT-NOTE (native pane): every series' `symbolSize: function (val) { return val[1] / 500; }` is a
//     JS closure. symbolVisual DEFERS callback symbol props (only literal option values are encoded —
//     symbolVisual.swift), so the native pane omits `symbolSize` and the dots fall back to the scatter
//     default (10px, uniform) instead of scaling with the day's step count. The web pane keeps the
//     closure verbatim, so the reference still shows value-scaled dots.
//   - `series` order/`calendarIndex` kept 1:1 with upstream; `export {};` and TS annotations dropped.
import Foundation

// The 366 rows of 2016 that `getVirtualData('2016')` would have produced, made deterministic (fixed-seed
// LCG stand-in for Math.random). Element shape is the upstream `[string, number]` pair.
private let calendarEffectData: [[Any]] = {
    var seed: UInt64 = 2016_01_01
    func nextUnit() -> Double {          // deterministic stand-in for Math.random() → [0, 1)
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        return Double((seed >> 33) % 1_000_000) / 1_000_000.0
    }
    let monthDays = [31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]   // 2016 IS a leap year → 366 days
    var rows: [[Any]] = []
    for (i, days) in monthDays.enumerated() {
        for day in 1...days {
            let date = String(format: "2016-%02d-%02d", i + 1, day)
            rows.append([date, (nextUnit() * 10000).rounded(.down)])
        }
    }
    return rows
}()

// Upstream: `data.sort((a, b) => b[1] - a[1]).slice(0, 12)` — the 12 highest-value days of the year.
private let calendarEffectTop12: [[Any]] = {
    calendarEffectData
        .sorted { (($0[1] as? Double) ?? 0) > (($1[1] as? Double) ?? 0) }
        .prefix(12)
        .map { $0 }
}()

// The full 366-row array as a JSON literal, spliced into the reference pane's JS (which runs the
// verbatim getVirtualData replacement + its own sort/slice for Top 12).
private let calendarEffectDataJSON: String = {
    guard let data = try? JSONSerialization.data(withJSONObject: calendarEffectData, options: []),
          let json = String(data: data, encoding: .utf8) else { return "[]" }
    return json
}()

private func calendarEffectCalendar(top: Double, range: [String], yearFormatter: String) -> [String: Any] {
    return [
        "top": top,
        "left": "center",
        "range": range,
        "splitLine": [
            "show": true,
            "lineStyle": ["color": "#000", "width": 4.0, "type": "solid"] as [String: Any]
        ] as [String: Any],
        "yearLabel": ["formatter": yearFormatter, "color": "#fff"] as [String: Any],
        "monthLabel": ["color": "#aaa"] as [String: Any],
        "dayLabel": ["color": "#aaa"] as [String: Any],
        "itemStyle": ["color": "#323c48", "borderWidth": 1.0, "borderColor": "#111"] as [String: Any]
    ]
}

extension EChartsDemoRegistry {
    static let official_calendar_effectscatter = EChartsDemo(
        name: "official-calendar-effectscatter", category: "calendar",
        summary: "热力特效散点图 — Calendar EffectScatter",
        width: 720, height: 620,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
// Upstream builds this with getVirtualData('2016') (Math.random per day); the identical deterministic
// 366-row array the native pane uses is inlined here instead, so the two panes are diffable.
var data = \#(calendarEffectDataJSON);

option = {
  backgroundColor: '#404a59',
  title: {
    top: 30,
    text: 'Daily Step Count in 2016',
    subtext: 'Fake Data',
    left: 'center',
    textStyle: { color: '#fff' }
  },
  tooltip: { trigger: 'item' },
  legend: {
    top: '30',
    left: '100',
    data: ['Steps', 'Top 12'],
    textStyle: { color: '#fff' }
  },
  calendar: [
    {
      top: 120,
      left: 'center',
      range: ['2016-01-01', '2016-06-30'],
      splitLine: { show: true, lineStyle: { color: '#000', width: 4, type: 'solid' } },
      yearLabel: { formatter: '{start}  1st', color: '#fff' },
      monthLabel: { color: '#aaa' },
      dayLabel: { color: '#aaa' },
      itemStyle: { color: '#323c48', borderWidth: 1, borderColor: '#111' }
    },
    {
      top: 340,
      left: 'center',
      range: ['2016-07-01', '2016-12-31'],
      splitLine: { show: true, lineStyle: { color: '#000', width: 4, type: 'solid' } },
      yearLabel: { formatter: '{start}  2nd', color: '#fff' },
      monthLabel: { color: '#aaa' },
      dayLabel: { color: '#aaa' },
      itemStyle: { color: '#323c48', borderWidth: 1, borderColor: '#111' }
    }
  ],
  series: [
    {
      name: 'Steps',
      type: 'scatter',
      coordinateSystem: 'calendar',
      data: data,
      symbolSize: function (val) { return val[1] / 500; },
      itemStyle: { color: '#ddb926' }
    },
    {
      name: 'Steps',
      type: 'scatter',
      coordinateSystem: 'calendar',
      calendarIndex: 1,
      data: data,
      symbolSize: function (val) { return val[1] / 500; },
      itemStyle: { color: '#ddb926' }
    },
    {
      name: 'Top 12',
      type: 'effectScatter',
      coordinateSystem: 'calendar',
      calendarIndex: 1,
      data: data.sort(function (a, b) { return b[1] - a[1]; }).slice(0, 12),
      symbolSize: function (val) { return val[1] / 500; },
      showEffectOn: 'render',
      rippleEffect: { brushType: 'stroke' },
      itemStyle: { color: '#f4e925', shadowBlur: 10, shadowColor: '#333' },
      zlevel: 1
    },
    {
      name: 'Top 12',
      type: 'effectScatter',
      coordinateSystem: 'calendar',
      data: data.sort(function (a, b) { return b[1] - a[1]; }).slice(0, 12),
      symbolSize: function (val) { return val[1] / 500; },
      showEffectOn: 'render',
      rippleEffect: { brushType: 'stroke' },
      itemStyle: { color: '#f4e925', shadowBlur: 10, shadowColor: '#333' },
      zlevel: 1
    }
  ]
};
"""#,
        option: [
            "backgroundColor": "#404a59",
            "title": [
                "top": 30.0,
                "text": "Daily Step Count in 2016",
                "subtext": "Fake Data",
                "left": "center",
                "textStyle": ["color": "#fff"] as [String: Any]
            ] as [String: Any],
            "tooltip": ["trigger": "item"] as [String: Any],
            "legend": [
                "top": "30",
                "left": "100",
                "data": ["Steps", "Top 12"],
                "textStyle": ["color": "#fff"] as [String: Any]
            ] as [String: Any],
            "calendar": [
                calendarEffectCalendar(top: 120.0, range: ["2016-01-01", "2016-06-30"], yearFormatter: "{start}  1st"),
                calendarEffectCalendar(top: 340.0, range: ["2016-07-01", "2016-12-31"], yearFormatter: "{start}  2nd")
            ],
            "series": [
                // PORT-NOTE: symbolSize (val[1]/500 closure) omitted — symbolVisual defers callback props.
                [
                    "name": "Steps",
                    "type": "scatter",
                    "coordinateSystem": "calendar",
                    "data": calendarEffectData,
                    "itemStyle": ["color": "#ddb926"] as [String: Any]
                ] as [String: Any],
                [
                    "name": "Steps",
                    "type": "scatter",
                    "coordinateSystem": "calendar",
                    "calendarIndex": 1.0,
                    "data": calendarEffectData,
                    "itemStyle": ["color": "#ddb926"] as [String: Any]
                ] as [String: Any],
                [
                    "name": "Top 12",
                    "type": "effectScatter",
                    "coordinateSystem": "calendar",
                    "calendarIndex": 1.0,
                    "data": calendarEffectTop12,
                    "showEffectOn": "render",
                    "rippleEffect": ["brushType": "stroke"] as [String: Any],
                    "itemStyle": ["color": "#f4e925", "shadowBlur": 10.0, "shadowColor": "#333"] as [String: Any],
                    "zlevel": 1.0
                ] as [String: Any],
                [
                    "name": "Top 12",
                    "type": "effectScatter",
                    "coordinateSystem": "calendar",
                    "data": calendarEffectTop12,
                    "showEffectOn": "render",
                    "rippleEffect": ["brushType": "stroke"] as [String: Any],
                    "itemStyle": ["color": "#f4e925", "shadowBlur": 10.0, "shadowColor": "#333"] as [String: Any],
                    "zlevel": 1.0
                ] as [String: Any]
            ]
        ])
}
