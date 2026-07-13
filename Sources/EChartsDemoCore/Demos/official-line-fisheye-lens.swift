// official-line-fisheye-lens — replica of https://echarts.apache.org/examples/zh/editor.html?c=line-fisheye-lens
// title: Fisheye Lens on Line Chart / titleCN: 折线图鱼眼放大
// A 1000-point line whose y-values sit in three far-apart plateaus (~0–10k, ~100k–105k, ~300k–305k);
// the official example lets you brush an area to fisheye-magnify it via ECharts 6 axis `breaks`.
//
// DEVIATIONS from the official source:
//   1. INTERACTION DROPPED. The gallery renders ONE static frame, so `initAxisBreakInteraction()` and
//      its `setTimeout(initAxisBreakInteraction, 0)` are gone: the zrender mousedown/mousemove/mouseup
//      brush rect, the `convertFromPixel` → `xAxis.breaks` / `yAxis.breaks` re-setOption (plus its
//      collapse-to-80%-gap transition), and the `graphic` "Reset" button that clears the breaks. What
//      both panes show is the INITIAL state: no breaks, so the `breakArea` styling on both axes is
//      declared but nothing is broken yet. (Also drops the source's TS type annotations, which are a
//      SyntaxError in the page's classic script.)
//   2. DATA FROZEN. `generateSeriesData()` is driven by `Math.random()`, so the two panes would plot
//      different curves and could not be diffed. The generator is reproduced verbatim in Swift with a
//      seeded LCG standing in for `Math.random()` (same piecewise ranges, resets, `makeRandom` walk and
//      `toFixed(0)` rounding); the ONE resulting sample is inlined into BOTH panes, so they are
//      identical by construction.
// No option key is a JS closure (`symbolSize` is the number 5), so the native option is complete.

import Foundation

extension EChartsDemoRegistry {
    static let official_line_fisheye_lens = EChartsDemo(
        name: "official-line-fisheye-lens", category: "line",
        summary: "折线图鱼眼放大 — Fisheye Lens on Line Chart",
        width: 640, height: 420,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
var GRID_TOP = 120;
var GRID_BOTTOM = 80;
var GRID_LEFT = 60;
var GRID_RIGHT = 60;

var _breakAreaStyle = {
  expandOnClick: false,
  zigzagZ: 200,
  zigzagAmplitude: 0,
  itemStyle: {
    borderColor: '#777',
    opacity: 0
  }
};

// One frozen sample of the source's generateSeriesData() — see DEVIATIONS (2).
var seriesData = \#(fisheyeLensDataJSON);

option = {
  title: {
    text: 'Fisheye Lens on Line Chart',
    subtext: 'Brush to magnify the details',
    left: 'center',
    textStyle: {
      fontSize: 20
    },
    subtextStyle: {
      color: '#175ce5',
      fontSize: 15,
      fontWeight: 'bold'
    }
  },
  tooltip: {
    trigger: 'axis',
  },
  legend: {},
  grid: {
    top: GRID_TOP,
    bottom: GRID_BOTTOM,
    left: GRID_LEFT,
    right: GRID_RIGHT
  },
  xAxis: [{
    splitLine: {
      show: false
    },
    breakArea: _breakAreaStyle
  }],
  yAxis: [{
    axisTick: {
      show: true
    },
    breakArea: _breakAreaStyle
  }],
  series: [{
    type: 'line',
    name: 'Data A',
    symbol: 'circle',
    showSymbol: false,
    symbolSize: 5,
    data: seriesData
  }]
};
"""#,
        option: [
            "title": [
                "text": "Fisheye Lens on Line Chart",
                "subtext": "Brush to magnify the details",
                "left": "center",
                "textStyle": [
                    "fontSize": 20.0
                ] as [String: Any],
                "subtextStyle": [
                    "color": "#175ce5",
                    "fontSize": 15.0,
                    "fontWeight": "bold"
                ] as [String: Any]
            ] as [String: Any],
            "tooltip": [
                "trigger": "axis"
            ] as [String: Any],
            "legend": [:] as [String: Any],
            "grid": [
                "top": fisheyeLensGridTop,
                "bottom": fisheyeLensGridBottom,
                "left": fisheyeLensGridLeft,
                "right": fisheyeLensGridRight
            ] as [String: Any],
            "xAxis": [
                [
                    "splitLine": [
                        "show": false
                    ] as [String: Any],
                    "breakArea": fisheyeLensBreakAreaStyle
                ] as [String: Any]
            ],
            "yAxis": [
                [
                    "axisTick": [
                        "show": true
                    ] as [String: Any],
                    "breakArea": fisheyeLensBreakAreaStyle
                ] as [String: Any]
            ],
            "series": [
                [
                    "type": "line",
                    "name": "Data A",
                    "symbol": "circle",
                    "showSymbol": false,
                    "symbolSize": 5.0,
                    "data": fisheyeLensData
                ] as [String: Any]
            ]
        ])
}

// MARK: - option constants (verbatim from the source's top-level vars)

private let fisheyeLensGridTop: Double = 120
private let fisheyeLensGridBottom: Double = 80
private let fisheyeLensGridLeft: Double = 60
private let fisheyeLensGridRight: Double = 60
private let fisheyeLensYDataRoundPrecision = 0

/// Shared by both axes, exactly as the source's `_breakAreaStyle`. Inert until a brush creates a
/// break (see DEVIATIONS (1)); kept so the option is a faithful copy.
private let fisheyeLensBreakAreaStyle: [String: Any] = [
    "expandOnClick": false,
    "zigzagZ": 200.0,
    "zigzagAmplitude": 0.0,
    "itemStyle": [
        "borderColor": "#777",
        "opacity": 0.0
    ] as [String: Any]
]

// MARK: - frozen series data (see DEVIATIONS (2))

/// The source's `generateSeriesData()`, line for line, with a seeded LCG in place of `Math.random()`
/// so the curve is deterministic and BOTH panes plot the same 1000 points.
private let fisheyeLensData: [[Double]] = {
    // xorshift64* — any reproducible uniform on [0, 1) does; the official uses Math.random().
    var state: UInt64 = 0x9E37_79B9_7F4A_7C15
    func random() -> Double {
        state ^= state >> 12
        state ^= state << 25
        state ^= state >> 27
        return Double((state &* 0x2545_F491_4F6C_DD1D) >> 11) / Double(1 << 53)
    }
    // roundXYValue: +(+val).toFixed(Y_DATA_ROUND_PRECISION), with the precision fixed at 0.
    func roundXYValue(_ val: Double) -> Double {
        let scale = pow(10.0, Double(fisheyeLensYDataRoundPrecision))
        return (val * scale).rounded() / scale
    }
    func makeRandom(_ lastYVal: Double, _ range: [Double], _ factor: Double) -> Double {
        let shifted = lastYVal - range[0]
        let delta = (random() - 0.5 * sin(shifted / factor)) * (range[1] - range[0]) * 0.8
        return roundXYValue(shifted + delta + range[0])
    }

    var seriesData: [[Double]] = []
    let dataCount = 1000
    var reset1 = true
    var reset2 = true
    var yVal: Double = 0
    for idx in 0..<dataCount {
        let i = Double(idx)
        let count = Double(dataCount)
        if i < count / 4 {
            yVal = makeRandom(yVal, [100, 10000], 50000)
        } else if i < (2 * count) / 3 {
            if reset1 { yVal = 110010; reset1 = false }
            yVal = makeRandom(yVal, [100000, 105000], 50000)
        } else {
            if reset2 { yVal = 300100; reset2 = false }
            yVal = makeRandom(yVal, [300000, 305000], 20000)
        }
        seriesData.append([i, yVal])
    }
    return seriesData
}()

/// The same points as a JS array literal, spliced into webOptionJS.
private let fisheyeLensDataJSON: String = {
    let pairs = fisheyeLensData.map { "[\(Int($0[0])),\(Int($0[1]))]" }
    return "[" + pairs.joined(separator: ",") + "]"
}()
