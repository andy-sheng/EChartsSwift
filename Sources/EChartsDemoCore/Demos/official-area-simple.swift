// official-area-simple — replica of https://echarts.apache.org/examples/zh/editor.html?c=area-simple
// title: Large scale area chart / titleCN: 大数据量面积图
//
// A 20,000-point random-walk line (symbol:'none', sampling:'lttb') with a vertical orange→pink gradient
// areaStyle, a category x-axis of 19,999 daily labels starting 1968/10/3, an `inside` + `slider`
// dataZoom pair windowed to the first 10%, and a toolbox (dataZoom / restore / saveAsImage).
//
// DEVIATIONS from the official source:
//   1. `Math.random()` → a seeded mulberry32 `random()` (identical 32-bit integer math on both sides:
//      JS `Math.imul`/`>>>` ↔ Swift `UInt32 &* / &+ / >>`). Upstream re-randomises the walk on every
//      reload, which would make the two panes undiffable; with the seed, the reference pane and the
//      Swift pane generate the SAME 20,000 values. The generation loop is otherwise verbatim, so the
//      data is NOT inlined — each pane runs the same algorithm.
//   2. `tooltip.position` is a JS closure; omitted from the Swift option (see the note below).
//   3. (Was a deviation; now fixed.) The gradient `areaStyle.color` renders as a gradient on the
//      native pane. EChartsKit's style bridge (`barStyleFromDict`, shared by LineView's area pass)
//      now converts a gradient option dict `{type:'linear'|'radial', ...}` (or an EChartsKit
//      `ZRColor.linearGradient/.radialGradient`) into a ZRenderKit `LinearGradient`/`RadialGradient`,
//      which NativePainter paints against the fill's bounding rect. Both panes now fade orange→pink.
//   4. Upstream's own off-by-one is preserved verbatim: `date` gets 19,999 labels while `data` gets
//      20,000 values (the loop starts at i=1 but seeds data[0] before it). Both panes see it.
import Foundation

// mulberry32 — the JS `random()` in webOptionJS below, bit-for-bit. `&*`/`&+` are the 32-bit wrapping
// ops JS gets from `Math.imul` and `^`'s ToInt32 coercion; `>>` on UInt32 is JS's `>>>`.
private struct Mulberry32 {
    private var s: UInt32
    init(seed: UInt32) { s = seed }
    mutating func next() -> Double {
        s = s &+ 0x6d2b79f5
        var t = s
        t = (t ^ (t >> 15)) &* (t | 1)
        t ^= t &+ ((t ^ (t >> 13)) &* (t | 61))
        return Double(t ^ (t >> 14)) / 4294967296.0
    }
}

// The 19,999 category labels: `new Date(1968, 9, 3)` + i days, formatted `Y/M/D` in LOCAL time —
// the same clock (and IANA tz database) the WKWebView pane's `new Date(base += oneDay)` reads.
private let areaSimpleDate: [String] = {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone.current
    let base = cal.date(from: DateComponents(year: 1968, month: 10, day: 3,
                                             hour: 0, minute: 0, second: 0))
        ?? Date(timeIntervalSince1970: 0)
    let oneDay: TimeInterval = 24 * 3600
    var out: [String] = []
    out.reserveCapacity(19999)
    for i in 1..<20000 {
        let c = cal.dateComponents([.year, .month, .day],
                                   from: base.addingTimeInterval(Double(i) * oneDay))
        out.append("\(c.year ?? 0)/\(c.month ?? 0)/\(c.day ?? 0)")
    }
    return out
}()

// The 20,000-value random walk. `Math.round(x)` is `floor(x + 0.5)` (ties toward +∞) — NOT Swift's
// `.rounded()` (ties away from zero), which would diverge from the JS pane on negative halves.
private let areaSimpleData: [Double] = {
    var rng = Mulberry32(seed: 1968100320)
    var data: [Double] = [rng.next() * 300]
    data.reserveCapacity(20000)
    for i in 1..<20000 {
        data.append(floor((rng.next() - 0.5) * 20 + data[i - 1] + 0.5))
    }
    return data
}()

extension EChartsDemoRegistry {
    static let official_area_simple = EChartsDemo(
        name: "official-area-simple", category: "dataZoom",
        summary: "大数据量面积图 — Large scale area chart",
        width: 640, height: 420,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
// DEVIATION (see the file header): seeded mulberry32 in place of Math.random(), so this pane and the
// Swift pane walk the SAME 20,000 values. Everything below is the official example, verbatim.
let __seed = 1968100320 >>> 0;
function random() {
  __seed = (__seed + 0x6d2b79f5) >>> 0;
  let t = __seed;
  t = Math.imul(t ^ (t >>> 15), t | 1);
  t ^= t + Math.imul(t ^ (t >>> 13), t | 61);
  return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
}

let base = +new Date(1968, 9, 3);
let oneDay = 24 * 3600 * 1000;
let date = [];

let data = [random() * 300];

for (let i = 1; i < 20000; i++) {
  var now = new Date((base += oneDay));
  date.push([now.getFullYear(), now.getMonth() + 1, now.getDate()].join('/'));
  data.push(Math.round((random() - 0.5) * 20 + data[i - 1]));
}

option = {
  tooltip: {
    trigger: 'axis',
    position: function (pt) {
      return [pt[0], '10%'];
    }
  },
  title: {
    left: 'center',
    text: 'Large Area Chart'
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
    type: 'category',
    boundaryGap: false,
    data: date
  },
  yAxis: {
    type: 'value',
    boundaryGap: [0, '100%']
  },
  dataZoom: [
    {
      type: 'inside',
      start: 0,
      end: 10
    },
    {
      start: 0,
      end: 10
    }
  ],
  series: [
    {
      name: 'Fake Data',
      type: 'line',
      symbol: 'none',
      sampling: 'lttb',
      itemStyle: {
        color: 'rgb(255, 70, 131)'
      },
      areaStyle: {
        color: new echarts.graphic.LinearGradient(0, 0, 0, 1, [
          {
            offset: 0,
            color: 'rgb(255, 158, 68)'
          },
          {
            offset: 1,
            color: 'rgb(255, 70, 131)'
          }
        ])
      },
      data: data
    }
  ]
};
"""#,
        option: [
            // tooltip.position omitted — the JS closure `function (pt) { return [pt[0], '10%']; }`
            //   pins the tooltip box to the pointer's x at 10% of the canvas height. No Swift equivalent;
            //   a tooltip never shows in the gallery's static frame anyway.
            "tooltip": [
                "trigger": "axis"
            ] as [String: Any],
            "title": [
                "left": "center",
                "text": "Large Area Chart"
            ] as [String: Any],
            "toolbox": [
                "feature": [
                    "dataZoom": ["yAxisIndex": "none"] as [String: Any],
                    "restore": [String: Any](),
                    "saveAsImage": [String: Any]()
                ] as [String: Any]
            ] as [String: Any],
            "xAxis": [
                "type": "category",
                "boundaryGap": false,
                "data": areaSimpleDate
            ] as [String: Any],
            "yAxis": [
                "type": "value",
                "boundaryGap": [0.0, "100%"] as [Any]
            ] as [String: Any],
            "dataZoom": [
                ["type": "inside", "start": 0.0, "end": 10.0] as [String: Any],
                ["start": 0.0, "end": 10.0] as [String: Any]
            ] as [Any],
            "series": [
                [
                    "name": "Fake Data",
                    "type": "line",
                    "symbol": "none",
                    "sampling": "lttb",
                    "itemStyle": ["color": "rgb(255, 70, 131)"] as [String: Any],
                    // The plain-object form of `new echarts.graphic.LinearGradient(0, 0, 0, 1, stops)`
                    //   (echarts accepts both). `barStyleFromDict` bridges this dict to a ZRenderKit
                    //   `LinearGradient`, so the native pane now paints the orange→pink gradient too.
                    "areaStyle": [
                        "color": [
                            "type": "linear",
                            "x": 0.0, "y": 0.0, "x2": 0.0, "y2": 1.0,
                            "colorStops": [
                                ["offset": 0.0, "color": "rgb(255, 158, 68)"] as [String: Any],
                                ["offset": 1.0, "color": "rgb(255, 70, 131)"] as [String: Any]
                            ] as [Any]
                        ] as [String: Any]
                    ] as [String: Any],
                    "data": areaSimpleData
                ] as [String: Any]
            ] as [Any]
        ])
}
