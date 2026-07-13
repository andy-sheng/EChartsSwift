// official-pie-nest — replica of https://echarts.apache.org/examples/zh/editor.html?c=pie-nest
// title: Nested Pies / titleCN: 嵌套环形图
// Two concentric `pie` series sharing one legend: an inner solid pie (radius [0, '30%'], inner labels,
// selectedMode 'single' with 'Marketing' pre-selected/offset) and an outer ring (radius ['45%','60%'])
// whose labels use a rich-text card (`{a|…}{abg|}\n{hr|}\n  {b|…}{c}  {per|{d}%}`) on a callout line.
// DEVIATIONS: none of substance — the official source is a single static `option` literal with no data
// fetch and no timers. Its `tooltip.formatter` and `series[1].label.formatter` are TEMPLATE STRINGS,
// not JS closures, so both panes carry them verbatim; the trailing `export {};` is dropped (a bare
// export is a SyntaxError in the classic script the reference pane runs).
extension EChartsDemoRegistry {
    static let official_pie_nest = EChartsDemo(
        name: "official-pie-nest", category: "pie",
        summary: "嵌套环形图 — Nested Pies",
        width: 640, height: 420,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
option = {
  tooltip: {
    trigger: 'item',
    formatter: '{a} <br/>{b}: {c} ({d}%)'
  },
  legend: {
    data: [
      'Direct',
      'Marketing',
      'Search Engine',
      'Email',
      'Union Ads',
      'Video Ads',
      'Baidu',
      'Google',
      'Bing',
      'Others'
    ]
  },
  series: [
    {
      name: 'Access From',
      type: 'pie',
      selectedMode: 'single',
      radius: [0, '30%'],
      label: {
        position: 'inner',
        fontSize: 14
      },
      labelLine: {
        show: false
      },
      data: [
        { value: 1548, name: 'Search Engine' },
        { value: 775, name: 'Direct' },
        { value: 679, name: 'Marketing', selected: true }
      ]
    },
    {
      name: 'Access From',
      type: 'pie',
      radius: ['45%', '60%'],
      labelLine: {
        length: 30
      },
      label: {
        formatter: '{a|{a}}{abg|}\n{hr|}\n  {b|{b}：}{c}  {per|{d}%}  ',
        backgroundColor: '#F6F8FC',
        borderColor: '#8C8D8E',
        borderWidth: 1,
        borderRadius: 4,

        rich: {
          a: {
            color: '#6E7079',
            lineHeight: 22,
            align: 'center'
          },
          hr: {
            borderColor: '#8C8D8E',
            width: '100%',
            borderWidth: 1,
            height: 0
          },
          b: {
            color: '#4C5058',
            fontSize: 14,
            fontWeight: 'bold',
            lineHeight: 33
          },
          per: {
            color: '#fff',
            backgroundColor: '#4C5058',
            padding: [3, 4],
            borderRadius: 4
          }
        }
      },
      data: [
        { value: 1048, name: 'Baidu' },
        { value: 335, name: 'Direct' },
        { value: 310, name: 'Email' },
        { value: 251, name: 'Google' },
        { value: 234, name: 'Union Ads' },
        { value: 147, name: 'Bing' },
        { value: 135, name: 'Video Ads' },
        { value: 102, name: 'Others' }
      ]
    }
  ]
};
"""#,
        option: [
            "tooltip": [
                "trigger": "item",
                "formatter": "{a} <br/>{b}: {c} ({d}%)"
            ] as [String: Any],
            "legend": [
                "data": [
                    "Direct", "Marketing", "Search Engine", "Email", "Union Ads",
                    "Video Ads", "Baidu", "Google", "Bing", "Others"
                ]
            ] as [String: Any],
            "series": [
                [
                    "name": "Access From",
                    "type": "pie",
                    "selectedMode": "single",
                    "radius": [0.0, "30%"] as [Any],
                    "label": [
                        "position": "inner",
                        "fontSize": 14.0
                    ] as [String: Any],
                    "labelLine": [
                        "show": false
                    ] as [String: Any],
                    "data": pieNestInnerData
                ] as [String: Any],
                [
                    "name": "Access From",
                    "type": "pie",
                    "radius": ["45%", "60%"],
                    "labelLine": [
                        "length": 30.0
                    ] as [String: Any],
                    "label": [
                        // The rich-text card: `{a|…}` series name, `{abg|}` (undeclared → plain) filler,
                        // `{hr|}` rule, `{b|…}` bold item name, `{per|…}` inverted percent pill.
                        "formatter": "{a|{a}}{abg|}\n{hr|}\n  {b|{b}：}{c}  {per|{d}%}  ",
                        "backgroundColor": "#F6F8FC",
                        "borderColor": "#8C8D8E",
                        "borderWidth": 1.0,
                        "borderRadius": 4.0,
                        "rich": [
                            "a": [
                                "color": "#6E7079",
                                "lineHeight": 22.0,
                                "align": "center"
                            ] as [String: Any],
                            "hr": [
                                "borderColor": "#8C8D8E",
                                "width": "100%",
                                "borderWidth": 1.0,
                                "height": 0.0
                            ] as [String: Any],
                            "b": [
                                "color": "#4C5058",
                                "fontSize": 14.0,
                                "fontWeight": "bold",
                                "lineHeight": 33.0
                            ] as [String: Any],
                            "per": [
                                "color": "#fff",
                                "backgroundColor": "#4C5058",
                                "padding": [3.0, 4.0],
                                "borderRadius": 4.0
                            ] as [String: Any]
                        ] as [String: Any]
                    ] as [String: Any],
                    "data": pieNestOuterData
                ] as [String: Any]
            ]
        ])
}

// Inner pie (traffic source buckets); 'Marketing' ships pre-selected (offset out) under selectedMode 'single'.
private let pieNestInnerData: [[String: Any]] = [
    ["value": 1548.0, "name": "Search Engine"],
    ["value": 775.0, "name": "Direct"],
    ["value": 679.0, "name": "Marketing", "selected": true]
]

// Outer ring: the same traffic broken down one level finer.
private let pieNestOuterData: [[String: Any]] = [
    ["value": 1048.0, "name": "Baidu"],
    ["value": 335.0, "name": "Direct"],
    ["value": 310.0, "name": "Email"],
    ["value": 251.0, "name": "Google"],
    ["value": 234.0, "name": "Union Ads"],
    ["value": 147.0, "name": "Bing"],
    ["value": 135.0, "name": "Video Ads"],
    ["value": 102.0, "name": "Others"]
]
