// official-calendar-heatmap — replica of https://echarts.apache.org/examples/zh/editor.html?c=calendar-heatmap
// title: Calendar Heatmap / titleCN: 日历热力图
// A full-year (2016) horizontal calendar coordinate system carrying a `heatmap` series — one cell per day,
// coloured by a PIECEWISE visualMap (min 0, max 10000) laid out horizontally above the calendar, under a
// centred 'Daily Step Count' title. `cellSize: ['auto', 13]` lets the week-columns stretch to the pane
// width while pinning each day-row to 13px; `yearLabel: { show: false }` drops the year watermark.
//
// DEVIATIONS from the official source:
//   - DATA: the example builds its data with `getVirtualData('2016')`, which walks every day of the year
//     (echarts.time.parse / echarts.time.format) and assigns `Math.floor(Math.random() * 10000)`. That is
//     NONDETERMINISTIC — the two panes would never agree, and no two renders of the same pane would agree
//     either, so the reference↔port diff would be meaningless. The 366 [date, value] rows (2016 IS a leap
//     year) are instead generated ONCE in Swift by a seeded LCG (same shape: '{yyyy}-{MM}-{dd}' × 0…9999)
//     and the SAME array is inlined into BOTH panes — spliced into webOptionJS as a JSON literal, and used
//     verbatim as the native `series.data`. The rest of the option is verbatim.
//     (Upstream also formats its timestamps with `useUTC = false` while parsing them as UTC, so west-of-UTC
//     viewers actually get the year shifted a day; our rows are the clean one-per-calendar-day-of-2016 set.)
//   - `series` is a bare object upstream; the Swift option wraps it in the one-element array echarts
//     normalizes it to anyway.
//   - `export {};` and the TS type annotations are dropped (a bare export is a SyntaxError in the reference
//     page's classic script).
//   - no PORT-NOTE below: the option has NO function-valued key (no formatter / renderItem / label
//     callback — `tooltip` is the bare `{}` upstream writes), so the Swift `option` mirrors the JS one
//     key-for-key with NOTHING dropped.
import Foundation

// The 366 rows of 2016 that `getVirtualData('2016')` would have produced, made deterministic: a fixed-seed
// LCG stands in for Math.random(). Element shape is the upstream `[string, number]` pair.
private let calendarHeatmapData: [[Any]] = {
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

// The same rows as a JSON literal, spliced into the reference pane's JS (see \#( ... ) below).
private let calendarHeatmapDataJSON: String = {
    guard let data = try? JSONSerialization.data(withJSONObject: calendarHeatmapData, options: []),
          let json = String(data: data, encoding: .utf8) else { return "[]" }
    return json
}()

extension EChartsDemoRegistry {
    static let official_calendar_heatmap = EChartsDemo(
        name: "official-calendar-heatmap", category: "calendar",
        summary: "日历热力图 — Calendar Heatmap",
        width: 720, height: 460,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
// Upstream builds this with getVirtualData('2016') (Math.random per day); the identical deterministic
// 366-row array the native pane uses is inlined here instead, so the two panes are diffable.
var data = \#(calendarHeatmapDataJSON);

option = {
  title: {
    top: 30,
    left: 'center',
    text: 'Daily Step Count'
  },
  tooltip: {},
  visualMap: {
    min: 0,
    max: 10000,
    type: 'piecewise',
    orient: 'horizontal',
    left: 'center',
    top: 65
  },
  calendar: {
    top: 120,
    left: 30,
    right: 30,
    cellSize: ['auto', 13],
    range: '2016',
    itemStyle: {
      borderWidth: 0.5
    },
    yearLabel: { show: false }
  },
  series: {
    type: 'heatmap',
    coordinateSystem: 'calendar',
    data: data
  }
};
"""#,
        option: [
            "title": [
                "top": 30.0,
                "left": "center",
                "text": "Daily Step Count"
            ] as [String: Any],
            "tooltip": [:] as [String: Any],
            "visualMap": [
                "min": 0.0,
                "max": 10000.0,
                "type": "piecewise",
                "orient": "horizontal",
                "left": "center",
                "top": 65.0
            ] as [String: Any],
            "calendar": [
                "top": 120.0,
                "left": 30.0,
                "right": 30.0,
                "cellSize": ["auto", 13.0] as [Any],
                "range": "2016",
                // The reference page resolves the default locale to Chinese. Pin it explicitly on
                // native so month/day labels do not inherit the process locale.
                "monthLabel": ["nameMap": "ZH"] as [String: Any],
                "dayLabel": ["nameMap": "ZH"] as [String: Any],
                "itemStyle": [
                    "borderWidth": 0.5
                ] as [String: Any],
                "yearLabel": ["show": false] as [String: Any]
            ] as [String: Any],
            "series": [
                [
                    "type": "heatmap",
                    "coordinateSystem": "calendar",
                    "data": calendarHeatmapData
                ] as [String: Any]
            ]
        ])
}
