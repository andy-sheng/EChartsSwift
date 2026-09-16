// official-funnel-align — replica of https://echarts.apache.org/examples/zh/editor.html?c=funnel-align
// title: Funnel Compare / titleCN: 漏斗图(对比)
// Four funnel series in a 2x2 grid over the same five-product data, differing only in `sort`
// (descending funnel vs `ascending` pyramid) and `funnelAlign` ('right' on the left column, 'left'
// on the right column) — the four combinations meet along the middle so the shapes mirror each other.
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
    static let official_funnel_align = EChartsDemo(
        name: "official-funnel-align", category: "funnel",
        summary: "漏斗图(对比) — Funnel Compare",
        width: 640, height: 420,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
option = {
  title: {
    text: 'Funnel Compare',
    subtext: 'Fake Data',
    left: 'left',
    top: 'bottom'
  },
  tooltip: {
    trigger: 'item',
    formatter: '{a} <br/>{b} : {c}%'
  },
  toolbox: {
    show: true,
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
    data: ['Prod A', 'Prod B', 'Prod C', 'Prod D', 'Prod E']
  },

  series: [
    {
      name: 'Funnel',
      type: 'funnel',
      width: '40%',
      height: '45%',
      left: '5%',
      top: '50%',
      funnelAlign: 'right',

      data: [
        { value: 60, name: 'Prod C' },
        { value: 30, name: 'Prod D' },
        { value: 10, name: 'Prod E' },
        { value: 80, name: 'Prod B' },
        { value: 100, name: 'Prod A' }
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
      funnelAlign: 'right',

      data: [
        { value: 60, name: 'Prod C' },
        { value: 30, name: 'Prod D' },
        { value: 10, name: 'Prod E' },
        { value: 80, name: 'Prod B' },
        { value: 100, name: 'Prod A' }
      ]
    },
    {
      name: 'Funnel',
      type: 'funnel',
      width: '40%',
      height: '45%',
      left: '55%',
      top: '5%',
      funnelAlign: 'left',

      data: [
        { value: 60, name: 'Prod C' },
        { value: 30, name: 'Prod D' },
        { value: 10, name: 'Prod E' },
        { value: 80, name: 'Prod B' },
        { value: 100, name: 'Prod A' }
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
      funnelAlign: 'left',

      data: [
        { value: 60, name: 'Prod C' },
        { value: 30, name: 'Prod D' },
        { value: 10, name: 'Prod E' },
        { value: 80, name: 'Prod B' },
        { value: 100, name: 'Prod A' }
      ]
    }
  ]
};
"""#,
        option: [
            "title": [
                "text": "Funnel Compare",
                "subtext": "Fake Data",
                "left": "left",
                "top": "bottom"
            ] as [String: Any],
            "tooltip": [
                "trigger": "item",
                // String template (not a closure) — echarts expands {a}/{b}/{c} itself.
                "formatter": "{a} <br/>{b} : {c}%"
            ] as [String: Any],
            "toolbox": [
                "show": true,
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
                "data": ["Prod A", "Prod B", "Prod C", "Prod D", "Prod E"]
            ] as [String: Any],
            "series": [
                // bottom-left: descending funnel, right-aligned
                [
                    "name": "Funnel",
                    "type": "funnel",
                    "width": "40%",
                    "height": "45%",
                    "left": "5%",
                    "top": "50%",
                    "funnelAlign": "right",
                    "data": funnelAlignData
                ] as [String: Any],
                // top-left: ascending pyramid, right-aligned
                [
                    "name": "Pyramid",
                    "type": "funnel",
                    "width": "40%",
                    "height": "45%",
                    "left": "5%",
                    "top": "5%",
                    "sort": "ascending",
                    "funnelAlign": "right",
                    "data": funnelAlignData
                ] as [String: Any],
                // top-right: descending funnel, left-aligned
                [
                    "name": "Funnel",
                    "type": "funnel",
                    "width": "40%",
                    "height": "45%",
                    "left": "55%",
                    "top": "5%",
                    "funnelAlign": "left",
                    "data": funnelAlignData
                ] as [String: Any],
                // bottom-right: ascending pyramid, left-aligned
                [
                    "name": "Pyramid",
                    "type": "funnel",
                    "width": "40%",
                    "height": "45%",
                    "left": "55%",
                    "top": "50%",
                    "sort": "ascending",
                    "funnelAlign": "left",
                    "data": funnelAlignData
                ] as [String: Any]
            ]
        ])
}

// The one data array all four series carry (identical in the official source, repeated four times there).
private let funnelAlignData: [[String: Any]] = [
    ["value": 60.0, "name": "Prod C"],
    ["value": 30.0, "name": "Prod D"],
    ["value": 10.0, "name": "Prod E"],
    ["value": 80.0, "name": "Prod B"],
    ["value": 100.0, "name": "Prod A"]
]
