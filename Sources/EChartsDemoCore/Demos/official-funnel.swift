// official-funnel — replica of https://echarts.apache.org/examples/zh/editor.html?c=funnel
// title: Funnel Chart / titleCN: 漏斗图
// A single descending funnel series (Show → Click → Visit → Inquiry → Order) with title, legend,
// toolbox (dataView/restore/saveAsImage) and an item tooltip.
//
// DEVIATIONS from the official source: none. The example is static (no setInterval / re-setOption),
// fetches nothing and carries no editor harness (`app.*` / `myChart.setOption`), so webOptionJS is
// the official source BYTE-FOR-BYTE. `tooltip.formatter` is a STRING template ('{a} <br/>{b} :
// {c}%'), not a JS closure, so it survives into the Swift option unchanged — no option key is
// dropped from the native `option`, which mirrors the JS one key-for-key.
//
// note (native pane only, framework gap — not a demo simplification): `toolbox.feature.dataView`
// is kept in the Swift option to stay faithful, but EChartsKit does not register a `dataView` feature
// (component/toolbox/toolboxFeatures.swift: it is the HTML-overlay table editor, DEFERRED as a
// host-DOM feature). ToolboxView skips unregistered features, so the native toolbox draws only the
// `restore` + `saveAsImage` icons where the web pane draws three. Everything else renders identically.
extension EChartsDemoRegistry {
    static let official_funnel = EChartsDemo(
        name: "official-funnel", category: "funnel",
        summary: "漏斗图 — Funnel Chart",
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
      name: 'Funnel',
      type: 'funnel',
      left: '10%',
      top: 60,
      bottom: 60,
      width: '80%',
      min: 0,
      max: 100,
      minSize: '0%',
      maxSize: '100%',
      sort: 'descending',
      gap: 2,
      label: {
        show: true,
        position: 'inside'
      },
      labelLine: {
        length: 10,
        lineStyle: {
          width: 1,
          type: 'solid'
        }
      },
      itemStyle: {
        borderColor: '#fff',
        borderWidth: 1
      },
      emphasis: {
        label: {
          fontSize: 20
        }
      },
      data: [
        { value: 60, name: 'Visit' },
        { value: 40, name: 'Inquiry' },
        { value: 20, name: 'Order' },
        { value: 80, name: 'Click' },
        { value: 100, name: 'Show' }
      ]
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
                    "name": "Funnel",
                    "type": "funnel",
                    "left": "10%",
                    "top": 60.0,
                    "bottom": 60.0,
                    "width": "80%",
                    "min": 0.0,
                    "max": 100.0,
                    "minSize": "0%",
                    "maxSize": "100%",
                    "sort": "descending",
                    "gap": 2.0,
                    "label": [
                        "show": true,
                        "position": "inside"
                    ] as [String: Any],
                    "labelLine": [
                        "length": 10.0,
                        "lineStyle": [
                            "width": 1.0,
                            "type": "solid"
                        ] as [String: Any]
                    ] as [String: Any],
                    "itemStyle": [
                        "borderColor": "#fff",
                        "borderWidth": 1.0
                    ] as [String: Any],
                    "emphasis": [
                        "label": [
                            "fontSize": 20.0
                        ] as [String: Any]
                    ] as [String: Any],
                    "data": [
                        ["value": 60.0, "name": "Visit"] as [String: Any],
                        ["value": 40.0, "name": "Inquiry"] as [String: Any],
                        ["value": 20.0, "name": "Order"] as [String: Any],
                        ["value": 80.0, "name": "Click"] as [String: Any],
                        ["value": 100.0, "name": "Show"] as [String: Any]
                    ]
                ] as [String: Any]
            ]
        ])
}
