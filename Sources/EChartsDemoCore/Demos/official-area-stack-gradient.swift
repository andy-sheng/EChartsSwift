// official-area-stack-gradient — replica of https://echarts.apache.org/examples/zh/editor.html?c=area-stack-gradient
// title: Gradient Stacked Area Chart / titleCN: 渐变堆叠面积图
//
// Five smooth line series stacked on 'Total' over a 7-day category x-axis. Each has a zero-width
// lineStyle and showSymbol:false, so the chart reads as five bands of pure areaStyle fill; every band
// is a vertical LinearGradient at opacity 0.8, and `emphasis.focus:'series'` fades the other four on
// hover. The topmost band (Line 5) also shows its data labels. Plus title, axis-trigger tooltip with a
// 'cross' axisPointer, legend and a saveAsImage toolbox.
//
// DEVIATIONS from the official source:
//   1. The trailing `export {};` is dropped — a bare export is a SyntaxError in the reference pane's
//      classic script and would kill the page. Nothing else in webOptionJS is changed: the option is
//      the official literal verbatim, `new echarts.graphic.LinearGradient(0, 0, 0, 1, stops)` included.
//   2. The Swift option spells those gradients as the plain-object form
//      (`{type:'linear', x:0, y:0, x2:0, y2:1, colorStops:[...]}`) — echarts accepts both, and it is
//      the only form a `[String: Any]` can carry.
//   3. NATIVE PANE: those gradients do not render as gradients. EChartsKit's style bridge
//      (`barStyleFromDict`, which LineView's area pass uses) bridges only solid colors — a gradient
//      fill is dropped and the band falls back to its flat series color (the `color` palette at the
//      top of the option: #80FFA5, #00DDFF, #37A2FF, #FF0087, #FFBF00). So the native pane shows five
//      FLAT stacked bands where the echarts.js pane shows five fading ones. Geometry (the smooth
//      stacked baselines), the palette, the labels, title/legend/toolbox all match.
//      This is the same gap already documented in official-area-simple.swift.
//   No closures anywhere in this example, so nothing is omitted from the Swift option.

extension EChartsDemoRegistry {
    static let official_area_stack_gradient = EChartsDemo(
        name: "official-area-stack-gradient", category: "line",
        summary: "渐变堆叠面积图 — Gradient Stacked Area Chart",
        width: 640, height: 420,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
option = {
  color: ['#80FFA5', '#00DDFF', '#37A2FF', '#FF0087', '#FFBF00'],
  title: {
    text: 'Gradient Stacked Area Chart'
  },
  tooltip: {
    trigger: 'axis',
    axisPointer: {
      type: 'cross',
      label: {
        backgroundColor: '#6a7985'
      }
    }
  },
  legend: {
    data: ['Line 1', 'Line 2', 'Line 3', 'Line 4', 'Line 5']
  },
  toolbox: {
    feature: {
      saveAsImage: {}
    }
  },
  xAxis: [
    {
      type: 'category',
      boundaryGap: false,
      data: ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']
    }
  ],
  yAxis: [
    {
      type: 'value'
    }
  ],
  series: [
    {
      name: 'Line 1',
      type: 'line',
      stack: 'Total',
      smooth: true,
      lineStyle: {
        width: 0
      },
      showSymbol: false,
      areaStyle: {
        opacity: 0.8,
        color: new echarts.graphic.LinearGradient(0, 0, 0, 1, [
          {
            offset: 0,
            color: 'rgb(128, 255, 165)'
          },
          {
            offset: 1,
            color: 'rgb(1, 191, 236)'
          }
        ])
      },
      emphasis: {
        focus: 'series'
      },
      data: [140, 232, 101, 264, 90, 340, 250]
    },
    {
      name: 'Line 2',
      type: 'line',
      stack: 'Total',
      smooth: true,
      lineStyle: {
        width: 0
      },
      showSymbol: false,
      areaStyle: {
        opacity: 0.8,
        color: new echarts.graphic.LinearGradient(0, 0, 0, 1, [
          {
            offset: 0,
            color: 'rgb(0, 221, 255)'
          },
          {
            offset: 1,
            color: 'rgb(77, 119, 255)'
          }
        ])
      },
      emphasis: {
        focus: 'series'
      },
      data: [120, 282, 111, 234, 220, 340, 310]
    },
    {
      name: 'Line 3',
      type: 'line',
      stack: 'Total',
      smooth: true,
      lineStyle: {
        width: 0
      },
      showSymbol: false,
      areaStyle: {
        opacity: 0.8,
        color: new echarts.graphic.LinearGradient(0, 0, 0, 1, [
          {
            offset: 0,
            color: 'rgb(55, 162, 255)'
          },
          {
            offset: 1,
            color: 'rgb(116, 21, 219)'
          }
        ])
      },
      emphasis: {
        focus: 'series'
      },
      data: [320, 132, 201, 334, 190, 130, 220]
    },
    {
      name: 'Line 4',
      type: 'line',
      stack: 'Total',
      smooth: true,
      lineStyle: {
        width: 0
      },
      showSymbol: false,
      areaStyle: {
        opacity: 0.8,
        color: new echarts.graphic.LinearGradient(0, 0, 0, 1, [
          {
            offset: 0,
            color: 'rgb(255, 0, 135)'
          },
          {
            offset: 1,
            color: 'rgb(135, 0, 157)'
          }
        ])
      },
      emphasis: {
        focus: 'series'
      },
      data: [220, 402, 231, 134, 190, 230, 120]
    },
    {
      name: 'Line 5',
      type: 'line',
      stack: 'Total',
      smooth: true,
      lineStyle: {
        width: 0
      },
      showSymbol: false,
      label: {
        show: true,
        position: 'top'
      },
      areaStyle: {
        opacity: 0.8,
        color: new echarts.graphic.LinearGradient(0, 0, 0, 1, [
          {
            offset: 0,
            color: 'rgb(255, 191, 0)'
          },
          {
            offset: 1,
            color: 'rgb(224, 62, 76)'
          }
        ])
      },
      emphasis: {
        focus: 'series'
      },
      data: [220, 302, 181, 234, 210, 290, 150]
    }
  ]
};
"""#,
        option: [
            "color": areaStackGradientPalette,
            "title": [
                "text": "Gradient Stacked Area Chart"
            ] as [String: Any],
            "tooltip": [
                "trigger": "axis",
                "axisPointer": [
                    "type": "cross",
                    "label": [
                        "backgroundColor": "#6a7985"
                    ] as [String: Any]
                ] as [String: Any]
            ] as [String: Any],
            "legend": [
                "data": ["Line 1", "Line 2", "Line 3", "Line 4", "Line 5"]
            ] as [String: Any],
            "toolbox": [
                "feature": [
                    "saveAsImage": [String: Any]()
                ] as [String: Any]
            ] as [String: Any],
            "xAxis": [
                [
                    "type": "category",
                    "boundaryGap": false,
                    "data": ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
                ] as [String: Any]
            ] as [Any],
            "yAxis": [
                [
                    "type": "value"
                ] as [String: Any]
            ] as [Any],
            "series": areaStackGradientSeries
        ])
}

// MARK: - file-scope data (hoisted + explicitly typed: the five series dicts inline would stall the
// type-checker on a heterogeneous literal this deeply nested).

private let areaStackGradientPalette: [String] = [
    "#80FFA5", "#00DDFF", "#37A2FF", "#FF0087", "#FFBF00"
]

/// One stacked band. `from`/`to` are the vertical gradient's top and bottom stops — the plain-object
/// spelling of `new echarts.graphic.LinearGradient(0, 0, 0, 1, [...])` (deviation 2 in the header).
/// `showLabel` is true only for Line 5, matching the official source.
private func areaStackGradientBand(name: String, from: String, to: String,
                                   data: [Double], showLabel: Bool = false) -> [String: Any] {
    var band: [String: Any] = [
        "name": name,
        "type": "line",
        "stack": "Total",
        "smooth": true,
        "lineStyle": ["width": 0.0] as [String: Any],
        "showSymbol": false,
        "areaStyle": [
            "opacity": 0.8,
            "color": [
                "type": "linear",
                "x": 0.0, "y": 0.0, "x2": 0.0, "y2": 1.0,
                "colorStops": [
                    ["offset": 0.0, "color": from] as [String: Any],
                    ["offset": 1.0, "color": to] as [String: Any]
                ] as [Any]
            ] as [String: Any]
        ] as [String: Any],
        "emphasis": ["focus": "series"] as [String: Any],
        "data": data
    ]
    if showLabel {
        band["label"] = ["show": true, "position": "top"] as [String: Any]
    }
    return band
}

private let areaStackGradientSeries: [Any] = [
    areaStackGradientBand(name: "Line 1", from: "rgb(128, 255, 165)", to: "rgb(1, 191, 236)",
                          data: [140, 232, 101, 264, 90, 340, 250]),
    areaStackGradientBand(name: "Line 2", from: "rgb(0, 221, 255)", to: "rgb(77, 119, 255)",
                          data: [120, 282, 111, 234, 220, 340, 310]),
    areaStackGradientBand(name: "Line 3", from: "rgb(55, 162, 255)", to: "rgb(116, 21, 219)",
                          data: [320, 132, 201, 334, 190, 130, 220]),
    areaStackGradientBand(name: "Line 4", from: "rgb(255, 0, 135)", to: "rgb(135, 0, 157)",
                          data: [220, 402, 231, 134, 190, 230, 120]),
    areaStackGradientBand(name: "Line 5", from: "rgb(255, 191, 0)", to: "rgb(224, 62, 76)",
                          data: [220, 302, 181, 234, 210, 290, 150], showLabel: true)
]
