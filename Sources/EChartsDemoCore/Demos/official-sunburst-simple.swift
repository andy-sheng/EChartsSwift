// official-sunburst-simple — replica of https://echarts.apache.org/examples/zh/editor.html?c=sunburst-simple
// title: Basic Sunburst / titleCN: 基础旭日图
//
// One sunburst series over a 3-level family tree; radius [0, '90%'] and radially-rotated labels.
//
// DEVIATIONS from the official source:
//   - The official option assigns `series` as a SINGLE OBJECT (`series: { type: 'sunburst', ... }`).
//     webOptionJS keeps that verbatim; the Swift `option` wraps it in the one-element array echarts
//     normalizes it to anyway (`normalizeToArray`) — same chart, no semantic difference.
//   - The `emphasis: { focus: 'ancestor' }` block is COMMENTED OUT in the official source; it is kept
//     commented in webOptionJS and simply absent from the Swift option.
//   - Nothing else: the example's `data` is a literal in its own source (no $.get, no asset), so the
//     tree below is that literal transcribed 1:1.

private let sunburstSimpleData: [[String: Any]] = [
    [
        "name": "Grandpa",
        "children": [
            [
                "name": "Uncle Leo",
                "value": 15.0,
                "children": [
                    ["name": "Cousin Jack", "value": 2.0] as [String: Any],
                    [
                        "name": "Cousin Mary",
                        "value": 5.0,
                        "children": [
                            ["name": "Jackson", "value": 2.0] as [String: Any]
                        ]
                    ] as [String: Any],
                    ["name": "Cousin Ben", "value": 4.0] as [String: Any]
                ]
            ] as [String: Any],
            [
                "name": "Father",
                "value": 10.0,
                "children": [
                    ["name": "Me", "value": 5.0] as [String: Any],
                    ["name": "Brother Peter", "value": 1.0] as [String: Any]
                ]
            ] as [String: Any]
        ]
    ] as [String: Any],
    [
        "name": "Nancy",
        "children": [
            [
                "name": "Uncle Nike",
                "children": [
                    ["name": "Cousin Betty", "value": 1.0] as [String: Any],
                    ["name": "Cousin Jenny", "value": 2.0] as [String: Any]
                ]
            ] as [String: Any]
        ]
    ] as [String: Any]
]

extension EChartsDemoRegistry {
    static let official_sunburst_simple = EChartsDemo(
        name: "official-sunburst-simple", category: "sunburst",
        summary: "基础旭日图 — Basic Sunburst",
        width: 640, height: 420,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
var data = [
  {
    name: 'Grandpa',
    children: [
      {
        name: 'Uncle Leo',
        value: 15,
        children: [
          {
            name: 'Cousin Jack',
            value: 2
          },
          {
            name: 'Cousin Mary',
            value: 5,
            children: [
              {
                name: 'Jackson',
                value: 2
              }
            ]
          },
          {
            name: 'Cousin Ben',
            value: 4
          }
        ]
      },
      {
        name: 'Father',
        value: 10,
        children: [
          {
            name: 'Me',
            value: 5
          },
          {
            name: 'Brother Peter',
            value: 1
          }
        ]
      }
    ]
  },
  {
    name: 'Nancy',
    children: [
      {
        name: 'Uncle Nike',
        children: [
          {
            name: 'Cousin Betty',
            value: 1
          },
          {
            name: 'Cousin Jenny',
            value: 2
          }
        ]
      }
    ]
  }
];

option = {
  series: {
    type: 'sunburst',
    // emphasis: {
    //     focus: 'ancestor'
    // },
    data: data,
    radius: [0, '90%'],
    label: {
      rotate: 'radial'
    }
  }
};
"""#,
        option: [
            "series": [
                [
                    "type": "sunburst",
                    // emphasis.focus: 'ancestor' is commented out in the official source — omitted here too.
                    "data": sunburstSimpleData,
                    "radius": [0.0, "90%"] as [Any],
                    "label": [
                        "rotate": "radial"
                    ] as [String: Any]
                ] as [String: Any]
            ]
        ])
}
