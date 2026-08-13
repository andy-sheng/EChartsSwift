// official-calendar-pie — replica of https://echarts.apache.org/examples/zh/editor.html?c=calendar-pie
// title: Calendar Pie / titleCN: 日历饼图
// A February-2017 calendar coordinate system (vertical orient, 80×80 cells) carrying 28 `pie` series —
// one pie per day, centred on that day's cell (`coordinateSystem: 'calendar'`, `center: '2017-02-dd'`) —
// plus one invisible `scatter` series (`symbolSize: 0`) whose only job is to print the day-of-month
// number in each cell's corner.
//
// DEVIATIONS from the official source:
//   - DATA: upstream is NONDETERMINISTIC — `getVirtualData()` walks Feb 2017 assigning
//     `Math.floor(Math.random() * 10000)` per day, and each pie's three slices are
//     `Math.round(Math.random() * 24)`. Two panes would never agree (nor would two renders of the same
//     pane), making the reference↔port diff meaningless. The 28 [date, value] scatter rows and the
//     28×3 pie values are instead generated ONCE in Swift by a seeded LCG (same shapes: '{yyyy}-{MM}-{dd}'
//     × 0…9999, and 0…24) and the SAME arrays feed BOTH panes — spliced into webOptionJS as JSON
//     literals, and used verbatim as the native series data. Everything else is verbatim, including the
//     `scatterData.map(...)` that builds the 28 pie series in the reference pane.
//   - The scatter series' JS `label.formatter` is represented by the native
//     `(CallbackDataParams) -> String` formatter seam; both panes print the two-digit day number.
//   - `export {};` and the TS type annotations/casts are dropped (a bare export is a SyntaxError in the
//     reference page's classic script).
//
// CANVAS SIZE (a gallery knob, not part of the option): vertical orient × 7 day-columns × 80px = 560px
// wide, and Feb 2017 spans 5 Monday-first week-rows (Jan 30 … Mar 5) × 80px = 400px tall. Add the
// `dayLabel.margin: 20` header row and the `legend.bottom: 20` footer and the chart needs ~540px of
// height; at the default 460 the legend would sit on top of the last week's pies.
import Foundation
import EChartsKit

// The random rows upstream would have produced, made deterministic: a fixed-seed LCG stands in for
// Math.random(). Generated in upstream's order — first the 28 scatter values, then 3 pie slices per day.
private let calendarPieGenerated: (scatter: [[Any]], pies: [[Double]]) = {
    var seed: UInt64 = 2017_02_01
    func nextUnit() -> Double {          // deterministic stand-in for Math.random() → [0, 1)
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        return Double((seed >> 33) % 1_000_000) / 1_000_000.0
    }
    var scatter: [[Any]] = []            // upstream `[string, number][]`: ['2017-02-01', 8123], ...
    for day in 1...28 {                  // Feb 2017 has 28 days; range is ['2017-02']
        scatter.append([String(format: "2017-02-%02d", day), (nextUnit() * 10000).rounded(.down)])
    }
    var pies: [[Double]] = []            // per day: [Work, Entertainment, Sleep], each 0…24
    for _ in 1...28 {
        pies.append([(nextUnit() * 24).rounded(), (nextUnit() * 24).rounded(), (nextUnit() * 24).rounded()])
    }
    return (scatter: scatter, pies: pies)
}()

private let calendarPieScatterData: [[Any]] = calendarPieGenerated.scatter
private let calendarPieValues: [[Double]] = calendarPieGenerated.pies
private let calendarPieDates: [String] = (1...28).map { String(format: "2017-02-%02d", $0) }

// The same two arrays as JSON literals, spliced into the reference pane's JS (see \#( ... ) below).
private func calendarPieJSON(_ value: Any) -> String {
    guard let data = try? JSONSerialization.data(withJSONObject: value, options: []),
          let json = String(data: data, encoding: .utf8) else { return "[]" }
    return json
}
private let calendarPieScatterJSON: String = calendarPieJSON(calendarPieScatterData)
private let calendarPieValuesJSON: String = calendarPieJSON(calendarPieValues)

// series = the day-number label scatter, then one pie per day — the Swift form of upstream's
// `[{ id: 'label', ... }, ...pieSeries]`.
private let calendarPieSeries: [[String: Any]] = {
    var series: [[String: Any]] = [
        [
            "id": "label",
            "type": "scatter",
            "coordinateSystem": "calendar",
            "symbolSize": 0.0,
            "label": [
                "show": true,
                "formatter": { (params: CallbackDataParams) -> String in
                    guard let row = params.value as? [Any],
                          let date = row.first as? String,
                          let day = date.split(separator: "-").last
                    else { return "" }
                    return String(day)
                } as (CallbackDataParams) -> String,
                "offset": [-30.0, -30.0],   // upstream: [-cellSize[0] / 2 + 10, -cellSize[1] / 2 + 10]
                "fontSize": 14.0
            ] as [String: Any],
            "data": calendarPieScatterData
        ] as [String: Any]
    ]
    for (index, values) in calendarPieValues.enumerated() {
        series.append([
            "type": "pie",
            "id": "pie-\(index)",
            "center": calendarPieDates[index],   // upstream: item[0] — the cell's date, on the calendar coord sys
            "radius": 30.0,                      // upstream: pieRadius
            "coordinateSystem": "calendar",
            "label": [
                "formatter": "{c}",
                "position": "inside"
            ] as [String: Any],
            "data": [
                ["name": "Work", "value": values[0]] as [String: Any],
                ["name": "Entertainment", "value": values[1]] as [String: Any],
                ["name": "Sleep", "value": values[2]] as [String: Any]
            ]
        ] as [String: Any])
    }
    return series
}()

extension EChartsDemoRegistry {
    static let official_calendar_pie = EChartsDemo(
        name: "official-calendar-pie", category: "calendar",
        summary: "日历饼图 — Calendar Pie",
        width: 720, height: 540,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
// This example requires ECharts v5.4.0 or later

const cellSize = [80, 80];
const pieRadius = 30;

// Upstream builds these with getVirtualData() (Math.floor(Math.random() * 10000) per day) and
// Math.round(Math.random() * 24) per pie slice; the identical deterministic arrays the native pane
// uses are inlined here instead, so the two panes are diffable.
const scatterData = \#(calendarPieScatterJSON);
const pieValues = \#(calendarPieValuesJSON);

const pieSeries = scatterData.map(function (item, index) {
  return {
    type: 'pie',
    id: 'pie-' + index,
    center: item[0],
    radius: pieRadius,
    coordinateSystem: 'calendar',
    label: {
      formatter: '{c}',
      position: 'inside'
    },
    data: [
      { name: 'Work', value: pieValues[index][0] },
      { name: 'Entertainment', value: pieValues[index][1] },
      { name: 'Sleep', value: pieValues[index][2] }
    ]
  };
});

option = {
  tooltip: {},
  legend: {
    data: ['Work', 'Entertainment', 'Sleep'],
    bottom: 20
  },
  calendar: {
    top: 'middle',
    left: 'center',
    orient: 'vertical',
    cellSize: cellSize,
    yearLabel: {
      show: false,
      fontSize: 30
    },
    dayLabel: {
      margin: 20,
      firstDay: 1,
      nameMap: ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']
    },
    monthLabel: {
      show: false
    },
    range: ['2017-02']
  },
  series: [
    {
      id: 'label',
      type: 'scatter',
      coordinateSystem: 'calendar',
      symbolSize: 0,
      label: {
        show: true,
        formatter: function (params) {
          return echarts.time.format(params.value[0], '{dd}', false);
        },
        offset: [-cellSize[0] / 2 + 10, -cellSize[1] / 2 + 10],
        fontSize: 14
      },
      data: scatterData
    },
    ...pieSeries
  ]
};
"""#,
        option: [
            "tooltip": [:] as [String: Any],
            "legend": [
                "data": ["Work", "Entertainment", "Sleep"],
                "bottom": 20.0
            ] as [String: Any],
            "calendar": [
                "top": "middle",
                "left": "center",
                "orient": "vertical",
                "cellSize": [80.0, 80.0],
                "yearLabel": [
                    "show": false,
                    "fontSize": 30.0
                ] as [String: Any],
                "dayLabel": [
                    "margin": 20.0,
                    "firstDay": 1.0,
                    "nameMap": ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
                ] as [String: Any],
                "monthLabel": [
                    "show": false
                ] as [String: Any],
                "range": ["2017-02"]
            ] as [String: Any],
            "series": calendarPieSeries
        ])
}
