// official-pie-simple — replica of https://echarts.apache.org/examples/zh/editor.html?c=pie-simple
// title: Referer of a Website / titleCN: 某站点用户访问来源
// A single-series pie: 5 traffic-source slices, centered title, vertical legend on the left, and a
// shadow emphasis state on hover.
// DEVIATIONS from the official source: none — the example is a static, self-contained option with no
// data fetch, no JS closures and no animation-driven behaviour, so webOptionJS is verbatim and the
// Swift option is a 1:1 translation.
extension EChartsDemoRegistry {
    static let official_pie_simple = EChartsDemo(
        name: "official-pie-simple", category: "pie",
        summary: "某站点用户访问来源 — Referer of a Website",
        width: 640, height: 420,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
option = {
  title: {
    text: 'Referer of a Website',
    subtext: 'Fake Data',
    left: 'center'
  },
  tooltip: {
    trigger: 'item'
  },
  legend: {
    orient: 'vertical',
    left: 'left'
  },
  series: [
    {
      name: 'Access From',
      type: 'pie',
      radius: '50%',
      data: [
        { value: 1048, name: 'Search Engine' },
        { value: 735, name: 'Direct' },
        { value: 580, name: 'Email' },
        { value: 484, name: 'Union Ads' },
        { value: 300, name: 'Video Ads' }
      ],
      emphasis: {
        itemStyle: {
          shadowBlur: 10,
          shadowOffsetX: 0,
          shadowColor: 'rgba(0, 0, 0, 0.5)'
        }
      }
    }
  ]
};
"""#,
        option: [
            "title": [
                "text": "Referer of a Website",
                "subtext": "Fake Data",
                "left": "center"
            ] as [String: Any],
            "tooltip": [
                "trigger": "item"
            ] as [String: Any],
            "legend": [
                "orient": "vertical",
                "left": "left"
            ] as [String: Any],
            "series": [
                [
                    "name": "Access From",
                    "type": "pie",
                    "radius": "50%",
                    "data": [
                        ["value": 1048.0, "name": "Search Engine"] as [String: Any],
                        ["value": 735.0, "name": "Direct"] as [String: Any],
                        ["value": 580.0, "name": "Email"] as [String: Any],
                        ["value": 484.0, "name": "Union Ads"] as [String: Any],
                        ["value": 300.0, "name": "Video Ads"] as [String: Any]
                    ],
                    "emphasis": [
                        "itemStyle": [
                            "shadowBlur": 10.0,
                            "shadowOffsetX": 0.0,
                            "shadowColor": "rgba(0, 0, 0, 0.5)"
                        ] as [String: Any]
                    ] as [String: Any]
                ] as [String: Any]
            ]
        ])
}
