// official-scatter-symbol-morph — replica of https://echarts.apache.org/examples/zh/editor.html?c=scatter-symbol-morph
// title: Symbol Shape Morph / titleCN: 散点图变形动画
// A 10x10 grid of scatter points on two HIDDEN category axes, in a grid inset to 0 on all four sides.
// `universalTransition: true` + `symbolKeepAspect: true` mean that a `setOption` changing nothing but
// `series[0].symbol` MORPHS all 100 marks from one SVG path into the next: roundRect → circle → heart
// → happy → evil → hipster → shocked → pie → users → mug → plane, then wraps.
//
// THE 700ms CYCLE IS PORTED, ON BOTH PANES. The web pane runs the example's own
//   setInterval(function () {
//     optionIndex = (optionIndex + 1) % options.length;
//     myChart.setOption(options[optionIndex]);
//   }, 700);
// verbatim; the native pane replays the same timeline through `drive` (see EChartsDemoChart). The morph
// IS the example — a first-frame-only port would show a static grid of rounded rectangles and quietly
// hide whatever `universalTransition` support the port is missing, which is the one thing this demo
// exists to expose.
//
// Note the example MERGES (`setOption(opt)`, NOT `setOption(opt, true)`): options[1…10] carry only
// `series[0].symbol` and rely on the merge to keep the base option's grid, axes, data, symbolSize and
// universalTransition alive — hence `notMerge: false` in `drive`. The still-frame PNG paths capture the
// first frame (options[0], the roundRect grid) and neuter setInterval, so a snapshot stays deterministic.
//
// DEVIATIONS from the official source:
//   - The TypeScript annotation `const options: echarts.EChartsOption[] = [...]` is dropped (the
//     reference page is a classic script and cannot parse it), as is the trailing `export {};` (a bare
//     export is a SyntaxError that would kill the page). The JS is otherwise VERBATIM — generator
//     loops, all 11 options, and the setInterval driver included.
//   - Canvas 560x560 (rather than the tab's default 640x420): the grid has zero padding on all four
//     sides, so 10 rows of 50px symbols need ~500px in BOTH axes or the marks overlap and clip. Square
//     cells also keep the aspect-preserved symbols undistorted, as on the official page.
//   - Native pane: the 100 data points, the two axis category arrays and the 11 options are hoisted to
//     file-scope `private let`s (Swift's type-checker times out on large inline literals); they are
//     built by the same loops and carry the same values as the JS. `xData`/`yData` stay NUMERIC
//     category data (0…9 as numbers), exactly as upstream pushes them.
//   - No note omissions: the option carries no JS function values.
import Foundation

extension EChartsDemoRegistry {
    static let official_scatter_symbol_morph = EChartsDemo(
        name: "official-scatter-symbol-morph", category: "scatter",
        summary: "散点图变形动画 — Symbol Shape Morph",
        width: 560, height: 560,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
let xData = [];
let yData = [];
let data = [];
for (let y = 0; y < 10; y++) {
  yData.push(y);
  for (let x = 0; x < 10; x++) {
    data.push([x, y, 10]);
  }
}
for (let x = 0; x < 10; x++) {
  xData.push(x);
}

const options = [
  {
    grid: {
      left: 0,
      right: 0,
      top: 0,
      bottom: 0
    },
    xAxis: {
      show: false,
      type: 'category',
      data: xData
    },
    yAxis: {
      show: false,
      type: 'category',
      data: yData
    },
    series: [
      {
        type: 'scatter',
        data: data,
        symbol: 'roundRect',
        symbolKeepAspect: true,
        universalTransition: true,
        symbolSize: 50
      }
    ]
  },
  {
    series: [
      {
        type: 'scatter',
        symbol: 'circle'
      }
    ]
  },

  {
    // heart
    series: [
      {
        symbol:
          'path://M23.6 2c-3.363 0-6.258 2.736-7.599 5.594-1.342-2.858-4.237-5.594-7.601-5.594-4.637 0-8.4 3.764-8.4 8.401 0 9.433 9.516 11.906 16.001 21.232 6.13-9.268 15.999-12.1 15.999-21.232 0-4.637-3.763-8.401-8.4-8.401z'
      }
    ]
  },

  {
    // happy
    series: [
      {
        symbol:
          'path://M16 0c-8.837 0-16 7.163-16 16s7.163 16 16 16 16-7.163 16-16-7.163-16-16-16zM22 8c1.105 0 2 1.343 2 3s-0.895 3-2 3-2-1.343-2-3 0.895-3 2-3zM10 8c1.105 0 2 1.343 2 3s-0.895 3-2 3-2-1.343-2-3 0.895-3 2-3zM16 28c-5.215 0-9.544-4.371-10-9.947 2.93 1.691 6.377 2.658 10 2.658s7.070-0.963 10-2.654c-0.455 5.576-4.785 9.942-10 9.942z'
      }
    ]
  },

  {
    // evil
    series: [
      {
        symbol:
          'path://M32 2c0-1.422-0.298-2.775-0.833-4-1.049 2.401-3.014 4.31-5.453 5.287-2.694-2.061-6.061-3.287-9.714-3.287s-7.021 1.226-9.714 3.287c-2.439-0.976-4.404-2.886-5.453-5.287-0.535 1.225-0.833 2.578-0.833 4 0 2.299 0.777 4.417 2.081 6.106-1.324 2.329-2.081 5.023-2.081 7.894 0 8.837 7.163 16 16 16s16-7.163 16-16c0-2.871-0.757-5.565-2.081-7.894 1.304-1.689 2.081-3.806 2.081-6.106zM18.003 11.891c0.064-1.483 1.413-2.467 2.55-3.036 1.086-0.543 2.16-0.814 2.205-0.826 0.536-0.134 1.079 0.192 1.213 0.728s-0.192 1.079-0.728 1.213c-0.551 0.139-1.204 0.379-1.779 0.667 0.333 0.357 0.537 0.836 0.537 1.363 0 1.105-0.895 2-2 2s-2-0.895-2-2c0-0.037 0.001-0.073 0.003-0.109zM8.030 8.758c0.134-0.536 0.677-0.862 1.213-0.728 0.045 0.011 1.119 0.283 2.205 0.826 1.137 0.569 2.486 1.553 2.55 3.036 0.002 0.036 0.003 0.072 0.003 0.109 0 1.105-0.895 2-2 2s-2-0.895-2-2c0-0.527 0.204-1.005 0.537-1.363-0.575-0.288-1.228-0.528-1.779-0.667-0.536-0.134-0.861-0.677-0.728-1.213zM16 26c-3.641 0-6.827-1.946-8.576-4.855l2.573-1.544c1.224 2.036 3.454 3.398 6.003 3.398s4.779-1.362 6.003-3.398l2.573 1.544c-1.749 2.908-4.935 4.855-8.576 4.855z'
      }
    ]
  },

  {
    // hipster
    series: [
      {
        symbol:
          'path://M16 0c-8.837 0-16 7.163-16 16s7.163 16 16 16 16-7.163 16-16-7.163-16-16-16zM22 8c1.105 0 2 0.895 2 2s-0.895 2-2 2-2-0.895-2-2 0.895-2 2-2zM10 8c1.105 0 2 0.895 2 2s-0.895 2-2 2-2-0.895-2-2 0.895-2 2-2zM16.994 21.23c-0.039-0.035-0.078-0.072-0.115-0.109-0.586-0.586-0.878-1.353-0.879-2.121-0 0.768-0.293 1.535-0.879 2.121-0.038 0.038-0.076 0.074-0.115 0.109-2.704 2.453-9.006-0.058-9.006-3.23 1.938 1.25 3.452 0.306 4.879-1.121 1.172-1.172 3.071-1.172 4.243 0 0.586 0.586 0.879 1.353 0.879 2.121 0-0.768 0.293-1.535 0.879-2.121 1.172-1.172 3.071-1.172 4.243 0 1.427 1.427 2.941 2.371 4.879 1.121 0 3.173-6.302 5.684-9.006 3.23z'
      }
    ]
  },

  {
    // shocked
    series: [
      {
        symbol:
          'path://M16 0c-8.837 0-16 7.163-16 16s7.163 16 16 16 16-7.163 16-16-7.163-16-16-16zM10 14c-1.105 0-2-1.343-2-3s0.895-3 2-3 2 1.343 2 3-0.895 3-2 3zM16 26c-2.209 0-4-1.791-4-4s1.791-4 4-4c2.209 0 4 1.791 4 4s-1.791 4-4 4zM22 14c-1.105 0-2-1.343-2-3s0.895-3 2-3 2 1.343 2 3-0.895 3-2 3z'
      }
    ]
  },

  {
    // pie chart
    series: [
      {
        symbol:
          'path://M14 18v-14c-7.732 0-14 6.268-14 14s6.268 14 14 14 14-6.268 14-14c0-2.251-0.532-4.378-1.476-6.262l-12.524 6.262zM28.524 7.738c-2.299-4.588-7.043-7.738-12.524-7.738v14l12.524-6.262z'
      }
    ]
  },

  {
    // users
    series: [
      {
        symbol:
          'path://M10.225 24.854c1.728-1.13 3.877-1.989 6.243-2.513-0.47-0.556-0.897-1.176-1.265-1.844-0.95-1.726-1.453-3.627-1.453-5.497 0-2.689 0-5.228 0.956-7.305 0.928-2.016 2.598-3.265 4.976-3.734-0.529-2.39-1.936-3.961-5.682-3.961-6 0-6 4.029-6 9 0 3.096 1.797 6.191 4 7.432v1.649c-6.784 0.555-12 3.888-12 7.918h8.719c0.454-0.403 0.956-0.787 1.506-1.146zM24 24.082v-1.649c2.203-1.241 4-4.337 4-7.432 0-4.971 0-9-6-9s-6 4.029-6 9c0 3.096 1.797 6.191 4 7.432v1.649c-6.784 0.555-12 3.888-12 7.918h28c0-4.030-5.216-7.364-12-7.918z'
      }
    ]
  },

  {
    // mug
    series: [
      {
        symbol:
          'path://M30 10h-6v-3c0-2.761-5.373-5-12-5s-12 2.239-12 5v20c0 2.761 5.373 5 12 5s12-2.239 12-5v-3h6c1.105 0 2-0.895 2-2v-10c0-1.105-0.895-2-2-2zM5.502 8.075c-1.156-0.381-1.857-0.789-2.232-1.075 0.375-0.286 1.075-0.694 2.232-1.075 1.811-0.597 4.118-0.925 6.498-0.925s4.688 0.329 6.498 0.925c1.156 0.381 1.857 0.789 2.232 1.075-0.375 0.286-1.076 0.694-2.232 1.075-1.811 0.597-4.118 0.925-6.498 0.925s-4.688-0.329-6.498-0.925zM28 20h-4v-6h4v6z'
      }
    ]
  },

  {
    // plane
    series: [
      {
        symbol:
          'path://M24 19.999l-5.713-5.713 13.713-10.286-4-4-17.141 6.858-5.397-5.397c-1.556-1.556-3.728-1.928-4.828-0.828s-0.727 3.273 0.828 4.828l5.396 5.396-6.858 17.143 4 4 10.287-13.715 5.713 5.713v7.999h4l2-6 6-2v-4l-7.999 0z'
      }
    ]
  }
];

let optionIndex = 0;
option = options[optionIndex];

setInterval(function () {
  optionIndex = (optionIndex + 1) % options.length;
  myChart.setOption(options[optionIndex]);
}, 700);
"""#,
        // The native pane's half of the same timeline: step through the 11 options every 700ms, exactly
        // as the example's setInterval does. `notMerge: false` is upstream's plain `setOption(opt)` —
        // options[1…10] are symbol-only patches, so a notMerge would throw away the grid, the axes, the
        // data and universalTransition on the very first tick and leave an empty chart.
        drive: { chart in
            var optionIndex = 0
            chart.every(0.7) {
                optionIndex = (optionIndex + 1) % scatterSymbolMorphOptions.count
                chart.setOption(scatterSymbolMorphOptions[optionIndex], notMerge: false)
            }
        },
        // Upstream's `option = options[optionIndex]` with optionIndex == 0 — the roundRect grid.
        option: scatterSymbolMorphOptions[0])
}

// MARK: - data (the official source's generator loops)

// `for (y…) for (x…) data.push([x, y, 10])` — 100 [x, y, value] triples.
private let scatterSymbolMorphData: [[Double]] = {
    var out: [[Double]] = []
    for y in 0..<10 {
        for x in 0..<10 {
            out.append([Double(x), Double(y), 10])
        }
    }
    return out
}()

// `xData` / `yData`: 0…9 as NUMBERS on a category axis, as upstream pushes them. Both axes are hidden;
// they exist only to lay the grid out.
private let scatterSymbolMorphXData: [Double] = (0..<10).map(Double.init)
private let scatterSymbolMorphYData: [Double] = (0..<10).map(Double.init)

// MARK: - the symbol paths, in the order the example cycles them

private let scatterSymbolMorphHeart = "path://M23.6 2c-3.363 0-6.258 2.736-7.599 5.594-1.342-2.858-4.237-5.594-7.601-5.594-4.637 0-8.4 3.764-8.4 8.401 0 9.433 9.516 11.906 16.001 21.232 6.13-9.268 15.999-12.1 15.999-21.232 0-4.637-3.763-8.401-8.4-8.401z"
private let scatterSymbolMorphHappy = "path://M16 0c-8.837 0-16 7.163-16 16s7.163 16 16 16 16-7.163 16-16-7.163-16-16-16zM22 8c1.105 0 2 1.343 2 3s-0.895 3-2 3-2-1.343-2-3 0.895-3 2-3zM10 8c1.105 0 2 1.343 2 3s-0.895 3-2 3-2-1.343-2-3 0.895-3 2-3zM16 28c-5.215 0-9.544-4.371-10-9.947 2.93 1.691 6.377 2.658 10 2.658s7.070-0.963 10-2.654c-0.455 5.576-4.785 9.942-10 9.942z"
private let scatterSymbolMorphEvil = "path://M32 2c0-1.422-0.298-2.775-0.833-4-1.049 2.401-3.014 4.31-5.453 5.287-2.694-2.061-6.061-3.287-9.714-3.287s-7.021 1.226-9.714 3.287c-2.439-0.976-4.404-2.886-5.453-5.287-0.535 1.225-0.833 2.578-0.833 4 0 2.299 0.777 4.417 2.081 6.106-1.324 2.329-2.081 5.023-2.081 7.894 0 8.837 7.163 16 16 16s16-7.163 16-16c0-2.871-0.757-5.565-2.081-7.894 1.304-1.689 2.081-3.806 2.081-6.106zM18.003 11.891c0.064-1.483 1.413-2.467 2.55-3.036 1.086-0.543 2.16-0.814 2.205-0.826 0.536-0.134 1.079 0.192 1.213 0.728s-0.192 1.079-0.728 1.213c-0.551 0.139-1.204 0.379-1.779 0.667 0.333 0.357 0.537 0.836 0.537 1.363 0 1.105-0.895 2-2 2s-2-0.895-2-2c0-0.037 0.001-0.073 0.003-0.109zM8.030 8.758c0.134-0.536 0.677-0.862 1.213-0.728 0.045 0.011 1.119 0.283 2.205 0.826 1.137 0.569 2.486 1.553 2.55 3.036 0.002 0.036 0.003 0.072 0.003 0.109 0 1.105-0.895 2-2 2s-2-0.895-2-2c0-0.527 0.204-1.005 0.537-1.363-0.575-0.288-1.228-0.528-1.779-0.667-0.536-0.134-0.861-0.677-0.728-1.213zM16 26c-3.641 0-6.827-1.946-8.576-4.855l2.573-1.544c1.224 2.036 3.454 3.398 6.003 3.398s4.779-1.362 6.003-3.398l2.573 1.544c-1.749 2.908-4.935 4.855-8.576 4.855z"
private let scatterSymbolMorphHipster = "path://M16 0c-8.837 0-16 7.163-16 16s7.163 16 16 16 16-7.163 16-16-7.163-16-16-16zM22 8c1.105 0 2 0.895 2 2s-0.895 2-2 2-2-0.895-2-2 0.895-2 2-2zM10 8c1.105 0 2 0.895 2 2s-0.895 2-2 2-2-0.895-2-2 0.895-2 2-2zM16.994 21.23c-0.039-0.035-0.078-0.072-0.115-0.109-0.586-0.586-0.878-1.353-0.879-2.121-0 0.768-0.293 1.535-0.879 2.121-0.038 0.038-0.076 0.074-0.115 0.109-2.704 2.453-9.006-0.058-9.006-3.23 1.938 1.25 3.452 0.306 4.879-1.121 1.172-1.172 3.071-1.172 4.243 0 0.586 0.586 0.879 1.353 0.879 2.121 0-0.768 0.293-1.535 0.879-2.121 1.172-1.172 3.071-1.172 4.243 0 1.427 1.427 2.941 2.371 4.879 1.121 0 3.173-6.302 5.684-9.006 3.23z"
private let scatterSymbolMorphShocked = "path://M16 0c-8.837 0-16 7.163-16 16s7.163 16 16 16 16-7.163 16-16-7.163-16-16-16zM10 14c-1.105 0-2-1.343-2-3s0.895-3 2-3 2 1.343 2 3-0.895 3-2 3zM16 26c-2.209 0-4-1.791-4-4s1.791-4 4-4c2.209 0 4 1.791 4 4s-1.791 4-4 4zM22 14c-1.105 0-2-1.343-2-3s0.895-3 2-3 2 1.343 2 3-0.895 3-2 3z"
private let scatterSymbolMorphPie = "path://M14 18v-14c-7.732 0-14 6.268-14 14s6.268 14 14 14 14-6.268 14-14c0-2.251-0.532-4.378-1.476-6.262l-12.524 6.262zM28.524 7.738c-2.299-4.588-7.043-7.738-12.524-7.738v14l12.524-6.262z"
private let scatterSymbolMorphUsers = "path://M10.225 24.854c1.728-1.13 3.877-1.989 6.243-2.513-0.47-0.556-0.897-1.176-1.265-1.844-0.95-1.726-1.453-3.627-1.453-5.497 0-2.689 0-5.228 0.956-7.305 0.928-2.016 2.598-3.265 4.976-3.734-0.529-2.39-1.936-3.961-5.682-3.961-6 0-6 4.029-6 9 0 3.096 1.797 6.191 4 7.432v1.649c-6.784 0.555-12 3.888-12 7.918h8.719c0.454-0.403 0.956-0.787 1.506-1.146zM24 24.082v-1.649c2.203-1.241 4-4.337 4-7.432 0-4.971 0-9-6-9s-6 4.029-6 9c0 3.096 1.797 6.191 4 7.432v1.649c-6.784 0.555-12 3.888-12 7.918h28c0-4.030-5.216-7.364-12-7.918z"
private let scatterSymbolMorphMug = "path://M30 10h-6v-3c0-2.761-5.373-5-12-5s-12 2.239-12 5v20c0 2.761 5.373 5 12 5s12-2.239 12-5v-3h6c1.105 0 2-0.895 2-2v-10c0-1.105-0.895-2-2-2zM5.502 8.075c-1.156-0.381-1.857-0.789-2.232-1.075 0.375-0.286 1.075-0.694 2.232-1.075 1.811-0.597 4.118-0.925 6.498-0.925s4.688 0.329 6.498 0.925c1.156 0.381 1.857 0.789 2.232 1.075-0.375 0.286-1.076 0.694-2.232 1.075-1.811 0.597-4.118 0.925-6.498 0.925s-4.688-0.329-6.498-0.925zM28 20h-4v-6h4v6z"
private let scatterSymbolMorphPlane = "path://M24 19.999l-5.713-5.713 13.713-10.286-4-4-17.141 6.858-5.397-5.397c-1.556-1.556-3.728-1.928-4.828-0.828s-0.727 3.273 0.828 4.828l5.396 5.396-6.858 17.143 4 4 10.287-13.715 5.713 5.713v7.999h4l2-6 6-2v-4l-7.999 0z"

// MARK: - the 11 options the example cycles through

// options[2…10] are symbol-ONLY patches (no `type`), exactly as upstream writes them — the merge carries
// everything else over from options[0].
private func scatterSymbolMorphSymbolPatch(_ symbol: String) -> [String: Any] {
    ["series": [["symbol": symbol] as [String: Any]]]
}

private let scatterSymbolMorphOptions: [[String: Any]] = [
    // options[0] — the full option: zero-inset grid, two hidden category axes, and the roundRect grid of
    // 100 aspect-kept 50px marks that every later option morphs.
    [
        "grid": [
            "left": 0.0,
            "right": 0.0,
            "top": 0.0,
            "bottom": 0.0
        ] as [String: Any],
        "xAxis": [
            "show": false,
            "type": "category",
            "data": scatterSymbolMorphXData
        ] as [String: Any],
        "yAxis": [
            "show": false,
            "type": "category",
            "data": scatterSymbolMorphYData
        ] as [String: Any],
        "series": [
            [
                "type": "scatter",
                "data": scatterSymbolMorphData,
                "symbol": "roundRect",
                "symbolKeepAspect": true,
                "universalTransition": true,
                "symbolSize": 50.0
            ] as [String: Any]
        ]
    ],
    // options[1] — the one patch upstream restates `type: 'scatter'` on.
    [
        "series": [
            [
                "type": "scatter",
                "symbol": "circle"
            ] as [String: Any]
        ]
    ],
    scatterSymbolMorphSymbolPatch(scatterSymbolMorphHeart),
    scatterSymbolMorphSymbolPatch(scatterSymbolMorphHappy),
    scatterSymbolMorphSymbolPatch(scatterSymbolMorphEvil),
    scatterSymbolMorphSymbolPatch(scatterSymbolMorphHipster),
    scatterSymbolMorphSymbolPatch(scatterSymbolMorphShocked),
    scatterSymbolMorphSymbolPatch(scatterSymbolMorphPie),
    scatterSymbolMorphSymbolPatch(scatterSymbolMorphUsers),
    scatterSymbolMorphSymbolPatch(scatterSymbolMorphMug),
    scatterSymbolMorphSymbolPatch(scatterSymbolMorphPlane)
]
