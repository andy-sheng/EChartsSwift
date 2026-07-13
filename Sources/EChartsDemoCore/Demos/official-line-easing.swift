// official-line-easing — replica of https://echarts.apache.org/examples/zh/editor.html?c=line-easing
// title: Line Easing Visualizing / titleCN: 缓动函数可视化
// A 6×6 tile wall (31 cells) plotting every zrender easing curve — linear, then the In/Out/InOut triples of
// quadratic, cubic, quartic, quintic, sinusoidal, exponential, circular, elastic, back, bounce — each as a
// symbol-less `line` of 31 points ([x, easing(x)] for x = i/30, i ∈ 0...30) on its OWN grid + hidden value
// axes (x ∈ [0, 1], y ∈ [-0.4, 1.4], so elastic/back overshoot is visible). One `title` per cell centred over
// its grid, plus a 32nd bottom-centre title. Grid geometry is computed, not literal: left/top/width/height are
// percent strings derived from `rowNumber = ceil(sqrt(31)) = 6`.
//
// DEVIATIONS from the official source:
//   - webOptionJS: the upstream file is TypeScript. The reference pane is a CLASSIC SCRIPT, where a type
//     annotation is a SyntaxError, so the declaration types are dropped — `Record<string, (k: number) => number>`,
//     the four `echarts.*ComponentOption[]` / `SeriesOption[]` array types, and the `easingName as any` cast —
//     and the trailing `export {};` removed. Every easing body, the sampling loop and the layout maths are
//     otherwise VERBATIM, so the web pane builds its 31 grids/axes/series/titles exactly as the example does.
//   - option (native): Swift cannot carry the JS `easingFuncs` map, so the 31 closures are reimplemented below
//     (`lineEasingFuncs`) with the same bodies and the same `--k` / `k *= 2` mutation order, and the same
//     `Object.keys(...).forEach` build loop runs in `lineEasingLayout`. Percent strings are formatted from the
//     identical IEEE arithmetic, so both panes lay the tiles out identically.
//   - `animationEasing` / `animationDuration` are kept on every series, but both panes snapshot ONE static
//     frame with animation forced off — the easing curves are what you SEE (the plotted lines), not what you
//     watch. Nothing in the render depends on the animation actually running.
//   - width/height bumped to 900×560 (the gallery max): at 640×420 a tile is ~100px wide and the 12px cell
//     titles collide. No option value changes with the canvas size — the layout is entirely percent-based.
import Foundation

extension EChartsDemoRegistry {
    static let official_line_easing = EChartsDemo(
        name: "official-line-easing", category: "line",
        summary: "缓动函数可视化 — Line Easing Visualizing",
        width: 900, height: 560,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
const easingFuncs = {
  linear: function (k) {
    return k;
  },
  quadraticIn: function (k) {
    return k * k;
  },
  quadraticOut: function (k) {
    return k * (2 - k);
  },
  quadraticInOut: function (k) {
    if ((k *= 2) < 1) {
      return 0.5 * k * k;
    }
    return -0.5 * (--k * (k - 2) - 1);
  },
  cubicIn: function (k) {
    return k * k * k;
  },
  cubicOut: function (k) {
    return --k * k * k + 1;
  },
  cubicInOut: function (k) {
    if ((k *= 2) < 1) {
      return 0.5 * k * k * k;
    }
    return 0.5 * ((k -= 2) * k * k + 2);
  },
  quarticIn: function (k) {
    return k * k * k * k;
  },
  quarticOut: function (k) {
    return 1 - --k * k * k * k;
  },
  quarticInOut: function (k) {
    if ((k *= 2) < 1) {
      return 0.5 * k * k * k * k;
    }
    return -0.5 * ((k -= 2) * k * k * k - 2);
  },
  quinticIn: function (k) {
    return k * k * k * k * k;
  },
  quinticOut: function (k) {
    return --k * k * k * k * k + 1;
  },
  quinticInOut: function (k) {
    if ((k *= 2) < 1) {
      return 0.5 * k * k * k * k * k;
    }
    return 0.5 * ((k -= 2) * k * k * k * k + 2);
  },
  sinusoidalIn: function (k) {
    return 1 - Math.cos((k * Math.PI) / 2);
  },
  sinusoidalOut: function (k) {
    return Math.sin((k * Math.PI) / 2);
  },
  sinusoidalInOut: function (k) {
    return 0.5 * (1 - Math.cos(Math.PI * k));
  },
  exponentialIn: function (k) {
    return k === 0 ? 0 : Math.pow(1024, k - 1);
  },
  exponentialOut: function (k) {
    return k === 1 ? 1 : 1 - Math.pow(2, -10 * k);
  },
  exponentialInOut: function (k) {
    if (k === 0) {
      return 0;
    }
    if (k === 1) {
      return 1;
    }
    if ((k *= 2) < 1) {
      return 0.5 * Math.pow(1024, k - 1);
    }
    return 0.5 * (-Math.pow(2, -10 * (k - 1)) + 2);
  },
  circularIn: function (k) {
    return 1 - Math.sqrt(1 - k * k);
  },
  circularOut: function (k) {
    return Math.sqrt(1 - --k * k);
  },
  circularInOut: function (k) {
    if ((k *= 2) < 1) {
      return -0.5 * (Math.sqrt(1 - k * k) - 1);
    }
    return 0.5 * (Math.sqrt(1 - (k -= 2) * k) + 1);
  },
  elasticIn: function (k) {
    var s;
    var a = 0.1;
    var p = 0.4;
    if (k === 0) {
      return 0;
    }
    if (k === 1) {
      return 1;
    }
    if (!a || a < 1) {
      a = 1;
      s = p / 4;
    } else {
      s = (p * Math.asin(1 / a)) / (2 * Math.PI);
    }
    return -(
      a *
      Math.pow(2, 10 * (k -= 1)) *
      Math.sin(((k - s) * (2 * Math.PI)) / p)
    );
  },
  elasticOut: function (k) {
    var s;
    var a = 0.1;
    var p = 0.4;
    if (k === 0) {
      return 0;
    }
    if (k === 1) {
      return 1;
    }
    if (!a || a < 1) {
      a = 1;
      s = p / 4;
    } else {
      s = (p * Math.asin(1 / a)) / (2 * Math.PI);
    }
    return (
      a * Math.pow(2, -10 * k) * Math.sin(((k - s) * (2 * Math.PI)) / p) + 1
    );
  },
  elasticInOut: function (k) {
    var s;
    var a = 0.1;
    var p = 0.4;
    if (k === 0) {
      return 0;
    }
    if (k === 1) {
      return 1;
    }
    if (!a || a < 1) {
      a = 1;
      s = p / 4;
    } else {
      s = (p * Math.asin(1 / a)) / (2 * Math.PI);
    }
    if ((k *= 2) < 1) {
      return (
        -0.5 *
        (a *
          Math.pow(2, 10 * (k -= 1)) *
          Math.sin(((k - s) * (2 * Math.PI)) / p))
      );
    }
    return (
      a *
        Math.pow(2, -10 * (k -= 1)) *
        Math.sin(((k - s) * (2 * Math.PI)) / p) *
        0.5 +
      1
    );
  },

  // 在某一动画开始沿指示的路径进行动画处理前稍稍收回该动画的移动
  backIn: function (k) {
    var s = 1.70158;
    return k * k * ((s + 1) * k - s);
  },
  backOut: function (k) {
    var s = 1.70158;
    return --k * k * ((s + 1) * k + s) + 1;
  },
  backInOut: function (k) {
    var s = 1.70158 * 1.525;
    if ((k *= 2) < 1) {
      return 0.5 * (k * k * ((s + 1) * k - s));
    }
    return 0.5 * ((k -= 2) * k * ((s + 1) * k + s) + 2);
  },

  // 创建弹跳效果
  bounceIn: function (k) {
    return 1 - easingFuncs.bounceOut(1 - k);
  },
  bounceOut: function (k) {
    if (k < 1 / 2.75) {
      return 7.5625 * k * k;
    } else if (k < 2 / 2.75) {
      return 7.5625 * (k -= 1.5 / 2.75) * k + 0.75;
    } else if (k < 2.5 / 2.75) {
      return 7.5625 * (k -= 2.25 / 2.75) * k + 0.9375;
    } else {
      return 7.5625 * (k -= 2.625 / 2.75) * k + 0.984375;
    }
  },
  bounceInOut: function (k) {
    if (k < 0.5) {
      return easingFuncs.bounceIn(k * 2) * 0.5;
    }
    return easingFuncs.bounceOut(k * 2 - 1) * 0.5 + 0.5;
  }
};

const N_POINT = 30;

const grids = [];
const xAxes = [];
const yAxes = [];
const series = [];
const titles = [];
let count = 0;
Object.keys(easingFuncs).forEach(function (easingName) {
  var easingFunc = easingFuncs[easingName];
  var data = [];
  for (var i = 0; i <= N_POINT; i++) {
    var x = i / N_POINT;
    var y = easingFunc(x);
    data.push([x, y]);
  }
  grids.push({
    show: true,
    borderWidth: 0,
    shadowColor: 'rgba(0, 0, 0, 0.3)',
    shadowBlur: 2
  });
  xAxes.push({
    type: 'value',
    show: false,
    min: 0,
    max: 1,
    gridIndex: count
  });
  yAxes.push({
    type: 'value',
    show: false,
    min: -0.4,
    max: 1.4,
    gridIndex: count
  });
  series.push({
    name: easingName,
    type: 'line',
    xAxisIndex: count,
    yAxisIndex: count,
    data: data,
    showSymbol: false,
    animationEasing: easingName,
    animationDuration: 1000
  });
  titles.push({
    textAlign: 'center',
    text: easingName,
    textStyle: {
      fontSize: 12,
      fontWeight: 'normal'
    }
  });
  count++;
});

var rowNumber = Math.ceil(Math.sqrt(count));
grids.forEach(function (grid, idx) {
  grid.left = ((idx % rowNumber) / rowNumber) * 100 + 0.5 + '%';
  grid.top = (Math.floor(idx / rowNumber) / rowNumber) * 100 + 0.5 + '%';
  grid.width = (1 / rowNumber) * 100 - 1 + '%';
  grid.height = (1 / rowNumber) * 100 - 1 + '%';

  titles[idx].left = parseFloat(grid.left) + parseFloat(grid.width) / 2 + '%';
  titles[idx].top = parseFloat(grid.top) + '%';
});

option = {
  title: titles.concat([
    {
      text: 'Different Easing Functions',
      top: 'bottom',
      left: 'center'
    }
  ]),
  grid: grids,
  xAxis: xAxes,
  yAxis: yAxes,
  series: series
};
"""#,
        option: [
            "title": lineEasingLayout.titles + [
                [
                    "text": "Different Easing Functions",
                    "top": "bottom",
                    "left": "center"
                ] as [String: Any]
            ],
            "grid": lineEasingLayout.grids,
            "xAxis": lineEasingLayout.xAxes,
            "yAxis": lineEasingLayout.yAxes,
            "series": lineEasingLayout.series
        ])
}

// MARK: - the Swift twin of the example's `easingFuncs` map

// zrender's easing bodies, transcribed one-for-one. JS's `--k` / `(k -= 2)` / `(k *= 2)` mutate the parameter
// mid-expression; Swift parameters are immutable, so each body shadows `k` in a `var` and performs the SAME
// mutations in the SAME order (the sequence matters: e.g. cubicOut decrements k BEFORE cubing it).
private func lineEasingBounceOut(_ k0: Double) -> Double {
    var k = k0
    if k < 1 / 2.75 {
        return 7.5625 * k * k
    } else if k < 2 / 2.75 {
        k -= 1.5 / 2.75
        return 7.5625 * k * k + 0.75
    } else if k < 2.5 / 2.75 {
        k -= 2.25 / 2.75
        return 7.5625 * k * k + 0.9375
    } else {
        k -= 2.625 / 2.75
        return 7.5625 * k * k + 0.984375
    }
}

private func lineEasingBounceIn(_ k: Double) -> Double {
    return 1 - lineEasingBounceOut(1 - k)
}

/// One tile: the easing's name (also the series' `animationEasing` value) and its curve.
private struct LineEasingFunc {
    let name: String
    let fn: (Double) -> Double
}

// Insertion order == `Object.keys(easingFuncs)` order in the JS, which is what drives grid index / tile
// position — so this array must stay in the upstream declaration order. 31 entries → rowNumber = ceil(√31) = 6.
private let lineEasingFuncs: [LineEasingFunc] = [
    LineEasingFunc(name: "linear", fn: { k in k }),
    LineEasingFunc(name: "quadraticIn", fn: { k in k * k }),
    LineEasingFunc(name: "quadraticOut", fn: { k in k * (2 - k) }),
    LineEasingFunc(name: "quadraticInOut", fn: { k0 in
        var k = k0 * 2
        if k < 1 { return 0.5 * k * k }
        k -= 1
        return -0.5 * (k * (k - 2) - 1)
    }),
    LineEasingFunc(name: "cubicIn", fn: { k in k * k * k }),
    LineEasingFunc(name: "cubicOut", fn: { k0 in
        let k = k0 - 1
        return k * k * k + 1
    }),
    LineEasingFunc(name: "cubicInOut", fn: { k0 in
        var k = k0 * 2
        if k < 1 { return 0.5 * k * k * k }
        k -= 2
        return 0.5 * (k * k * k + 2)
    }),
    LineEasingFunc(name: "quarticIn", fn: { k in k * k * k * k }),
    LineEasingFunc(name: "quarticOut", fn: { k0 in
        let k = k0 - 1
        return 1 - k * k * k * k
    }),
    LineEasingFunc(name: "quarticInOut", fn: { k0 in
        var k = k0 * 2
        if k < 1 { return 0.5 * k * k * k * k }
        k -= 2
        return -0.5 * (k * k * k * k - 2)
    }),
    LineEasingFunc(name: "quinticIn", fn: { k in k * k * k * k * k }),
    LineEasingFunc(name: "quinticOut", fn: { k0 in
        let k = k0 - 1
        return k * k * k * k * k + 1
    }),
    LineEasingFunc(name: "quinticInOut", fn: { k0 in
        var k = k0 * 2
        if k < 1 { return 0.5 * k * k * k * k * k }
        k -= 2
        return 0.5 * (k * k * k * k * k + 2)
    }),
    LineEasingFunc(name: "sinusoidalIn", fn: { k in 1 - cos((k * Double.pi) / 2) }),
    LineEasingFunc(name: "sinusoidalOut", fn: { k in sin((k * Double.pi) / 2) }),
    LineEasingFunc(name: "sinusoidalInOut", fn: { k in 0.5 * (1 - cos(Double.pi * k)) }),
    LineEasingFunc(name: "exponentialIn", fn: { k in k == 0 ? 0 : pow(1024, k - 1) }),
    LineEasingFunc(name: "exponentialOut", fn: { k in k == 1 ? 1 : 1 - pow(2, -10 * k) }),
    LineEasingFunc(name: "exponentialInOut", fn: { k0 in
        if k0 == 0 { return 0 }
        if k0 == 1 { return 1 }
        let k = k0 * 2
        if k < 1 { return 0.5 * pow(1024, k - 1) }
        return 0.5 * (-pow(2, -10 * (k - 1)) + 2)
    }),
    LineEasingFunc(name: "circularIn", fn: { k in 1 - (1 - k * k).squareRoot() }),
    LineEasingFunc(name: "circularOut", fn: { k0 in
        let k = k0 - 1
        return (1 - k * k).squareRoot()
    }),
    LineEasingFunc(name: "circularInOut", fn: { k0 in
        var k = k0 * 2
        if k < 1 { return -0.5 * ((1 - k * k).squareRoot() - 1) }
        k -= 2
        return 0.5 * ((1 - k * k).squareRoot() + 1)
    }),
    // elastic: upstream declares `a = 0.1`, `p = 0.4`, then branches on `if (!a || a < 1)`. `a` is a literal
    // 0.1, so that branch ALWAYS fires and the `else` (`s = p·asin(1/a) / 2π`) is dead code — Swift's flow
    // analysis proves it and warns. The branch is therefore folded to its only outcome, `a = 1, s = p / 4`,
    // which is what the JS actually computes on every call. Verified: all 31 curves match the JS to 12dp.
    LineEasingFunc(name: "elasticIn", fn: { k0 in
        let a = 1.0, p = 0.4, s = 0.4 / 4        // JS: a = 0.1 → `a < 1` → a = 1, s = p / 4
        if k0 == 0 { return 0 }
        if k0 == 1 { return 1 }
        let k = k0 - 1
        return -(a * pow(2, 10 * k) * sin(((k - s) * (2 * Double.pi)) / p))
    }),
    LineEasingFunc(name: "elasticOut", fn: { k in
        let a = 1.0, p = 0.4, s = 0.4 / 4
        if k == 0 { return 0 }
        if k == 1 { return 1 }
        return a * pow(2, -10 * k) * sin(((k - s) * (2 * Double.pi)) / p) + 1
    }),
    LineEasingFunc(name: "elasticInOut", fn: { k0 in
        let a = 1.0, p = 0.4, s = 0.4 / 4
        if k0 == 0 { return 0 }
        if k0 == 1 { return 1 }
        var k = k0 * 2
        if k < 1 {
            k -= 1
            return -0.5 * (a * pow(2, 10 * k) * sin(((k - s) * (2 * Double.pi)) / p))
        }
        k -= 1
        return a * pow(2, -10 * k) * sin(((k - s) * (2 * Double.pi)) / p) * 0.5 + 1
    }),
    // back: pull back slightly before running the motion.
    LineEasingFunc(name: "backIn", fn: { k in
        let s = 1.70158
        return k * k * ((s + 1) * k - s)
    }),
    LineEasingFunc(name: "backOut", fn: { k0 in
        let s = 1.70158
        let k = k0 - 1
        return k * k * ((s + 1) * k + s) + 1
    }),
    LineEasingFunc(name: "backInOut", fn: { k0 in
        let s = 1.70158 * 1.525
        var k = k0 * 2
        if k < 1 { return 0.5 * (k * k * ((s + 1) * k - s)) }
        k -= 2
        return 0.5 * (k * k * ((s + 1) * k + s) + 2)
    }),
    // bounce.
    LineEasingFunc(name: "bounceIn", fn: lineEasingBounceIn),
    LineEasingFunc(name: "bounceOut", fn: lineEasingBounceOut),
    LineEasingFunc(name: "bounceInOut", fn: { k in
        if k < 0.5 { return lineEasingBounceIn(k * 2) * 0.5 }
        return lineEasingBounceOut(k * 2 - 1) * 0.5 + 0.5
    })
]

/// The four parallel component arrays the example's `forEach` builds, plus the per-tile titles.
private struct LineEasingLayout {
    let grids: [[String: Any]]
    let xAxes: [[String: Any]]
    let yAxes: [[String: Any]]
    let series: [[String: Any]]
    let titles: [[String: Any]]
}

// The Swift twin of the example's build loop: one grid + hidden x/y axis pair + line series + title per easing,
// then a second pass laying the tiles out on a `rowNumber × rowNumber` percent grid. The percent strings are
// interpolated from the same IEEE arithmetic as the JS (`(idx % rowNumber) / rowNumber * 100 + 0.5`, …), so the
// two panes place the tiles on the same pixels.
private let lineEasingLayout: LineEasingLayout = {
    let nPoint = 30
    var grids: [[String: Any]] = []
    var xAxes: [[String: Any]] = []
    var yAxes: [[String: Any]] = []
    var series: [[String: Any]] = []
    var titles: [[String: Any]] = []

    for (count, easing) in lineEasingFuncs.enumerated() {
        var data: [[Double]] = []
        for i in 0...nPoint {
            let x = Double(i) / Double(nPoint)
            data.append([x, easing.fn(x)])
        }
        grids.append([
            "show": true,
            "borderWidth": 0.0,
            "shadowColor": "rgba(0, 0, 0, 0.3)",
            "shadowBlur": 2.0
        ] as [String: Any])
        xAxes.append([
            "type": "value",
            "show": false,
            "min": 0.0,
            "max": 1.0,
            "gridIndex": Double(count)
        ] as [String: Any])
        yAxes.append([
            "type": "value",
            "show": false,
            "min": -0.4,
            "max": 1.4,
            "gridIndex": Double(count)
        ] as [String: Any])
        series.append([
            "name": easing.name,
            "type": "line",
            "xAxisIndex": Double(count),
            "yAxisIndex": Double(count),
            "data": data,
            "showSymbol": false,
            "animationEasing": easing.name,
            "animationDuration": 1000.0
        ] as [String: Any])
        titles.append([
            "textAlign": "center",
            "text": easing.name,
            "textStyle": [
                "fontSize": 12.0,
                "fontWeight": "normal"
            ] as [String: Any]
        ] as [String: Any])
    }

    let rowNumber = Int(Double(lineEasingFuncs.count).squareRoot().rounded(.up))
    let size = (1 / Double(rowNumber)) * 100 - 1
    for idx in grids.indices {
        let left = (Double(idx % rowNumber) / Double(rowNumber)) * 100 + 0.5
        let top = (Double(idx / rowNumber) / Double(rowNumber)) * 100 + 0.5   // JS: Math.floor(idx / rowNumber)
        grids[idx]["left"] = "\(left)%"
        grids[idx]["top"] = "\(top)%"
        grids[idx]["width"] = "\(size)%"
        grids[idx]["height"] = "\(size)%"

        titles[idx]["left"] = "\(left + size / 2)%"
        titles[idx]["top"] = "\(top)%"
    }

    return LineEasingLayout(grids: grids, xAxes: xAxes, yAxes: yAxes, series: series, titles: titles)
}()
