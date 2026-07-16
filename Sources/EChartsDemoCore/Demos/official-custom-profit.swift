// official-custom-profit — replica of https://echarts.apache.org/examples/zh/editor.html?c=custom-profit
// title: Profit / titleCN: 利润分布直方图
// A `custom` series histogram: each datum is [from, to, profit, name] and renderItem draws one rect
// spanning [from, to] on the x-axis with height `profit`, filled from a 6-colour palette (per-datum
// itemStyle). `dimensions` + `encode` (x: [0,1], y: 2, tooltip: [0,1,2], itemName: 3) give the axes,
// tooltip and labels their names; the top label shows the profit.
//
// DEVIATIONS:
//   - nativeSupported: TRUE. `renderItem` is ported statement-for-statement as customProfitRenderItem
//     (below) and set PER-SERIES on the option bag under the "renderItem" key. CustomView resolves
//     `customSeries.getRenderItem() ?? getCustomSeries(subType)` (CustomView.swift:739), so this rides the
//     per-series door — it does not touch the global registry (Demos/custom-basic.swift registers a
//     DIFFERENT bar renderItem under the "custom" subType there; the per-series closure here takes
//     precedence over that fallback, so the two demos can't cross-contaminate). Safe for this demo
//     specifically: WebPage.swift only JSON-serializes `option` when `webOptionJS` is nil, and we set it.
//   - webOptionJS: the official source is TypeScript; the TS-only syntax (`api.size!(...)`, `as number`,
//     `as number[]`, trailing `export {};`) is stripped so the reference pane runs it as classic JS.
//     Everything else — colours, data, the .map() that attaches itemStyle, renderItem — is verbatim.
import Foundation
import EChartsKit

// Coerce a ParsedValue (Any: Double | Int | NSNumber) to Double — the recurring Int-vs-Double read trap.
private func customProfitNum(_ v: Any?) -> Double {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let n = v as? NSNumber { return n.doubleValue }
    return 0
}

// The official `renderItem`, statement for statement.
//   var yValue = api.value(2);
//   var start = api.coord([api.value(0), yValue]);
//   var size = api.size([api.value(1) - api.value(0), yValue]);
//   var style = api.style();
//   return { type: 'rect', shape: { x: start[0], y: start[1], width: size[0], height: size[1] }, style };
private let customProfitRenderItem: CustomSeriesRenderItem = { params, api in
    let yValue = customProfitNum(api.value(2.0, nil))
    let start = api.coord([customProfitNum(api.value(0.0, nil)), yValue], nil)
    let size = api.size(
        [customProfitNum(api.value(1.0, nil)) - customProfitNum(api.value(0.0, nil)), yValue],
        nil
    ) as? [Double] ?? []
    let style = api.style(nil, nil)

    guard start.count >= 2, size.count >= 2 else { return nil }

    return [
        "type": "rect",
        "shape": [
            "x": start[0],
            "y": start[1],
            "width": size[0],
            "height": size[1]
        ] as [String: Any],
        "style": style
    ] as [String: Any]
}

extension EChartsDemoRegistry {
    static let official_custom_profit = EChartsDemo(
        name: "official-custom-profit", category: "custom",
        summary: "利润分布直方图 — Profit",
        width: 720, height: 460,
        nativeSupported: true,
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
                    "renderItem": customProfitRenderItem,
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
