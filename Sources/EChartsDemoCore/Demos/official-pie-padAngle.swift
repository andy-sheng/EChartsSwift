// official-pie-padAngle — replica of https://echarts.apache.org/examples/zh/editor.html?c=pie-padAngle
// title: Pie with padAngle / titleCN: 饼图扇区间隙
// The same 5-slice doughnut (radius ['40%','70%']) as pie-borderRadius, but the slices are separated by
// `padAngle: 5` — a 5° gap between neighbouring sectors — instead of a white border, and each sector is
// rounded via itemStyle.borderRadius: 10. Labels are hidden until hover, where emphasis.label shows the
// slice name centered in the hole at 40px bold; labelLine is off.
// DEVIATIONS: none — the official source is a single static `option` literal with no data fetch, no
// closures and no timers, so both panes carry it verbatim (only the trailing `export {};`, a
// SyntaxError in a classic script, is dropped from webOptionJS).
extension EChartsDemoRegistry {
    static let official_pie_padangle = EChartsDemo(
        name: "official-pie-padAngle", category: "pie",
        summary: "饼图扇区间隙 — Pie with padAngle",
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
      padAngle: 5,
      itemStyle: {
        borderRadius: 10,
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
                    "padAngle": 5.0,
                    "itemStyle": [
                        "borderRadius": 10.0
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
                    "data": piePadAngleData
                ] as [String: Any]
            ]
        ])
}

// The 5 traffic-source slices; hoisted out of the option literal to keep the type-checker fast.
private let piePadAngleData: [[String: Any]] = [
    ["value": 1048.0, "name": "Search Engine"],
    ["value": 735.0, "name": "Direct"],
    ["value": 580.0, "name": "Email"],
    ["value": 484.0, "name": "Union Ads"],
    ["value": 300.0, "name": "Video Ads"]
]
