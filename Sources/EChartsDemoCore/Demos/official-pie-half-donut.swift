// official-pie-half-donut — replica of https://echarts.apache.org/examples/zh/editor.html?c=pie-half-donut
// title: Half Doughnut Chart / titleCN: 半环形图
// A doughnut pie (radius 40%–70%) swept from startAngle 180 to endAngle 360, i.e. only the upper
// half of the ring is drawn; center is pushed down to 70% so the half-ring sits in the canvas.
// Requires echarts >= 5.5.0 (endAngle on the pie series).
// DEVIATIONS: none — the official source is a single static `option` literal with no data fetch,
// no closures and no timers, so both panes carry it verbatim (minus the trailing `export {};`,
// which is a SyntaxError in the reference pane's classic script).
extension EChartsDemoRegistry {
    static let official_pie_half_donut = EChartsDemo(
        name: "official-pie-half-donut", category: "pie",
        summary: "半环形图 — Half Doughnut Chart",
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
      center: ['50%', '70%'],
      // adjust the start and end angle
      startAngle: 180,
      endAngle: 360,
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
                    "center": ["50%", "70%"],
                    // adjust the start and end angle
                    "startAngle": 180.0,
                    "endAngle": 360.0,
                    "data": pieHalfDonutData
                ] as [String: Any]
            ]
        ])
}

private let pieHalfDonutData: [[String: Any]] = [
    ["value": 1048.0, "name": "Search Engine"],
    ["value": 735.0, "name": "Direct"],
    ["value": 580.0, "name": "Email"],
    ["value": 484.0, "name": "Union Ads"],
    ["value": 300.0, "name": "Video Ads"]
]
