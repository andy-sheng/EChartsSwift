// official-pie-doughnut — replica of https://echarts.apache.org/examples/zh/editor.html?c=pie-doughnut
// title: Doughnut Chart / titleCN: 环形图
// A single pie series with an inner radius (radius: ['40%','70%']); slice labels are hidden and only
// re-appear, centered and large, on hover (emphasis.label). Top-center legend, item tooltip.
// DEVIATIONS: none of substance — the official source is one static `option` literal with no data
// fetch, no closures and no timers, so both panes carry it verbatim. Only the trailing `export {};`
// is dropped (a bare export is a SyntaxError in the reference pane's classic script).
extension EChartsDemoRegistry {
    static let official_pie_doughnut = EChartsDemo(
        name: "official-pie-doughnut", category: "pie",
        summary: "环形图 — Doughnut Chart",
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
                    "data": pieDoughnutData
                ] as [String: Any]
            ]
        ])
}

private let pieDoughnutData: [[String: Any]] = [
    ["value": 1048.0, "name": "Search Engine"],
    ["value": 735.0, "name": "Direct"],
    ["value": 580.0, "name": "Email"],
    ["value": 484.0, "name": "Union Ads"],
    ["value": 300.0, "name": "Video Ads"]
]
