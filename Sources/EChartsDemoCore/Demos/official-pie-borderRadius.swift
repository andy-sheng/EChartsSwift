// official-pie-borderRadius — replica of https://echarts.apache.org/examples/zh/editor.html?c=pie-borderRadius
// title: Doughnut Chart with Rounded Corner / titleCN: 圆角环形图
// A 5-slice doughnut (radius ['40%','70%']) whose sectors carry itemStyle.borderRadius: 10 plus a 2px
// white border, so each slice reads as a separate rounded pill. Labels are hidden until hover, where
// emphasis.label shows the slice name centered in the hole at 40px bold; labelLine is off.
// DEVIATIONS: none — the official source is a single static `option` literal with no data fetch, no
// closures and no timers, so both panes carry it verbatim (only the trailing `export {};`, a
// SyntaxError in a classic script, is dropped from webOptionJS).
extension EChartsDemoRegistry {
    static let official_pie_borderradius = EChartsDemo(
        name: "official-pie-borderRadius", category: "pie",
        summary: "圆角环形图 — Doughnut Chart with Rounded Corner",
        width: 640, height: 420,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
option = {
  tooltip: {
    trigger: 'item'
  },
  legend: {
    top: '5%',
    left: 'center'
  },
  series: [
    {
      name: 'Access From',
      type: 'pie',
      radius: ['40%', '70%'],
      avoidLabelOverlap: false,
      itemStyle: {
        borderRadius: 10,
        borderColor: '#fff',
        borderWidth: 2
      },
      label: {
        show: false,
        position: 'center'
      },
      emphasis: {
        label: {
          show: true,
          fontSize: 40,
          fontWeight: 'bold'
        }
      },
      labelLine: {
        show: false
      },
      data: [
        { value: 1048, name: 'Search Engine' },
        { value: 735, name: 'Direct' },
        { value: 580, name: 'Email' },
        { value: 484, name: 'Union Ads' },
        { value: 300, name: 'Video Ads' }
      ]
    }
  ]
};
"""#,
        option: [
            "tooltip": [
                "trigger": "item"
            ] as [String: Any],
            "legend": [
                "top": "5%",
                "left": "center"
            ] as [String: Any],
            "series": [
                [
                    "name": "Access From",
                    "type": "pie",
                    "radius": ["40%", "70%"],
                    "avoidLabelOverlap": false,
                    "itemStyle": [
                        "borderRadius": 10.0,
                        "borderColor": "#fff",
                        "borderWidth": 2.0
                    ] as [String: Any],
                    "label": [
                        "show": false,
                        "position": "center"
                    ] as [String: Any],
                    "emphasis": [
                        "label": [
                            "show": true,
                            "fontSize": 40.0,
                            "fontWeight": "bold"
                        ] as [String: Any]
                    ] as [String: Any],
                    "labelLine": [
                        "show": false
                    ] as [String: Any],
                    "data": pieBorderRadiusData
                ] as [String: Any]
            ]
        ])
}

// The 5 traffic-source slices; hoisted out of the option literal to keep the type-checker fast.
private let pieBorderRadiusData: [[String: Any]] = [
    ["value": 1048.0, "name": "Search Engine"],
    ["value": 735.0, "name": "Direct"],
    ["value": 580.0, "name": "Email"],
    ["value": 484.0, "name": "Union Ads"],
    ["value": 300.0, "name": "Video Ads"]
]
