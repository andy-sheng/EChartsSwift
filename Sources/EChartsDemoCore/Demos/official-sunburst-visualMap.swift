// official-sunburst-visualMap — replica of https://echarts.apache.org/examples/zh/editor.html?c=sunburst-visualMap
// title: Sunburst VisualMap / titleCN: 旭日图使用视觉编码
//
// A family tree (20 nodes, 4 levels) coloured by a continuous `visualMap` (0…10) over a 4-stop ramp,
// so every sector's fill encodes its own value. NOT the same tree as sunburst-simple: this one adds an
// `Aunt Jane → Cousin Kate` branch and an entire `Mike → Uncle Dan` root. One node ('Me') pins
// `itemStyle: { color: 'red' }`, which WINS over the visualMap's mapped colour — a per-datum itemStyle
// beating the visual encoding is the point of the example, so that node must stay red.
//
// DEVIATIONS from the official source:
//   - The official option assigns `series` as a SINGLE OBJECT (`series: { type: 'sunburst', ... }`).
//     webOptionJS keeps that verbatim; the Swift `option` wraps it in the one-element array echarts
//     normalizes it to anyway (`normalizeToArray`) — same chart, no semantic difference.
//   - The trailing `export {};` is dropped from webOptionJS (a bare `export` is a SyntaxError in the
//     page's classic script and would kill the whole pane).
//   - Nothing else: the example's `data` is a literal in its own source (no $.get, no asset), no
//     closures, no timers — the tree below is that literal transcribed 1:1, `itemStyle` included.

private let sunburstVisualMapData: [[String: Any]] = [
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
                "name": "Aunt Jane",
                "children": [
                    ["name": "Cousin Kate", "value": 4.0] as [String: Any]
                ]
            ] as [String: Any],
            [
                "name": "Father",
                "value": 10.0,
                "children": [
                    [
                        "name": "Me",
                        "value": 5.0,
                        "itemStyle": ["color": "red"] as [String: Any]
                    ] as [String: Any],
                    ["name": "Brother Peter", "value": 1.0] as [String: Any]
                ]
            ] as [String: Any]
        ]
    ] as [String: Any],
    [
        "name": "Mike",
        "children": [
            [
                "name": "Uncle Dan",
                "children": [
                    ["name": "Cousin Lucy", "value": 3.0] as [String: Any],
                    [
                        "name": "Cousin Luck",
                        "value": 4.0,
                        "children": [
                            ["name": "Nephew", "value": 2.0] as [String: Any]
                        ]
                    ] as [String: Any]
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
    static let official_sunburst_visualmap = EChartsDemo(
        name: "official-sunburst-visualMap", category: "sunburst",
        summary: "旭日图使用视觉编码 — Sunburst VisualMap",
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
        name: 'Aunt Jane',
        children: [
          {
            name: 'Cousin Kate',
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
            value: 5,
            itemStyle: {
              color: 'red'
            }
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
    name: 'Mike',
    children: [
      {
        name: 'Uncle Dan',
        children: [
          {
            name: 'Cousin Lucy',
            value: 3
          },
          {
            name: 'Cousin Luck',
            value: 4,
            children: [
              {
                name: 'Nephew',
                value: 2
              }
            ]
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
  visualMap: {
    type: 'continuous',
    min: 0,
    max: 10,
    inRange: {
      color: ['#2F93C8', '#AEC48F', '#FFDB5C', '#F98862']
    }
  },
  series: {
    type: 'sunburst',
    data: data,
    radius: [0, '90%'],
    label: {
      rotate: 'radial'
    }
  }
};
"""#,
        option: [
            "visualMap": [
                "type": "continuous",
                "min": 0.0,
                "max": 10.0,
                "inRange": [
                    "color": ["#2F93C8", "#AEC48F", "#FFDB5C", "#F98862"]
                ] as [String: Any]
            ] as [String: Any],
            "series": [
                [
                    "type": "sunburst",
                    "data": sunburstVisualMapData,
                    "radius": [0.0, "90%"] as [Any],
                    "label": [
                        "rotate": "radial"
                    ] as [String: Any]
                ] as [String: Any]
            ]
        ])
}
