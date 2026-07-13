// official-scatter-jitter — replica of https://echarts.apache.org/examples/zh/editor.html?c=scatter-jitter
// title: Scatter with Jittering / titleCN: 带抖动的散点图
// 7 days x 1000 points on a category x-axis. Every day carries the SAME y-sequence (tan(i)/2 + 7), so
// without jitter each day is one vertical hairline; `xAxis.jitter` spreads the points across the band
// (colorBy: 'data', itemStyle.opacity 0.4) and the hairline reads as a distribution.
//
// DEVIATIONS from the official source:
//   - web pane: the official `myChart.getWidth()` (the editor's live chart instance) is NOT in scope
//     in our page — WebPage.swift declares `var myChart` AFTER the option script, so at option time it
//     is hoisted-but-undefined and `.getWidth()` would throw. We read the container's clientWidth,
//     which is the same number the chart would report (the #main div is the demo's width, 640).
//   - native pane: the 3rd data dimension is `Math.random()` upstream. Nothing consumes it (no
//     visualMap, no symbolSize closure, colorBy is 'data' = by index), so the Swift port fills it from
//     a seeded LCG to keep the native render reproducible.
//   - native pane: `jitter` / `jitterOverlap` / `jitterMargin` exist in EChartsKit's axis defaults, but
//     the jitter LAYOUT (upstream `fixJitter`) is not ported — the native pane is expected to draw the
//     un-jittered hairlines. That gap is the point of carrying this example; it still renders, so
//     nativeSupported stays true.
//   - the jitter offset is itself `Math.random()`-based upstream (jitterOverlap defaults to true), so
//     even the reference pane is non-deterministic frame to frame.

import Foundation

extension EChartsDemoRegistry {
    static let official_scatter_jitter = EChartsDemo(
        name: "official-scatter-jitter", category: "scatter",
        summary: "带抖动的散点图 — Scatter with Jittering",
        width: 640, height: 420,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
const grid = {
  left: 80,
  right: 50
};
// upstream: `myChart.getWidth() - grid.left - grid.right` (see DEVIATIONS in the Swift header).
const width = document.getElementById('main').clientWidth - grid.left - grid.right;
const data = [];
for (let day = 0; day < 7; ++day) {
  for (let i = 0; i < 1000; ++i) {
    const y = Math.tan(i) / 2 + 7;
    data.push([day, y, Math.random()]);
  }
}
option = {
  title: {
    text: 'Scatter with Jittering'
  },
  grid,
  xAxis: {
    type: 'category',
    jitter: (width / 7) * 0.8,
    data: ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']
  },
  yAxis: {
    type: 'value',
    max: 10,
    min: 0
  },
  series: [
    {
      name: 'Sleeping Hours',
      type: 'scatter',
      data,
      colorBy: 'data',
      itemStyle: {
        opacity: 0.4
      }
    }
  ]
};
"""#,
        option: [
            "title": [
                "text": "Scatter with Jittering"
            ] as [String: Any],
            "grid": [
                "left": scatterJitterGridLeft,
                "right": scatterJitterGridRight
            ] as [String: Any],
            "xAxis": [
                "type": "category",
                "jitter": scatterJitterAmount,
                "data": ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
            ] as [String: Any],
            "yAxis": [
                "type": "value",
                "max": 10.0,
                "min": 0.0
            ] as [String: Any],
            "series": [
                [
                    "name": "Sleeping Hours",
                    "type": "scatter",
                    "data": scatterJitterData,
                    "colorBy": "data",
                    "itemStyle": [
                        "opacity": 0.4
                    ] as [String: Any]
                ] as [String: Any]
            ]
        ])
}

// The example derives the jitter width from the live chart: `myChart.getWidth() - left - right`.
// Our canvas is a fixed 640 wide (see `width:` above), so the same arithmetic is a constant here.
private let scatterJitterGridLeft = 80.0
private let scatterJitterGridRight = 50.0
private let scatterJitterAmount = (640.0 - scatterJitterGridLeft - scatterJitterGridRight) / 7.0 * 0.8

// 7 days x 1000 points: [dayIndex, tan(i)/2 + 7, <unused random dim>].
// The 3rd dim is `Math.random()` upstream and feeds nothing; a seeded LCG keeps the native pane
// reproducible run to run.
private let scatterJitterData: [[Double]] = {
    var out: [[Double]] = []
    out.reserveCapacity(7 * 1000)
    var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
    for day in 0..<7 {
        for i in 0..<1000 {
            let y = tan(Double(i)) / 2 + 7
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            let r = Double(seed >> 11) / Double(1 << 53)
            out.append([Double(day), y, r])
        }
    }
    return out
}()
