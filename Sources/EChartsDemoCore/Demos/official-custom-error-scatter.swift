// official-custom-error-scatter — replica of https://echarts.apache.org/examples/zh/editor.html?c=custom-error-scatter
// title: Error Scatter on Catesian / titleCN: 使用自定系列给散点图添加误差范围
// ACME Fashion's spring/summer 2016 line: a `scatter` series plots each garment at (prime cost, price),
// and a second, `custom` series overlays a two-axis error cross per point — a horizontal whisker spanning
// [prime cost min, prime cost max] and a vertical one spanning [price min, price max], each capped with a
// 5px serif. Both series read the same 7-column rows through `dimensions` + `encode`. Value x/y axes,
// slider + inside dataZoom, legend, tooltip.
//
// DEVIATIONS from the official source:
//   - TS ANNOTATIONS STRIPPED in the web pane: the official source is TypeScript (`params:
//     echarts.CustomSeriesRenderItemParams`, `api.visual('color') as string`, `var shape:
//     Record<string, number>`). The page runs a CLASSIC SCRIPT, where those are syntax errors, so the
//     types are removed. Every statement is otherwise verbatim, including `makeShape`'s dimension-
//     swapping trick and the vestigial `legend.data: ['bar', 'error']` (no series is named `bar`).
//   - NOTHING ELSE. `renderItem` IS ported natively (errorScatterRenderItem, below) statement for
//     statement, so BOTH panes draw the whole chart: scatter points + the two-axis error crosses.
//
// WHY THE NATIVE renderItem IS MANDATORY (do not "simplify" it back out):
//   CustomView resolves the callback as `customSeries.getRenderItem() ?? getCustomSeries(subType)`
//   (CustomView.swift:739). A Swift [String: Any] CAN carry the closure — `getRenderItem()` is exactly
//   `self.get("renderItem") as? CustomSeriesRenderItem` (CustomSeries.swift:459), and Util.clone passes
//   a non-dict/non-array value through untouched. It is safe here because WebPage.swift only
//   JSON-serializes `option` when `webOptionJS` is nil, and we set `webOptionJS`.
//   Omitting it would NOT leave an inert series: the `?? getCustomSeries("custom")` fallback reaches the
//   GLOBAL registry, where Demos/custom-basic.swift registers its own bar renderItem under the "custom"
//   subType (a side effect of `demo_custom_basic`, which `EChartsDemoRegistry.everything` forces). The
//   native pane would then silently draw custom-basic's BARS against this demo's 7-column garment rows
//   (its api.value(0) reads our `name` column → 0) — a WRONG chart, which is worse than a missing one.
//
// VERIFIED BY READING (this port was audited under a no-build constraint):
//   group + line elements with x1/y1/x2/y2 shapes (CustomView.swift:613), api.coord / api.value, and
//   api.style's userProps merge (CustomView.swift:917 — a deferred best-effort stub, but it does apply
//   the `stroke` we pass). NOT verified: whether a `custom` series' itemVisual carries a palette colour,
//   i.e. whether api.visual('color') is non-nil. If it is nil the crosses' GEOMETRY is unaffected; only
//   their stroke colour falls back to the visual bag's default.
import Foundation
import EChartsKit

extension EChartsDemoRegistry {
    static let official_custom_error_scatter = EChartsDemo(
        name: "official-custom-error-scatter", category: "custom",
        summary: "使用自定系列给散点图添加误差范围 — Error Scatter on Catesian",
        width: 720, height: 460,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
// Prime Costs and Prices for ACME Fashion\nCollection "Spring-Summer, 2016"
// Data from https://playground.anychart.com/gallery/7.12.0/Error_Charts/Marker_Chart

// prettier-ignore
const dimensions = [
    'name', 'Price', 'Prime cost', 'Prime cost min', 'Prime cost max', 'Price min', 'Price max'
];
// prettier-ignore
const data = [
    ['Blouse "Blue Viola"', 101.88, 99.75, 76.75, 116.75, 69.88, 119.88],
    ['Dress "Daisy"', 155.8, 144.03, 126.03, 156.03, 129.8, 188.8],
    ['Trousers "Cutesy Classic"', 203.25, 173.56, 151.56, 187.56, 183.25, 249.25],
    ['Dress "Morning Dew"', 256, 120.5, 98.5, 136.5, 236, 279],
    ['Turtleneck "Dark Chocolate"', 408.89, 294.75, 276.75, 316.75, 385.89, 427.89],
    ['Jumper "Early Spring"', 427.36, 430.24, 407.24, 452.24, 399.36, 461.36],
    ['Breeches "Summer Mood"', 356, 135.5, 123.5, 151.5, 333, 387],
    ['Dress "Mauve Chamomile"', 406, 95.5, 73.5, 111.5, 366, 429],
    ['Dress "Flying Tits"', 527.36, 503.24, 488.24, 525.24, 485.36, 551.36],
    ['Dress "Singing Nightingales"', 587.36, 543.24, 518.24, 555.24, 559.36, 624.36],
    ['Sundress "Cloudy weather"', 603.36, 407.24, 392.24, 419.24, 581.36, 627.36],
    ['Sundress "East motives"', 633.36, 477.24, 445.24, 487.24, 594.36, 652.36],
    ['Sweater "Cold morning"', 517.36, 437.24, 416.24, 454.24, 488.36, 565.36],
    ['Trousers "Lavender Fields"', 443.36, 387.24, 370.24, 413.24, 412.36, 484.36],
    ['Jumper "Coffee with Milk"', 543.36, 307.24, 288.24, 317.24, 509.36, 574.36],
    ['Blouse "Blooming Cactus"', 790.36, 277.24, 254.24, 295.24, 764.36, 818.36],
    ['Sweater "Fluffy Comfort"', 790.34, 678.34, 660.34, 690.34, 762.34, 824.34]
];

function renderItem(params, api) {
  const group = {
    type: 'group',
    children: []
  };
  let coordDims = ['x', 'y'];

  for (let baseDimIdx = 0; baseDimIdx < 2; baseDimIdx++) {
    let otherDimIdx = 1 - baseDimIdx;
    let encode = params.encode;
    let baseValue = api.value(encode[coordDims[baseDimIdx]][0]);
    let param = [];
    param[baseDimIdx] = baseValue;
    param[otherDimIdx] = api.value(encode[coordDims[otherDimIdx]][1]);
    let highPoint = api.coord(param);
    param[otherDimIdx] = api.value(encode[coordDims[otherDimIdx]][2]);
    let lowPoint = api.coord(param);
    let halfWidth = 5;

    var style = api.style({
      stroke: api.visual('color'),
      fill: undefined
    });

    group.children.push(
      {
        type: 'line',
        transition: ['shape'],
        shape: makeShape(
          baseDimIdx,
          highPoint[baseDimIdx] - halfWidth,
          highPoint[otherDimIdx],
          highPoint[baseDimIdx] + halfWidth,
          highPoint[otherDimIdx]
        ),
        style: style
      },
      {
        type: 'line',
        transition: ['shape'],
        shape: makeShape(
          baseDimIdx,
          highPoint[baseDimIdx],
          highPoint[otherDimIdx],
          lowPoint[baseDimIdx],
          lowPoint[otherDimIdx]
        ),
        style: style
      },
      {
        type: 'line',
        transition: ['shape'],
        shape: makeShape(
          baseDimIdx,
          lowPoint[baseDimIdx] - halfWidth,
          lowPoint[otherDimIdx],
          lowPoint[baseDimIdx] + halfWidth,
          lowPoint[otherDimIdx]
        ),
        style: style
      }
    );
  }

  function makeShape(baseDimIdx, base1, value1, base2, value2) {
    var shape = {};
    shape[coordDims[baseDimIdx] + '1'] = base1;
    shape[coordDims[1 - baseDimIdx] + '1'] = value1;
    shape[coordDims[baseDimIdx] + '2'] = base2;
    shape[coordDims[1 - baseDimIdx] + '2'] = value2;
    return shape;
  }

  return group;
}

option = {
  tooltip: {},
  legend: {
    data: ['bar', 'error'],
    top: 15
  },
  dataZoom: [
    {
      type: 'slider'
    },
    {
      type: 'inside'
    }
  ],
  grid: {
    top: 60
  },
  xAxis: {},
  yAxis: {},
  series: [
    {
      type: 'scatter',
      name: 'error',
      data: data,
      dimensions: dimensions,
      encode: {
        x: 2,
        y: 1,
        tooltip: [2, 1, 3, 4, 5, 6],
        itemName: 0
      },
      itemStyle: {
        color: '#77bef7'
      }
    },
    {
      type: 'custom',
      name: 'error',
      renderItem: renderItem,
      dimensions: dimensions,
      encode: {
        x: [2, 3, 4],
        y: [1, 5, 6],
        tooltip: [2, 1, 3, 4, 5, 6],
        itemName: 0
      },
      data: data,
      z: 100
    }
  ]
};
"""#,
        option: [
            "tooltip": [:] as [String: Any],
            "legend": [
                // `bar` is vestigial upstream — no series carries that name. Kept verbatim.
                "data": ["bar", "error"],
                "top": 15.0
            ] as [String: Any],
            "dataZoom": [
                ["type": "slider"] as [String: Any],
                ["type": "inside"] as [String: Any]
            ],
            "grid": [
                "top": 60.0
            ] as [String: Any],
            "xAxis": [:] as [String: Any],
            "yAxis": [:] as [String: Any],
            "series": [
                [
                    "type": "scatter",
                    "name": "error",
                    "data": errorScatterData,
                    "dimensions": errorScatterDimensions,
                    "encode": [
                        "x": 2.0,
                        "y": 1.0,
                        "tooltip": [2.0, 1.0, 3.0, 4.0, 5.0, 6.0],
                        "itemName": 0.0
                    ] as [String: Any],
                    "itemStyle": [
                        "color": "#77bef7"
                    ] as [String: Any]
                ] as [String: Any],
                [
                    "type": "custom",
                    "name": "error",
                    // The per-series closure (see header: this key is what keeps the global custom-series
                    // registry's `getCustomSeries("custom")` fallback from hijacking this chart).
                    "renderItem": errorScatterRenderItem,
                    "dimensions": errorScatterDimensions,
                    "encode": [
                        "x": [2.0, 3.0, 4.0],
                        "y": [1.0, 5.0, 6.0],
                        "tooltip": [2.0, 1.0, 3.0, 4.0, 5.0, 6.0],
                        "itemName": 0.0
                    ] as [String: Any],
                    "data": errorScatterData,
                    "z": 100.0
                ] as [String: Any]
            ]
        ])
}

private let errorScatterDimensions: [String] = [
    "name", "Price", "Prime cost", "Prime cost min", "Prime cost max", "Price min", "Price max"
]

// One garment per row, matching `errorScatterDimensions`:
// [name, price, prime cost, prime cost min, prime cost max, price min, price max].
private let errorScatterData: [[Any]] = [
    ["Blouse \"Blue Viola\"", 101.88, 99.75, 76.75, 116.75, 69.88, 119.88],
    ["Dress \"Daisy\"", 155.8, 144.03, 126.03, 156.03, 129.8, 188.8],
    ["Trousers \"Cutesy Classic\"", 203.25, 173.56, 151.56, 187.56, 183.25, 249.25],
    ["Dress \"Morning Dew\"", 256.0, 120.5, 98.5, 136.5, 236.0, 279.0],
    ["Turtleneck \"Dark Chocolate\"", 408.89, 294.75, 276.75, 316.75, 385.89, 427.89],
    ["Jumper \"Early Spring\"", 427.36, 430.24, 407.24, 452.24, 399.36, 461.36],
    ["Breeches \"Summer Mood\"", 356.0, 135.5, 123.5, 151.5, 333.0, 387.0],
    ["Dress \"Mauve Chamomile\"", 406.0, 95.5, 73.5, 111.5, 366.0, 429.0],
    ["Dress \"Flying Tits\"", 527.36, 503.24, 488.24, 525.24, 485.36, 551.36],
    ["Dress \"Singing Nightingales\"", 587.36, 543.24, 518.24, 555.24, 559.36, 624.36],
    ["Sundress \"Cloudy weather\"", 603.36, 407.24, 392.24, 419.24, 581.36, 627.36],
    ["Sundress \"East motives\"", 633.36, 477.24, 445.24, 487.24, 594.36, 652.36],
    ["Sweater \"Cold morning\"", 517.36, 437.24, 416.24, 454.24, 488.36, 565.36],
    ["Trousers \"Lavender Fields\"", 443.36, 387.24, 370.24, 413.24, 412.36, 484.36],
    ["Jumper \"Coffee with Milk\"", 543.36, 307.24, 288.24, 317.24, 509.36, 574.36],
    ["Blouse \"Blooming Cactus\"", 790.36, 277.24, 254.24, 295.24, 764.36, 818.36],
    ["Sweater \"Fluffy Comfort\"", 790.34, 678.34, 660.34, 690.34, 762.34, 824.34]
]

// Coerce a ParsedValue (Any: Double | Int | NSNumber) to Double — the recurring Int-vs-Double read trap.
private func errorScatterNum(_ v: Any?) -> Double {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let n = v as? NSNumber { return n.doubleValue }
    return 0
}

// The official `renderItem`, statement for statement. Typed EXACTLY `CustomSeriesRenderItem` so
// CustomView's `get("renderItem") as? CustomSeriesRenderItem` cast holds (see header).
//
// One datum → one error CROSS, as a `group` of six `line`s. The loop runs baseDimIdx over BOTH coord
// dims, so the same code emits the vertical whisker (baseDimIdx 0: x = prime cost, y spans price
// min→max) and the horizontal one (baseDimIdx 1: y = price, x spans prime cost min→max). Per axis it
// reads the encoded min/max — encode.x = [2,3,4] (prime cost / min / max), encode.y = [1,5,6] (price /
// min / max) — projects them through api.coord to a highPoint and a lowPoint, and strokes three lines:
// the min→max spine plus a 5px-half-width serif cap at each end. `makeShape` names each line's
// {x1,y1,x2,y2} by swapping base/other dim per iteration.
private let errorScatterRenderItem: CustomSeriesRenderItem = { params, api in
    let coordDims = ["x", "y"]

    // JS: shape[coordDims[baseDimIdx] + '1'] = base1, etc. — the dimension-swapping trick, verbatim.
    func makeShape(
        _ baseDimIdx: Int, _ base1: Double, _ value1: Double, _ base2: Double, _ value2: Double
    ) -> [String: Any] {
        var shape: [String: Any] = [:]
        shape[coordDims[baseDimIdx] + "1"] = base1
        shape[coordDims[1 - baseDimIdx] + "1"] = value1
        shape[coordDims[baseDimIdx] + "2"] = base2
        shape[coordDims[1 - baseDimIdx] + "2"] = value2
        return shape
    }

    var children: [[String: Any]] = []

    for baseDimIdx in 0..<2 {
        let otherDimIdx = 1 - baseDimIdx
        let encode = params.encode   // WrapEncodeDefRet == [String: [Double]]
        // `api.value` takes a DimensionLoose (Any); a NUMERIC dim must be a Double — SeriesData
        //   .getDimensionIndex force-casts it `as! Double`, so an Int would crash. `encode` already
        //   holds Doubles. Guard the arity the official code assumes (base[0], other[1], other[2]).
        guard let baseEnc = encode[coordDims[baseDimIdx]], baseEnc.count >= 1,
              let otherEnc = encode[coordDims[otherDimIdx]], otherEnc.count >= 3 else { continue }

        let baseValue = errorScatterNum(api.value(baseEnc[0], nil))
        // JS builds a sparse `param = []` and fills both slots; both indices are always written.
        var param = [0.0, 0.0]
        param[baseDimIdx] = baseValue
        param[otherDimIdx] = errorScatterNum(api.value(otherEnc[1], nil))
        let highPoint = api.coord(param, nil)
        param[otherDimIdx] = errorScatterNum(api.value(otherEnc[2], nil))
        let lowPoint = api.coord(param, nil)
        guard highPoint.count >= 2, lowPoint.count >= 2 else { continue }
        let halfWidth = 5.0

        // JS: api.style({ stroke: api.visual('color'), fill: undefined }).
        //   `fill: undefined` → the key is ABSENT (a `line` never fills anyway); Swift cannot store an
        //   `undefined`, so drop the key from the merged bag rather than writing NSNull.
        var userProps: [String: Any] = [:]
        if let color = api.visual("color", nil) { userProps["stroke"] = color }
        var style = api.style(userProps, nil)
        style.removeValue(forKey: "fill")

        children.append(contentsOf: [
            [
                "type": "line",
                "transition": ["shape"],
                "shape": makeShape(
                    baseDimIdx,
                    highPoint[baseDimIdx] - halfWidth,
                    highPoint[otherDimIdx],
                    highPoint[baseDimIdx] + halfWidth,
                    highPoint[otherDimIdx]
                ),
                "style": style
            ] as [String: Any],
            [
                "type": "line",
                "transition": ["shape"],
                "shape": makeShape(
                    baseDimIdx,
                    highPoint[baseDimIdx],
                    highPoint[otherDimIdx],
                    lowPoint[baseDimIdx],
                    lowPoint[otherDimIdx]
                ),
                "style": style
            ] as [String: Any],
            [
                "type": "line",
                "transition": ["shape"],
                "shape": makeShape(
                    baseDimIdx,
                    lowPoint[baseDimIdx] - halfWidth,
                    lowPoint[otherDimIdx],
                    lowPoint[baseDimIdx] + halfWidth,
                    lowPoint[otherDimIdx]
                ),
                "style": style
            ] as [String: Any]
        ])
    }

    return [
        "type": "group",
        "children": children
    ] as [String: Any]
}
