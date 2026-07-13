// official-radar2 — replica of https://echarts.apache.org/examples/zh/editor.html?c=radar2
// title: Proportion of Browsers / titleCN: 浏览器占比变化
// 28 single-datum radar series (one per year 2001..2028) over a 5-indicator radar (IE8-, IE9+,
// Safari, Firefox, Chrome), coloured red→yellow by a calculable continuous visualMap, with a
// scrolling legend of the years. Fake, formula-generated data.
// DEVIATIONS:
//   - webOptionJS: the TypeScript-only bits are stripped — the `as echarts.RadarSeriesOption` cast
//     on the series IIFE's return and the trailing `export {};` (both are SyntaxErrors in the
//     classic script the reference pane runs). Everything else, including both IIFEs, is verbatim.
//   - option (native): the `legend.data` and `series` IIFEs are evaluated at build time into the
//     file-scope `radar2Years` / `radar2Series` literals below — same loops, same values.
extension EChartsDemoRegistry {
    static let official_radar2 = EChartsDemo(
        name: "official-radar2", category: "radar",
        summary: "浏览器占比变化 — Proportion of Browsers",
        width: 640, height: 420,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
option = {
  title: {
    text: 'Proportion of Browsers',
    subtext: 'Fake Data',
    top: 10,
    left: 10
  },
  tooltip: {
    trigger: 'item'
  },
  legend: {
    type: 'scroll',
    bottom: 10,
    data: (function () {
      var list = [];
      for (var i = 1; i <= 28; i++) {
        list.push(i + 2000 + '');
      }
      return list;
    })()
  },
  visualMap: {
    top: 'middle',
    right: 10,
    inRange: {
      color: ['red', 'yellow']
    },
    calculable: true
  },
  radar: {
    indicator: [
      { text: 'IE8-', max: 400 },
      { text: 'IE9+', max: 400 },
      { text: 'Safari', max: 400 },
      { text: 'Firefox', max: 400 },
      { text: 'Chrome', max: 400 }
    ]
  },
  series: (function () {
    var series = [];
    for (var i = 1; i <= 28; i++) {
      series.push({
        type: 'radar',
        symbol: 'none',
        lineStyle: {
          width: 1
        },
        emphasis: {
          areaStyle: {
            color: 'rgba(0,250,0,0.3)'
          }
        },
        data: [
          {
            value: [
              (40 - i) * 10,
              (38 - i) * 4 + 60,
              i * 5 + 10,
              i * 9,
              (i * i) / 2
            ],
            name: i + 2000 + ''
          }
        ]
      });
    }
    return series;
  })()
};
"""#,
        option: [
            "title": [
                "text": "Proportion of Browsers",
                "subtext": "Fake Data",
                "top": 10.0,
                "left": 10.0
            ] as [String: Any],
            "tooltip": [
                "trigger": "item"
            ] as [String: Any],
            "legend": [
                "type": "scroll",
                "bottom": 10.0,
                "data": radar2Years
            ] as [String: Any],
            "visualMap": [
                "top": "middle",
                "right": 10.0,
                "inRange": [
                    "color": ["red", "yellow"]
                ] as [String: Any],
                "calculable": true
            ] as [String: Any],
            "radar": [
                "indicator": radar2Indicator
            ] as [String: Any],
            "series": radar2Series
        ])
}

// legend.data — the years 2001..2028, i.e. the official `list.push(i + 2000 + '')` loop.
private let radar2Years: [String] = (1...28).map { String($0 + 2000) }

// `text` is the deprecated-but-supported alias for an indicator's `name`; kept as the source has it.
private let radar2Indicator: [[String: Any]] = [
    ["text": "IE8-", "max": 400.0],
    ["text": "IE9+", "max": 400.0],
    ["text": "Safari", "max": 400.0],
    ["text": "Firefox", "max": 400.0],
    ["text": "Chrome", "max": 400.0]
]

// One radar series per year; the value tuple is the official formula
// [(40-i)*10, (38-i)*4+60, i*5+10, i*9, i*i/2] over the 5 indicators.
private let radar2Series: [[String: Any]] = (1...28).map { i -> [String: Any] in
    let d = Double(i)
    let value: [Double] = [
        (40.0 - d) * 10.0,
        (38.0 - d) * 4.0 + 60.0,
        d * 5.0 + 10.0,
        d * 9.0,
        (d * d) / 2.0
    ]
    return [
        "type": "radar",
        "symbol": "none",
        "lineStyle": [
            "width": 1.0
        ] as [String: Any],
        "emphasis": [
            "areaStyle": [
                "color": "rgba(0,250,0,0.3)"
            ] as [String: Any]
        ] as [String: Any],
        "data": [
            [
                "value": value,
                "name": String(i + 2000)
            ] as [String: Any]
        ]
    ]
}
