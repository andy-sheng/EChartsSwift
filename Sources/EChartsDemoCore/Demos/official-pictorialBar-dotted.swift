// official-pictorialBar-dotted — replica of https://echarts.apache.org/examples/zh/editor.html?c=pictorialBar-dotted
// title: Dotted bar / titleCN: 虚线柱状图效果
// Four series stacked on one category axis over a dark (#0f375f) background: a smoothed `line` with
// emptyCircle symbols, a rounded gradient `bar` (the solid columns), a second `bar` at
// `barGap:'-100%'` (z:-12) drawn to the LINE's values as a fading glow column behind it, and a
// `pictorialBar` (z:-10) that repeats a 12×4 `rect` symbol filled with the BACKGROUND colour up the
// same line values — the repeated background-coloured rects punch horizontal gaps through the glow
// column, which is what makes it look dotted/dashed.
//
// DEVIATIONS from the official source:
//   1. DATA INLINED + DETERMINISTIC. Upstream generates all 20 points at load time from
//      `Math.random() * 200` with categories walking one day at a time off `+new Date()` — the values
//      AND the axis labels would differ between the two panes, and between two runs of the same pane,
//      making the reference↔port diff meaningless. The same 20-step loop is therefore run ONCE in
//      Swift against a fixed-seed LCG with `dottedBase` pinned to 2024-01-01T00:00:00Z (values rounded
//      to 2dp so both panes carry byte-identical numbers), and the resulting `category` / `barData` /
//      `lineData` arrays are spliced into webOptionJS in place of the generator loop. Everything below
//      the `// option` line is the example verbatim.
//   2. The Swift option spells the two `new echarts.graphic.LinearGradient(0, 0, 0, 1, [...])` fills as
//      the plain-object form (`{type:'linear', x:0, y:0, x2:0, y2:1, colorStops:[...]}`) — echarts
//      accepts both, and it is the only form a `[String: Any]` can carry. webOptionJS keeps the
//      constructor calls verbatim.
//   3. The trailing `export {};` is dropped — a bare export is a SyntaxError in the reference pane's
//      classic script and would blank the whole page.
//   No `drive`: the example is a single static `option` — it never touches `myChart`, sets no timer and
//   registers no handler. No PORT-NOTE either: the option has NO function-valued key (no formatter, no
//   symbolSize callback), so the Swift option mirrors the JS one key-for-key with nothing dropped.
//
// NATIVE PANE: the two gradient `itemStyle.color`s are the same shape official-bar-gradient.swift
// records as an EChartsKit gap (BarView's `barStyleFromDict` bridges only solid colours) — if that gap
// is still open, the native columns and the glow column fall back to a flat fill while the line, the
// symbols, the axes and the pictorialBar's repeated rects still lay out. That is exactly what this pane
// is for; the gradients stay in the option rather than being flattened to hide it.
import Foundation

// MARK: - the upstream generator loop, made deterministic (DEVIATION 1)

private struct PictorialDottedGenerated {
    let category: [String]
    let barData: [Double]
    let lineData: [Double]
}

private let pictorialDottedGenerated: PictorialDottedGenerated = {
    // Deterministic stand-in for `Math.random()`: a fixed-seed LCG, so every run of either pane sees
    // the same 20 points.
    var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
    func nextUnit() -> Double {
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        return Double((seed >> 33) % 1_000_000) / 1_000_000.0
    }
    func round2(_ v: Double) -> Double { (v * 100).rounded() / 100 }

    // `let dottedBase = +new Date()` pinned to 2024-01-01T00:00:00Z. Upstream ADVANCES the base by one
    // day BEFORE reading it (`new Date((dottedBase += 3600 * 24 * 1000))`), so the first category is the
    // day after the base.
    var utc = Calendar(identifier: .gregorian)
    utc.timeZone = TimeZone(identifier: "UTC")!
    let base = Date(timeIntervalSince1970: 1_704_067_200)

    var category: [String] = []
    var barData: [Double] = []
    var lineData: [Double] = []
    for i in 0..<20 {
        let date = base.addingTimeInterval(Double(i + 1) * 3600 * 24)
        let c = utc.dateComponents([.year, .month, .day], from: date)
        // `[date.getFullYear(), date.getMonth() + 1, date.getDate()].join('-')` — unpadded.
        category.append("\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)")
        let b = round2(nextUnit() * 200)
        let d = round2(nextUnit() * 200)
        barData.append(b)
        lineData.append(round2(d + b))
    }
    return PictorialDottedGenerated(category: category, barData: barData, lineData: lineData)
}()

private let pictorialDottedCategory: [String] = pictorialDottedGenerated.category
private let pictorialDottedBarData: [Double] = pictorialDottedGenerated.barData
private let pictorialDottedLineData: [Double] = pictorialDottedGenerated.lineData

/// The three `let` declarations the example's generator loop would have produced, as JS literals — the
/// SAME arrays the native pane plots, so the panes are diffable point for point.
private let pictorialDottedDataJS: String = {
    func jsStrings(_ values: [String]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: values, options: []),
              let text = String(data: data, encoding: .utf8) else { return "[]" }
        return text
    }
    // Swift's shortest round-trip Double description ("159.39") parses back to the very same double the
    // native pane holds — unlike JSONSerialization, which spells it "159.38999999999999".
    func jsNumbers(_ values: [Double]) -> String {
        "[" + values.map { String($0) }.joined(separator: ", ") + "]"
    }
    return """
    let category = \(jsStrings(pictorialDottedCategory));
    let barData = \(jsNumbers(pictorialDottedBarData));
    let lineData = \(jsNumbers(pictorialDottedLineData));
    """
}()

// MARK: - the two gradient fills (DEVIATION 2)

/// `new echarts.graphic.LinearGradient(0, 0, 0, 1, stops)` in plain-object form: a top-to-bottom ramp
/// over the element's bounding box.
private func pictorialDottedLinear(_ stops: [(Double, String)]) -> [String: Any] {
    [
        "type": "linear",
        "x": 0.0, "y": 0.0, "x2": 0.0, "y2": 1.0,
        "colorStops": stops.map { ["offset": $0.0, "color": $0.1] as [String: Any] } as [Any]
    ]
}

private let pictorialDottedBarFill: [String: Any] = pictorialDottedLinear([
    (0.0, "#14c8d4"), (1.0, "#43eec6")
])

/// The glow column behind the line (z:-12): teal fading to fully transparent at the bottom.
private let pictorialDottedGlowFill: [String: Any] = pictorialDottedLinear([
    (0.0, "rgba(20,200,212,0.5)"), (0.2, "rgba(20,200,212,0.2)"), (1.0, "rgba(20,200,212,0)")
])

extension EChartsDemoRegistry {
    static let official_pictorialbar_dotted = EChartsDemo(
        name: "official-pictorialBar-dotted", category: "pictorialBar",
        summary: "虚线柱状图效果 — Dotted bar",
        width: 640, height: 420,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
// Generate data — upstream fills these three arrays from `Math.random() * 200` off `+new Date()`;
// the deterministic arrays the native pane plots are inlined verbatim instead (DEVIATION 1).
\#(pictorialDottedDataJS)

// option
option = {
  backgroundColor: '#0f375f',
  tooltip: {
    trigger: 'axis',
    axisPointer: {
      type: 'shadow'
    }
  },
  legend: {
    data: ['line', 'bar'],
    textStyle: {
      color: '#ccc'
    }
  },
  xAxis: {
    data: category,
    axisLine: {
      lineStyle: {
        color: '#ccc'
      }
    }
  },
  yAxis: {
    splitLine: { show: false },
    axisLine: {
      lineStyle: {
        color: '#ccc'
      }
    }
  },
  series: [
    {
      name: 'line',
      type: 'line',
      smooth: true,
      showAllSymbol: true,
      symbol: 'emptyCircle',
      symbolSize: 15,
      data: lineData
    },
    {
      name: 'bar',
      type: 'bar',
      barWidth: 10,
      itemStyle: {
        borderRadius: 5,
        color: new echarts.graphic.LinearGradient(0, 0, 0, 1, [
          { offset: 0, color: '#14c8d4' },
          { offset: 1, color: '#43eec6' }
        ])
      },
      data: barData
    },
    {
      name: 'line',
      type: 'bar',
      barGap: '-100%',
      barWidth: 10,
      itemStyle: {
        color: new echarts.graphic.LinearGradient(0, 0, 0, 1, [
          { offset: 0, color: 'rgba(20,200,212,0.5)' },
          { offset: 0.2, color: 'rgba(20,200,212,0.2)' },
          { offset: 1, color: 'rgba(20,200,212,0)' }
        ])
      },
      z: -12,
      data: lineData
    },
    {
      name: 'dotted',
      type: 'pictorialBar',
      symbol: 'rect',
      itemStyle: {
        color: '#0f375f'
      },
      symbolRepeat: true,
      symbolSize: [12, 4],
      symbolMargin: 1,
      z: -10,
      data: lineData
    }
  ]
};
"""#,
        option: [
            "backgroundColor": "#0f375f",
            "tooltip": [
                "trigger": "axis",
                "axisPointer": [
                    "type": "shadow"
                ] as [String: Any]
            ] as [String: Any],
            "legend": [
                "data": ["line", "bar"],
                "textStyle": [
                    "color": "#ccc"
                ] as [String: Any]
            ] as [String: Any],
            "xAxis": [
                "data": pictorialDottedCategory,
                "axisLine": [
                    "lineStyle": [
                        "color": "#ccc"
                    ] as [String: Any]
                ] as [String: Any]
            ] as [String: Any],
            "yAxis": [
                "splitLine": [
                    "show": false
                ] as [String: Any],
                "axisLine": [
                    "lineStyle": [
                        "color": "#ccc"
                    ] as [String: Any]
                ] as [String: Any]
            ] as [String: Any],
            "series": [
                [
                    "name": "line",
                    "type": "line",
                    "smooth": true,
                    "showAllSymbol": true,
                    "symbol": "emptyCircle",
                    "symbolSize": 15.0,
                    "data": pictorialDottedLineData
                ] as [String: Any],
                [
                    "name": "bar",
                    "type": "bar",
                    "barWidth": 10.0,
                    "itemStyle": [
                        "borderRadius": 5.0,
                        "color": pictorialDottedBarFill
                    ] as [String: Any],
                    "data": pictorialDottedBarData
                ] as [String: Any],
                [
                    "name": "line",
                    "type": "bar",
                    "barGap": "-100%",
                    "barWidth": 10.0,
                    "itemStyle": [
                        "color": pictorialDottedGlowFill
                    ] as [String: Any],
                    "z": -12.0,
                    "data": pictorialDottedLineData
                ] as [String: Any],
                [
                    "name": "dotted",
                    "type": "pictorialBar",
                    "symbol": "rect",
                    "itemStyle": [
                        "color": "#0f375f"
                    ] as [String: Any],
                    "symbolRepeat": true,
                    "symbolSize": [12.0, 4.0],
                    "symbolMargin": 1.0,
                    "z": -10.0,
                    "data": pictorialDottedLineData
                ] as [String: Any]
            ] as [Any]
        ])
}
