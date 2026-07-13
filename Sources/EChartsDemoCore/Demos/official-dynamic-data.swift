// official-dynamic-data — replica of https://echarts.apache.org/examples/zh/editor.html?c=dynamic-data
// title: Dynamic Data / titleCN: 动态数据
// A live-ticker dashboard frozen at frame 0: a `bar` series ("Dynamic Bar", 0–1000 orders) on the SECOND
// x/y axis pair (xAxisIndex/yAxisIndex 1 — a 0…9 category axis + the 'Order' value axis, max 1200) drawn
// behind a `line` series ("Dynamic Line", 5–15 price) on the FIRST pair (a wall-clock category axis + the
// 'Price' value axis, max 30). Crosshair (`axisPointer: 'cross'`) tooltip, legend, a full toolbox
// (dataView/restore/saveAsImage) and an invisible full-range `dataZoom` (`show: false`, 0→100%).
//
// DEVIATIONS from the official source:
//   - DATA IS PINNED, NOT GENERATED. Three of the four seed IIFEs are NONDETERMINISTIC: `categories` reads
//     the wall clock (`now.toLocaleTimeString().replace(/^\D*/, '')`, walking back 2s per step), and `data` /
//     `data2` are `Math.round(Math.random() * 1000)` / `+(Math.random() * 10 + 5).toFixed(1)`. Left as-is the
//     two panes would draw different bars, different lines and different tick labels on every render, so the
//     reference↔port diff would be meaningless. One draw of each is frozen into the `private let`s below and
//     the SAME arrays feed BOTH panes: spliced into webOptionJS as JSON literals, handed to the native
//     `series.data` / `xAxis.data` as-is.
//   - The pinned `categories` strings are the LOCALE-STRIPPED shape upstream's regex produces ('10:19:42' —
//     `/^\D*/` exists to eat a leading locale prefix such as zh-CN's '下午'), not en-US's '10:19:42 AM'.
//   - `categories2` (0…9) is KEPT VERBATIM as its IIFE — that generator is already deterministic.
//   - ANIMATION: the trailing `setInterval(..., 2100)` — which shifts one point off the head of all four
//     arrays, pushes a fresh random value + the next clock tick + `app.count++`, and re-`setOption`s every
//     2.1s — is DROPPED. The gallery renders ONE static frame, so this is the INITIAL state only.
//   - Editor-harness lines dropped: `app.count = 11`, `myChart.setOption(...)` and the trailing `export {};`.
//   - Native pane: this option carries NO JS closures (no formatter/renderItem), so nothing is omitted — the
//     Swift option is the JS option key-for-key. The toolbox features are interactive-only and inert in a
//     static frame, but are kept so both panes lay out (and reserve room for) the same toolbox icons.
import Foundation

// One frozen draw of each nondeterministic generator (see DEVIATIONS). Shared verbatim by both panes.

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

// The same arrays as JSON literals, spliced into the reference pane's JS (see \#( ... ) below) so the two
// panes cannot drift apart.
private func dynamicDataJSON(_ obj: Any) -> String {
    guard let d = try? JSONSerialization.data(withJSONObject: obj, options: []),
          let s = String(data: d, encoding: .utf8) else { return "[]" }
    return s
}
private let dynamicDataCategoriesJSON = dynamicDataJSON(dynamicDataCategories)
private let dynamicDataBarJSON = dynamicDataJSON(dynamicDataBar)
private let dynamicDataLineJSON = dynamicDataJSON(dynamicDataLine)

extension EChartsDemoRegistry {
    static let official_dynamic_data = EChartsDemo(
        name: "official-dynamic-data", category: "bar",
        summary: "动态数据 — Dynamic Data",
        width: 640, height: 420,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
// DEVIATION: upstream builds `categories` from the wall clock and `data` / `data2` from Math.random().
// The identical frozen arrays the native pane uses are inlined here instead, so the two panes are diffable.
// `categories2` is deterministic, so its IIFE is kept verbatim. The trailing setInterval ticker (shift/push
// every 2.1s) is dropped — this is its INITIAL frame.
const categories = \#(dynamicDataCategoriesJSON);
const categories2 = (function () {
  let res = [];
  let len = 10;
  while (len--) {
    res.push(10 - len - 1);
  }
  return res;
})();
const data = \#(dynamicDataBarJSON);
const data2 = \#(dynamicDataLineJSON);

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
"""#,
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
