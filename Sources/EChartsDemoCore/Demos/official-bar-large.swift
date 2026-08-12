// official-bar-large — replica of https://echarts.apache.org/examples/zh/editor.html?c=bar-large
// title: Large Scale Bar Chart / titleCN: 大数据量柱图
// 500,000 procedurally-generated bars (one per second from 2011-01-01) on a category x-axis, drawn
// through the bar series' `large: true` fast path, with an inside + slider dataZoom pair and a
// dataZoom / saveAsImage toolbox.
//
// DEVIATIONS from the official source:
//   1. webOptionJS is the example verbatim except: the TypeScript annotations are stripped
//      (`count: number`, `idx: number`, `let smallBaseValue: number;`) — the reference pane runs a
//      classic script, not TS — and the trailing `export {};` is dropped (a bare export is a
//      SyntaxError in a classic script and would blank the whole page). `echarts.format.addCommas`
//      and `echarts.format.formatTime` stay as-is: both are real echarts API, still exported by the
//      6.1.0 dist the pane loads.
//   2. The upstream data is RANDOM (`Math.random()`) and regenerated on every load. The gallery pins
//      both panes to the same seeded 32-bit LCG, keeping the original recurrence and call order while
//      making the 500,000 bars and their dataZoom shadow directly comparable.
//   3. Upstream pushes `next(i).toFixed(2)` — numeric STRINGS ("3288.00"). `next()` is always
//      integer-valued (`Math.max(0, Math.round(...) + 3000)`), so the native pane carries plain
//      Doubles: the same numbers, minus a string round-trip the Swift option bag has no reason to
//      reproduce.
//   4. `title.text` is `echarts.format.addCommas(dataCount) + ' Data'` and each category is
//      `echarts.format.formatTime('yyyy-MM-dd\nhh:mm:ss', time, false)`. Both are helpers called
//      while BUILDING the option, not closures IN it, so the native pane pre-computes the same
//      strings ("500,000 Data", "2011-01-01\n00:00:00", …) rather than omitting them.
//   5. `toolbox` and `dataZoom` are interactive; the gallery snapshots ONE static frame, so both
//      panes show them in their initial (full-range) state.
//
// KNOWN NATIVE GAP (kept faithful on purpose — surfacing it is the point of this demo): with
// `large: true` and 500k >= `largeThreshold` (400), `modelUtil.preparePipelineContext` sets
// `pipelineContext.large`, so BarView takes `_renderLarge` — a PORT-NOTE(deferred) stub (upstream
// `createLarge` / `LargePath` / `util/throttle` are not ported) that only updates the clip. The
// native pane is expected to draw title, axes, dataZoom and toolbox but NO BARS until LargePath
// lands. Dropping `large` to make the native pane "work" would hide exactly the gap we are hunting,
// so it stays.
import Foundation

// MARK: - the upstream `generateData(5e5)`, ported

private let barLargeDataCount = 500_000

/// Seeded 32-bit LCG shared bit-for-bit with `rnd()` in the web pane.
private struct BarLargeRandom {
    private var state: UInt32
    init(seed: UInt32) { self.state = seed }
    /// The `Math.random()` contract: a Double in [0, 1).
    mutating func next01() -> Double {
        state = state &* 1_664_525 &+ 1_013_904_223
        return Double(state) / 4_294_967_296.0
    }
}

/// Both arrays of the upstream `generateData`, built in one pass.
///
/// The categories are what `echarts.format.formatTime('yyyy-MM-dd\nhh:mm:ss', time, false)` yields
/// for `time = +new Date(2011, 0, 1) + i * 1000` — i.e. padded LOCAL wall-clock fields, `hh` being
/// the 24-hour one. 500k seconds is 5d 18h 53m 20s, so the range stays inside 2011-01-01 … 2011-01-06:
/// no month/year boundary is crossed, which lets this be integer arithmetic instead of 500k Calendar
/// round-trips.
private let barLargeGenerated: (categories: [String], values: [Double]) = {
    var rng = BarLargeRandom(seed: 0x1234_5678)
    var baseValue = rng.next01() * 1000
    var smallBaseValue = 0.0   // JS `let smallBaseValue;` — never read before idx 0 assigns it.

    // upstream `next(idx)`. `Math.round` is floor(x + 0.5) (half-up, not half-away-from-zero).
    func next(_ idx: Int) -> Double {
        smallBaseValue = idx % 30 == 0
            ? rng.next01() * 700
            : smallBaseValue + rng.next01() * 500 - 250
        baseValue += rng.next01() * 20 - 10
        return max(0, (baseValue + smallBaseValue + 0.5).rounded(.down) + 3000)
    }

    func pad2(_ v: Int) -> String { v < 10 ? "0\(v)" : "\(v)" }

    var categories: [String] = []
    var values: [Double] = []
    categories.reserveCapacity(barLargeDataCount)
    values.reserveCapacity(barLargeDataCount)

    for i in 0..<barLargeDataCount {
        let day = 1 + i / 86_400        // 2011-01-01 … 2011-01-06
        let rem = i % 86_400
        categories.append(
            "2011-01-\(pad2(day))\n\(pad2(rem / 3600)):\(pad2((rem % 3600) / 60)):\(pad2(rem % 60))")
        values.append(next(i))
    }
    return (categories, values)
}()

private let barLargeCategoryData: [String] = barLargeGenerated.categories
private let barLargeValueData: [Double] = barLargeGenerated.values
/// `echarts.format.addCommas(5e5) + ' Data'`, pre-computed.
private let barLargeTitleText = "500,000 Data"

// MARK: - demo

extension EChartsDemoRegistry {
    static let official_bar_large = EChartsDemo(
        name: "official-bar-large", category: "bar",
        summary: "大数据量柱图 — Large Scale Bar Chart",
        width: 640, height: 420,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
let barLargeRngState = 0x12345678 >>> 0;
function barLargeRnd() {
  barLargeRngState = (Math.imul(barLargeRngState, 1664525) + 1013904223) >>> 0;
  return barLargeRngState / 4294967296;
}

const dataCount = 5e5;
const data = generateData(dataCount);

option = {
  title: {
    text: echarts.format.addCommas(dataCount) + ' Data',
    left: 10
  },
  toolbox: {
    feature: {
      dataZoom: {
        yAxisIndex: false
      },
      saveAsImage: {
        pixelRatio: 2
      }
    }
  },
  tooltip: {
    trigger: 'axis',
    axisPointer: {
      type: 'shadow'
    }
  },
  grid: {
    bottom: 90
  },
  dataZoom: [
    {
      type: 'inside'
    },
    {
      type: 'slider'
    }
  ],
  xAxis: {
    data: data.categoryData,
    silent: false,
    splitLine: {
      show: false
    },
    splitArea: {
      show: false
    }
  },
  yAxis: {
    splitArea: {
      show: false
    }
  },
  series: [
    {
      type: 'bar',
      data: data.valueData,
      // Set `large` for large data amount
      large: true,
      // Snapshot harness: finish the full large path synchronously before capture.
      progressive: 0
    }
  ]
};

function generateData(count) {
  let baseValue = barLargeRnd() * 1000;
  let time = +new Date(2011, 0, 1);
  let smallBaseValue;

  function next(idx) {
    smallBaseValue =
      idx % 30 === 0
        ? barLargeRnd() * 700
        : smallBaseValue + barLargeRnd() * 500 - 250;
    baseValue += barLargeRnd() * 20 - 10;
    return Math.max(0, Math.round(baseValue + smallBaseValue) + 3000);
  }

  const categoryData = [];
  const valueData = [];

  for (let i = 0; i < count; i++) {
    categoryData.push(
      echarts.format.formatTime('yyyy-MM-dd\nhh:mm:ss', time, false)
    );
    valueData.push(next(i).toFixed(2));
    time += 1000;
  }

  return {
    categoryData: categoryData,
    valueData: valueData
  };
}
"""#,
        option: [
            "title": [
                "text": barLargeTitleText,
                "left": 10.0
            ] as [String: Any],
            "toolbox": [
                "feature": [
                    "dataZoom": [
                        "yAxisIndex": false
                    ] as [String: Any],
                    "saveAsImage": [
                        "pixelRatio": 2.0
                    ] as [String: Any]
                ] as [String: Any]
            ] as [String: Any],
            "tooltip": [
                "trigger": "axis",
                "axisPointer": [
                    "type": "shadow"
                ] as [String: Any]
            ] as [String: Any],
            "grid": [
                "bottom": 90.0
            ] as [String: Any],
            "dataZoom": [
                ["type": "inside"] as [String: Any],
                ["type": "slider"] as [String: Any]
            ],
            "xAxis": [
                "data": barLargeCategoryData,
                "silent": false,
                "splitLine": [
                    "show": false
                ] as [String: Any],
                "splitArea": [
                    "show": false
                ] as [String: Any]
            ] as [String: Any],
            "yAxis": [
                "splitArea": [
                    "show": false
                ] as [String: Any]
            ] as [String: Any],
            "series": [
                [
                    "type": "bar",
                    "data": barLargeValueData,
                    // Set `large` for large data amount
                    "large": true,
                    "progressive": 0.0
                ] as [String: Any]
            ]
        ])
}
