// official-bar-race — replica of https://echarts.apache.org/examples/zh/editor.html?c=bar-race
// title: Bar Race / titleCN: 动态排序柱状图
// Five bars (A…E) on an inverted category y-axis clipped to `max: 2` — only the largest THREE are ever on
// screen — racing against a `max: 'dataMax'` value x-axis that rescales as the values grow.
// `series.realtimeSort` re-ranks the bars as their values change, the label rides each bar's right end and
// counts up with it (`valueAnimation: true`), and the 3s linear `animationDurationUpdate` is what makes the
// race read as motion rather than as jumps.
//
// THE RACE IS PORTED, on both panes. Upstream runs `run()` once at `setTimeout(…, 0)` and then every
// `setInterval(…, 3000)`; each call bumps all five values (usually by `Math.round(Math.random() * 200)`, but
// with a 10% chance by up to 2000 — that is the overtake) and re-`setOption`s a MERGE carrying only
// `series[0].data`. The web pane runs that timeline verbatim; the native pane replays it through `drive`
// (see EChartsDemoChart), passing `notMerge: false` because upstream's tick is a merge — the axes, label,
// legend and animation settings from the initial option must survive it.
//
// The headless PNG path compares the deterministic sorted seed frame. The live gallery still drives the
// upstream 0ms kick and 3s cadence through `drive`; the web pane only schedules those timers when the
// snapshot harness has not set `__snapshot`.
//
// DEVIATIONS from the official source:
//  - THE SEED DATA IS PINNED, and the SAME five values feed BOTH panes (inlined into webOptionJS as a JS
//    literal, handed to the native option as-is). Upstream seeds with
//    `for (let i = 0; i < 5; ++i) data.push(Math.round(Math.random() * 200))`, so each pane would otherwise
//    roll its own dice and frame 0 would differ for reasons that have nothing to do with the port.
//  - THE RACE'S OWN DICE ARE PINNED to a repeating delta table shared by both panes. Random input makes
//    animation validation impossible: after the first tick the values and often the rank order differ,
//    so a frame mismatch says nothing about the tween implementation. The table deliberately contains
//    the same small increments plus occasional large "jackpots" as upstream, preserving overtakes while
//    making every transition reproducible and frame-comparable.
//  - TypeScript-only syntax dropped, as a classic script cannot parse it: the `: number[]` annotation on
//    `data`, the `myChart.setOption<echarts.EChartsOption>(…)` type argument, and the trailing `export {};`.
//    `run()` and both timers are KEPT.
//  - Native pane: this option carries NO JS closures (no formatter/renderItem/symbolSize), so nothing is
//    omitted — the Swift option is the JS option key-for-key. Whether `realtimeSort`, the `valueAnimation`
//    label and the linear update animation actually land is exactly what the two panes are here to show.
import Foundation

// The 5 seed values — one draw of the official `Math.round(Math.random() * 200)` ×5, pinned so both panes
// start from the same frame (see DEVIATIONS).
private let barRaceData: [Double] = [117, 42, 178, 96, 151]

/// The same array as a JS literal, spliced into the reference pane's JS below so the two panes cannot drift
/// apart at frame 0. Built by hand as integers — that is what `Math.round` returns, and it keeps the
/// reference pane's source reading like the example's own data.
private let barRaceDataJS: String =
    "[" + barRaceData.map { String(Int($0)) }.joined(separator: ", ") + "]"

/// Reproducible equivalents of the official small increments and occasional 0...2000 jackpots.
private let barRaceDeltas: [[Double]] = [
    [83, 1270, 43, 155, 74],
    [120, 35, 1600, 89, 51],
    [61, 144, 72, 1320, 96],
    [930, 88, 117, 46, 181],
    [151, 73, 99, 165, 1110],
    [42, 191, 1280, 57, 136],
    [176, 1050, 38, 143, 64],
    [69, 121, 184, 970, 53]
]

private let barRaceDeltasJS: String = "[" + barRaceDeltas.map { row in
    "[" + row.map { String(Int($0)) }.joined(separator: ", ") + "]"
}.joined(separator: ", ") + "]"

private func barRaceStep(_ data: inout [Double], step: inout Int) {
    let deltas = barRaceDeltas[step % barRaceDeltas.count]
    for i in data.indices {
        data[i] += deltas[i]
    }
    step += 1
}

private let barRaceCategories = ["A", "B", "C", "D", "E"]
private func barRacePairs(_ values: [Double]) -> [[Any]] {
    zip(values, barRaceCategories).map { [$0.0, $0.1] }
}

extension EChartsDemoRegistry {
    static let official_bar_race = EChartsDemo(
        name: "official-bar-race", category: "bar",
        summary: "动态排序柱状图 — Bar Race",
        width: 640, height: 420,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
// DEVIATION: the official source fills `data` with 5 `Math.round(Math.random() * 200)` values. The identical
// pinned array the native pane starts from is inlined here instead, so frame 0 is diffable. Everything below
// — including `run()`, which keeps rolling fresh random values — is the official source.
const data = \#(barRaceDataJS);
const deltas = \#(barRaceDeltasJS);
let step = 0;
const categories = ['A', 'B', 'C', 'D', 'E'];
function pairedData() {
  return data.map(function (value, index) { return [value, categories[index]]; });
}

option = {
  xAxis: {
    max: 'dataMax'
  },
  yAxis: {
    type: 'category',
    data: ['C', 'E', 'A', 'D', 'B'],
    inverse: true,
    animationDuration: 300,
    animationDurationUpdate: 300,
    max: 2 // only the largest 3 bars will be displayed
  },
  series: [
    {
      realtimeSort: true,
      name: 'X',
      type: 'bar',
      data: pairedData(),
      label: {
        show: true,
        position: 'right',
        valueAnimation: true
      }
    }
  ],
  legend: {
    show: true
  },
  animationDuration: 0,
  animationDurationUpdate: 3000,
  animationEasing: 'linear',
  animationEasingUpdate: 'linear'
};

function run() {
  for (var i = 0; i < data.length; ++i) {
    data[i] += deltas[step % deltas.length][i];
  }
  step++;
  myChart.setOption({
    series: [
      {
        type: 'bar',
        data: pairedData()
      }
    ]
  });
}

if (!__snapshot) {
  setTimeout(function () {
    run();
  }, 0);
  setInterval(function () {
    run();
  }, 3000);
}
"""#,
        // The native pane's half of the same timeline. One `run` closure is driven by BOTH schedulers — the
        // `setTimeout(…, 0)` kick and the 3s `setInterval` — so they share the one mutable `data`, exactly as
        // the example's two timers share the one JS array.
        drive: { chart in
            var data = barRaceData
            var step = 0
            let run: @MainActor () -> Void = {
                barRaceStep(&data, step: &step)
                // `myChart.setOption({ series: [{ type: 'bar', data }] })` — a MERGE: only the series data is
                // re-sent, everything the initial option set up stays.
                chart.setOption(["series": [["type": "bar", "data": barRacePairs(data)] as [String: Any]]],
                                notMerge: false)
            }
            chart.after(0, run)   // setTimeout(function () { run(); }, 0)
            chart.every(3, run)   // setInterval(function () { run(); }, 3000)
        },
        option: [
            "xAxis": [
                "max": "dataMax"
            ] as [String: Any],
            "yAxis": [
                "type": "category",
                "data": ["C", "E", "A", "D", "B"],
                "inverse": true,
                "animationDuration": 300.0,
                "animationDurationUpdate": 300.0,
                "max": 2.0   // only the largest 3 bars will be displayed
            ] as [String: Any],
            "series": [
                [
                    "realtimeSort": true,
                    "name": "X",
                    "type": "bar",
                    "data": barRacePairs(barRaceData),
                    "label": [
                        "show": true,
                        "position": "right",
                        "valueAnimation": true
                    ] as [String: Any]
                ] as [String: Any]
            ],
            "legend": [
                "show": true
            ] as [String: Any],
            "animationDuration": 0.0,
            "animationDurationUpdate": 3000.0,
            "animationEasing": "linear",
            "animationEasingUpdate": "linear"
        ])
}
