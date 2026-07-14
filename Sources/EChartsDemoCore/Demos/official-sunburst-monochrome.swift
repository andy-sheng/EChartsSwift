// official-sunburst-monochrome — replica of https://echarts.apache.org/examples/zh/editor.html?c=sunburst-monochrome
// title: Monochrome Sunburst / titleCN: 单色旭日图
//
// A 4-level, name-less sunburst: every node carries only a `value` (or none — those are summed from
// their children) and, on some nodes, one of three shared `itemStyle` objects from a single warm
// ramp (#F54F4A / #FF8C75 / #FFB499). Nodes without an itemStyle fall back to the series-level
// `itemStyle.color: '#ddd'`, so the chart reads as one monochrome family. `sort: undefined` keeps the
// rings in data order, and `label.rotate: 'radial'` aligns the (blank) labels along the radius.
//
// DEVIATIONS from the official source:
//   - The official option assigns `series` as a SINGLE OBJECT (`series: { type: 'sunburst', ... }`).
//     webOptionJS keeps that verbatim; the Swift `option` wraps it in the one-element array echarts
//     normalizes it to anyway (`normalizeToArray`) — same chart, no semantic difference.
//   - `sort: undefined` has no Swift spelling; the option below passes `NSNull()`, which upstream's
//     `sort != null` guard (sunburstLayout) treats identically — no sorting — while still shadowing
//     the `sort: 'desc'` default during defaults-merge (a key that is PRESENT is never filled in by
//     `merge(target, defaults, false)`).
//   - The trailing `export {};` is dropped from webOptionJS (a bare export is a SyntaxError in the
//     page's classic script and would kill the whole pane).
//   - Nothing else: the example's `data` is a literal in its own source (no $.get, no asset), it has
//     no closures and no timers — hence no `drive`. The tree below is that literal transcribed 1:1,
//     including the three shared itemStyle objects.

import Foundation   // NSNull (the `sort: undefined` spelling, below)

// const item1 / item2 / item3 — the example's three shared itemStyle objects (JS shares one object
// reference across many nodes; Swift dicts are values, so each node gets a copy — identical option).
private let sunburstMonochromeItem1: [String: Any] = ["color": "#F54F4A"]
private let sunburstMonochromeItem2: [String: Any] = ["color": "#FF8C75"]
private let sunburstMonochromeItem3: [String: Any] = ["color": "#FFB499"]

private let sunburstMonochromeData: [[String: Any]] = [
    [
        "children": [
            [
                "value": 5.0,
                "children": [
                    ["value": 1.0, "itemStyle": sunburstMonochromeItem1] as [String: Any],
                    [
                        "value": 2.0,
                        "children": [
                            ["value": 1.0, "itemStyle": sunburstMonochromeItem2] as [String: Any]
                        ]
                    ] as [String: Any],
                    [
                        "children": [
                            ["value": 1.0] as [String: Any]
                        ]
                    ] as [String: Any]
                ],
                "itemStyle": sunburstMonochromeItem1
            ] as [String: Any],
            [
                "value": 10.0,
                "children": [
                    [
                        "value": 6.0,
                        "children": [
                            ["value": 1.0, "itemStyle": sunburstMonochromeItem1] as [String: Any],
                            ["value": 1.0] as [String: Any],
                            ["value": 1.0, "itemStyle": sunburstMonochromeItem2] as [String: Any],
                            ["value": 1.0] as [String: Any]
                        ],
                        "itemStyle": sunburstMonochromeItem3
                    ] as [String: Any],
                    [
                        "value": 2.0,
                        "children": [
                            ["value": 1.0] as [String: Any]
                        ],
                        "itemStyle": sunburstMonochromeItem3
                    ] as [String: Any],
                    [
                        "children": [
                            ["value": 1.0, "itemStyle": sunburstMonochromeItem2] as [String: Any]
                        ]
                    ] as [String: Any]
                ],
                "itemStyle": sunburstMonochromeItem1
            ] as [String: Any]
        ],
        "itemStyle": sunburstMonochromeItem1
    ] as [String: Any],
    [
        "value": 9.0,
        "children": [
            [
                "value": 4.0,
                "children": [
                    ["value": 2.0, "itemStyle": sunburstMonochromeItem2] as [String: Any],
                    [
                        "children": [
                            ["value": 1.0, "itemStyle": sunburstMonochromeItem1] as [String: Any]
                        ]
                    ] as [String: Any]
                ],
                "itemStyle": sunburstMonochromeItem1
            ] as [String: Any],
            [
                "children": [
                    [
                        "value": 3.0,
                        "children": [
                            ["value": 1.0] as [String: Any],
                            ["value": 1.0, "itemStyle": sunburstMonochromeItem2] as [String: Any]
                        ]
                    ] as [String: Any]
                ],
                "itemStyle": sunburstMonochromeItem3
            ] as [String: Any]
        ],
        "itemStyle": sunburstMonochromeItem2
    ] as [String: Any],
    [
        "value": 7.0,
        "children": [
            [
                "children": [
                    ["value": 1.0, "itemStyle": sunburstMonochromeItem3] as [String: Any],
                    [
                        "value": 3.0,
                        "children": [
                            ["value": 1.0, "itemStyle": sunburstMonochromeItem2] as [String: Any],
                            ["value": 1.0] as [String: Any]
                        ],
                        "itemStyle": sunburstMonochromeItem2
                    ] as [String: Any],
                    [
                        "value": 2.0,
                        "children": [
                            ["value": 1.0] as [String: Any],
                            ["value": 1.0, "itemStyle": sunburstMonochromeItem1] as [String: Any]
                        ],
                        "itemStyle": sunburstMonochromeItem1
                    ] as [String: Any]
                ],
                "itemStyle": sunburstMonochromeItem3
            ] as [String: Any]
        ],
        "itemStyle": sunburstMonochromeItem1
    ] as [String: Any],
    [
        "children": [
            [
                "value": 6.0,
                "children": [
                    ["value": 1.0, "itemStyle": sunburstMonochromeItem2] as [String: Any],
                    [
                        "value": 2.0,
                        "children": [
                            ["value": 2.0, "itemStyle": sunburstMonochromeItem2] as [String: Any]
                        ],
                        "itemStyle": sunburstMonochromeItem1
                    ] as [String: Any],
                    ["value": 1.0, "itemStyle": sunburstMonochromeItem3] as [String: Any]
                ],
                "itemStyle": sunburstMonochromeItem3
            ] as [String: Any],
            [
                "value": 3.0,
                "children": [
                    ["value": 1.0] as [String: Any],
                    [
                        "children": [
                            ["value": 1.0, "itemStyle": sunburstMonochromeItem2] as [String: Any]
                        ]
                    ] as [String: Any],
                    ["value": 1.0] as [String: Any]
                ],
                "itemStyle": sunburstMonochromeItem3
            ] as [String: Any]
        ],
        "itemStyle": sunburstMonochromeItem1
    ] as [String: Any]
]

extension EChartsDemoRegistry {
    static let official_sunburst_monochrome = EChartsDemo(
        name: "official-sunburst-monochrome", category: "sunburst",
        summary: "单色旭日图 — Monochrome Sunburst",
        width: 640, height: 420,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
const item1 = {
  color: '#F54F4A'
};
const item2 = {
  color: '#FF8C75'
};
const item3 = {
  color: '#FFB499'
};

const data = [
  {
    children: [
      {
        value: 5,
        children: [
          {
            value: 1,
            itemStyle: item1
          },
          {
            value: 2,
            children: [
              {
                value: 1,
                itemStyle: item2
              }
            ]
          },
          {
            children: [
              {
                value: 1
              }
            ]
          }
        ],
        itemStyle: item1
      },
      {
        value: 10,
        children: [
          {
            value: 6,
            children: [
              {
                value: 1,
                itemStyle: item1
              },
              {
                value: 1
              },
              {
                value: 1,
                itemStyle: item2
              },
              {
                value: 1
              }
            ],
            itemStyle: item3
          },
          {
            value: 2,
            children: [
              {
                value: 1
              }
            ],
            itemStyle: item3
          },
          {
            children: [
              {
                value: 1,
                itemStyle: item2
              }
            ]
          }
        ],
        itemStyle: item1
      }
    ],
    itemStyle: item1
  },
  {
    value: 9,
    children: [
      {
        value: 4,
        children: [
          {
            value: 2,
            itemStyle: item2
          },
          {
            children: [
              {
                value: 1,
                itemStyle: item1
              }
            ]
          }
        ],
        itemStyle: item1
      },
      {
        children: [
          {
            value: 3,
            children: [
              {
                value: 1
              },
              {
                value: 1,
                itemStyle: item2
              }
            ]
          }
        ],
        itemStyle: item3
      }
    ],
    itemStyle: item2
  },
  {
    value: 7,
    children: [
      {
        children: [
          {
            value: 1,
            itemStyle: item3
          },
          {
            value: 3,
            children: [
              {
                value: 1,
                itemStyle: item2
              },
              {
                value: 1
              }
            ],
            itemStyle: item2
          },
          {
            value: 2,
            children: [
              {
                value: 1
              },
              {
                value: 1,
                itemStyle: item1
              }
            ],
            itemStyle: item1
          }
        ],
        itemStyle: item3
      }
    ],
    itemStyle: item1
  },
  {
    children: [
      {
        value: 6,
        children: [
          {
            value: 1,
            itemStyle: item2
          },
          {
            value: 2,
            children: [
              {
                value: 2,
                itemStyle: item2
              }
            ],
            itemStyle: item1
          },
          {
            value: 1,
            itemStyle: item3
          }
        ],
        itemStyle: item3
      },
      {
        value: 3,
        children: [
          {
            value: 1
          },
          {
            children: [
              {
                value: 1,
                itemStyle: item2
              }
            ]
          },
          {
            value: 1
          }
        ],
        itemStyle: item3
      }
    ],
    itemStyle: item1
  }
];

option = {
  series: {
    radius: ['15%', '80%'],
    type: 'sunburst',
    sort: undefined,
    emphasis: {
      focus: 'ancestor'
    },
    data: data,
    label: {
      rotate: 'radial'
    },
    levels: [],
    itemStyle: {
      color: '#ddd',
      borderWidth: 2
    }
  }
};
"""#,
        option: [
            "series": [
                [
                    "radius": ["15%", "80%"] as [Any],
                    "type": "sunburst",
                    // `sort: undefined` — NSNull() is the Swift spelling: sunburstLayout's
                    // `sort != null` guard skips initChildren, and defaults-merge cannot fill the
                    // `sort: 'desc'` default over a key that is already present.
                    "sort": NSNull(),
                    "emphasis": [
                        "focus": "ancestor"
                    ] as [String: Any],
                    "data": sunburstMonochromeData,
                    "label": [
                        "rotate": "radial"
                    ] as [String: Any],
                    "levels": [[String: Any]](),
                    "itemStyle": [
                        "color": "#ddd",
                        "borderWidth": 2.0
                    ] as [String: Any]
                ] as [String: Any]
            ]
        ])
}
