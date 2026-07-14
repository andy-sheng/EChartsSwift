// official-tree-legend — replica of https://echarts.apache.org/examples/zh/editor.html?c=tree-legend
// title: Multiple Trees / titleCN: 多棵树
//
// TWO `tree` series in one chart, side by side (each boxed by its own top/left/bottom/right), named
// tree1 / tree2 so a vertical `legend` can toggle them. tree1 is the full flare hierarchy, tree2 a
// three-branch subset. Internal nodes label on their left, leaves on their right; hovering a node
// focuses its descendants (`emphasis.focus: 'descendant'`).
//
// DEVIATIONS from the official source:
//   - The official snippet wraps the option in the editor's live harness: `myChart.showLoading()` …
//     `myChart.hideLoading(); myChart.setOption((option = { … }));` plus a trailing `export {};`. The
//     gallery drives setOption itself (and a bare `export` is a SyntaxError in a classic script), so
//     the loading pair, the setOption call and the export are dropped and the assignment is flattened
//     to a top-level `option = { … }`. Nothing inside the option changed.
//   - Both hierarchies are defined ONCE, as the JSON literals below, and spliced into the web JS in
//     place of the example's `const data = {…}` / `var data2 = {…}` object literals — same content
//     (JSON is valid JS), one source of truth for both panes, no chance of the two drifting.
//   - `expandAndCollapse: true` keeps its upstream value, but the gallery renders ONE static frame
//     (animation forced off, no clicks), so only the initial fully-expanded state is ever visible;
//     animationDuration / animationDurationUpdate likewise never play. The legend is drawn but never
//     clicked, so both series always show.
//
// No option key is a JS closure, so the native option is a COMPLETE port of the web one — every key
// (tooltip, legend.{top,left,orient,data,borderColor}, and per series {type,name,data,top,left,bottom,
// right,symbolSize,label,leaves,emphasis,expandAndCollapse,animationDuration,animationDurationUpdate})
// is present below, nothing omitted or simplified.
//
// KNOWN NATIVE-vs-WEB DIVERGENCE (framework gap, NOT an option simplification): `leaves.label` has no
// effect on the native pane — see the long note in official-tree-basic.swift (TreeSeries' `beforeLink`
// reparents leaf item models via `SeriesData.wrapMethod('getItemModel', …)`, and the ported wrapMethod
// is bookkeeping-only). Leaf labels therefore inherit the SERIES `label` (position 'left', align
// 'right') on both trees instead of fanning out to the right as they do in the web pane.
import Foundation

// MARK: - the two hierarchies (name/children/value), inlined verbatim from the official source

private func treeLegendParse(_ json: String) -> [String: Any] {
    guard let data = json.data(using: .utf8),
          let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
        return ["name": "flare", "children": [] as [Any]]   // degrade to a bare root, never crash
    }
    return obj
}

// The example's `const data` — the full flare package hierarchy.
private let treeLegendData1JSON = #"""
{
  "name": "flare",
  "children": [
    {
      "name": "data",
      "children": [
        {
          "name": "converters",
          "children": [
            { "name": "Converters", "value": 721 },
            { "name": "DelimitedTextConverter", "value": 4294 }
          ]
        },
        { "name": "DataUtil", "value": 3322 }
      ]
    },
    {
      "name": "display",
      "children": [
        { "name": "DirtySprite", "value": 8833 },
        { "name": "LineSprite", "value": 1732 },
        { "name": "RectSprite", "value": 3623 }
      ]
    },
    {
      "name": "flex",
      "children": [{ "name": "FlareVis", "value": 4116 }]
    },
    {
      "name": "query",
      "children": [
        { "name": "AggregateExpression", "value": 1616 },
        { "name": "And", "value": 1027 },
        { "name": "Arithmetic", "value": 3891 },
        { "name": "Average", "value": 891 },
        { "name": "BinaryExpression", "value": 2893 },
        { "name": "Comparison", "value": 5103 },
        { "name": "CompositeExpression", "value": 3677 },
        { "name": "Count", "value": 781 },
        { "name": "DateUtil", "value": 4141 },
        { "name": "Distinct", "value": 933 },
        { "name": "Expression", "value": 5130 },
        { "name": "ExpressionIterator", "value": 3617 },
        { "name": "Fn", "value": 3240 },
        { "name": "If", "value": 2732 },
        { "name": "IsA", "value": 2039 },
        { "name": "Literal", "value": 1214 },
        { "name": "Match", "value": 3748 },
        { "name": "Maximum", "value": 843 },
        {
          "name": "methods",
          "children": [
            { "name": "add", "value": 593 },
            { "name": "and", "value": 330 },
            { "name": "average", "value": 287 },
            { "name": "count", "value": 277 },
            { "name": "distinct", "value": 292 },
            { "name": "div", "value": 595 },
            { "name": "eq", "value": 594 },
            { "name": "fn", "value": 460 },
            { "name": "gt", "value": 603 },
            { "name": "gte", "value": 625 },
            { "name": "iff", "value": 748 },
            { "name": "isa", "value": 461 },
            { "name": "lt", "value": 597 },
            { "name": "lte", "value": 619 },
            { "name": "max", "value": 283 },
            { "name": "min", "value": 283 },
            { "name": "mod", "value": 591 },
            { "name": "mul", "value": 603 },
            { "name": "neq", "value": 599 },
            { "name": "not", "value": 386 },
            { "name": "or", "value": 323 },
            { "name": "orderby", "value": 307 },
            { "name": "range", "value": 772 },
            { "name": "select", "value": 296 },
            { "name": "stddev", "value": 363 },
            { "name": "sub", "value": 600 },
            { "name": "sum", "value": 280 },
            { "name": "update", "value": 307 },
            { "name": "variance", "value": 335 },
            { "name": "where", "value": 299 },
            { "name": "xor", "value": 354 },
            { "name": "_", "value": 264 }
          ]
        },
        { "name": "Minimum", "value": 843 },
        { "name": "Not", "value": 1554 },
        { "name": "Or", "value": 970 },
        { "name": "Query", "value": 13896 },
        { "name": "Range", "value": 1594 },
        { "name": "StringUtil", "value": 4130 },
        { "name": "Sum", "value": 791 },
        { "name": "Variable", "value": 1124 },
        { "name": "Variance", "value": 1876 },
        { "name": "Xor", "value": 1101 }
      ]
    },
    {
      "name": "scale",
      "children": [
        { "name": "IScaleMap", "value": 2105 },
        { "name": "LinearScale", "value": 1316 },
        { "name": "LogScale", "value": 3151 },
        { "name": "OrdinalScale", "value": 3770 },
        { "name": "QuantileScale", "value": 2435 },
        { "name": "QuantitativeScale", "value": 4839 },
        { "name": "RootScale", "value": 1756 },
        { "name": "Scale", "value": 4268 },
        { "name": "ScaleType", "value": 1821 },
        { "name": "TimeScale", "value": 5833 }
      ]
    }
  ]
}
"""#

// The example's `var data2` — a three-branch subset of the same hierarchy.
private let treeLegendData2JSON = #"""
{
  "name": "flare",
  "children": [
    {
      "name": "flex",
      "children": [{ "name": "FlareVis", "value": 4116 }]
    },
    {
      "name": "scale",
      "children": [
        { "name": "IScaleMap", "value": 2105 },
        { "name": "LinearScale", "value": 1316 },
        { "name": "LogScale", "value": 3151 },
        { "name": "OrdinalScale", "value": 3770 },
        { "name": "QuantileScale", "value": 2435 },
        { "name": "QuantitativeScale", "value": 4839 },
        { "name": "RootScale", "value": 1756 },
        { "name": "Scale", "value": 4268 },
        { "name": "ScaleType", "value": 1821 },
        { "name": "TimeScale", "value": 5833 }
      ]
    },
    {
      "name": "display",
      "children": [{ "name": "DirtySprite", "value": 8833 }]
    }
  ]
}
"""#

private let treeLegendData1: [String: Any] = treeLegendParse(treeLegendData1JSON)
private let treeLegendData2: [String: Any] = treeLegendParse(treeLegendData2JSON)

extension EChartsDemoRegistry {
    static let official_tree_legend = EChartsDemo(
        name: "official-tree-legend", category: "tree",
        summary: "多棵树 — Multiple Trees",
        width: 720, height: 460,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
const data = \#(treeLegendData1JSON);

var data2 = \#(treeLegendData2JSON);

option = {
  tooltip: {
    trigger: 'item',
    triggerOn: 'mousemove'
  },
  legend: {
    top: '2%',
    left: '3%',
    orient: 'vertical',
    data: [
      {
        name: 'tree1',
        icon: 'rectangle'
      },
      {
        name: 'tree2',
        icon: 'rectangle'
      }
    ],
    borderColor: '#c23531'
  },
  series: [
    {
      type: 'tree',

      name: 'tree1',

      data: [data],

      top: '5%',
      left: '7%',
      bottom: '2%',
      right: '60%',

      symbolSize: 7,

      label: {
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
    },
    {
      type: 'tree',
      name: 'tree2',
      data: [data2],

      top: '20%',
      left: '60%',
      bottom: '22%',
      right: '18%',

      symbolSize: 7,

      label: {
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

      expandAndCollapse: true,

      emphasis: {
        focus: 'descendant'
      },

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
            "legend": [
                "top": "2%",
                "left": "3%",
                "orient": "vertical",
                "data": [
                    ["name": "tree1", "icon": "rectangle"] as [String: Any],
                    ["name": "tree2", "icon": "rectangle"] as [String: Any]
                ] as [Any],
                "borderColor": "#c23531"
            ] as [String: Any],
            "series": [
                [
                    "type": "tree",
                    "name": "tree1",
                    "data": [treeLegendData1] as [Any],
                    "top": "5%",
                    "left": "7%",
                    "bottom": "2%",
                    "right": "60%",
                    "symbolSize": 7.0,
                    "label": [
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
                ] as [String: Any],
                [
                    "type": "tree",
                    "name": "tree2",
                    "data": [treeLegendData2] as [Any],
                    "top": "20%",
                    "left": "60%",
                    "bottom": "22%",
                    "right": "18%",
                    "symbolSize": 7.0,
                    "label": [
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
                    "expandAndCollapse": true,
                    "emphasis": [
                        "focus": "descendant"
                    ] as [String: Any],
                    "animationDuration": 550.0,
                    "animationDurationUpdate": 750.0
                ] as [String: Any]
            ]
        ])
}
