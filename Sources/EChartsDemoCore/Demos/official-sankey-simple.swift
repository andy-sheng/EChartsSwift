// official-sankey-simple — replica of https://echarts.apache.org/examples/zh/editor.html?c=sankey-simple
// title: Basic Sankey / titleCN: 基础桑基图
//
// A single sankey (flow) series: 6 nodes (a, b, a1, a2, b1, c) laid out left→right by depth, 6
// weighted links carrying the flow. `emphasis.focus: 'adjacency'` dims everything but the hovered
// node and its neighbours — a hover-only behaviour, so it does not show in the gallery's static frame.
//
// DEVIATIONS from the official source: none. `webOptionJS` is the example verbatim (only its
// title-comment block and the trailing `export {}` are dropped — neither is part of the option). No
// closures in the option, so the Swift port omits nothing. The example fetches no data and has no
// setInterval/re-setOption, so the single static frame IS the whole example.
//
// `series` is a bare object here (not an array), exactly as upstream writes it — the single-component
// form is honest, not a shortcut. Real echarts normalizes it in `GlobalModel.visitComponent` via
// `modelUtil.normalizeToArray`; the port's equivalent is `normalizeToComponentOptionList`
// (model/Global.swift), whose non-array branch wraps the lone bag as `[one]` and keeps the whole
// option in `.rawOption` — i.e. the same bag the array form would have produced per element.
extension EChartsDemoRegistry {
    static let official_sankey_simple = EChartsDemo(
        name: "official-sankey-simple", category: "sankey",
        summary: "基础桑基图 — Basic Sankey",
        width: 640, height: 420,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
option = {
  series: {
    type: 'sankey',
    layout: 'none',
    emphasis: {
      focus: 'adjacency'
    },
    data: [
      {
        name: 'a'
      },
      {
        name: 'b'
      },
      {
        name: 'a1'
      },
      {
        name: 'a2'
      },
      {
        name: 'b1'
      },
      {
        name: 'c'
      }
    ],
    links: [
      {
        source: 'a',
        target: 'a1',
        value: 5
      },
      {
        source: 'a',
        target: 'a2',
        value: 3
      },
      {
        source: 'b',
        target: 'b1',
        value: 8
      },
      {
        source: 'a',
        target: 'b1',
        value: 3
      },
      {
        source: 'b1',
        target: 'a1',
        value: 1
      },
      {
        source: 'b1',
        target: 'c',
        value: 2
      }
    ]
  }
};
"""#,
        option: [
            "series": [
                "type": "sankey",
                "layout": "none",
                "emphasis": [
                    "focus": "adjacency"
                ] as [String: Any],
                "data": officialSankeySimpleData,
                "links": officialSankeySimpleLinks
            ] as [String: Any]
        ])
}

// Hoisted out of the option literal with explicit types: Swift's type-checker chokes on large
// untyped heterogeneous nested literals.
private let officialSankeySimpleData: [[String: Any]] = [
    ["name": "a"],
    ["name": "b"],
    ["name": "a1"],
    ["name": "a2"],
    ["name": "b1"],
    ["name": "c"]
]

private let officialSankeySimpleLinks: [[String: Any]] = [
    ["source": "a", "target": "a1", "value": 5.0],
    ["source": "a", "target": "a2", "value": 3.0],
    ["source": "b", "target": "b1", "value": 8.0],
    ["source": "a", "target": "b1", "value": 3.0],
    ["source": "b1", "target": "a1", "value": 1.0],
    ["source": "b1", "target": "c", "value": 2.0]
]
