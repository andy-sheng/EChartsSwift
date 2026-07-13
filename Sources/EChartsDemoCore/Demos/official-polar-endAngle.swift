// official-polar-endAngle — replica of https://echarts.apache.org/examples/zh/editor.html?c=polar-endAngle
// title: Polar endAngle / titleCN: 极坐标系 endAngle
// Two polar coordinate systems, each a quadrant carved out by an angleAxis startAngle/endAngle pair
// (90°→0° and -90°→-180°), each carrying its own category angleAxis + bar series.
// DEVIATIONS: none — the official source is a single static `option` literal with no data fetch,
// no closures and no timers, so both panes carry it verbatim.
extension EChartsDemoRegistry {
    static let official_polar_endangle = EChartsDemo(
        name: "official-polar-endAngle", category: "bar",
        summary: "极坐标系 endAngle — Polar endAngle",
        width: 640, height: 420,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
option = {
  tooltip: {},
  angleAxis: [
    {
      type: 'category',
      polarIndex: 0,
      startAngle: 90,
      endAngle: 0,
      data: ['S1', 'S2', 'S3']
    },
    {
      type: 'category',
      polarIndex: 1,
      startAngle: -90,
      endAngle: -180,
      data: ['T1', 'T2', 'T3']
    }
  ],
  radiusAxis: [{ polarIndex: 0 }, { polarIndex: 1 }],
  polar: [{}, {}],
  series: [
    {
      type: 'bar',
      polarIndex: 0,
      data: [1, 2, 3],
      coordinateSystem: 'polar'
    },
    {
      type: 'bar',
      polarIndex: 1,
      data: [1, 2, 3],
      coordinateSystem: 'polar'
    }
  ]
};
"""#,
        option: [
            "tooltip": [:] as [String: Any],
            "angleAxis": [
                [
                    "type": "category",
                    "polarIndex": 0.0,
                    "startAngle": 90.0,
                    "endAngle": 0.0,
                    "data": ["S1", "S2", "S3"]
                ] as [String: Any],
                [
                    "type": "category",
                    "polarIndex": 1.0,
                    "startAngle": -90.0,
                    "endAngle": -180.0,
                    "data": ["T1", "T2", "T3"]
                ] as [String: Any]
            ],
            "radiusAxis": [
                ["polarIndex": 0.0] as [String: Any],
                ["polarIndex": 1.0] as [String: Any]
            ],
            "polar": [
                [:] as [String: Any],
                [:] as [String: Any]
            ],
            "series": [
                [
                    "type": "bar",
                    "polarIndex": 0.0,
                    "data": [1.0, 2.0, 3.0],
                    "coordinateSystem": "polar"
                ] as [String: Any],
                [
                    "type": "bar",
                    "polarIndex": 1.0,
                    "data": [1.0, 2.0, 3.0],
                    "coordinateSystem": "polar"
                ] as [String: Any]
            ]
        ])
}
