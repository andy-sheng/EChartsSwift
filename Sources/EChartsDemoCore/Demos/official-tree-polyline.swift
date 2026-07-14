// official-tree-polyline — replica of https://echarts.apache.org/examples/zh/editor.html?c=tree-polyline
// title: Tree with Polyline Edge / titleCN: 折线树图
//
// A left-to-right `tree` over a trimmed flare hierarchy drawn with ORTHOGONAL POLYLINE edges
// (`edgeShape: 'polyline'`, fork at 63% of the span) instead of the default beziers, expanded to
// depth 3, internal labels on a white background to the left of their symbol, leaf labels to the
// right, and `emphasis.focus: 'descendant'` on hover.
//
// DEVIATIONS from the official source:
//   - `export {};` dropped from the web JS (a bare `export` is a SyntaxError in a classic script and
//     would kill the whole page). Nothing else is changed: the example inlines its own `data` literal
//     (no ROOT_PATH / $.get), so webOptionJS carries the source VERBATIM — same `const data = {...}`,
//     same `option = {...}`.
//   - No `drive`, and that is CORRECT, not a simplification: `drive` exists to replay an example's own
//     `setInterval` / `setOption` timeline, and this example has neither — it assigns `option` and
//     stops. Its remaining dynamics are USER-INTERACTIVE (`expandAndCollapse` click-to-collapse,
//     tooltip on mousemove, `emphasis.focus: 'descendant'` on hover), which both LIVE panes already
//     serve without any help from the demo: the web pane is real echarts in a WKWebView, and the
//     native gallery pane runs an AnimationLoop over `zr.animation` and forwards mouseMoved/mouseDown
//     into the chart (Sources/EChartsDemoGallery/EChartsHostView.swift). `animationDuration` (550ms
//     initial draw) and `animationDurationUpdate` (750ms re-layout after an expand/collapse) therefore
//     DO play on the live panes. Only the HEADLESS still-frame paths freeze them — `--render` forces
//     `animation = false` (Entry.swift `renderNativeGroup`), and `--web-snapshot` / `--compare` do the
//     same web-side via `snapshot: true` (WebPage.swift) — so the PNGs show the depth-3 initial state.
//
// No option key is a JS function, so the native option is a COMPLETE port of the web one — every key
// (tooltip, series[0].{type,id,name,data,top,left,bottom,right,symbolSize,edgeShape,edgeForkPosition,
// initialTreeDepth,lineStyle,label,leaves,emphasis,expandAndCollapse,animationDuration,
// animationDurationUpdate}) is present below, nothing omitted or simplified.
//
// KNOWN NATIVE-vs-WEB DIVERGENCE (framework gap, NOT an option simplification): `leaves.label` is
// inert on the native pane. Upstream reparents each leaf's item model onto a `leavesModel` inside
// `TreeSeries.getInitialData`'s `beforeLink`, via `SeriesData.wrapMethod('getItemModel', ...)`; the
// ported `wrapMethod` is bookkeeping-only (it cannot rebind a method by name — see the POTENTIAL-BUG
// note in Sources/EChartsKit/chart/tree/TreeSeries.swift, and `SeriesData.getItemModel`, which never
// consults the injection). Leaf labels therefore inherit the SERIES `label` (position 'left', align
// 'right') rather than `leaves.label` (position 'right', align 'left'): the web pane fans the leaf
// names out to the RIGHT of the tree, the native pane draws them to the left of their symbol. The
// `leaves` block is passed verbatim so the demo lights up the moment `wrapMethod` becomes real.
import Foundation

// The example's inline hierarchy. Built through two typed helpers rather than one big nested literal:
// a ~60-node heterogeneous `[String: Any]` literal is exactly the shape that times out Swift's
// type-checker.
private func tpLeaf(_ name: String, _ value: Double) -> [String: Any] {
    ["name": name, "value": value]
}
private func tpNode(_ name: String, _ children: [[String: Any]]) -> [String: Any] {
    ["name": name, "children": children]
}

private let treePolylineQueryMethods: [[String: Any]] = [
    tpLeaf("add", 593), tpLeaf("and", 330), tpLeaf("average", 287), tpLeaf("count", 277),
    tpLeaf("distinct", 292), tpLeaf("div", 595), tpLeaf("eq", 594), tpLeaf("fn", 460),
    tpLeaf("gt", 603), tpLeaf("gte", 625), tpLeaf("iff", 748), tpLeaf("isa", 461),
    tpLeaf("lt", 597), tpLeaf("lte", 619), tpLeaf("max", 283), tpLeaf("min", 283),
    tpLeaf("mod", 591), tpLeaf("mul", 603), tpLeaf("neq", 599), tpLeaf("not", 386),
    tpLeaf("or", 323), tpLeaf("orderby", 307), tpLeaf("range", 772), tpLeaf("select", 296),
    tpLeaf("stddev", 363), tpLeaf("sub", 600), tpLeaf("sum", 280), tpLeaf("update", 307),
    tpLeaf("variance", 335), tpLeaf("where", 299), tpLeaf("xor", 354), tpLeaf("x_x", 264)
]

private let treePolylineQuery: [[String: Any]] = [
    tpLeaf("AggregateExpression", 1616),
    tpLeaf("And", 1027),
    tpLeaf("Arithmetic", 3891),
    tpLeaf("Average", 891),
    tpLeaf("BinaryExpression", 2893),
    tpLeaf("Comparison", 5103),
    tpLeaf("CompositeExpression", 3677),
    tpLeaf("Count", 781),
    tpLeaf("DateUtil", 4141),
    tpLeaf("Distinct", 933),
    tpLeaf("Expression", 5130),
    tpLeaf("ExpressionIterator", 3617),
    tpLeaf("Fn", 3240),
    tpLeaf("If", 2732),
    tpLeaf("IsA", 2039),
    tpLeaf("Literal", 1214),
    tpLeaf("Match", 3748),
    tpLeaf("Maximum", 843),
    tpNode("methods", treePolylineQueryMethods),
    tpLeaf("Minimum", 843),
    tpLeaf("Not", 1554),
    tpLeaf("Or", 970),
    tpLeaf("Query", 13896),
    tpLeaf("Range", 1594),
    tpLeaf("StringUtil", 4130),
    tpLeaf("Sum", 791),
    tpLeaf("Variable", 1124),
    tpLeaf("Variance", 1876),
    tpLeaf("Xor", 1101)
]

private let treePolylineScale: [[String: Any]] = [
    tpLeaf("IScaleMap", 2105),
    tpLeaf("LinearScale", 1316),
    tpLeaf("LogScale", 3151),
    tpLeaf("OrdinalScale", 3770),
    tpLeaf("QuantileScale", 2435),
    tpLeaf("QuantitativeScale", 4839),
    tpLeaf("RootScale", 1756),
    tpLeaf("Scale", 4268),
    tpLeaf("ScaleType", 1821),
    tpLeaf("TimeScale", 5833)
]

private let treePolylineData: [String: Any] = tpNode("flare", [
    tpNode("data", [
        tpNode("converters", [
            tpLeaf("Converters", 721),
            tpLeaf("DelimitedTextConverter", 4294)
        ]),
        tpLeaf("DataUtil", 3322)
    ]),
    tpNode("display", [
        tpLeaf("DirtySprite", 8833),
        tpLeaf("LineSprite", 1732),
        tpLeaf("RectSprite", 3623)
    ]),
    tpNode("flex", [
        tpLeaf("FlareVis", 4116)
    ]),
    tpNode("query", treePolylineQuery),
    tpNode("scale", treePolylineScale)
])

extension EChartsDemoRegistry {
    static let official_tree_polyline = EChartsDemo(
        name: "official-tree-polyline", category: "tree",
        summary: "折线树图 — Tree with Polyline Edge",
        width: 720, height: 460,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
const data = {
  name: 'flare',
  children: [
    {
      name: 'data',
      children: [
        {
          name: 'converters',
          children: [
            { name: 'Converters', value: 721 },
            { name: 'DelimitedTextConverter', value: 4294 }
          ]
        },
        {
          name: 'DataUtil',
          value: 3322
        }
      ]
    },
    {
      name: 'display',
      children: [
        { name: 'DirtySprite', value: 8833 },
        { name: 'LineSprite', value: 1732 },
        { name: 'RectSprite', value: 3623 }
      ]
    },
    {
      name: 'flex',
      children: [{ name: 'FlareVis', value: 4116 }]
    },
    {
      name: 'query',
      children: [
        { name: 'AggregateExpression', value: 1616 },
        { name: 'And', value: 1027 },
        { name: 'Arithmetic', value: 3891 },
        { name: 'Average', value: 891 },
        { name: 'BinaryExpression', value: 2893 },
        { name: 'Comparison', value: 5103 },
        { name: 'CompositeExpression', value: 3677 },
        { name: 'Count', value: 781 },
        { name: 'DateUtil', value: 4141 },
        { name: 'Distinct', value: 933 },
        { name: 'Expression', value: 5130 },
        { name: 'ExpressionIterator', value: 3617 },
        { name: 'Fn', value: 3240 },
        { name: 'If', value: 2732 },
        { name: 'IsA', value: 2039 },
        { name: 'Literal', value: 1214 },
        { name: 'Match', value: 3748 },
        { name: 'Maximum', value: 843 },
        {
          name: 'methods',
          children: [
            { name: 'add', value: 593 },
            { name: 'and', value: 330 },
            { name: 'average', value: 287 },
            { name: 'count', value: 277 },
            { name: 'distinct', value: 292 },
            { name: 'div', value: 595 },
            { name: 'eq', value: 594 },
            { name: 'fn', value: 460 },
            { name: 'gt', value: 603 },
            { name: 'gte', value: 625 },
            { name: 'iff', value: 748 },
            { name: 'isa', value: 461 },
            { name: 'lt', value: 597 },
            { name: 'lte', value: 619 },
            { name: 'max', value: 283 },
            { name: 'min', value: 283 },
            { name: 'mod', value: 591 },
            { name: 'mul', value: 603 },
            { name: 'neq', value: 599 },
            { name: 'not', value: 386 },
            { name: 'or', value: 323 },
            { name: 'orderby', value: 307 },
            { name: 'range', value: 772 },
            { name: 'select', value: 296 },
            { name: 'stddev', value: 363 },
            { name: 'sub', value: 600 },
            { name: 'sum', value: 280 },
            { name: 'update', value: 307 },
            { name: 'variance', value: 335 },
            { name: 'where', value: 299 },
            { name: 'xor', value: 354 },
            { name: 'x_x', value: 264 }
          ]
        },
        { name: 'Minimum', value: 843 },
        { name: 'Not', value: 1554 },
        { name: 'Or', value: 970 },
        { name: 'Query', value: 13896 },
        { name: 'Range', value: 1594 },
        { name: 'StringUtil', value: 4130 },
        { name: 'Sum', value: 791 },
        { name: 'Variable', value: 1124 },
        { name: 'Variance', value: 1876 },
        { name: 'Xor', value: 1101 }
      ]
    },
    {
      name: 'scale',
      children: [
        { name: 'IScaleMap', value: 2105 },
        { name: 'LinearScale', value: 1316 },
        { name: 'LogScale', value: 3151 },
        { name: 'OrdinalScale', value: 3770 },
        { name: 'QuantileScale', value: 2435 },
        { name: 'QuantitativeScale', value: 4839 },
        { name: 'RootScale', value: 1756 },
        { name: 'Scale', value: 4268 },
        { name: 'ScaleType', value: 1821 },
        { name: 'TimeScale', value: 5833 }
      ]
    }
  ]
};

option = {
  tooltip: {
    trigger: 'item',
    triggerOn: 'mousemove'
  },
  series: [
    {
      type: 'tree',
      id: 0,
      name: 'tree1',
      data: [data],

      top: '10%',
      left: '8%',
      bottom: '22%',
      right: '20%',

      symbolSize: 7,

      edgeShape: 'polyline',
      edgeForkPosition: '63%',
      initialTreeDepth: 3,

      lineStyle: {
        width: 2
      },

      label: {
        backgroundColor: '#fff',
        position: 'left',
        verticalAlign: 'middle',
        align: 'right'
      },

      leaves: {
        label: {
          position: 'right',
          verticalAlign: 'middle',
          align: 'left'
        }
      },

      emphasis: {
        focus: 'descendant'
      },

      expandAndCollapse: true,
      animationDuration: 550,
      animationDurationUpdate: 750
    }
  ]
};
"""#,
        option: [
            "tooltip": [
                "trigger": "item",
                "triggerOn": "mousemove"
            ] as [String: Any],
            "series": [
                [
                    "type": "tree",
                    "id": 0.0,
                    "name": "tree1",
                    "data": [treePolylineData] as [Any],

                    "top": "10%",
                    "left": "8%",
                    "bottom": "22%",
                    "right": "20%",

                    "symbolSize": 7.0,

                    "edgeShape": "polyline",
                    "edgeForkPosition": "63%",
                    "initialTreeDepth": 3.0,

                    "lineStyle": [
                        "width": 2.0
                    ] as [String: Any],

                    "label": [
                        "backgroundColor": "#fff",
                        "position": "left",
                        "verticalAlign": "middle",
                        "align": "right"
                    ] as [String: Any],

                    "leaves": [
                        "label": [
                            "position": "right",
                            "verticalAlign": "middle",
                            "align": "left"
                        ] as [String: Any]
                    ] as [String: Any],

                    "emphasis": [
                        "focus": "descendant"
                    ] as [String: Any],

                    "expandAndCollapse": true,
                    "animationDuration": 550.0,
                    "animationDurationUpdate": 750.0
                ] as [String: Any]
            ]
        ])
}
