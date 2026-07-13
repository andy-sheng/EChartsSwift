// official-polar-roundCap — replica of https://echarts.apache.org/examples/zh/editor.html?c=polar-roundCap
// title: Rounded Bar on Polar / titleCN: 圆角环形图
// Two `bar` series on a polar coord (category radiusAxis 'v'..'z', angleAxis max 2, startAngle 30),
// drawn on top of each other so the `roundCap: true` series (green border) shows its rounded end caps
// against the square-capped one (red border).
// DEVIATIONS: one, and it is cosmetic — the web pane drops the source's trailing `export {};` (a bare
// export is a SyntaxError in a classic script and would kill the page). Otherwise both panes carry the
// example verbatim: the official source is a single static `option` literal with no data fetch, no
// closures and no timers, so nothing is omitted from the native port either.
extension EChartsDemoRegistry {
    static let official_polar_roundcap = EChartsDemo(
        name: "official-polar-roundCap", category: "bar",
        summary: "圆角环形图 — Rounded Bar on Polar",
        width: 640, height: 420,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
option = {
  angleAxis: {
    max: 2,
    startAngle: 30,
    splitLine: {
      show: false
    }
  },
  radiusAxis: {
    type: 'category',
    data: ['v', 'w', 'x', 'y', 'z'],
    z: 10
  },
  polar: {},
  series: [
    {
      type: 'bar',
      data: [4, 3, 2, 1, 0],
      coordinateSystem: 'polar',
      name: 'Without Round Cap',
      itemStyle: {
        borderColor: 'red',
        opacity: 0.8,
        borderWidth: 1
      }
    },
    {
      type: 'bar',
      data: [4, 3, 2, 1, 0],
      coordinateSystem: 'polar',
      name: 'With Round Cap',
      roundCap: true,
      itemStyle: {
        borderColor: 'green',
        opacity: 0.8,
        borderWidth: 1
      }
    }
  ],
  legend: {
    show: true,
    data: ['Without Round Cap', 'With Round Cap']
  }
};
"""#,
        option: [
            "angleAxis": [
                "max": 2.0,
                "startAngle": 30.0,
                "splitLine": [
                    "show": false
                ] as [String: Any]
            ] as [String: Any],
            "radiusAxis": [
                "type": "category",
                "data": ["v", "w", "x", "y", "z"],
                "z": 10.0
            ] as [String: Any],
            "polar": [:] as [String: Any],
            "series": [
                [
                    "type": "bar",
                    "data": polarRoundCapData,
                    "coordinateSystem": "polar",
                    "name": "Without Round Cap",
                    "itemStyle": [
                        "borderColor": "red",
                        "opacity": 0.8,
                        "borderWidth": 1.0
                    ] as [String: Any]
                ] as [String: Any],
                [
                    "type": "bar",
                    "data": polarRoundCapData,
                    "coordinateSystem": "polar",
                    "name": "With Round Cap",
                    "roundCap": true,
                    "itemStyle": [
                        "borderColor": "green",
                        "opacity": 0.8,
                        "borderWidth": 1.0
                    ] as [String: Any]
                ] as [String: Any]
            ],
            "legend": [
                "show": true,
                "data": ["Without Round Cap", "With Round Cap"]
            ] as [String: Any]
        ])
}

// Bar value per radiusAxis category ('v'..'z'); both series carry the same data.
private let polarRoundCapData: [Double] = [4, 3, 2, 1, 0]
