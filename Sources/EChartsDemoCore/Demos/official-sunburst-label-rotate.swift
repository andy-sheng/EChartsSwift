// official-sunburst-label-rotate — replica of https://echarts.apache.org/examples/zh/editor.html?c=sunburst-label-rotate
// title: Sunburst Label Rotate / titleCN: 旭日图标签旋转
//
// One `silent` sunburst over an unnamed 4-level tree; each `levels[i]` paints its ring a different
// colour and sets a different `label.rotate` ('radial' / 'tangential' / 0), and the series-level
// `label.formatter` writes the ring's own rotate mode into every sector — the label TEXT is the
// demonstration. `sort: undefined` suppresses the default 'desc' so the rings keep data order.
//
// DEVIATIONS from the official source:
//   - webOptionJS is the example verbatim, minus the TypeScript annotation on the formatter's
//     parameter (`function (param: any)` → `function (param)`; a classic <script> cannot parse it)
//     and the trailing `export {};` (a bare export is a SyntaxError that kills the page).
//   - `series[0].label.formatter` (a JS closure) is dropped from the Swift `option`, so the native
//     pane renders the sectors with their DEFAULT label text instead of 'radial'/'tangential'/'0'.
//     The nodes have no `name`, so those default labels come out empty: the native pane shows the
//     rings and their rotations but no words, where the web pane shows the words. That gap is the
//     point of the side-by-side — see the PORT-NOTE at the label block for WHY it cannot be carried
//     (it is NOT "Swift dicts can't hold closures" — they can, and the framework casts for one).
//   - `sort: undefined` has no Swift spelling; the option below passes `NSNull()`, which upstream's
//     `sort != null` guard (sunburstLayout) treats identically — no sorting — while still shadowing
//     the `sort: 'desc'` default during defaults-merge.
//   - Data is a literal in the example's own source (no $.get, no asset); the tree below is that
//     literal transcribed 1:1.

import Foundation

// The example's tree: values only, no names. Nodes at depth 2 of the last three roots carry no
// `value` of their own (they inherit the sum of their children) — kept exactly as upstream has it.
private let sunburstLabelRotateData: [[String: Any]] = [
    [
        "value": 8.0,
        "children": [
            [
                "value": 4.0,
                "children": [
                    ["value": 2.0] as [String: Any],
                    ["value": 1.0] as [String: Any],
                    ["value": 1.0] as [String: Any],
                    ["value": 0.5] as [String: Any]
                ]
            ] as [String: Any],
            ["value": 2.0] as [String: Any]
        ]
    ] as [String: Any],
    [
        "value": 4.0,
        "children": [
            [
                "children": [
                    ["value": 2.0] as [String: Any]
                ]
            ] as [String: Any]
        ]
    ] as [String: Any],
    [
        "value": 4.0,
        "children": [
            [
                "children": [
                    ["value": 2.0] as [String: Any]
                ]
            ] as [String: Any]
        ]
    ] as [String: Any],
    [
        "value": 3.0,
        "children": [
            [
                "children": [
                    ["value": 1.0] as [String: Any]
                ]
            ] as [String: Any]
        ]
    ] as [String: Any]
]

// One entry per depth: root ring inherits defaults, then radial / tangential / horizontal labels.
private let sunburstLabelRotateLevels: [[String: Any]] = [
    [:] as [String: Any],
    [
        "itemStyle": ["color": "#CD4949"] as [String: Any],
        "label": ["rotate": "radial"] as [String: Any]
    ] as [String: Any],
    [
        "itemStyle": ["color": "#F47251"] as [String: Any],
        "label": ["rotate": "tangential"] as [String: Any]
    ] as [String: Any],
    [
        "itemStyle": ["color": "#FFC75F"] as [String: Any],
        "label": ["rotate": 0.0] as [String: Any]
    ] as [String: Any]
]

extension EChartsDemoRegistry {
    static let official_sunburst_label_rotate = EChartsDemo(
        name: "official-sunburst-label-rotate", category: "sunburst",
        summary: "旭日图标签旋转 — Sunburst Label Rotate",
        width: 640, height: 420,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
option = {
  silent: true,
  series: [
    {
      radius: ['15%', '80%'],
      type: 'sunburst',
      sort: undefined,
      emphasis: {
        focus: 'ancestor'
      },
      data: [
        {
          value: 8,
          children: [
            {
              value: 4,
              children: [
                {
                  value: 2
                },
                {
                  value: 1
                },
                {
                  value: 1
                },
                {
                  value: 0.5
                }
              ]
            },
            {
              value: 2
            }
          ]
        },
        {
          value: 4,
          children: [
            {
              children: [
                {
                  value: 2
                }
              ]
            }
          ]
        },
        {
          value: 4,
          children: [
            {
              children: [
                {
                  value: 2
                }
              ]
            }
          ]
        },
        {
          value: 3,
          children: [
            {
              children: [
                {
                  value: 1
                }
              ]
            }
          ]
        }
      ],
      label: {
        color: '#000',
        textBorderColor: '#fff',
        textBorderWidth: 2,
        formatter: function (param) {
          var depth = param.treePathInfo.length;
          if (depth === 2) {
            return 'radial';
          } else if (depth === 3) {
            return 'tangential';
          } else if (depth === 4) {
            return '0';
          }
          return '';
        }
      },
      levels: [
        {},
        {
          itemStyle: {
            color: '#CD4949'
          },
          label: {
            rotate: 'radial'
          }
        },
        {
          itemStyle: {
            color: '#F47251'
          },
          label: {
            rotate: 'tangential'
          }
        },
        {
          itemStyle: {
            color: '#FFC75F'
          },
          label: {
            rotate: 0
          }
        }
      ]
    }
  ]
};
"""#,
        option: [
            "silent": true,
            "series": [
                [
                    "radius": ["15%", "80%"],
                    "type": "sunburst",
                    // `sort: undefined` — NSNull() is the Swift spelling: sunburstLayout's
                    // `sort != null` guard skips initChildren, and defaults-merge cannot fill the
                    // `sort: 'desc'` default over a key that is already present.
                    "sort": NSNull(),
                    "emphasis": ["focus": "ancestor"] as [String: Any],
                    "data": sunburstLabelRotateData,
                    "label": [
                        "color": "#000",
                        "textBorderColor": "#fff",
                        "textBorderWidth": 2.0
                        // PORT-NOTE: label.formatter omitted — the JS closure read
                        // `param.treePathInfo.length` (the node's depth) and returned the ring's own
                        // rotate mode as its text: 'radial' at depth 2, 'tangential' at depth 3, '0'
                        // at depth 4, '' at the root.
                        //
                        // The blocker is NOT the closure itself: a Swift `(CallbackDataParams) ->
                        // String` in this dict WOULD be honoured — `DataFormatMixin.getFormattedLabel`
                        // casts to exactly that signature (model/mixin/dataFormat.swift), and
                        // SunburstPiece routes its label text through it. The blocker is the closure's
                        // ARGUMENT: `treePathInfo` does not exist on the ported `CallbackDataParams`
                        // (util/types.swift), because `SunburstSeries.getDataParams` — the override
                        // that would attach it — is still deferred, blocked on `CallbackDataParams`
                        // gaining the `treePathInfo` slot (SYMBOLS row 18); `treeHelper.wrapTreePathInfo`
                        // is already fully ported. With no depth on the params
                        // there is nothing for the closure to branch on, so it is dropped: the native
                        // pane falls back to the default label (the node `name`, which this data does
                        // not set) and the sectors come out unlabelled.
                        //
                        // Deliberately NOT worked around by hanging a literal `formatter: "radial"` off
                        // each `levels[i].label` (which would resolve — the level model is the item
                        // model's parentModel, which is exactly how `rotate`/`itemStyle.color` below
                        // reach the sectors). Faking the text would hide the missing `treePathInfo`
                        // behind a label the port never actually computed. When `getDataParams` lands,
                        // this key becomes a one-line Swift closure and the panes converge.
                    ] as [String: Any],
                    "levels": sunburstLabelRotateLevels
                ] as [String: Any]
            ]
        ])
}
