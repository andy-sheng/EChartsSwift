// official-bar-data-color — replica of https://echarts.apache.org/examples/zh/editor.html?c=bar-data-color
// title: Set Style of Single Bar. / titleCN: 自定义单个柱子颜色
// A plain category bar series where ONE data item (Tue, 200) is an object carrying its own
// `itemStyle.color`, overriding the series colour for that bar only.
// DEVIATIONS: none — the official source is a single static `option` literal (no data fetch, no
// closures, no timers). Only the trailing `export {};` is dropped: a bare export is a SyntaxError
// in the reference pane's classic script.
extension EChartsDemoRegistry {
    static let official_bar_data_color = EChartsDemo(
        name: "official-bar-data-color", category: "bar",
        summary: "自定义单个柱子颜色 — Set Style of Single Bar.",
        width: 640, height: 420,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
option = {
  xAxis: {
    type: 'category',
    data: ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']
  },
  yAxis: {
    type: 'value'
  },
  series: [
    {
      data: [
        120,
        {
          value: 200,
          itemStyle: {
            color: '#505372'
          }
        },
        150,
        80,
        70,
        110,
        130
      ],
      type: 'bar'
    }
  ]
};
"""#,
        option: [
            "xAxis": [
                "type": "category",
                "data": ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
            ] as [String: Any],
            "yAxis": [
                "type": "value"
            ] as [String: Any],
            "series": [
                [
                    "data": barDataColorData,
                    "type": "bar"
                ] as [String: Any]
            ]
        ])
}

// Heterogeneous by design: plain numbers, except Tue which is an item object with its own itemStyle.
private let barDataColorData: [Any] = [
    120.0,
    [
        "value": 200.0,
        "itemStyle": [
            "color": "#505372"
        ] as [String: Any]
    ] as [String: Any],
    150.0,
    80.0,
    70.0,
    110.0,
    130.0
]
