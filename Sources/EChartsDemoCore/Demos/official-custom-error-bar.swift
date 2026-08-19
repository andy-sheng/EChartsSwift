// official-custom-error-bar — replica of https://echarts.apache.org/examples/zh/editor.html?c=custom-error-bar
// title: Error Bar on Catesian / titleCN: 使用自定系列给柱状图添加误差范围
// 100 procedurally-generated bars on a category x-axis, each overlaid by an I-beam error bar drawn by a
// second, `custom` series: per datum a `group` of three `line`s — a vertical spine from the low value to
// the high one, capped top and bottom by a horizontal serif whose half-width is 10% of one category band
// (`api.size([1, 0])[0] * 0.1`). Title, legend, shadow-axisPointer tooltip, and a slider + inside dataZoom
// pair windowed to 50%–70% so the bars are wide enough to read.
//
// DEVIATIONS from the official source:
//   1. The web pane is the example VERBATIM except: the TypeScript annotations are stripped
//      (`api.size!([1, 0]) as number[]`, `api.visual('color') as string`) — the page runs a CLASSIC
//      SCRIPT, where those are syntax errors — the trailing `export {};` is dropped (a bare export is a
//      SyntaxError that would blank the whole page), and the `/* title: … */` editor-metadata block is
//      dropped. Every statement, including the data loop and `echarts.number.round`, is otherwise as-is
//      (`echarts.number` is still exported by the 6.1.0 dist the pane loads).
//   2. The upstream data is RANDOM (`Math.random()`). We run its recurrence once with a seeded PRNG and
//      inject the resulting arrays into both panes for deterministic pixel comparison.
//   3. `tooltip` and `dataZoom` are interactive; the gallery snapshots ONE static frame, so both panes
//      show them in their initial state (the dataZoom window the option itself sets, 50%–70%).
//   4. NOTHING ELSE. `renderItem` IS ported natively (errorBarRenderItem, below) statement for
//      statement, so BOTH panes draw the whole chart: the bars AND their error bars.
//
// WHY THE NATIVE renderItem IS MANDATORY (do not "simplify" it back out):
//   CustomView resolves the callback as `customSeries.getRenderItem() ?? getCustomSeries(subType)`
//   (CustomView.swift:739). A Swift [String: Any] CAN carry the closure — `getRenderItem()` is exactly
//   `self.get("renderItem") as? CustomSeriesRenderItem` (CustomSeries.swift:459). It is safe here because
//   WebPage.swift only JSON-serializes `option` when `webOptionJS` is nil, and we set `webOptionJS`.
//   Omitting it would NOT leave an inert series: the `?? getCustomSeries("custom")` fallback reaches the
//   GLOBAL registry, where Demos/custom-basic.swift registers its own bar renderItem under the "custom"
//   subType, and the native pane would silently draw THAT against this demo's [i, low, high] rows — a
//   wrong chart, which is worse than a missing one.
import Foundation
import EChartsKit

// MARK: - the upstream data loop, ported

private let errorBarDataCount = 100

/// Upstream drives the data off `Math.random()`; a gallery frame must be reproducible, so the native
/// pane runs the identical recurrence on a seeded xorshift64* stream (see DEVIATION 2).
private struct ErrorBarRandom {
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
/// clamped to [0, 20]. Half-away-from-zero, like `toFixed` on the positive values used here. The values
/// stay under ~1100, so `x * 1e10` is far inside Double's exactly-representable integer range.
private func errorBarRound(_ x: Double, _ precision: Int = 10) -> Double {
    let p = pow(10.0, Double(min(max(0, precision), 20)))
    return (x * p).rounded() / p
}

/// All three upstream arrays, built in ONE pass so the PRNG draw order matches the JS exactly: per `i`
/// the loop draws `val`, then the low bound's jitter, then the high bound's.
///
/// A row of `errors` is `[i, low, high]` — index 0 is the CATEGORY INDEX, not a label; the custom series
/// reaches the labels through `encode: { x: 0 }` against the category axis.
private let errorBarGenerated: (categories: [String], errors: [[Double]], bars: [Double]) = {
    var rng = ErrorBarRandom(seed: 0x9E37_79B9_7F4A_7C15)
    var categories: [String] = []
    var errors: [[Double]] = []
    var bars: [Double] = []
    categories.reserveCapacity(errorBarDataCount)
    errors.reserveCapacity(errorBarDataCount)
    bars.reserveCapacity(errorBarDataCount)

    for i in 0..<errorBarDataCount {
        let val = rng.next01() * 1000
        categories.append("category\(i)")
        errors.append([
            Double(i),
            errorBarRound(max(0, val - rng.next01() * 100)),
            errorBarRound(val + rng.next01() * 80)
        ])
        bars.append(errorBarRound(val, 2))
    }
    return (categories, errors, bars)
}()

private let errorBarCategoryData: [String] = errorBarGenerated.categories
private let errorBarErrorData: [[Double]] = errorBarGenerated.errors
private let errorBarBarData: [Double] = errorBarGenerated.bars

private func errorBarJSON(_ value: Any) -> String {
    guard let data = try? JSONSerialization.data(withJSONObject: value, options: []),
          let json = String(data: data, encoding: .utf8) else { return "[]" }
    return json
}
private let errorBarCategoryDataJSON = errorBarJSON(errorBarCategoryData)
private let errorBarErrorDataJSON = errorBarJSON(errorBarErrorData)
private let errorBarBarDataJSON = errorBarJSON(errorBarBarData)

// MARK: - the upstream renderItem, ported

/// Coerce a ParsedValue (Any: Double | Int | NSNumber) to Double — the recurring Int-vs-Double read trap.
private func errorBarNum(_ v: Any?) -> Double {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let n = v as? NSNumber { return n.doubleValue }
    return 0
}

/// The official `renderItem`, statement for statement. Typed EXACTLY `CustomSeriesRenderItem` so
/// CustomView's `get("renderItem") as? CustomSeriesRenderItem` cast holds (see header).
///
/// One datum → one I-beam, as a `group` of three `line`s. Dim 0 is the category index; dims 1 and 2 are
/// the error bounds, projected through `api.coord` to two pixel points. (Upstream names them `highPoint`
/// and `lowPoint` even though dim 1 is the LOWER bound — the names are kept verbatim; only the serif
/// order on screen differs, not the geometry.) The serif half-width is 10% of one category band, which
/// `api.size([1, 0])[0]` measures.
private let errorBarRenderItem: CustomSeriesRenderItem = { _, api in
    let xValue = errorBarNum(api.value(0.0, nil))
    // `api.value` takes a DimensionLoose (Any); a NUMERIC dim must be a Double — SeriesData
    //   .getDimensionIndex force-casts it `as! Double`, so an Int literal would crash.
    let highPoint = api.coord([xValue, errorBarNum(api.value(1.0, nil))], nil)
    let lowPoint = api.coord([xValue, errorBarNum(api.value(2.0, nil))], nil)
    guard highPoint.count >= 2, lowPoint.count >= 2 else { return nil }
    let halfWidth = ((api.size([1.0, 0.0], nil) as? [Double])?.first ?? 0) * 0.1

    // JS: api.style({ stroke: api.visual('color'), fill: undefined }).
    //   `fill: undefined` → the key is ABSENT (a `line` never fills anyway); Swift cannot store an
    //   `undefined`, so drop the key from the merged bag rather than writing NSNull.
    var userProps: [String: Any] = [:]
    if let color = api.visual("color", nil) { userProps["stroke"] = color }
    var style = api.style(userProps, nil)
    style.removeValue(forKey: "fill")

    // Built as an explicitly-typed local rather than inlined into the return literal: Swift's
    //   type-checker times out on large nested heterogeneous literals.
    let children: [[String: Any]] = [
        // the serif capping dim 1's end
        [
            "type": "line",
            "transition": ["shape"],
            "shape": [
                "x1": highPoint[0] - halfWidth, "y1": highPoint[1],
                "x2": highPoint[0] + halfWidth, "y2": highPoint[1]
            ] as [String: Any],
            "style": style
        ],
        // the spine, dim 1 → dim 2
        [
            "type": "line",
            "transition": ["shape"],
            "shape": [
                "x1": highPoint[0], "y1": highPoint[1],
                "x2": lowPoint[0], "y2": lowPoint[1]
            ] as [String: Any],
            "style": style
        ],
        // the serif capping dim 2's end
        [
            "type": "line",
            "transition": ["shape"],
            "shape": [
                "x1": lowPoint[0] - halfWidth, "y1": lowPoint[1],
                "x2": lowPoint[0] + halfWidth, "y2": lowPoint[1]
            ] as [String: Any],
            "style": style
        ]
    ]

    return [
        "type": "group",
        "children": children
    ] as [String: Any]
}

extension EChartsDemoRegistry {
    static let official_custom_error_bar = EChartsDemo(
        name: "official-custom-error-bar", category: "custom",
        summary: "使用自定系列给柱状图添加误差范围 — Error Bar on Catesian",
        width: 720, height: 460,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
var categoryData = \#(errorBarCategoryDataJSON);
var errorData = \#(errorBarErrorDataJSON);
var barData = \#(errorBarBarDataJSON);

option = {
  tooltip: {
    trigger: 'axis',
    axisPointer: {
      type: 'shadow'
    }
  },
  title: {
    text: 'Error bar chart'
  },
  legend: {
    data: ['bar', 'error'],
    top: 20,
    right: 30
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
    data: categoryData
  },
  yAxis: {},
  series: [
    {
      type: 'bar',
      name: 'bar',
      data: barData,
      itemStyle: {
        color: '#77bef7'
      }
    },
    {
      type: 'custom',
      name: 'error',
      itemStyle: {
        borderWidth: 1.5
      },
      renderItem: function (params, api) {
        var xValue = api.value(0);
        var highPoint = api.coord([xValue, api.value(1)]);
        var lowPoint = api.coord([xValue, api.value(2)]);
        var halfWidth = api.size([1, 0])[0] * 0.1;
        var style = api.style({
          stroke: api.visual('color'),
          fill: undefined
        });

        return {
          type: 'group',
          children: [
            {
              type: 'line',
              transition: ['shape'],
              shape: {
                x1: highPoint[0] - halfWidth,
                y1: highPoint[1],
                x2: highPoint[0] + halfWidth,
                y2: highPoint[1]
              },
              style: style
            },
            {
              type: 'line',
              transition: ['shape'],
              shape: {
                x1: highPoint[0],
                y1: highPoint[1],
                x2: lowPoint[0],
                y2: lowPoint[1]
              },
              style: style
            },
            {
              type: 'line',
              transition: ['shape'],
              shape: {
                x1: lowPoint[0] - halfWidth,
                y1: lowPoint[1],
                x2: lowPoint[0] + halfWidth,
                y2: lowPoint[1]
              },
              style: style
            }
          ]
        };
      },
      encode: {
        x: 0,
        y: [1, 2]
      },
      data: errorData,
      z: 100
    }
  ]
};
"""#,
        option: [
            "tooltip": [
                "trigger": "axis",
                "axisPointer": [
                    "type": "shadow"
                ] as [String: Any]
            ] as [String: Any],
            "title": [
                "text": "Error bar chart"
            ] as [String: Any],
            "legend": [
                "data": ["bar", "error"],
                "top": 20.0,
                "right": 30.0
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
                "data": errorBarCategoryData
            ] as [String: Any],
            "yAxis": [:] as [String: Any],
            "series": [
                [
                    "type": "bar",
                    "name": "bar",
                    "data": errorBarBarData,
                    "itemStyle": [
                        "color": "#77bef7"
                    ] as [String: Any]
                ] as [String: Any],
                [
                    "type": "custom",
                    "name": "error",
                    "itemStyle": [
                        "borderWidth": 1.5
                    ] as [String: Any],
                    // The per-series closure (see header: this key is what keeps the global custom-series
                    // registry's `getCustomSeries("custom")` fallback from hijacking this chart).
                    "renderItem": errorBarRenderItem,
                    "encode": [
                        "x": 0.0,
                        "y": [1.0, 2.0]
                    ] as [String: Any],
                    "data": errorBarErrorData,
                    "z": 100.0
                ] as [String: Any]
            ]
        ])
}
