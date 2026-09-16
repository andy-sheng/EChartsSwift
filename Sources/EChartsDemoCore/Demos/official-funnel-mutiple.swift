// official-funnel-mutiple — replica of https://echarts.apache.org/examples/zh/editor.html?c=funnel-mutiple
// title: Multiple Funnels / titleCN: 多漏斗图
// Four funnel series in a 2x2 grid over the same five-stage conversion data (Show → Click → Visit →
// Inquiry → Order), differing only in `sort` (descending funnel vs `ascending` pyramid) and in where the
// labels sit (default 'inside'-style on the left column, `label.position: 'left'` on the right column).
// Title bottom-left, vertical legend, vertical center toolbox, item tooltip.
//
// DEVIATIONS from the official source: none. The example is static (no data fetch, no setInterval /
// re-setOption, no editor harness), so webOptionJS is the official source BYTE-FOR-BYTE except for the
// trailing `export {};` (a bare export is a SyntaxError in the page's classic script). `tooltip.formatter`
// is a STRING template ('{a} <br/>{b} : {c}%'), not a JS closure, so it survives into the Swift option
// unchanged — the native `option` mirrors the JS one key-for-key. The four series' identical `data`
// arrays are hoisted into one file-scope `private let` (same values, four references).
//
// note (native pane only, framework gap — not a demo simplification): `toolbox.feature.dataView`
// is kept in the Swift option to stay faithful, but EChartsKit does not register a `dataView` feature
// (component/toolbox/toolboxFeatures.swift: it is the HTML-overlay table editor, DEFERRED as a host-DOM
// feature). ToolboxView skips unregistered features, so the native toolbox draws only the `restore` +
// `saveAsImage` icons where the web pane draws three.
extension EChartsDemoRegistry {
    static let official_funnel_mutiple = EChartsDemo(
        name: "official-funnel-mutiple", category: "funnel",
        summary: "多漏斗图 — Multiple Funnels",
        width: 640, height: 420,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
option = {
  title: {
    text: 'Funnel',
    left: 'left',
    top: 'bottom'
  },
  tooltip: {
    trigger: 'item',
    formatter: '{a} <br/>{b} : {c}%'
  },
  toolbox: {
    orient: 'vertical',
    top: 'center',
    feature: {
      dataView: { readOnly: false },
      restore: {},
      saveAsImage: {}
    }
  },
  legend: {
    orient: 'vertical',
    left: 'left',
    data: ['Show', 'Click', 'Visit', 'Inquiry', 'Order']
  },

  series: [
    {
      name: 'Funnel',
      type: 'funnel',
      width: '40%',
      height: '45%',
      left: '5%',
      top: '50%',
      data: [
        { value: 60, name: 'Visit' },
        { value: 30, name: 'Inquiry' },
        { value: 10, name: 'Order' },
        { value: 80, name: 'Click' },
        { value: 100, name: 'Show' }
      ]
    },
    {
      name: 'Pyramid',
      type: 'funnel',
      width: '40%',
      height: '45%',
      left: '5%',
      top: '5%',
      sort: 'ascending',
      data: [
        { value: 60, name: 'Visit' },
        { value: 30, name: 'Inquiry' },
        { value: 10, name: 'Order' },
        { value: 80, name: 'Click' },
        { value: 100, name: 'Show' }
      ]
    },
    {
      name: 'Funnel',
      type: 'funnel',
      width: '40%',
      height: '45%',
      left: '55%',
      top: '5%',
      label: {
        position: 'left'
      },
      data: [
        { value: 60, name: 'Visit' },
        { value: 30, name: 'Inquiry' },
        { value: 10, name: 'Order' },
        { value: 80, name: 'Click' },
        { value: 100, name: 'Show' }
      ]
    },
    {
      name: 'Pyramid',
      type: 'funnel',
      width: '40%',
      height: '45%',
      left: '55%',
      top: '50%',
      sort: 'ascending',
      label: {
        position: 'left'
      },
      data: [
        { value: 60, name: 'Visit' },
        { value: 30, name: 'Inquiry' },
        { value: 10, name: 'Order' },
        { value: 80, name: 'Click' },
        { value: 100, name: 'Show' }
      ]
    }
  ]
};
"""#,
        option: [
            "title": [
                "text": "Funnel",
                "left": "left",
                "top": "bottom"
            ] as [String: Any],
            "tooltip": [
                "trigger": "item",
                // String template (not a closure) — echarts expands {a}/{b}/{c} itself.
                "formatter": "{a} <br/>{b} : {c}%"
            ] as [String: Any],
            "toolbox": [
                "orient": "vertical",
                "top": "center",
                "feature": [
                    // `dataView` is unregistered in EChartsKit (DOM overlay editor, deferred);
                    // ToolboxView skips it, so this key is inert natively but kept for option fidelity.
                    "dataView": ["readOnly": false] as [String: Any],
                    "restore": [:] as [String: Any],
                    "saveAsImage": [:] as [String: Any]
                ] as [String: Any]
            ] as [String: Any],
            "legend": [
                "orient": "vertical",
                "left": "left",
                "data": ["Show", "Click", "Visit", "Inquiry", "Order"]
            ] as [String: Any],
            "series": [
                // bottom-left: descending funnel, default labels
                [
                    "name": "Funnel",
                    "type": "funnel",
                    "width": "40%",
                    "height": "45%",
                    "left": "5%",
                    "top": "50%",
                    "data": funnelMutipleData
                ] as [String: Any],
                // top-left: ascending pyramid, default labels
                [
                    "name": "Pyramid",
                    "type": "funnel",
                    "width": "40%",
                    "height": "45%",
                    "left": "5%",
                    "top": "5%",
                    "sort": "ascending",
                    "data": funnelMutipleData
                ] as [String: Any],
                // top-right: descending funnel, labels outside on the left
                [
                    "name": "Funnel",
                    "type": "funnel",
                    "width": "40%",
                    "height": "45%",
                    "left": "55%",
                    "top": "5%",
                    "label": [
                        "position": "left"
                    ] as [String: Any],
                    "data": funnelMutipleData
                ] as [String: Any],
                // bottom-right: ascending pyramid, labels outside on the left
                [
                    "name": "Pyramid",
                    "type": "funnel",
                    "width": "40%",
                    "height": "45%",
                    "left": "55%",
                    "top": "50%",
                    "sort": "ascending",
                    "label": [
                        "position": "left"
                    ] as [String: Any],
                    "data": funnelMutipleData
                ] as [String: Any]
            ]
        ])
}

// The one data array all four series carry (identical in the official source, repeated four times there).
private let funnelMutipleData: [[String: Any]] = [
    ["value": 60.0, "name": "Visit"],
    ["value": 30.0, "name": "Inquiry"],
    ["value": 10.0, "name": "Order"],
    ["value": 80.0, "name": "Click"],
    ["value": 100.0, "name": "Show"]
]
