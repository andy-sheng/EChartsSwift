// official-area-time-axis — replica of https://echarts.apache.org/examples/zh/editor.html?c=area-time-axis
// title: Area Chart with Time Axis / titleCN: 时间轴折线图
// A 20 000-point random-walk on a `time` xAxis, drawn as a smooth symbol-less area line, with an
// `inside` + slider dataZoom pair windowed to the first 20% and a toolbox (dataZoom/restore/saveAsImage).
//
// DEVIATIONS from the official source:
//   - DATA FROZEN / DETERMINISTIC. Upstream builds its 20 000 rows at load time from `Math.random()`:
//     one point per day starting at `+new Date(1988, 9, 3)`, each value a ±10 walk off the previous
//     (`Math.round((Math.random() - 0.5) * 20 + prev)`). That is NONDETERMINISTIC — the two panes would
//     never agree and no two renders of one pane would agree either, so the reference↔port diff would be
//     meaningless. The identical walk is instead run ONCE in Swift with a fixed-seed LCG standing in for
//     Math.random() (same step count, same ±10 band, same `Math.round` = floor(x + 0.5) half-up rule),
//     and the SAME array feeds BOTH panes — spliced into webOptionJS as a JSON literal, and used verbatim
//     as the native `series.data`. Point count (20 000) and shape ([epochMillis, value]) are unchanged.
//   - `base` is the epoch-millis of LOCAL midnight 1988-10-03, exactly as `+new Date(1988, 9, 3)` yields;
//     it is resolved once in Swift so both panes read the same timestamps.
//   - `title.text` keeps upstream's 'Large Ara Chart' typo verbatim.
//   - `tooltip.position` is a JS closure and is dropped from the native option (see note); it only
//     affects the hover tooltip, which a static snapshot never shows. The reference pane keeps it.
//   - the rest of the option is verbatim.
import Foundation

// Epoch-millis of `+new Date(1988, 9, 3)` — local midnight, Oct 3 1988 (JS months are 0-based).
private let areaTimeAxisBase: Double = {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = .current
    let midnight = cal.date(from: DateComponents(year: 1988, month: 10, day: 3))
    // Fallback: the same instant at UTC, so the demo still renders if the components don't resolve.
    return ((midnight?.timeIntervalSince1970 ?? 591_840_000) * 1000).rounded()
}()

// The 20 000 [epochMillis, value] rows upstream's loop would have produced, made deterministic (see the
// file header): a fixed-seed LCG stands in for Math.random().
private let areaTimeAxisData: [[Double]] = {
    var seed: UInt64 = 1988_10_03
    func nextUnit() -> Double {              // deterministic stand-in for Math.random() → [0, 1)
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        return Double((seed >> 33) % 1_000_000) / 1_000_000.0
    }
    let oneDay = 24.0 * 3600.0 * 1000.0
    var now = areaTimeAxisBase
    var rows: [[Double]] = [[now, nextUnit() * 300]]
    rows.reserveCapacity(20_000)
    for i in 1..<20_000 {
        now += oneDay
        // JS `Math.round` is half-UP (not half-away-from-zero), i.e. floor(x + 0.5).
        rows.append([now, ((nextUnit() - 0.5) * 20 + rows[i - 1][1] + 0.5).rounded(.down)])
    }
    return rows
}()

// The same rows as a JSON literal, spliced into the reference pane's JS (see \#( ... ) below).
private let areaTimeAxisDataJSON: String = {
    guard let data = try? JSONSerialization.data(withJSONObject: areaTimeAxisData, options: []),
          let json = String(data: data, encoding: .utf8) else { return "[]" }
    return json
}()

extension EChartsDemoRegistry {
    static let official_area_time_axis = EChartsDemo(
        name: "official-area-time-axis", category: "line",
        summary: "时间轴折线图 — Area Chart with Time Axis",
        width: 640, height: 420,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
// Upstream walks 20 000 days off `+new Date(1988, 9, 3)` with Math.random(); the identical deterministic
// array the native pane uses is inlined here instead, so the two panes are diffable.
let data = \#(areaTimeAxisDataJSON);

option = {
  tooltip: {
    trigger: 'axis',
    position: function (pt) {
      return [pt[0], '10%'];
    }
  },
  title: {
    left: 'center',
    text: 'Large Ara Chart'
  },
  toolbox: {
    feature: {
      dataZoom: {
        yAxisIndex: 'none'
      },
      restore: {},
      saveAsImage: {}
    }
  },
  xAxis: {
    type: 'time',
    boundaryGap: false
  },
  yAxis: {
    type: 'value',
    boundaryGap: [0, '100%']
  },
  dataZoom: [
    {
      type: 'inside',
      start: 0,
      end: 20
    },
    {
      start: 0,
      end: 20
    }
  ],
  series: [
    {
      name: 'Fake Data',
      type: 'line',
      smooth: true,
      symbol: 'none',
      areaStyle: {},
      data: data
    }
  ]
};
"""#,
        option: [
            "tooltip": [
                "trigger": "axis"
                // tooltip.position omitted — JS closure `function (pt) { return [pt[0], '10%']; }`,
                // which pins the tooltip box to the cursor's x and 10% of the grid height.
            ] as [String: Any],
            "title": [
                "left": "center",
                "text": "Large Ara Chart"
            ] as [String: Any],
            "toolbox": [
                "feature": [
                    "dataZoom": [
                        "yAxisIndex": "none"
                    ] as [String: Any],
                    "restore": [:] as [String: Any],
                    "saveAsImage": [:] as [String: Any]
                ] as [String: Any]
            ] as [String: Any],
            "xAxis": [
                "type": "time",
                "boundaryGap": false
            ] as [String: Any],
            "yAxis": [
                "type": "value",
                "boundaryGap": [0.0, "100%"] as [Any]
            ] as [String: Any],
            "dataZoom": [
                [
                    "type": "inside",
                    "start": 0.0,
                    "end": 20.0
                ] as [String: Any],
                [
                    "start": 0.0,
                    "end": 20.0
                ] as [String: Any]
            ],
            "series": [
                [
                    "name": "Fake Data",
                    "type": "line",
                    "smooth": true,
                    "symbol": "none",
                    "areaStyle": [:] as [String: Any],
                    "data": areaTimeAxisData
                ] as [String: Any]
            ]
        ])
}
