// official-line-function — replica of https://echarts.apache.org/examples/zh/editor.html?c=line-function
// title: Function Plot / titleCN: 函数绘图
// A dense analytic curve — y = sin(x/10)·cos(x/5+1)·sin(3x/10+2)·50, sampled every 0.1 over x ∈ [-200, 200]
// (~4001 points) — drawn as a symbol-less, clipped `line` on a VALUE x-axis, with minor ticks + minor
// split lines on both axes and two `inside` dataZooms (filterMode 'none') framing the initial window at
// x ∈ [-20, 20], y ∈ [-20, 20]. `animation: false`, as upstream.
//
// DEVIATIONS from the official source:
//   - webOptionJS: the upstream file is TypeScript (`function func(x: number)`); the reference pane is a
//     CLASSIC SCRIPT, where a type annotation is a SyntaxError. The single `: number` is dropped and the
//     trailing `export {};` removed. `func` / `generateData` and the option itself are otherwise verbatim,
//     so the web pane generates its 4001 points exactly as the example does.
//   - option (native): Swift cannot carry the JS generator, so `generateData()` is reimplemented as
//     `lineFunctionData` below — the SAME `for (i = -200; i <= 200; i += 0.1)` accumulation (IEEE doubles,
//     drift included) over the same `func`, so both panes sample identical x's.
//   - Nothing else: no data fetch, no timers, no formatters in the original.
import Foundation

extension EChartsDemoRegistry {
    static let official_line_function = EChartsDemo(
        name: "official-line-function", category: "line",
        summary: "函数绘图 — Function Plot",
        width: 640, height: 420,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
function func(x) {
  x /= 10;
  return Math.sin(x) * Math.cos(x * 2 + 1) * Math.sin(x * 3 + 2) * 50;
}

function generateData() {
  let data = [];
  for (let i = -200; i <= 200; i += 0.1) {
    data.push([i, func(i)]);
  }
  return data;
}

option = {
  animation: false,
  grid: {
    top: 40,
    left: 50,
    right: 40,
    bottom: 50
  },
  xAxis: {
    name: 'x',
    minorTick: {
      show: true
    },
    minorSplitLine: {
      show: true
    }
  },
  yAxis: {
    name: 'y',
    min: -100,
    max: 100,
    minorTick: {
      show: true
    },
    minorSplitLine: {
      show: true
    }
  },
  dataZoom: [
    {
      show: true,
      type: 'inside',
      filterMode: 'none',
      xAxisIndex: [0],
      startValue: -20,
      endValue: 20
    },
    {
      show: true,
      type: 'inside',
      filterMode: 'none',
      yAxisIndex: [0],
      startValue: -20,
      endValue: 20
    }
  ],
  series: [
    {
      type: 'line',
      showSymbol: false,
      clip: true,
      data: generateData()
    }
  ]
};
"""#,
        option: [
            "animation": false,
            "grid": [
                "top": 40.0,
                "left": 50.0,
                "right": 40.0,
                "bottom": 50.0
            ] as [String: Any],
            "xAxis": [
                "name": "x",
                "minorTick": ["show": true] as [String: Any],
                "minorSplitLine": ["show": true] as [String: Any]
            ] as [String: Any],
            "yAxis": [
                "name": "y",
                "min": -100.0,
                "max": 100.0,
                "minorTick": ["show": true] as [String: Any],
                "minorSplitLine": ["show": true] as [String: Any]
            ] as [String: Any],
            "dataZoom": [
                [
                    "show": true,
                    "type": "inside",
                    "filterMode": "none",
                    "xAxisIndex": [0.0],
                    "startValue": -20.0,
                    "endValue": 20.0
                ] as [String: Any],
                [
                    "show": true,
                    "type": "inside",
                    "filterMode": "none",
                    "yAxisIndex": [0.0],
                    "startValue": -20.0,
                    "endValue": 20.0
                ] as [String: Any]
            ],
            "series": [
                [
                    "type": "line",
                    "showSymbol": false,
                    "clip": true,
                    "data": lineFunctionData
                ] as [String: Any]
            ]
        ])
}

// The Swift twin of the example's `generateData()`: `func(x) = sin(x/10)·cos(2·x/10+1)·sin(3·x/10+2)·50`
// sampled with the same 0.1-step floating-point accumulation the JS `for` loop uses (so the two panes
// land on the same x values, drift and all). ~4001 [x, y] pairs.
private let lineFunctionData: [[Double]] = {
    func fn(_ x0: Double) -> Double {
        let x = x0 / 10
        return sin(x) * cos(x * 2 + 1) * sin(x * 3 + 2) * 50
    }
    var data: [[Double]] = []
    var i = -200.0
    while i <= 200 {
        data.append([i, fn(i)])
        i += 0.1
    }
    return data
}()
