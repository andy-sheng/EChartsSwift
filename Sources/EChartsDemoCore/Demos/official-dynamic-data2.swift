// official-dynamic-data2 — replica of https://echarts.apache.org/examples/zh/editor.html?c=dynamic-data2
// title: Dynamic Data + Time Axis / titleCN: 动态数据 + 时间坐标轴
// A 1000-point random walk on a `time` x-axis (split lines off on both axes, `boundaryGap: [0, '100%']`
// lifting the walk off the bottom edge, symbols hidden) that SCROLLS: every second the example drops the
// 5 oldest points and appends 5 new ones, one simulated day apart, so the line marches left forever and
// the time axis keeps re-labelling itself.
//
// THE 1s TICKER IS PORTED, ON BOTH PANES. The web pane runs the example's own
// `setInterval(function () { ...shift 5 / push 5...; myChart.setOption({ series: [{ data: data }] }); }, 1000)`
// verbatim — note it MERGES (no `true`), replacing only `series[0].data`; the native pane replays the same
// timeline through `drive` (see EChartsDemoChart), continuing the SAME walk its initial `option` ended on.
// The still-frame PNG paths capture the first frame and neuter the timer, so a snapshot stays deterministic.
//
// DEVIATIONS from the official source:
//   - RANDOMNESS IS SEEDED, IDENTICALLY IN BOTH PANES. Upstream's walk is `Math.random()`-driven, so the
//     reference and the port would plot two different lines and no two renders would agree — the pane↔pane
//     diff (the whole point of the gallery) and the headless `--compare` would both be meaningless. So
//     `Math.random()` is replaced, in the JS *and* in the Swift, by the same 32-bit LCG from the same seed
//     (`Math.imul(s, 1664525) + 1013904223 >>> 0` ≡ `s &* 1664525 &+ 1013904223`, over 2^32, /2^32). Both
//     panes then generate the same 1000 seed points AND the same appended points on every tick — verified
//     equal through tick 1. NOTHING ELSE about the walk changes: same start (1997/10/3), same `+= r*21-10`
//     step, same flat-24h day cursor, same `Math.round` (half toward +∞, hence `(v + 0.5).rounded(.down)`),
//     same `{ name, value: ['YYYY/M/D', y] }` item shape, same 1000 points, same shift-5/push-5 cadence.
//   - `item.name` is `now.toString()` on the web pane (verbatim) and the same string minus the trailing
//     parenthesised zone name on the native one ("Sat Oct 04 1997 00:00:00 GMT+0800" vs
//     "… GMT+0800 (China Standard Time)") — DateFormatter has no format for that suffix. Its only reader is
//     the tooltip formatter, which is omitted natively; nothing renders from it.
//   - `tooltip.formatter` is a JS closure — omitted on the native pane (note at the key), verbatim on
//     the web pane. Everything else in the option is carried.
//   - webOptionJS drops only what a classic script cannot parse: the `interface DataItem` block and the type
//     annotations (`(): DataItem`, `: DataItem[]`, `params: any`, `setOption<echarts.EChartsOption>`), plus
//     the trailing `export {};`.
import Foundation

// MARK: - the example's walk, in Swift (the JS half of this lives in webOptionJS, digit-for-digit)

// `now.toString()`: JS's local-time Date string, minus the "(China Standard Time)" tail (see DEVIATIONS).
private let dynamicData2NameFormatter: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "EEE MMM dd yyyy HH:mm:ss 'GMT'ZZZ"
    return f
}()

/// Upstream's three module-level bindings (`now`, `value`, and the RNG) that `randomData()` walks, and
/// that the seeding loop and the `setInterval` SHARE — hence one value carried from `option` into `drive`.
private struct DynamicData2Walk {
    var seed: UInt32 = 19_971_003
    var now: Date
    var value: Double

    init() {
        // `let now = new Date(1997, 9, 3);` — LOCAL midnight, 3 Oct 1997 (JS months are 0-based).
        var c = DateComponents()
        c.year = 1997; c.month = 10; c.day = 3
        now = Calendar.current.date(from: c) ?? Date(timeIntervalSince1970: 875_808_000)
        value = 0
        value = rand() * 1000                       // `let value = Math.random() * 1000;`
    }

    /// The seeded stand-in for `Math.random()` → [0, 1). Mirrors the JS `rand()` exactly.
    mutating func rand() -> Double {
        seed = seed &* 1664525 &+ 1013904223
        return Double(seed) / 4294967296.0
    }

    /// `function randomData(): DataItem`. `value` accumulates UNROUNDED — upstream rounds only the emitted
    /// point. The day cursor adds a flat 24h to the timestamp (`new Date(+now + oneDay)`), not a calendar
    /// day, so in a DST zone the local wall clock drifts exactly as upstream's does.
    mutating func randomData() -> [String: Any] {
        now = now.addingTimeInterval(24 * 3600)     // oneDay = 24 * 3600 * 1000 (ms)
        value = value + rand() * 21 - 10
        let c = Calendar.current.dateComponents([.year, .month, .day], from: now)
        let stamp = "\(c.year ?? 0)/\(c.month ?? 0)/\(c.day ?? 0)"   // [y, m + 1, d].join('/')
        return [
            "name": dynamicData2NameFormatter.string(from: now),
            "value": [stamp, (value + 0.5).rounded(.down)] as [Any]  // Math.round: half toward +∞
        ]
    }
}

/// The initial 1000 points, plus the walk state they left behind so `drive` KEEPS WALKING instead of
/// restarting — upstream's seeding loop and its `setInterval` mutate one shared `data`/`now`/`value`.
private struct DynamicData2Seed {
    let points: [[String: Any]]
    let walk: DynamicData2Walk
}

private let dynamicData2Seed: DynamicData2Seed = {
    var walk = DynamicData2Walk()
    var points: [[String: Any]] = []
    points.reserveCapacity(1000)
    for _ in 0..<1000 {                             // `for (var i = 0; i < 1000; i++) data.push(randomData());`
        points.append(walk.randomData())
    }
    return DynamicData2Seed(points: points, walk: walk)
}()

extension EChartsDemoRegistry {
    static let official_dynamic_data2 = EChartsDemo(
        name: "official-dynamic-data2", category: "line",
        summary: "动态数据 + 时间坐标轴 — Dynamic Data + Time Axis",
        width: 640, height: 420,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
// Upstream's `Math.random()` — replaced by a seeded LCG the Swift side reproduces bit for bit, so both
// panes walk the SAME line and stay diffable (see the file header). Nothing else about the walk changes.
var __seed = 19971003;
function rand() {
  __seed = (Math.imul(__seed, 1664525) + 1013904223) >>> 0;
  return __seed / 4294967296;
}

function randomData() {
  now = new Date(+now + oneDay);
  value = value + rand() * 21 - 10;
  return {
    name: now.toString(),
    value: [
      [now.getFullYear(), now.getMonth() + 1, now.getDate()].join('/'),
      Math.round(value)
    ]
  };
}

let data = [];
let now = new Date(1997, 9, 3);
let oneDay = 24 * 3600 * 1000;
let value = rand() * 1000;
for (var i = 0; i < 1000; i++) {
  data.push(randomData());
}

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

setInterval(function () {
  for (var i = 0; i < 5; i++) {
    data.shift();
    data.push(randomData());
  }

  myChart.setOption({
    series: [
      {
        data: data
      }
    ]
  });
}, 1000);
"""#,
        // The native pane's half of the same ticker: once a second, drop the 5 oldest points, append 5
        // fresh ones from the walk the seed left off at, and re-apply ONLY `series[0].data` — upstream's
        // `myChart.setOption({ ... })` with no `true`, i.e. a MERGE (`notMerge: false`); replacing would
        // throw away the title, the tooltip and both axes.
        drive: { chart in
            var data = dynamicData2Seed.points
            var walk = dynamicData2Seed.walk
            chart.every(1) {
                for _ in 0..<5 {
                    data.removeFirst()
                    data.append(walk.randomData())
                }
                chart.setOption(["series": [["data": data as [Any]] as [String: Any]]], notMerge: false)
            }
        },
        option: dynamicData2Option)
}

// The example's first frame: the 1000 seeded points on a time axis.
private let dynamicData2Option: [String: Any] = [
    "title": [
        "text": "Dynamic Data & Time Axis"
    ] as [String: Any],
    "tooltip": [
        "trigger": "axis",
        // tooltip.formatter omitted — a JS closure. It took the axis trigger's first param,
        // re-parsed `params.name` (the JS Date string) into a Date, and rendered the row as
        // `D/M/YYYY : <value>` (e.g. '4/10/1997 : 46'). A Swift [String: Any] cannot carry a closure, so
        // the native pane falls back to the default axis tooltip (series name + raw value).
        "axisPointer": [
            "animation": false
        ] as [String: Any]
    ] as [String: Any],
    "xAxis": [
        "type": "time",
        "axisLabel": [
            // The reference WKWebView uses zh-CN, while the DOM-less native core defaults to EN.
            // Match its visible quarter labels and preserve ECharts' emphasized primary-year level.
            "formatter": [
                "year": ["{yyyy}", "{primary|{yyyy}}"],
                "month": ["{M}月", "{primary|{yyyy}}"]
            ] as [String: Any]
        ] as [String: Any],
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
            "data": dynamicData2Seed.points as [Any]
        ] as [String: Any]
    ]
]
