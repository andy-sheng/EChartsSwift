// official-bar-race — replica of https://echarts.apache.org/examples/zh/editor.html?c=bar-race
// title: Bar Race / titleCN: 动态排序柱状图
// A `realtimeSort` bar series on an inverted category y-axis clipped to `max: 2` (only the top 3 of
// the 5 categories are on screen at a time); `xAxis.max: 'dataMax'` rescales as values grow, and the
// value label rides the bar end with `valueAnimation`.
//
// DEVIATIONS from the official source:
//  - DATA IS FIXED, NOT RANDOM. The official source seeds the series with 5 `Math.round(Math.random()
//    * 200)` values. Both panes here use one hard-coded seed array (`barRaceData`) instead — a random
//    seed would make the native/web panes disagree on every run and destroy the whole point of the diff.
//  - THE RACE IS GONE — only its first frame remains. The official example drives the chart with
//    `run()` (bumps every value, re-`setOption`s the series) via `setTimeout(run, 0)` +
//    `setInterval(run, 3000)`. The gallery renders ONE static frame, so `run` and both timers are
//    dropped; what you see is the option as first set, before any race step. `animationDuration*` /
//    `animationEasing*` are kept verbatim even though the page forces `animation = false`.
//  - Editor-harness lines dropped: `myChart.setOption(...)` and the trailing `export {};`.
extension EChartsDemoRegistry {
    static let official_bar_race = EChartsDemo(
        name: "official-bar-race", category: "bar",
        summary: "动态排序柱状图 — Bar Race",
        width: 640, height: 420,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
// DEVIATION: the official source fills `data` with 5 `Math.round(Math.random() * 200)` values.
// Fixed here so this pane and the native pane render the identical frame.
const data = [117, 42, 178, 96, 151];

option = {
  xAxis: {
    max: 'dataMax'
  },
  yAxis: {
    type: 'category',
    data: ['A', 'B', 'C', 'D', 'E'],
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
      data: data,
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
"""#,
        option: [
            "xAxis": [
                "max": "dataMax"
            ] as [String: Any],
            "yAxis": [
                "type": "category",
                "data": ["A", "B", "C", "D", "E"],
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
                    "data": barRaceData,
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

// The 5 seed values. Official: `Math.round(Math.random() * 200)` x5 — pinned so both panes agree.
private let barRaceData: [Double] = [117, 42, 178, 96, 151]
