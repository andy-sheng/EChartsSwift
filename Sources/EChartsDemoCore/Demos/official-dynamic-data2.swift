// official-dynamic-data2 — replica of https://echarts.apache.org/examples/zh/editor.html?c=dynamic-data2
// title: Dynamic Data + Time Axis / titleCN: 动态数据 + 时间坐标轴
// A 1000-point random-walk line on a `time` x-axis (split lines off on both axes, `boundaryGap: [0, '100%']`
// lifting the walk off the bottom edge), symbols hidden — upstream a live ticker shifts/pushes 5 points a second.
//
// DEVIATIONS from the official source:
//   - DATA: upstream seeds `value = Math.random() * 1000` and calls `randomData()` 1000×, each step walking
//     `value += Math.random() * 21 - 10` one day forward from 1997/10/3. That is NONDETERMINISTIC — the two
//     panes would plot different walks and no two renders would agree, so the reference↔port diff would be
//     meaningless. The same generator is run ONCE in Swift with a seeded LCG in place of `Math.random()`, and
//     the SAME 1000 items are used by BOTH panes: spliced into webOptionJS as a JSON literal, and handed to the
//     native `series.data` as-is. Item shape is upstream's `{ name, value: ['YYYY/M/D', number] }`.
//   - `item.name` is the compact 'YYYY/M/D' string, not upstream's `now.toString()` (a locale/timezone-dependent
//     full date string, e.g. 'Fri Oct 03 1997 00:00:00 GMT+0800 (...)'). Nothing is lost: the only reader is the
//     tooltip formatter's `new Date(params.name)`, which parses 'YYYY/M/D' just as happily — the reference pane's
//     formatter still runs verbatim.
//   - ANIMATION: the trailing `setInterval(..., 1000)` — which shifts 5 points off the head, pushes 5 new ones,
//     and re-`setOption`s every second — is DROPPED. The gallery renders one static frame, so this is the
//     INITIAL state only: the 1000 points as first generated.
//   - Native pane: `tooltip.formatter` omitted (a JS closure; see PORT-NOTE). Everything else is verbatim.
import Foundation

// The 1000 items `randomData()` would have produced, made deterministic: a fixed-seed LCG stands in for
// Math.random(), and the day cursor walks UTC-midnight-to-UTC-midnight from 1997/10/3 (upstream adds a flat
// 24h to a LOCAL Date, which in a DST zone can repeat/skip a calendar day — UTC keeps the sequence clean).
// The first item is 1997/10/4: upstream's `randomData()` advances `now` BEFORE reading it.
private let dynamicData2Data: [[String: Any]] = {
    var seed: UInt64 = 1997_10_03
    func nextUnit() -> Double {          // deterministic stand-in for Math.random() → [0, 1)
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        return Double((seed >> 33) % 1_000_000) / 1_000_000.0
    }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let start = calendar.date(from: DateComponents(year: 1997, month: 10, day: 3))!

    var value = nextUnit() * 1000        // upstream: `let value = Math.random() * 1000`
    var items: [[String: Any]] = []
    for i in 0..<1000 {
        // `now = new Date(+now + oneDay)` — one day per point.
        let day = calendar.date(byAdding: .day, value: i + 1, to: start)!
        let c = calendar.dateComponents([.year, .month, .day], from: day)
        let stamp = "\(c.year!)/\(c.month!)/\(c.day!)"     // [y, m + 1, d].join('/')
        value = value + nextUnit() * 21 - 10
        let rounded = (value + 0.5).rounded(.down)         // JS Math.round: half rounds toward +∞
        items.append(["name": stamp, "value": [stamp, rounded] as [Any]])
    }
    return items
}()

// The same items as a JSON literal, spliced into the reference pane's JS (see \#( ... ) below).
private let dynamicData2DataJSON: String = {
    guard let data = try? JSONSerialization.data(withJSONObject: dynamicData2Data, options: []),
          let json = String(data: data, encoding: .utf8) else { return "[]" }
    return json
}()

extension EChartsDemoRegistry {
    static let official_dynamic_data2 = EChartsDemo(
        name: "official-dynamic-data2", category: "line",
        summary: "动态数据 + 时间坐标轴 — Dynamic Data + Time Axis",
        width: 640, height: 420,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
// Upstream fills `data` by calling randomData() 1000× (a Math.random() walk one day per step); the identical
// deterministic array the native pane uses is inlined here instead, so the two panes are diffable. The trailing
// setInterval ticker (shift 5 / push 5 / re-setOption every second) is dropped — this is its INITIAL frame.
var data = \#(dynamicData2DataJSON);

option = {
  title: {
    text: 'Dynamic Data & Time Axis'
  },
  tooltip: {
    trigger: 'axis',
    formatter: function (params) {
      params = params[0];
      var date = new Date(params.name);
      return (
        date.getDate() +
        '/' +
        (date.getMonth() + 1) +
        '/' +
        date.getFullYear() +
        ' : ' +
        params.value[1]
      );
    },
    axisPointer: {
      animation: false
    }
  },
  xAxis: {
    type: 'time',
    splitLine: {
      show: false
    }
  },
  yAxis: {
    type: 'value',
    boundaryGap: [0, '100%'],
    splitLine: {
      show: false
    }
  },
  series: [
    {
      name: 'Fake Data',
      type: 'line',
      showSymbol: false,
      data: data
    }
  ]
};
"""#,
        option: [
            "title": [
                "text": "Dynamic Data & Time Axis"
            ] as [String: Any],
            "tooltip": [
                "trigger": "axis",
                // PORT-NOTE: tooltip.formatter omitted — a JS closure. It took the axis-trigger's first
                // param, re-parsed `params.name` into a Date, and rendered the row as
                // `D/M/YYYY : <value>` (e.g. '4/10/1997 : 512'). Without it the native tooltip falls
                // back to the default axis tooltip (series name + raw value).
                "axisPointer": [
                    "animation": false
                ] as [String: Any]
            ] as [String: Any],
            "xAxis": [
                "type": "time",
                "splitLine": [
                    "show": false
                ] as [String: Any]
            ] as [String: Any],
            "yAxis": [
                "type": "value",
                "boundaryGap": [0.0, "100%"] as [Any],
                "splitLine": [
                    "show": false
                ] as [String: Any]
            ] as [String: Any],
            "series": [
                [
                    "name": "Fake Data",
                    "type": "line",
                    "showSymbol": false,
                    "data": dynamicData2Data
                ] as [String: Any]
            ]
        ])
}
