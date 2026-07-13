// official-area-pieces — replica of https://echarts.apache.org/examples/zh/editor.html?c=area-pieces
// title: Area Pieces / titleCN: 折线图区域高亮
// A smoothed area line over a category x-axis, with a hidden `piecewise` visualMap re-colouring the
// x-index ranges (1,3) and (5,7), and a label-less markLine dropping verticals at x = 1/3/5/7.
// DEVIATIONS: none of substance — the official source is a single static `option` literal with no
// data fetch, no closures and no timers. Only the file's leading title block and the trailing
// `export {};` are dropped (a bare export is a SyntaxError in the reference pane's classic script).
extension EChartsDemoRegistry {
    static let official_area_pieces = EChartsDemo(
        name: "official-area-pieces", category: "line",
        summary: "折线图区域高亮 — Area Pieces",
        width: 640, height: 420,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
option = {
  xAxis: {
    type: 'category',
    boundaryGap: false
  },
  yAxis: {
    type: 'value',
    boundaryGap: [0, '30%']
  },
  visualMap: {
    type: 'piecewise',
    show: false,
    dimension: 0,
    seriesIndex: 0,
    pieces: [
      {
        gt: 1,
        lt: 3,
        color: 'rgba(0, 0, 180, 0.4)'
      },
      {
        gt: 5,
        lt: 7,
        color: 'rgba(0, 0, 180, 0.4)'
      }
    ]
  },
  series: [
    {
      type: 'line',
      smooth: 0.6,
      symbol: 'none',
      lineStyle: {
        color: '#5470C6',
        width: 5
      },
      markLine: {
        symbol: ['none', 'none'],
        label: { show: false },
        data: [{ xAxis: 1 }, { xAxis: 3 }, { xAxis: 5 }, { xAxis: 7 }]
      },
      areaStyle: {},
      data: [
        ['2019-10-10', 200],
        ['2019-10-11', 560],
        ['2019-10-12', 750],
        ['2019-10-13', 580],
        ['2019-10-14', 250],
        ['2019-10-15', 300],
        ['2019-10-16', 450],
        ['2019-10-17', 300],
        ['2019-10-18', 100]
      ]
    }
  ]
};
"""#,
        option: [
            "xAxis": [
                "type": "category",
                "boundaryGap": false
            ] as [String: Any],
            "yAxis": [
                "type": "value",
                "boundaryGap": [0.0, "30%"] as [Any]
            ] as [String: Any],
            "visualMap": [
                "type": "piecewise",
                "show": false,
                "dimension": 0.0,
                "seriesIndex": 0.0,
                "pieces": areaPiecesPieces
            ] as [String: Any],
            "series": [
                [
                    "type": "line",
                    "smooth": 0.6,
                    "symbol": "none",
                    "lineStyle": [
                        "color": "#5470C6",
                        "width": 5.0
                    ] as [String: Any],
                    "markLine": [
                        "symbol": ["none", "none"],
                        "label": ["show": false] as [String: Any],
                        "data": areaPiecesMarkLineData
                    ] as [String: Any],
                    "areaStyle": [:] as [String: Any],
                    "data": areaPiecesData
                ] as [String: Any]
            ]
        ])
}

// The two highlighted x-index bands, keyed on dimension 0 (the category index).
private let areaPiecesPieces: [[String: Any]] = [
    ["gt": 1.0, "lt": 3.0, "color": "rgba(0, 0, 180, 0.4)"],
    ["gt": 5.0, "lt": 7.0, "color": "rgba(0, 0, 180, 0.4)"]
]

// Verticals at the band edges; both ends symbol-less and unlabelled.
private let areaPiecesMarkLineData: [[String: Any]] = [
    ["xAxis": 1.0],
    ["xAxis": 3.0],
    ["xAxis": 5.0],
    ["xAxis": 7.0]
]

// [date category, value] per point.
private let areaPiecesData: [[Any]] = [
    ["2019-10-10", 200.0],
    ["2019-10-11", 560.0],
    ["2019-10-12", 750.0],
    ["2019-10-13", 580.0],
    ["2019-10-14", 250.0],
    ["2019-10-15", 300.0],
    ["2019-10-16", 450.0],
    ["2019-10-17", 300.0],
    ["2019-10-18", 100.0]
]
