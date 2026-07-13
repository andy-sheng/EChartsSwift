// official-scatter-label-align-top — replica of https://echarts.apache.org/examples/zh/editor.html?c=scatter-label-align-top
// title: Align Label on the Top / titleCN: 散点图标签顶部对齐
// GDP-per-capita (x) vs life-expectancy (y) bubbles for 19 countries in 1990, each labelled with its
// country name pinned above the symbol: `label.position: 'top'` + `labelLayout` (y: 20, align: 'center',
// hideOverlap, moveOverlap: 'shiftX') pushes every label onto one top band and de-overlaps it, with a
// leader `labelLine` back to the bubble.
// DEVIATIONS from the official source:
//   - The official source's `data` holds two year-slices (1990, 2015) but the option only ever plots
//     data[0]; webOptionJS keeps both verbatim, the native pane inlines only the 1990 slice it uses.
//   - `export {};` and the TS parameter annotation (`param: any`) are stripped from webOptionJS — both
//     are SyntaxErrors in the reference pane's classic script.
//   - NATIVE PANE: `series.symbolSize` (a JS closure) and `label.formatter` (ditto) are omitted, so the
//     native bubbles are all the default size and the labels show the default value text instead of the
//     country name. See the PORT-NOTEs. Everything else is identical.
extension EChartsDemoRegistry {
    static let official_scatter_label_align_top = EChartsDemo(
        name: "official-scatter-label-align-top", category: "scatter",
        summary: "散点图标签顶部对齐 — Align Label on the Top",
        width: 640, height: 420,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
// prettier-ignore
const data = [
  [[28604,77,17096869,'Australia',1990],[31163,77.4,27662440,'Canada',1990],[1516,68,1154605773,'China',1990],[13670,74.7,10582082,'Cuba',1990],[28599,75,4986705,'Finland',1990],[29476,77.1,56943299,'France',1990],[31476,75.4,78958237,'Germany',1990],[28666,78.1,254830,'Iceland',1990],[1777,57.7,870601776,'India',1990],[29550,79.1,122249285,'Japan',1990],[2076,67.9,20194354,'North Korea',1990],[12087,72,42972254,'South Korea',1990],[24021,75.4,3397534,'New Zealand',1990],[43296,76.8,4240375,'Norway',1990],[10088,70.8,38195258,'Poland',1990],[19349,69.6,147568552,'Russia',1990],[10670,67.3,53994605,'Turkey',1990],[26424,75.7,57110117,'United Kingdom',1990],[37062,75.4,252847810,'United States',1990]],
  [[44056,81.8,23968973,'Australia',2015],[43294,81.7,35939927,'Canada',2015],[13334,76.9,1376048943,'China',2015],[21291,78.5,11389562,'Cuba',2015],[38923,80.8,5503457,'Finland',2015],[37599,81.9,64395345,'France',2015],[44053,81.1,80688545,'Germany',2015],[42182,82.8,329425,'Iceland',2015],[5903,66.8,1311050527,'India',2015],[36162,83.5,126573481,'Japan',2015],[1390,71.4,25155317,'North Korea',2015],[34644,80.7,50293439,'South Korea',2015],[34186,80.6,4528526,'New Zealand',2015],[64304,81.6,5210967,'Norway',2015],[24787,77.3,38611794,'Poland',2015],[23038,73.13,143456918,'Russia',2015],[19360,76.5,78665830,'Turkey',2015],[38225,81.4,64715810,'United Kingdom',2015],[53354,79.1,321773631,'United States',2015]]
];

option = {
  xAxis: {},
  yAxis: {
    scale: true
  },
  series: [
    {
      name: '1990',
      data: data[0],
      type: 'scatter',
      symbolSize: function (data) {
        return Math.sqrt(data[2]) / 5e2;
      },
      emphasis: {
        focus: 'self'
      },
      labelLayout: {
        y: 20,
        align: 'center',
        hideOverlap: true,
        moveOverlap: 'shiftX'
      },
      labelLine: {
        show: true,
        length2: 5,
        lineStyle: {
          color: '#bbb'
        }
      },
      label: {
        show: true,
        formatter: function (param) {
          return param.data[3];
        },
        minMargin: 10,
        position: 'top'
      }
    }
  ]
};
"""#,
        option: [
            "xAxis": [:] as [String: Any],
            "yAxis": [
                "scale": true
            ] as [String: Any],
            "series": [
                [
                    "name": "1990",
                    "data": scatterLabelAlignTop1990Data,
                    "type": "scatter",
                    // PORT-NOTE: symbolSize omitted — the JS closure sized each bubble by population,
                    // `Math.sqrt(data[2]) / 5e2`; Swift cannot carry a closure, so the native pane uses
                    // the default symbol size and every bubble is the same radius.
                    "emphasis": [
                        "focus": "self"
                    ] as [String: Any],
                    "labelLayout": [
                        "y": 20.0,
                        "align": "center",
                        "hideOverlap": true,
                        "moveOverlap": "shiftX"
                    ] as [String: Any],
                    "labelLine": [
                        "show": true,
                        "length2": 5.0,
                        "lineStyle": [
                            "color": "#bbb"
                        ] as [String: Any]
                    ] as [String: Any],
                    "label": [
                        "show": true,
                        // PORT-NOTE: label.formatter omitted — the JS closure returned `param.data[3]`,
                        // the country name (dimension 3); without it the native labels fall back to the
                        // default series-value text.
                        "minMargin": 10.0,
                        "position": "top"
                    ] as [String: Any]
                ] as [String: Any]
            ]
        ])
}

// The 1990 slice of the official `data` (the only one the option plots):
// [GDP per capita, life expectancy, population, country, year].
private let scatterLabelAlignTop1990Data: [[Any]] = [
    [28604.0, 77.0, 17096869.0, "Australia", 1990.0],
    [31163.0, 77.4, 27662440.0, "Canada", 1990.0],
    [1516.0, 68.0, 1154605773.0, "China", 1990.0],
    [13670.0, 74.7, 10582082.0, "Cuba", 1990.0],
    [28599.0, 75.0, 4986705.0, "Finland", 1990.0],
    [29476.0, 77.1, 56943299.0, "France", 1990.0],
    [31476.0, 75.4, 78958237.0, "Germany", 1990.0],
    [28666.0, 78.1, 254830.0, "Iceland", 1990.0],
    [1777.0, 57.7, 870601776.0, "India", 1990.0],
    [29550.0, 79.1, 122249285.0, "Japan", 1990.0],
    [2076.0, 67.9, 20194354.0, "North Korea", 1990.0],
    [12087.0, 72.0, 42972254.0, "South Korea", 1990.0],
    [24021.0, 75.4, 3397534.0, "New Zealand", 1990.0],
    [43296.0, 76.8, 4240375.0, "Norway", 1990.0],
    [10088.0, 70.8, 38195258.0, "Poland", 1990.0],
    [19349.0, 69.6, 147568552.0, "Russia", 1990.0],
    [10670.0, 67.3, 53994605.0, "Turkey", 1990.0],
    [26424.0, 75.7, 57110117.0, "United Kingdom", 1990.0],
    [37062.0, 75.4, 252847810.0, "United States", 1990.0]
]
