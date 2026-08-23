// official-bar-gradient — replica of https://echarts.apache.org/examples/zh/editor.html?c=bar-gradient
// title: Clickable Column Chart with Gradient / titleCN: 特性示例：渐变色 阴影 点击缩放
//
// 20 columns on a category x-axis whose labels are drawn INSIDE the bars (white, no axisTick/axisLine,
// z:10 so they paint over the columns). Each column is filled with a vertical LinearGradient
// (#83bff6 → #188df0), sits on a `showBackground` track, and swaps to a second, inverted gradient
// (#2378f7 → #83bff6) on emphasis. An `inside` dataZoom lets the real chart be pinch/scroll-zoomed.
//
// DEVIATIONS from the official source:
//   1. The `myChart.on('click', ...)` handler (the "Click Zoom" half of the title — it dispatches a
//      `dataZoom` action windowed ±3 categories around the clicked bar) is dropped from BOTH panes.
//      The gallery renders ONE static frame with no event loop, and the chart does not exist yet when
//      the option script runs (WebPage.swift inits it AFTER, in the same script block, so `myChart` is
//      hoisted-but-undefined there): keeping the handler would throw a TypeError and blank the
//      reference pane. Both panes therefore show the un-zoomed initial frame: all 20 columns, dataZoom
//      at its default full range.
//   2. The trailing `export {};` is dropped — a bare export is a SyntaxError in the reference pane's
//      classic script.
//   3. The Swift option spells the two gradients as the plain-object form
//      (`{type:'linear', x:0, y:0, x2:0, y2:1, colorStops:[...]}`) instead of
//      `new echarts.graphic.LinearGradient(0, 0, 0, 1, [...])` — echarts accepts both, and it is the
//      only form a `[String: Any]` can carry. webOptionJS keeps the `new echarts.graphic...` calls
//      verbatim.
//   The example's `dataShadow` array (a vestige of the pre-`showBackground` version) is computed and
//   never read in the official source; webOptionJS keeps that loop verbatim, the Swift option omits it.
//   No closures anywhere in this option, so nothing is omitted from the Swift port for that reason.

extension EChartsDemoRegistry {
    static let official_bar_gradient = EChartsDemo(
        name: "official-bar-gradient", category: "bar",
        summary: "特性示例：渐变色 阴影 点击缩放 — Clickable Column Chart with Gradient",
        width: 640, height: 420,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
// prettier-ignore
let dataAxis = ['点', '击', '柱', '子', '或', '者', '两', '指', '在', '触', '屏', '上', '滑', '动', '能', '够', '自', '动', '缩', '放'];
// prettier-ignore
let data = [220, 182, 191, 234, 290, 330, 310, 123, 442, 321, 90, 149, 210, 122, 133, 334, 198, 123, 125, 220];
let yMax = 500;
let dataShadow = [];

for (let i = 0; i < data.length; i++) {
  dataShadow.push(yMax);
}

option = {
  title: {
    text: '特性示例：渐变色 阴影 点击缩放',
    subtext: 'Feature Sample: Gradient Color, Shadow, Click Zoom'
  },
  xAxis: {
    data: dataAxis,
    axisLabel: {
      inside: true,
      color: '#fff'
    },
    axisTick: {
      show: false
    },
    axisLine: {
      show: false
    },
    z: 10
  },
  yAxis: {
    axisLine: {
      show: false
    },
    axisTick: {
      show: false
    },
    axisLabel: {
      color: '#999'
    }
  },
  dataZoom: [
    {
      type: 'inside'
    }
  ],
  series: [
    {
      type: 'bar',
      showBackground: true,
      itemStyle: {
        color: new echarts.graphic.LinearGradient(0, 0, 0, 1, [
          { offset: 0, color: '#83bff6' },
          { offset: 0.5, color: '#188df0' },
          { offset: 1, color: '#188df0' }
        ])
      },
      emphasis: {
        itemStyle: {
          color: new echarts.graphic.LinearGradient(0, 0, 0, 1, [
            { offset: 0, color: '#2378f7' },
            { offset: 0.7, color: '#2378f7' },
            { offset: 1, color: '#83bff6' }
          ])
        }
      },
      data: data
    }
  ]
};
"""#,
        option: [
            "title": [
                "text": "特性示例：渐变色 阴影 点击缩放",
                "subtext": "Feature Sample: Gradient Color, Shadow, Click Zoom"
            ] as [String: Any],
            "xAxis": [
                "data": barGradientAxisData,
                "axisLabel": [
                    "inside": true,
                    "color": "#fff"
                ] as [String: Any],
                "axisTick": [
                    "show": false
                ] as [String: Any],
                "axisLine": [
                    "show": false
                ] as [String: Any],
                "z": 10.0
            ] as [String: Any],
            "yAxis": [
                "axisLine": [
                    "show": false
                ] as [String: Any],
                "axisTick": [
                    "show": false
                ] as [String: Any],
                "axisLabel": [
                    "color": "#999"
                ] as [String: Any]
            ] as [String: Any],
            "dataZoom": [
                [
                    "type": "inside"
                ] as [String: Any]
            ] as [Any],
            "series": [
                [
                    "type": "bar",
                    "showBackground": true,
                    "itemStyle": [
                        "color": barGradientNormalFill
                    ] as [String: Any],
                    "emphasis": [
                        "itemStyle": [
                            "color": barGradientEmphasisFill
                        ] as [String: Any]
                    ] as [String: Any],
                    "data": barGradientData
                ] as [String: Any]
            ] as [Any]
        ])
}

// MARK: - file-scope data (hoisted + explicitly typed: 20-element literals inline stall the type-checker)

private let barGradientAxisData: [String] = [
    "点", "击", "柱", "子", "或", "者", "两", "指", "在", "触",
    "屏", "上", "滑", "动", "能", "够", "自", "动", "缩", "放"
]

private let barGradientData: [Double] = [
    220, 182, 191, 234, 290, 330, 310, 123, 442, 321,
    90, 149, 210, 122, 133, 334, 198, 123, 125, 220
]

/// `new echarts.graphic.LinearGradient(0, 0, 0, 1, stops)` in plain-object form (deviation 3): a
/// top-to-bottom ramp over the bar's bounding box.
private func barGradientLinear(_ stops: [(Double, String)]) -> [String: Any] {
    [
        "type": "linear",
        "x": 0.0, "y": 0.0, "x2": 0.0, "y2": 1.0,
        "colorStops": stops.map { ["offset": $0.0, "color": $0.1] as [String: Any] } as [Any]
    ]
}

private let barGradientNormalFill: [String: Any] = barGradientLinear([
    (0.0, "#83bff6"), (0.5, "#188df0"), (1.0, "#188df0")
])

private let barGradientEmphasisFill: [String: Any] = barGradientLinear([
    (0.0, "#2378f7"), (0.7, "#2378f7"), (1.0, "#83bff6")
])
