// official-custom-bar-trend — replica of https://echarts.apache.org/examples/zh/editor.html?c=custom-bar-trend
// title: Custom Bar Trend / titleCN: 使用自定义系列添加柱状图趋势
// 7 grouped bar series (2010…2016, 30 categories, opacity 0.5) overlaid by a `custom` series named
// 'trend': per category its renderItem returns ONE `polyline` threading the tops of that category's 7
// bars — the bars' pixel x's come from `api.barLayout({ barGap: '30%', barCategoryGap: '20%', count:
// currentSeriesIndices.length - 1 })[i - 1].offsetCenter`, i.e. the custom series asks the bar layout
// where each bar's centre landed instead of guessing, and lifts each vertex 20px above the bar top.
// Legend, axis tooltip, and a slider + inside dataZoom pair windowed to 50%–70% so the bars are wide
// enough for the trend line to read.
//
// DEVIATIONS from the official source:
//   1. The web pane is the example VERBATIM except: the TypeScript-only syntax is stripped (the
//      `: string[]` / `: number[][]` annotations, `api.visual('color') as string`, `as
//      echarts.BarSeriesOption`) — the page runs a CLASSIC SCRIPT, where those are syntax errors — the
//      trailing `export {};` is dropped (a bare export is a SyntaxError that would blank the whole
//      page), and the `/* title: … */` editor-metadata block is dropped. Every statement, including the
//      data loop, `echarts.number.round`, the spread of `dataList.map(...)` and renderItem, is as-is
//      (`echarts.number` is still exported by the 6.1.0 dist the pane loads).
//   2. The data is RANDOM (`Math.random()`) and regenerated on every load — upstream ships no fixed
//      dataset, so the two panes CANNOT show identical bars by construction. The native pane runs the
//      SAME recurrence (each year = the previous year ± up to 100, floored at 0) off a SEEDED PRNG so
//      its frame is stable across runs and diffable against itself. Compare the panes for layout,
//      axes, legend, dataZoom window, bar grouping, and for the FORM of the trend polyline (one open
//      stroke per category, vertices centred on the bars and 20px above them) — not for per-bar values.
//   3. `tooltip`, `legend` and `dataZoom` are interactive; the gallery snapshots ONE static frame, so
//      both panes show them in their initial state (the 50%–70% window the option itself sets).
//   4. NOTHING ELSE. `renderItem` IS ported natively (barTrendRenderItem, below) statement for
//      statement, so BOTH panes draw the whole chart: the bars AND the trend line over them.
//
// WHY THE NATIVE renderItem IS MANDATORY (do not "simplify" it back out):
//   CustomView resolves the callback as `customSeries.getRenderItem() ?? getCustomSeries(subType)`
//   (CustomView.swift:739). A Swift [String: Any] CAN carry the closure — `getRenderItem()` is exactly
//   `self.get("renderItem") as? CustomSeriesRenderItem` (CustomSeries.swift:459). It is safe here because
//   WebPage.swift only JSON-serializes `option` when `webOptionJS` is nil, and we set `webOptionJS`.
//   Omitting it would NOT leave an inert series: the `?? getCustomSeries("custom")` fallback reaches the
//   GLOBAL registry, where Demos/custom-basic.swift registers its own bar renderItem under the "custom"
//   subType, and the native pane would silently draw THAT against this demo's [i, v2010…v2016] rows — a
//   wrong chart, which is worse than a missing one.
import Foundation
import EChartsKit

// MARK: - the upstream data loop, ported

private let barTrendYearCount = 7
private let barTrendCategoryCount = 30

/// Upstream drives the data off `Math.random()`; a gallery frame must be reproducible, so the native
/// pane runs the identical recurrence on a seeded xorshift64* stream (see DEVIATION 2).
private struct BarTrendRandom {
    private var state: UInt64
    init(seed: UInt64) { self.state = seed }
    /// The `Math.random()` contract: a Double in [0, 1).
    mutating func next01() -> Double {
        state ^= state >> 12
        state ^= state << 25
        state ^= state >> 27
        let x = state &* 2_685_821_657_736_338_717
        return Double(x >> 11) * (1.0 / 9_007_199_254_740_992.0)   // 53-bit mantissa, like V8
    }
}

/// `echarts.number.round(x, precision)` — `+(+x).toFixed(precision)`, precision defaulting to 10 and
/// clamped to [0, 20]. The values stay under a few thousand, so `x * 1e2` is far inside Double's
/// exactly-representable integer range.
private func barTrendRound(_ x: Double, _ precision: Int = 10) -> Double {
    let p = pow(10.0, Double(min(max(0, precision), 20)))
    return (x * p).rounded() / p
}

/// All four upstream arrays, built in ONE pass so the PRNG draw order matches the JS exactly: per
/// category the loop draws `val` (year 0), then one jitter per later year.
///
/// A row of `customData` is `[i, v2010, …, v2016]` — index 0 is the CATEGORY INDEX, not a label; the
/// custom series reaches the labels through `encode: { x: 0 }` against the category axis, and each
/// year through `encode: { y: [1…7] }` (dim = that year's SERIES INDEX, which is what renderItem
/// passes to `api.value`).
private let barTrendGenerated: (categories: [String], custom: [[Double]], years: [[Double]], legend: [String]) = {
    var rng = BarTrendRandom(seed: 0x9E37_79B9_7F4A_7C15)

    var legend: [String] = ["trend"]
    var years: [[Double]] = []
    for i in 0..<barTrendYearCount {
        legend.append("\(2010 + i)")
        years.append([])
    }

    var categories: [String] = []
    var custom: [[Double]] = []
    categories.reserveCapacity(barTrendCategoryCount)
    custom.reserveCapacity(barTrendCategoryCount)

    for i in 0..<barTrendCategoryCount {
        let val = rng.next01() * 1000
        categories.append("category\(i)")
        var customVal: [Double] = [Double(i)]

        for j in 0..<years.count {
            // year 0 is the seed value; every later year walks from the PREVIOUS year's value at the
            // SAME category by ±100, floored at 0 (upstream reads dataList[j - 1][i], which the j - 1
            // iteration has just pushed).
            let value = j == 0
                ? barTrendRound(val, 2)
                : barTrendRound(max(0, years[j - 1][i] + (rng.next01() - 0.5) * 200), 2)
            years[j].append(value)
            customVal.append(value)
        }
        custom.append(customVal)
    }
    return (categories, custom, years, legend)
}()

private let barTrendXAxisData: [String] = barTrendGenerated.categories
private let barTrendCustomData: [[Double]] = barTrendGenerated.custom
private let barTrendDataList: [[Double]] = barTrendGenerated.years
private let barTrendLegendData: [String] = barTrendGenerated.legend

/// `encodeY` — dim 1…7 of a customData row, one per year series. Doubles: `api.value` /
/// `SeriesData.getDimensionIndex` force-cast a numeric DimensionLoose `as! Double`.
private let barTrendEncodeY: [Double] = (0..<barTrendYearCount).map { 1.0 + Double($0) }

// MARK: - the upstream renderItem, ported

/// Coerce a ParsedValue (Any: Double | Int | NSNumber) to Double — the recurring Int-vs-Double read trap.
private func barTrendNum(_ v: Any?) -> Double {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let n = v as? NSNumber { return n.doubleValue }
    return 0
}

/// The official `renderItem`, statement for statement. Typed EXACTLY `CustomSeriesRenderItem` so
/// CustomView's `get("renderItem") as? CustomSeriesRenderItem` cast holds (see header).
///
/// One datum (one category) → one `polyline` through that category's bar tops. The x of a bar is NOT
/// the category's centre: `api.coord` lands on the band centre, so each vertex is nudged by that bar's
/// `offsetCenter` from `api.barLayout` — the SAME layout the bar series themselves use, which is why
/// `count` is `currentSeriesIndices.length - 1` (all current series except this custom one). The
/// custom series' own index is skipped, so barLayout is indexed `i - 1`.
private let barTrendRenderItem: CustomSeriesRenderItem = { params, api in
    let xValue = barTrendNum(api.value(0.0, nil))
    let currentSeriesIndices = api.currentSeriesIndices()
    // `barLayout` returns `BarGridLayoutResultForCustomSeries` ([BarGridLayoutResultItem]?) through an
    //   `Any?` — nil when the base axis is not ordinal (not the case here: xAxis is a category axis).
    let barLayout = api.barLayout([
        "barGap": "30%",
        "barCategoryGap": "20%",
        "count": Double(currentSeriesIndices.count - 1)
    ] as [String: Any]) as? [BarGridLayoutResultItem]

    var points: [[Double]] = []
    for i in 0..<currentSeriesIndices.count {
        let seriesIndex = currentSeriesIndices[i]
        if seriesIndex != params.seriesIndex {
            // JS reads barLayout[i - 1] unguarded; an out-of-range read is `undefined` there but a CRASH
            //   in Swift, so the bounds are checked (they hold whenever this custom series is the first
            //   of the current series, which is how the option declares it).
            guard i >= 1, let layout = barLayout, i - 1 < layout.count else { continue }
            var point = api.coord([xValue, barTrendNum(api.value(seriesIndex, nil))], nil)
            guard point.count >= 2 else { continue }
            point[0] += layout[i - 1].offsetCenter
            point[1] -= 20
            points.append(point)
        }
    }
    // JS: api.style({ stroke: api.visual('color'), fill: 'none' }). A missing visual is `undefined` in
    //   JS (an absent key); Swift cannot store that, so the key is simply not written.
    var userProps: [String: Any] = ["fill": "none"]
    if let color = api.visual("color", nil) { userProps["stroke"] = color }
    let style = api.style(userProps, nil)

    return [
        "type": "polyline",
        "shape": [
            "points": points
        ] as [String: Any],
        "style": style
    ] as [String: Any]
}

// MARK: - series

/// Upstream's `...dataList.map(...)`: one plain bar series per year, half-opaque and un-animated.
private let barTrendBarSeries: [[String: Any]] = barTrendDataList.enumerated().map { index, data in
    [
        "type": "bar",
        "animation": false,
        "name": barTrendLegendData[index + 1],
        "itemStyle": [
            "opacity": 0.5
        ] as [String: Any],
        "data": data
    ] as [String: Any]
}

/// The trend overlay. `z: 100` keeps the polyline above every bar.
private let barTrendCustomSeries: [String: Any] = [
    "type": "custom",
    "name": "trend",
    // The per-series closure (see header: this key is what keeps the global custom-series registry's
    // `getCustomSeries("custom")` fallback from hijacking this chart).
    "renderItem": barTrendRenderItem,
    "itemStyle": [
        "borderWidth": 2.0
    ] as [String: Any],
    "encode": [
        "x": 0.0,
        "y": barTrendEncodeY
    ] as [String: Any],
    "data": barTrendCustomData,
    "z": 100.0
]

private let barTrendSeries: [[String: Any]] = [barTrendCustomSeries] + barTrendBarSeries

extension EChartsDemoRegistry {
    static let official_custom_bar_trend = EChartsDemo(
        name: "official-custom-bar-trend", category: "custom",
        summary: "使用自定义系列添加柱状图趋势 — Custom Bar Trend",
        width: 720, height: 460,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
const yearCount = 7;
const categoryCount = 30;

const xAxisData = [];
const customData = [];
const legendData = [];
const dataList = [];

legendData.push('trend');
const encodeY = [];
for (var i = 0; i < yearCount; i++) {
  legendData.push(2010 + i + '');
  dataList.push([]);
  encodeY.push(1 + i);
}

for (var i = 0; i < categoryCount; i++) {
  var val = Math.random() * 1000;
  xAxisData.push('category' + i);
  var customVal = [i];
  customData.push(customVal);

  for (var j = 0; j < dataList.length; j++) {
    var value =
      j === 0
        ? echarts.number.round(val, 2)
        : echarts.number.round(
            Math.max(0, dataList[j - 1][i] + (Math.random() - 0.5) * 200),
            2
          );
    dataList[j].push(value);
    customVal.push(value);
  }
}

option = {
  tooltip: {
    trigger: 'axis'
  },
  legend: {
    data: legendData,
    top: 20
  },
  dataZoom: [
    {
      type: 'slider',
      start: 50,
      end: 70
    },
    {
      type: 'inside',
      start: 50,
      end: 70
    }
  ],
  xAxis: {
    data: xAxisData
  },
  yAxis: {},
  series: [
    {
      type: 'custom',
      name: 'trend',
      renderItem: function (params, api) {
        var xValue = api.value(0);
        var currentSeriesIndices = api.currentSeriesIndices();
        var barLayout = api.barLayout({
          barGap: '30%',
          barCategoryGap: '20%',
          count: currentSeriesIndices.length - 1
        });

        var points = [];
        for (var i = 0; i < currentSeriesIndices.length; i++) {
          var seriesIndex = currentSeriesIndices[i];
          if (seriesIndex !== params.seriesIndex) {
            var point = api.coord([xValue, api.value(seriesIndex)]);
            point[0] += barLayout[i - 1].offsetCenter;
            point[1] -= 20;
            points.push(point);
          }
        }
        var style = api.style({
          stroke: api.visual('color'),
          fill: 'none'
        });

        return {
          type: 'polyline',
          shape: {
            points: points
          },
          style: style
        };
      },
      itemStyle: {
        borderWidth: 2
      },
      encode: {
        x: 0,
        y: encodeY
      },
      data: customData,
      z: 100
    },
    ...dataList.map(function (data, index) {
      return {
        type: 'bar',
        animation: false,
        name: legendData[index + 1],
        itemStyle: {
          opacity: 0.5
        },
        data: data
      };
    })
  ]
};
"""#,
        option: [
            "tooltip": [
                "trigger": "axis"
            ] as [String: Any],
            "legend": [
                "data": barTrendLegendData,
                "top": 20.0
            ] as [String: Any],
            "dataZoom": [
                [
                    "type": "slider",
                    "start": 50.0,
                    "end": 70.0
                ] as [String: Any],
                [
                    "type": "inside",
                    "start": 50.0,
                    "end": 70.0
                ] as [String: Any]
            ],
            "xAxis": [
                "data": barTrendXAxisData
            ] as [String: Any],
            "yAxis": [:] as [String: Any],
            "series": barTrendSeries
        ])
}
