// official-calendar-simple — replica of https://echarts.apache.org/examples/zh/editor.html?c=calendar-simple
// title: Simple Calendar / titleCN: 基础日历图
// A full-year (2017) calendar coordinate system with a `heatmap` series on it: one cell per day, coloured
// by a hidden continuous `visualMap` (min 0, max 10000).
//
// DEVIATIONS from the official source:
//   - DATA: the example builds its data with `getVirtualData('2017')`, which walks every day of the year
//     (echarts.time.parse / echarts.time.format) and assigns `Math.floor(Math.random() * 10000)`. That is
//     NONDETERMINISTIC — the two panes would never agree, and no two renders of the same pane would agree
//     either, so the reference↔port diff would be meaningless. The 365 [date, value] rows are instead
//     generated ONCE in Swift by a seeded LCG (same shape: '{yyyy}-{MM}-{dd}' × 0…9999) and the SAME array
//     is inlined into BOTH panes — spliced into webOptionJS as a JSON literal, and used verbatim as the
//     native `series.data`. The rest of the option is verbatim.
//   - `series` is a bare object upstream; the Swift option wraps it in the one-element array echarts
//     normalizes it to anyway.
//   - no PORT-NOTE below: the option has NO function-valued key (no formatter / renderItem / label
//     callback), so the Swift `option` mirrors the JS one key-for-key with NOTHING dropped.
//     `visualMap.type` is left unspelled because the official leaves it unspelled — visualMap's
//     typeDefaulter resolves min/max to `continuous`, and writing it out would be an embellishment.
//
// CANVAS SIZE (a gallery knob, not part of the option): at echarts' calendar defaults (`left: 80`,
// `cellSize: 20`) the 53 week-columns of 2017 span 80 + 53×20 = 1140px. The pane is therefore 1160×300,
// so the whole year is on-canvas. At a narrower pane the last ~4 months fall off the right edge — of
// BOTH panes identically, so nothing looks broken, but that slice of the chart is then never actually
// compared. Both galleries aspect-fit the pane (magnification / pageZoom), so a wide canvas costs nothing.
import Foundation

// The 365 rows of 2017 that `getVirtualData('2017')` would have produced, made deterministic: a fixed-seed
// LCG stands in for Math.random(). Element shape is the upstream `[string, number]` pair.
private let calendarSimpleData: [[Any]] = {
    var seed: UInt64 = 2017_01_01
    func nextUnit() -> Double {          // deterministic stand-in for Math.random() → [0, 1)
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        return Double((seed >> 33) % 1_000_000) / 1_000_000.0
    }
    let monthDays = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]   // 2017 is not a leap year
    var rows: [[Any]] = []
    for (i, days) in monthDays.enumerated() {
        for day in 1...days {
            let date = String(format: "2017-%02d-%02d", i + 1, day)
            rows.append([date, (nextUnit() * 10000).rounded(.down)])
        }
    }
    return rows
}()

// The same rows as a JSON literal, spliced into the reference pane's JS (see \#( ... ) below).
private let calendarSimpleDataJSON: String = {
    guard let data = try? JSONSerialization.data(withJSONObject: calendarSimpleData, options: []),
          let json = String(data: data, encoding: .utf8) else { return "[]" }
    return json
}()

extension EChartsDemoRegistry {
    static let official_calendar_simple = EChartsDemo(
        name: "official-calendar-simple", category: "calendar",
        summary: "基础日历图 — Simple Calendar",
        width: 1160, height: 300,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
// Upstream builds this with getVirtualData('2017') (Math.random per day); the identical deterministic
// 365-row array the native pane uses is inlined here instead, so the two panes are diffable.
var data = \#(calendarSimpleDataJSON);

option = {
  visualMap: {
    show: false,
    min: 0,
    max: 10000
  },
  calendar: {
    range: '2017'
  },
  series: {
    type: 'heatmap',
    coordinateSystem: 'calendar',
    data: data
  }
};
"""#,
        option: [
            "visualMap": [
                "show": false,
                "min": 0.0,
                "max": 10000.0
            ] as [String: Any],
            "calendar": [
                "range": "2017",
                // The zh official example resolves the page locale to Chinese. Native rendering does
                // not inherit that browser locale, so pin the equivalent calendar name map explicitly.
                "monthLabel": ["nameMap": "ZH"] as [String: Any],
                "dayLabel": ["nameMap": "ZH"] as [String: Any]
            ] as [String: Any],
            "series": [
                [
                    "type": "heatmap",
                    "coordinateSystem": "calendar",
                    "data": calendarSimpleData
                ] as [String: Any]
            ]
        ])
}
