// official-funnel-customize — replica of https://echarts.apache.org/examples/zh/editor.html?c=funnel-customize
// title: Customized Funnel / titleCN: 漏斗图
// Two funnel series stacked on the same left/width band: a translucent "Expected" funnel (opacity 0.7,
// no labelLine) and a narrower "Actual" funnel drawn on top (maxSize '80%', white 2px borders,
// opacity 0.5, z: 100 so the outer shape never covers the inner one on hover). Each has its own
// emphasis label template.
//
// DEVIATIONS from the official source: none of substance. `webOptionJS` is the official source
// verbatim except for the trailing `export {};` (a bare `export` is a SyntaxError in the page's
// classic script and would kill the whole reference pane). Every `formatter` here is a STRING template
// ('{a} <br/>{b} : {c}%', '{b}Expected', '{c}%', ...), NOT a JS closure, so all of them survive into
// the Swift option unchanged — no option key is dropped from the native `option`, which mirrors the JS
// one key-for-key. The example is static: no fetch, no setInterval/setTimeout, no `myChart` use, so
// there is no `drive`.
//
// note (native pane only, framework gap — not a demo simplification): `toolbox.feature.dataView`
// is kept in the Swift option to stay faithful, but EChartsKit does not register a `dataView` feature
// (component/toolbox/toolboxFeatures.swift: it is the HTML-overlay table editor, DEFERRED as a
// host-DOM feature). ToolboxView skips unregistered features, so the native toolbox draws only the
// `restore` + `saveAsImage` icons where the web pane draws three.
extension EChartsDemoRegistry {
    static let official_funnel_customize = EChartsDemo(
        name: "official-funnel-customize", category: "funnel",
        summary: "漏斗图 — Customized Funnel",
        width: 640, height: 420,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
option = {
  title: {
    text: 'Funnel'
  },
  tooltip: {
    trigger: 'item',
    formatter: '{a} <br/>{b} : {c}%'
  },
  toolbox: {
    feature: {
      dataView: { readOnly: false },
      restore: {},
      saveAsImage: {}
    }
  },
  legend: {
    data: ['Show', 'Click', 'Visit', 'Inquiry', 'Order']
  },
  series: [
    {
      name: 'Expected',
      type: 'funnel',
      left: '10%',
      width: '80%',
      label: {
        formatter: '{b}Expected'
      },
      labelLine: {
        show: false
      },
      itemStyle: {
        opacity: 0.7
      },
      emphasis: {
        label: {
          position: 'inside',
          formatter: '{b}Expected: {c}%'
        }
      },
      data: [
        { value: 60, name: 'Visit' },
        { value: 40, name: 'Inquiry' },
        { value: 20, name: 'Order' },
        { value: 80, name: 'Click' },
        { value: 100, name: 'Show' }
      ]
    },
    {
      name: 'Actual',
      type: 'funnel',
      left: '10%',
      width: '80%',
      maxSize: '80%',
      label: {
        position: 'inside',
        formatter: '{c}%',
        color: '#fff'
      },
      itemStyle: {
        opacity: 0.5,
        borderColor: '#fff',
        borderWidth: 2
      },
      emphasis: {
        label: {
          position: 'inside',
          formatter: '{b}Actual: {c}%'
        }
      },
      data: [
        { value: 30, name: 'Visit' },
        { value: 10, name: 'Inquiry' },
        { value: 5, name: 'Order' },
        { value: 50, name: 'Click' },
        { value: 80, name: 'Show' }
      ],
      // Ensure outer shape will not be over inner shape when hover.
      z: 100
    }
  ]
};
"""#,
        option: [
            "title": [
                "text": "Funnel"
            ] as [String: Any],
            "tooltip": [
                "trigger": "item",
                // String template (not a closure) — echarts expands {a}/{b}/{c} itself.
                "formatter": "{a} <br/>{b} : {c}%"
            ] as [String: Any],
            "toolbox": [
                "feature": [
                    // `dataView` is unregistered in EChartsKit (DOM overlay editor, deferred);
                    // ToolboxView skips it, so this key is inert natively but kept for option fidelity.
                    "dataView": ["readOnly": false] as [String: Any],
                    "restore": [:] as [String: Any],
                    "saveAsImage": [:] as [String: Any]
                ] as [String: Any]
            ] as [String: Any],
            "legend": [
                "data": ["Show", "Click", "Visit", "Inquiry", "Order"]
            ] as [String: Any],
            "series": [
                [
                    "name": "Expected",
                    "type": "funnel",
                    "left": "10%",
                    "width": "80%",
                    "label": [
                        "formatter": "{b}Expected"
                    ] as [String: Any],
                    "labelLine": [
                        "show": false
                    ] as [String: Any],
                    "itemStyle": [
                        "opacity": 0.7
                    ] as [String: Any],
                    "emphasis": [
                        "label": [
                            "position": "inside",
                            "formatter": "{b}Expected: {c}%"
                        ] as [String: Any]
                    ] as [String: Any],
                    "data": funnelCustomizeExpectedData
                ] as [String: Any],
                [
                    "name": "Actual",
                    "type": "funnel",
                    "left": "10%",
                    "width": "80%",
                    "maxSize": "80%",
                    "label": [
                        "position": "inside",
                        "formatter": "{c}%",
                        "color": "#fff"
                    ] as [String: Any],
                    "itemStyle": [
                        "opacity": 0.5,
                        "borderColor": "#fff",
                        "borderWidth": 2.0
                    ] as [String: Any],
                    "emphasis": [
                        "label": [
                            "position": "inside",
                            "formatter": "{b}Actual: {c}%"
                        ] as [String: Any]
                    ] as [String: Any],
                    "data": funnelCustomizeActualData,
                    // Ensure outer shape will not be over inner shape when hover.
                    "z": 100.0
                ] as [String: Any]
            ]
        ])
}

private let funnelCustomizeExpectedData: [[String: Any]] = [
    ["value": 60.0, "name": "Visit"],
    ["value": 40.0, "name": "Inquiry"],
    ["value": 20.0, "name": "Order"],
    ["value": 80.0, "name": "Click"],
    ["value": 100.0, "name": "Show"]
]

private let funnelCustomizeActualData: [[String: Any]] = [
    ["value": 30.0, "name": "Visit"],
    ["value": 10.0, "name": "Inquiry"],
    ["value": 5.0, "name": "Order"],
    ["value": 50.0, "name": "Click"],
    ["value": 80.0, "name": "Show"]
]
