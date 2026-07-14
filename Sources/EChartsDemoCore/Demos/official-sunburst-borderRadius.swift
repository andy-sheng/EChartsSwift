// official-sunburst-borderRadius — replica of https://echarts.apache.org/examples/zh/editor.html?c=sunburst-borderRadius
// title: Sunburst with Rounded Corner / titleCN: 圆角旭日图
//
// One sunburst series over the same 3-level family tree as sunburst-simple, but with a donut hole
// (radius [60, '90%']) and rounded, 2px-bordered sectors (itemStyle.borderRadius: 7); labels off.
//
// DEVIATIONS from the official source:
//   - The official option assigns `series` as a SINGLE OBJECT (`series: { type: 'sunburst', ... }`).
//     webOptionJS keeps that verbatim; the Swift `option` wraps it in the one-element array echarts
//     normalizes it to anyway (`normalizeToArray`) — same chart, no semantic difference.
//   - The trailing `export {};` is dropped from webOptionJS (a bare export is a SyntaxError in the
//     page's classic script and would kill the whole pane).
//   - Nothing else: the example's `data` is a literal in its own source (no $.get, no asset), so the
//     tree below is that literal transcribed 1:1. No closures, no timers — hence no `drive`.

private let sunburstBorderRadiusData: [[String: Any]] = [
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
    static let official_sunburst_borderradius = EChartsDemo(
        name: "official-sunburst-borderRadius", category: "sunburst",
        summary: "圆角旭日图 — Sunburst with Rounded Corner",
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
    data: data,
    radius: [60, '90%'],
    itemStyle: {
      borderRadius: 7,
      borderWidth: 2
    },
    label: {
      show: false
    }
  }
};
"""#,
        option: [
            "series": [
                [
                    "type": "sunburst",
                    "data": sunburstBorderRadiusData,
                    "radius": [60.0, "90%"] as [Any],
                    "itemStyle": [
                        "borderRadius": 7.0,
                        "borderWidth": 2.0
                    ] as [String: Any],
                    "label": [
                        "show": false
                    ] as [String: Any]
                ] as [String: Any]
            ]
        ])
}
