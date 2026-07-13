// official-line-in-cartesian-coordinate-system — replica of
// https://echarts.apache.org/examples/zh/editor.html?c=line-in-cartesian-coordinate-system
// title: Line Chart in Cartesian Coordinate System / titleCN: 双数值轴折线图
// A 3-point line series on two implicit VALUE axes (`xAxis: {}` / `yAxis: {}`), so each datum is an
// [x, y] pair rather than an index into a category axis.
// DEVIATIONS: none — the official source is a single static `option` literal with no data fetch, no
// closures and no timers. The source's trailing `export {};` is dropped from webOptionJS (a bare
// export is a SyntaxError in the page's classic script and would kill the whole pane).
extension EChartsDemoRegistry {
    static let official_line_in_cartesian_coordinate_system = EChartsDemo(
        name: "official-line-in-cartesian-coordinate-system", category: "line",
        summary: "双数值轴折线图 — Line Chart in Cartesian Coordinate System",
        width: 640, height: 420,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
option = {
  xAxis: {},
  yAxis: {},
  series: [
    {
      data: [
        [10, 40],
        [50, 100],
        [40, 20]
      ],
      type: 'line'
    }
  ]
};
"""#,
        option: [
            "xAxis": [:] as [String: Any],
            "yAxis": [:] as [String: Any],
            "series": [
                [
                    "data": lineInCartesianCoordinateSystemData,
                    "type": "line"
                ] as [String: Any]
            ]
        ])
}

// [x, y] pairs on two value axes.
private let lineInCartesianCoordinateSystemData: [[Double]] = [
    [10, 40],
    [50, 100],
    [40, 20]
]
