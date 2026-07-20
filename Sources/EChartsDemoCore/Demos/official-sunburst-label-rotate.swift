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
//   - `series[0].label.formatter` (a JS closure) is carried as a Swift
//     `(CallbackDataParams) -> String` closure in the `option` dict — the framework casts for exactly
//     that signature (`DataFormatMixin.getFormattedLabel`) and `params.treePathInfo` is populated by
//     `SunburstSeriesModel.getDataParams`, so both panes write the same 'radial'/'tangential'/'0'.
//   - `sort: undefined` has no Swift spelling; the option below passes `NSNull()`, which upstream's
//     `sort != null` guard (sunburstLayout) treats identically — no sorting — while still shadowing
//     the `sort: 'desc'` default during defaults-merge.
//   - Data is a literal in the example's own source (no $.get, no asset); the tree below is that
//     literal transcribed 1:1.

import Foundation
import EChartsKit

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
                        "textBorderWidth": 2.0,
                        // formatter: function (param) {
                        //   var depth = param.treePathInfo.length;
                        //   if (depth === 2) { return 'radial'; }
                        //   else if (depth === 3) { return 'tangential'; }
                        //   else if (depth === 4) { return '0'; }
                        //   return '';
                        // }
                        // PORT-NOTE: `params.treePathInfo` is now populated by
                        //   `SunburstSeriesModel.getDataParams` (chart/sunburst/SunburstSeries.swift), which
                        //   calls `treeHelper.wrapTreePathInfo`. A `(CallbackDataParams) -> String` closure in
                        //   this dict is honoured verbatim: `DataFormatMixin.getFormattedLabel` casts to
                        //   exactly that signature (model/mixin/dataFormat.swift) and SunburstPiece routes its
                        //   label text through it. `treePathInfo` is Optional here (it stays `nil` for every
                        //   non-tree series), so the count reads through `?? 0` — which lands in the `default`
                        //   branch, i.e. upstream's trailing `return ''`.
                        "formatter": { (param: CallbackDataParams) -> String in
                            let depth = param.treePathInfo?.count ?? 0
                            switch depth {
                            case 2: return "radial"
                            case 3: return "tangential"
                            case 4: return "0"
                            default: return ""
                            }
                        } as (CallbackDataParams) -> String
                    ] as [String: Any],
                    "levels": sunburstLabelRotateLevels
                ] as [String: Any]
            ]
        ])
}
