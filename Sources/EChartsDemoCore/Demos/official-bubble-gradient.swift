// official-bubble-gradient — replica of https://echarts.apache.org/examples/zh/editor.html?c=bubble-gradient
// title: Bubble Chart / titleCN: 气泡图
//
// Two scatter series (1990 / 2015) of GDP-per-capita (x) against life expectancy (y) for 19 countries,
// each bubble sized by sqrt(population)/500 and filled with a RadialGradient (red ramp for 1990, cyan
// ramp for 2015) plus a coloured drop shadow; the canvas itself carries a RadialGradient background.
//
// DEVIATIONS from the official source:
//   1. The trailing `export {};` is dropped — a bare export is a SyntaxError in the reference pane's
//      classic script.
//   2. The two `formatter: function (param: any)` signatures lose their TypeScript `: any` annotation
//      in webOptionJS. The official editor compiles TS; the reference pane runs the snippet as plain
//      JS, where `param: any` is a SyntaxError that would blank the whole page. Nothing else changes.
//   3. The Swift option spells the three gradients as the plain-object form
//      (`{type:'radial', x:.., y:.., r:.., colorStops:[...]}`) instead of
//      `new echarts.graphic.RadialGradient(x, y, r, [...])` — echarts accepts both, and it is the only
//      form a `[String: Any]` can carry. webOptionJS keeps the `new echarts.graphic...` calls verbatim.
//   4. The Swift option omits the two JS closures (`symbolSize` and `emphasis.label.formatter`) — see
//      the PORT-NOTE lines where they would have gone.
//   5. NATIVE PANE (renders, but three visual gaps — all pre-existing framework limits, none of them
//      specific to this demo):
//        * the bubbles are all the DEFAULT symbol size (10px), not population-scaled: `symbolSize` is
//          a JS closure the Swift option cannot carry (deviation 4).
//        * the two item gradients do not render. EChartsKit's `barStyleFromDict` (BarView.swift, also
//          used by SymbolElement for scatter) bridges only SOLID colors to the ZRenderKit path style,
//          so a gradient fill is dropped and the symbols fall back to the palette/default fill. The
//          shadowBlur/shadowColor/shadowOffsetY beside it DO bridge. Same gap as official-bar-gradient.
//        * the gradient `backgroundColor` is ignored: `ECharts.render` reads the top-level
//          backgroundColor as `as? String` only, so a gradient object yields no background rect and
//          the native canvas stays white.
//      Geometry (the two point clouds, the dashed splitLines, the scaled y-axis, title and legend) match.

extension EChartsDemoRegistry {
    static let official_bubble_gradient = EChartsDemo(
        name: "official-bubble-gradient", category: "scatter",
        summary: "气泡图 — Bubble Chart",
        width: 640, height: 420,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
const data = [
  [
    [28604, 77, 17096869, 'Australia', 1990],
    [31163, 77.4, 27662440, 'Canada', 1990],
    [1516, 68, 1154605773, 'China', 1990],
    [13670, 74.7, 10582082, 'Cuba', 1990],
    [28599, 75, 4986705, 'Finland', 1990],
    [29476, 77.1, 56943299, 'France', 1990],
    [31476, 75.4, 78958237, 'Germany', 1990],
    [28666, 78.1, 254830, 'Iceland', 1990],
    [1777, 57.7, 870601776, 'India', 1990],
    [29550, 79.1, 122249285, 'Japan', 1990],
    [2076, 67.9, 20194354, 'North Korea', 1990],
    [12087, 72, 42972254, 'South Korea', 1990],
    [24021, 75.4, 3397534, 'New Zealand', 1990],
    [43296, 76.8, 4240375, 'Norway', 1990],
    [10088, 70.8, 38195258, 'Poland', 1990],
    [19349, 69.6, 147568552, 'Russia', 1990],
    [10670, 67.3, 53994605, 'Turkey', 1990],
    [26424, 75.7, 57110117, 'United Kingdom', 1990],
    [37062, 75.4, 252847810, 'United States', 1990]
  ],
  [
    [44056, 81.8, 23968973, 'Australia', 2015],
    [43294, 81.7, 35939927, 'Canada', 2015],
    [13334, 76.9, 1376048943, 'China', 2015],
    [21291, 78.5, 11389562, 'Cuba', 2015],
    [38923, 80.8, 5503457, 'Finland', 2015],
    [37599, 81.9, 64395345, 'France', 2015],
    [44053, 81.1, 80688545, 'Germany', 2015],
    [42182, 82.8, 329425, 'Iceland', 2015],
    [5903, 66.8, 1311050527, 'India', 2015],
    [36162, 83.5, 126573481, 'Japan', 2015],
    [1390, 71.4, 25155317, 'North Korea', 2015],
    [34644, 80.7, 50293439, 'South Korea', 2015],
    [34186, 80.6, 4528526, 'New Zealand', 2015],
    [64304, 81.6, 5210967, 'Norway', 2015],
    [24787, 77.3, 38611794, 'Poland', 2015],
    [23038, 73.13, 143456918, 'Russia', 2015],
    [19360, 76.5, 78665830, 'Turkey', 2015],
    [38225, 81.4, 64715810, 'United Kingdom', 2015],
    [53354, 79.1, 321773631, 'United States', 2015]
  ]
];

option = {
  backgroundColor: new echarts.graphic.RadialGradient(0.3, 0.3, 0.8, [
    {
      offset: 0,
      color: '#f7f8fa'
    },
    {
      offset: 1,
      color: '#cdd0d5'
    }
  ]),
  title: {
    text: 'Life Expectancy and GDP by Country',
    left: '5%',
    top: '3%'
  },
  legend: {
    right: '10%',
    top: '3%',
    data: ['1990', '2015']
  },
  grid: {
    left: '8%',
    top: '10%'
  },
  xAxis: {
    splitLine: {
      lineStyle: {
        type: 'dashed'
      }
    }
  },
  yAxis: {
    splitLine: {
      lineStyle: {
        type: 'dashed'
      }
    },
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
        focus: 'series',
        label: {
          show: true,
          formatter: function (param) {
            return param.data[3];
          },
          position: 'top'
        }
      },
      itemStyle: {
        shadowBlur: 10,
        shadowColor: 'rgba(120, 36, 50, 0.5)',
        shadowOffsetY: 5,
        color: new echarts.graphic.RadialGradient(0.4, 0.3, 1, [
          {
            offset: 0,
            color: 'rgb(251, 118, 123)'
          },
          {
            offset: 1,
            color: 'rgb(204, 46, 72)'
          }
        ])
      }
    },
    {
      name: '2015',
      data: data[1],
      type: 'scatter',
      symbolSize: function (data) {
        return Math.sqrt(data[2]) / 5e2;
      },
      emphasis: {
        focus: 'series',
        label: {
          show: true,
          formatter: function (param) {
            return param.data[3];
          },
          position: 'top'
        }
      },
      itemStyle: {
        shadowBlur: 10,
        shadowColor: 'rgba(25, 100, 150, 0.5)',
        shadowOffsetY: 5,
        color: new echarts.graphic.RadialGradient(0.4, 0.3, 1, [
          {
            offset: 0,
            color: 'rgb(129, 227, 238)'
          },
          {
            offset: 1,
            color: 'rgb(25, 183, 207)'
          }
        ])
      }
    }
  ]
};
"""#,
        option: [
            "backgroundColor": bubbleGradientBackground,
            "title": [
                "text": "Life Expectancy and GDP by Country",
                "left": "5%",
                "top": "3%"
            ] as [String: Any],
            "legend": [
                "right": "10%",
                "top": "3%",
                "data": ["1990", "2015"]
            ] as [String: Any],
            "grid": [
                "left": "8%",
                "top": "10%"
            ] as [String: Any],
            "xAxis": [
                "splitLine": [
                    "lineStyle": [
                        "type": "dashed"
                    ] as [String: Any]
                ] as [String: Any]
            ] as [String: Any],
            "yAxis": [
                "splitLine": [
                    "lineStyle": [
                        "type": "dashed"
                    ] as [String: Any]
                ] as [String: Any],
                "scale": true
            ] as [String: Any],
            "series": [
                [
                    "name": "1990",
                    "data": bubbleGradientData1990,
                    "type": "scatter",
                    // PORT-NOTE: symbolSize omitted — the JS closure sized each bubble by its population:
                    //   `Math.sqrt(data[2]) / 5e2`. Native bubbles use the default symbol size.
                    "emphasis": [
                        "focus": "series",
                        "label": [
                            "show": true,
                            // PORT-NOTE: formatter omitted — the JS closure returned `param.data[3]`,
                            //   the country name, as the hover label.
                            "position": "top"
                        ] as [String: Any]
                    ] as [String: Any],
                    "itemStyle": [
                        "shadowBlur": 10.0,
                        "shadowColor": "rgba(120, 36, 50, 0.5)",
                        "shadowOffsetY": 5.0,
                        "color": bubbleGradient1990Fill
                    ] as [String: Any]
                ] as [String: Any],
                [
                    "name": "2015",
                    "data": bubbleGradientData2015,
                    "type": "scatter",
                    // PORT-NOTE: symbolSize omitted — same population-scaling closure as the 1990 series.
                    "emphasis": [
                        "focus": "series",
                        "label": [
                            "show": true,
                            // PORT-NOTE: formatter omitted — same `param.data[3]` (country name) closure.
                            "position": "top"
                        ] as [String: Any]
                    ] as [String: Any],
                    "itemStyle": [
                        "shadowBlur": 10.0,
                        "shadowColor": "rgba(25, 100, 150, 0.5)",
                        "shadowOffsetY": 5.0,
                        "color": bubbleGradient2015Fill
                    ] as [String: Any]
                ] as [String: Any]
            ] as [Any]
        ])
}

// MARK: - file-scope data (hoisted + explicitly typed: 19-row heterogeneous literals inline stall the type-checker)

// [GDP per capita, life expectancy, population, country, year] per bubble.
private let bubbleGradientData1990: [[Any]] = [
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

private let bubbleGradientData2015: [[Any]] = [
    [44056.0, 81.8, 23968973.0, "Australia", 2015.0],
    [43294.0, 81.7, 35939927.0, "Canada", 2015.0],
    [13334.0, 76.9, 1376048943.0, "China", 2015.0],
    [21291.0, 78.5, 11389562.0, "Cuba", 2015.0],
    [38923.0, 80.8, 5503457.0, "Finland", 2015.0],
    [37599.0, 81.9, 64395345.0, "France", 2015.0],
    [44053.0, 81.1, 80688545.0, "Germany", 2015.0],
    [42182.0, 82.8, 329425.0, "Iceland", 2015.0],
    [5903.0, 66.8, 1311050527.0, "India", 2015.0],
    [36162.0, 83.5, 126573481.0, "Japan", 2015.0],
    [1390.0, 71.4, 25155317.0, "North Korea", 2015.0],
    [34644.0, 80.7, 50293439.0, "South Korea", 2015.0],
    [34186.0, 80.6, 4528526.0, "New Zealand", 2015.0],
    [64304.0, 81.6, 5210967.0, "Norway", 2015.0],
    [24787.0, 77.3, 38611794.0, "Poland", 2015.0],
    [23038.0, 73.13, 143456918.0, "Russia", 2015.0],
    [19360.0, 76.5, 78665830.0, "Turkey", 2015.0],
    [38225.0, 81.4, 64715810.0, "United Kingdom", 2015.0],
    [53354.0, 79.1, 321773631.0, "United States", 2015.0]
]

/// `new echarts.graphic.RadialGradient(x, y, r, stops)` in plain-object form (deviation 3).
private func bubbleGradientRadial(_ x: Double, _ y: Double, _ r: Double,
                                  _ stops: [(Double, String)]) -> [String: Any] {
    [
        "type": "radial",
        "x": x, "y": y, "r": r,
        "colorStops": stops.map { ["offset": $0.0, "color": $0.1] as [String: Any] } as [Any]
    ]
}

private let bubbleGradientBackground: [String: Any] = bubbleGradientRadial(0.3, 0.3, 0.8, [
    (0.0, "#f7f8fa"), (1.0, "#cdd0d5")
])

private let bubbleGradient1990Fill: [String: Any] = bubbleGradientRadial(0.4, 0.3, 1.0, [
    (0.0, "rgb(251, 118, 123)"), (1.0, "rgb(204, 46, 72)")
])

private let bubbleGradient2015Fill: [String: Any] = bubbleGradientRadial(0.4, 0.3, 1.0, [
    (0.0, "rgb(129, 227, 238)"), (1.0, "rgb(25, 183, 207)")
])
