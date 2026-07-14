// official-dynamic-data — replica of https://echarts.apache.org/examples/zh/editor.html?c=dynamic-data
// title: Dynamic Data / titleCN: 动态数据
// A live ticker: a `bar` series ("Dynamic Bar", 0–1000 orders) on the SECOND x/y axis pair
// (xAxisIndex/yAxisIndex 1 — a 0…9 counter category axis + the 'Order' value axis, max 1200) drawn behind
// a `line` series ("Dynamic Line", 5–15 price) on the FIRST pair (a wall-clock category axis + the 'Price'
// value axis, max 30). Crosshair (`axisPointer: 'cross'`) tooltip, legend, a full toolbox
// (dataView/restore/saveAsImage) and an invisible full-range `dataZoom` (`show: false`, 0→100%).
//
// THE 2.1s TICKER IS PORTED, on both panes. Every 2100ms the example shifts the oldest point off all four
// arrays and pushes a fresh one — a new random order, a new random price, the current clock time, and
// `app.count++` — then re-`setOption`s, scrolling both category axes. The web pane runs that
// `setInterval` verbatim; the native pane replays the same timeline through `drive` (see
// EChartsDemoChart). Upstream's tick is a MERGE `setOption` (only `xAxis[].data` and `series[].data` are
// re-sent, everything else must survive), so `drive` passes `notMerge: false`. The still-frame PNG paths
// capture frame 0 and neuter the timer, so a snapshot stays deterministic.
//
// DEVIATIONS from the official source:
//   - THE SEED DATA IS PINNED, and the SAME arrays feed BOTH panes (spliced into webOptionJS as JSON
//     literals, handed to the native option as-is). Three of the four seed IIFEs are nondeterministic —
//     `categories` reads the wall clock (`now.toLocaleTimeString().replace(/^\D*/, '')`, walking back 2s
//     per step) and `data` / `data2` are `Math.round(Math.random() * 1000)` /
//     `+(Math.random() * 10 + 5).toFixed(1)` — so each pane would otherwise roll its own dice and frame 0
//     would differ for reasons that have nothing to do with the port. Pinning them keeps the panes
//     diffable at the frame the snapshot captures. `categories2` (0…9) is already deterministic, so its
//     IIFE is kept verbatim.
//   - The pinned `categories` strings are bare 24-hour stamps ('10:19:42'). Note what `/^\D*/` does and does
//     not do: it eats a LEADING run of non-digits (a locale prefix such as zh-CN's '下午'), so it does NOT
//     strip a TRAILING marker — in a 12-hour locale upstream's own labels are '10:19:42 AM'. Both panes' tickers
//     append whatever the host locale hands them, and they agree with each other (the JS regex and
//     `dynamicDataNextTimeLabel` implement the same rule), so on a 12-hour host the ticks carry an ' AM'/' PM'
//     the pinned seed does not. Cosmetic, identical on both panes: the seed is pinned for diffability at
//     frame 0, not to assert a locale.
//   - The TICKS ARE NOT PINNED, and cannot be: each pane's ticker rolls its own `Math.random()` /
//     `Double.random(in:)` and reads its own clock, exactly as upstream does. Live, the two panes scroll
//     in step but carry different numbers after frame 0 — compare the cadence and the structure, not the
//     pixels.
//   - TypeScript-only syntax dropped, as a classic script cannot parse it: the `: number[]` annotations on
//     `data` / `data2`, the `myChart.setOption<echarts.EChartsOption>(...)` type argument, and the trailing
//     `export {};`. `app.count = 11` is KEPT — the page declares `app`, and the tick reads `app.count++`
//     for the second axis' labels.
//   - Native pane: this option carries NO JS closures (no formatter/renderItem), so nothing is omitted —
//     the Swift option is the JS option key-for-key. The toolbox features are interactive-only and inert
//     in a static frame, but are kept so both panes lay out (and reserve room for) the same toolbox icons.
import Foundation

// MARK: - the pinned seed (see DEVIATIONS) — one draw of each nondeterministic generator, shared by both panes

// `categories`: 10 wall-clock stamps, oldest first, 2s apart — upstream `unshift`es while walking `now` back.
private let dynamicDataCategories: [String] = [
    "10:19:42", "10:19:44", "10:19:46", "10:19:48", "10:19:50",
    "10:19:52", "10:19:54", "10:19:56", "10:19:58", "10:20:00"
]
// `categories2`: `res.push(10 - len - 1)` for len 9…0 → 0…9. Deterministic; the JS pane keeps the IIFE.
private let dynamicDataCategories2: [Double] = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]
// `data`: 10 × `Math.round(Math.random() * 1000)` → the bar series (Order axis, max 1200).
private let dynamicDataBar: [Double] = [712, 264, 891, 438, 605, 129, 973, 356, 540, 187]
// `data2`: 10 × `+(Math.random() * 10 + 5).toFixed(1)` → the line series (Price axis, max 30).
private let dynamicDataLine: [Double] = [9.4, 12.7, 6.3, 14.1, 8.8, 11.2, 7.5, 13.6, 10.9, 6.8]

// The same arrays as JS literals, spliced into the reference pane's JS (see \#( ... ) below) so the two
// panes cannot drift apart at frame 0.
// Strings go through JSONSerialization (it quotes/escapes them correctly). NUMBERS DO NOT: JSONSerialization
// spells 9.4 as "9.4000000000000004" and 12.7 as "12.699999999999999" — the very same IEEE doubles, but they
// read nothing like the one-decimal values `+(Math.random() * 10 + 5).toFixed(1)` actually produces, and the
// reference pane's source is meant to be readable as the example. Swift's shortest round-trip description
// ("9.4") parses back to exactly the double the native pane holds; integral values (upstream's
// `Math.round`) are written with no fractional part, as `Math.round` returns them.
private func dynamicDataJSStrings(_ values: [String]) -> String {
    guard let d = try? JSONSerialization.data(withJSONObject: values, options: []),
          let s = String(data: d, encoding: .utf8) else { return "[]" }
    return s
}
private func dynamicDataJSNumbers(_ values: [Double]) -> String {
    let parts = values.map { v -> String in
        v == v.rounded() && abs(v) < 1e15 ? String(Int(v)) : String(v)
    }
    return "[" + parts.joined(separator: ", ") + "]"
}
private let dynamicDataCategoriesJS = dynamicDataJSStrings(dynamicDataCategories)
private let dynamicDataBarJS = dynamicDataJSNumbers(dynamicDataBar)
private let dynamicDataLineJS = dynamicDataJSNumbers(dynamicDataLine)

// MARK: - the ticker's own generators, for the native pane's `drive` (the JS pane runs the JS ones)

// `Math.round(Math.random() * 1000)`
private func dynamicDataNextOrder() -> Double {
    (Double.random(in: 0..<1) * 1000).rounded()
}
// `+(Math.random() * 10 + 5).toFixed(1)` — one decimal, back to a number.
private func dynamicDataNextPrice() -> Double {
    ((Double.random(in: 0..<1) * 10 + 5) * 10).rounded() / 10
}
// `new Date().toLocaleTimeString().replace(/^\D*/, '')` — a medium-style local time, leading non-digits
// (a locale prefix such as zh-CN's '下午') dropped.
private let dynamicDataTimeFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateStyle = .none
    f.timeStyle = .medium
    return f
}()
private func dynamicDataNextTimeLabel() -> String {
    let s = dynamicDataTimeFormatter.string(from: Date())
    guard let firstDigit = s.firstIndex(where: { $0.isNumber }) else { return s }
    return String(s[firstDigit...])
}

extension EChartsDemoRegistry {
    static let official_dynamic_data = EChartsDemo(
        name: "official-dynamic-data", category: "bar",
        summary: "动态数据 — Dynamic Data",
        width: 640, height: 420,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
// DEVIATION: upstream seeds `categories` from the wall clock and `data` / `data2` from Math.random().
// The identical pinned arrays the native pane starts from are inlined here instead, so frame 0 is
// diffable. `categories2` is deterministic, so its IIFE is kept verbatim. Everything below — including
// the 2.1s ticker, which keeps rolling fresh random values — is the official source.
const categories = \#(dynamicDataCategoriesJS);
const categories2 = (function () {
  let res = [];
  let len = 10;
  while (len--) {
    res.push(10 - len - 1);
  }
  return res;
})();
const data = \#(dynamicDataBarJS);
const data2 = \#(dynamicDataLineJS);

option = {
  title: {
    text: 'Dynamic Data'
  },
  tooltip: {
    trigger: 'axis',
    axisPointer: {
      type: 'cross',
      label: {
        backgroundColor: '#283b56'
      }
    }
  },
  legend: {},
  toolbox: {
    show: true,
    feature: {
      dataView: { readOnly: false },
      restore: {},
      saveAsImage: {}
    }
  },
  dataZoom: {
    show: false,
    start: 0,
    end: 100
  },
  xAxis: [
    {
      type: 'category',
      boundaryGap: true,
      data: categories
    },
    {
      type: 'category',
      boundaryGap: true,
      data: categories2
    }
  ],
  yAxis: [
    {
      type: 'value',
      scale: true,
      name: 'Price',
      max: 30,
      min: 0,
      boundaryGap: [0.2, 0.2]
    },
    {
      type: 'value',
      scale: true,
      name: 'Order',
      max: 1200,
      min: 0,
      boundaryGap: [0.2, 0.2]
    }
  ],
  series: [
    {
      name: 'Dynamic Bar',
      type: 'bar',
      xAxisIndex: 1,
      yAxisIndex: 1,
      data: data
    },
    {
      name: 'Dynamic Line',
      type: 'line',
      data: data2
    }
  ]
};

app.count = 11;
setInterval(function () {
  let axisData = new Date().toLocaleTimeString().replace(/^\D*/, '');

  data.shift();
  data.push(Math.round(Math.random() * 1000));
  data2.shift();
  data2.push(+(Math.random() * 10 + 5).toFixed(1));

  categories.shift();
  categories.push(axisData);
  categories2.shift();
  categories2.push(app.count++);

  myChart.setOption({
    xAxis: [
      {
        data: categories
      },
      {
        data: categories2
      }
    ],
    series: [
      {
        data: data
      },
      {
        data: data2
      }
    ]
  });
}, 2100);
"""#,
        // The native pane's half of the same timeline. Upstream mutates the four seed arrays in place and
        // re-setOptions them every 2100ms; the four `var`s below ARE those arrays, seeded from the same
        // pinned values the initial `option` carries. `notMerge: false` is upstream's plain
        // `myChart.setOption({ xAxis: [...], series: [...] })` — a notMerge would drop the title, legend,
        // toolbox, tooltip, dataZoom and both axes' type/name/max, none of which the tick re-sends.
        drive: { chart in
            var categories = dynamicDataCategories
            var categories2 = dynamicDataCategories2
            var data = dynamicDataBar
            var data2 = dynamicDataLine
            var count = 11.0   // app.count = 11

            chart.every(2.1) {
                let axisData = dynamicDataNextTimeLabel()

                data.removeFirst()                       // data.shift()
                data.append(dynamicDataNextOrder())
                data2.removeFirst()
                data2.append(dynamicDataNextPrice())

                categories.removeFirst()
                categories.append(axisData)
                categories2.removeFirst()
                categories2.append(count)                // categories2.push(app.count++)
                count += 1

                chart.setOption([
                    "xAxis": [
                        ["data": categories] as [String: Any],
                        ["data": categories2] as [String: Any]
                    ],
                    "series": [
                        ["data": data] as [String: Any],
                        ["data": data2] as [String: Any]
                    ]
                ], notMerge: false)
            }
        },
        option: [
            "title": [
                "text": "Dynamic Data"
            ] as [String: Any],
            "tooltip": [
                "trigger": "axis",
                "axisPointer": [
                    "type": "cross",
                    "label": [
                        "backgroundColor": "#283b56"
                    ] as [String: Any]
                ] as [String: Any]
            ] as [String: Any],
            "legend": [:] as [String: Any],
            "toolbox": [
                "show": true,
                "feature": [
                    "dataView": ["readOnly": false] as [String: Any],
                    "restore": [:] as [String: Any],
                    "saveAsImage": [:] as [String: Any]
                ] as [String: Any]
            ] as [String: Any],
            // Upstream passes a bare object, not an array; echarts (and the port's
            // normalizeToComponentOptionList) wrap it into a one-element component list. Kept as-is.
            "dataZoom": [
                "show": false,
                "start": 0.0,
                "end": 100.0
            ] as [String: Any],
            "xAxis": [
                [
                    "type": "category",
                    "boundaryGap": true,
                    "data": dynamicDataCategories
                ] as [String: Any],
                [
                    "type": "category",
                    "boundaryGap": true,
                    "data": dynamicDataCategories2
                ] as [String: Any]
            ],
            "yAxis": [
                [
                    "type": "value",
                    "scale": true,
                    "name": "Price",
                    "max": 30.0,
                    "min": 0.0,
                    "boundaryGap": [0.2, 0.2] as [Any]
                ] as [String: Any],
                [
                    "type": "value",
                    "scale": true,
                    "name": "Order",
                    "max": 1200.0,
                    "min": 0.0,
                    "boundaryGap": [0.2, 0.2] as [Any]
                ] as [String: Any]
            ],
            "series": [
                [
                    "name": "Dynamic Bar",
                    "type": "bar",
                    "xAxisIndex": 1.0,
                    "yAxisIndex": 1.0,
                    "data": dynamicDataBar
                ] as [String: Any],
                [
                    "name": "Dynamic Line",
                    "type": "line",
                    "data": dynamicDataLine
                ] as [String: Any]
            ]
        ])
}
