// official-custom-profit — replica of https://echarts.apache.org/examples/zh/editor.html?c=custom-profit
// title: Profit / titleCN: 利润分布直方图
// A `custom` series histogram: each datum is [from, to, profit, name] and renderItem draws one rect
// spanning [from, to] on the x-axis with height `profit`, filled from a 6-colour palette (per-datum
// itemStyle). `dimensions` + `encode` (x: [0,1], y: 2, tooltip: [0,1,2], itemName: 3) give the axes,
// tooltip and labels their names; the top label shows the profit.
//
// DEVIATIONS:
//   - nativeSupported: FALSE. The chart IS the renderItem closure — without it a `custom` series draws
//     nothing at all, and the Swift [String: Any] option here carries no closure. Two corrections to the
//     obvious guesses about why, both verified in the framework:
//       * It is NOT that EChartsKit cannot carry a Swift renderItem. CustomView resolves
//         `customSeries.getRenderItem() ?? getCustomSeries(subType)` (CustomView.swift:739), so a closure
//         may ride PER-SERIES on the option bag under the "renderItem" key — that door does not touch the
//         global registry and would not clobber anything. (Safe for this demo specifically: WebPage.swift
//         only JSON-serializes `option` when `webOptionJS` is nil, and we set it.)
//       * But the GLOBAL door is a live hazard, so it is deliberately not used: Demos/custom-basic.swift
//         does `registerCustomSeries("custom", ...)`, and that registry is keyed by series subType. Were
//         this demo flipped on without its own per-series closure, the `?? getCustomSeries("custom")`
//         fallback would silently resolve to custom-basic's renderItem and draw the WRONG chart.
//     The flag is false because the one thing this chart needs most is unproven and could not be run (this
//     port was audited under a no-build constraint): the bars take their entire 6-colour palette from
//     `api.style()`, which is an explicitly DEFERRED best-effort stub in CustomView (style() at
//     CustomView.swift:917 returns just the raw item-visual bag — no itemStyle/label/ec4 compat), so the
//     per-datum colours are exactly what would not be trustworthy. Lighting the native pane up is a real,
//     tracked follow-up — not an impossibility. Until it is actually run, the flag stays honest.
//   - webOptionJS: the official source is TypeScript; the TS-only syntax (`api.size!(...)`, `as number`,
//     `as number[]`, trailing `export {};`) is stripped so the reference pane runs it as classic JS.
//     Everything else — colours, data, the .map() that attaches itemStyle, renderItem — is verbatim.
extension EChartsDemoRegistry {
    static let official_custom_profit = EChartsDemo(
        name: "official-custom-profit", category: "custom",
        summary: "利润分布直方图 — Profit",
        width: 720, height: 460,
        nativeSupported: false,
        collection: .official,
        webOptionJS: #"""
const colorList = [
  '#4f81bd',
  '#c0504d',
  '#9bbb59',
  '#604a7b',
  '#948a54',
  '#e46c0b'
];

const data = [
  [10, 16, 3, 'A'],
  [16, 18, 15, 'B'],
  [18, 26, 12, 'C'],
  [26, 32, 22, 'D'],
  [32, 56, 7, 'E'],
  [56, 62, 17, 'F']
].map(function (item, index) {
  return {
    value: item,
    itemStyle: {
      color: colorList[index]
    }
  };
});

option = {
  title: {
    text: 'Profit',
    left: 'center'
  },
  tooltip: {},
  xAxis: {
    scale: true
  },
  yAxis: {},
  series: [
    {
      type: 'custom',
      renderItem: function (params, api) {
        var yValue = api.value(2);
        var start = api.coord([api.value(0), yValue]);
        var size = api.size([api.value(1) - api.value(0), yValue]);
        var style = api.style();

        return {
          type: 'rect',
          shape: {
            x: start[0],
            y: start[1],
            width: size[0],
            height: size[1]
          },
          style: style
        };
      },
      label: {
        show: true,
        position: 'top'
      },
      dimensions: ['from', 'to', 'profit'],
      encode: {
        x: [0, 1],
        y: 2,
        tooltip: [0, 1, 2],
        itemName: 3
      },
      data: data
    }
  ]
};
"""#,
        option: [
            "title": [
                "text": "Profit",
                "left": "center"
            ] as [String: Any],
            "tooltip": [:] as [String: Any],
            "xAxis": [
                "scale": true
            ] as [String: Any],
            "yAxis": [:] as [String: Any],
            "series": [
                [
                    "type": "custom",
                    // PORT-NOTE: renderItem omitted — the JS closure read api.value(2) (profit), projected
                    // api.coord([api.value(0), profit]) to the bar's top-left pixel and api.size([to - from,
                    // profit]) to its pixel width/height, then returned a `rect` element with that shape and
                    // api.style() (the per-datum itemStyle colour). It IS the chart; see nativeSupported: false.
                    "label": [
                        "show": true,
                        "position": "top"
                    ] as [String: Any],
                    "dimensions": ["from", "to", "profit"],
                    "encode": [
                        "x": [0.0, 1.0],
                        "y": 2.0,
                        "tooltip": [0.0, 1.0, 2.0],
                        "itemName": 3.0
                    ] as [String: Any],
                    "data": customProfitData
                ] as [String: Any]
            ]
        ])
}

// The official palette, one colour per bin.
private let customProfitColorList: [String] = [
    "#4f81bd",
    "#c0504d",
    "#9bbb59",
    "#604a7b",
    "#948a54",
    "#e46c0b"
]

// [from, to, profit, name] per bin.
private let customProfitBins: [[Any]] = [
    [10.0, 16.0, 3.0, "A"],
    [16.0, 18.0, 15.0, "B"],
    [18.0, 26.0, 12.0, "C"],
    [26.0, 32.0, 22.0, "D"],
    [32.0, 56.0, 7.0, "E"],
    [56.0, 62.0, 17.0, "F"]
]

// The official `.map()`: each bin becomes { value: bin, itemStyle: { color: palette[i] } }.
private let customProfitData: [[String: Any]] = customProfitBins.enumerated().map { index, bin in
    [
        "value": bin,
        "itemStyle": ["color": customProfitColorList[index]] as [String: Any]
    ] as [String: Any]
}
