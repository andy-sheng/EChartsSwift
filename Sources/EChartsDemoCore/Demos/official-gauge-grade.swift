// official-gauge-grade — replica of https://echarts.apache.org/examples/zh/editor.html?c=gauge-grade
// title: Grade Gauge / titleCN: 等级仪表盘
// A half gauge (startAngle 180 → endAngle 0) over 0…1, split into 4 coloured grade bands by a
// segmented `axisLine.lineStyle.color`; a triangular `path://` pointer, `color: 'auto'` ticks /
// splitLines, tangentially-rotated axis labels naming the grades, and a `detail` showing value×100.
//
// DEVIATIONS from the official source:
//   - webOptionJS is the example VERBATIM, minus the TypeScript `(value: number)` annotations and the
//     trailing `export {};` (a bare export is a SyntaxError in a classic script). Both formatters run.
//   - NATIVE pane: the two JS formatter functions are represented by equivalent Swift
//     `(Double) -> String` callbacks supported by GaugeView.
//   - No timers, no data fetch, no map: no `drive`, no assets.
extension EChartsDemoRegistry {
    static let official_gauge_grade = EChartsDemo(
        name: "official-gauge-grade", category: "gauge",
        summary: "等级仪表盘 — Grade Gauge",
        width: 640, height: 420,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
option = {
  series: [
    {
      type: 'gauge',
      startAngle: 180,
      endAngle: 0,
      center: ['50%', '75%'],
      radius: '90%',
      min: 0,
      max: 1,
      splitNumber: 8,
      axisLine: {
        lineStyle: {
          width: 6,
          color: [
            [0.25, '#FF6E76'],
            [0.5, '#FDDD60'],
            [0.75, '#58D9F9'],
            [1, '#7CFFB2']
          ]
        }
      },
      pointer: {
        icon: 'path://M12.8,0.7l12,40.1H0.7L12.8,0.7z',
        length: '12%',
        width: 20,
        offsetCenter: [0, '-60%'],
        itemStyle: {
          color: 'auto'
        }
      },
      axisTick: {
        length: 12,
        lineStyle: {
          color: 'auto',
          width: 2
        }
      },
      splitLine: {
        length: 20,
        lineStyle: {
          color: 'auto',
          width: 5
        }
      },
      axisLabel: {
        color: '#464646',
        fontSize: 20,
        distance: -60,
        rotate: 'tangential',
        formatter: function (value) {
          if (value === 0.875) {
            return 'Grade A';
          } else if (value === 0.625) {
            return 'Grade B';
          } else if (value === 0.375) {
            return 'Grade C';
          } else if (value === 0.125) {
            return 'Grade D';
          }
          return '';
        }
      },
      title: {
        offsetCenter: [0, '-10%'],
        fontSize: 20
      },
      detail: {
        fontSize: 30,
        offsetCenter: [0, '-35%'],
        valueAnimation: true,
        formatter: function (value) {
          return Math.round(value * 100) + '';
        },
        color: 'inherit'
      },
      data: [
        {
          value: 0.7,
          name: 'Grade Rating'
        }
      ]
    }
  ]
};
"""#,
        option: [
            "series": [
                [
                    "type": "gauge",
                    "startAngle": 180.0,
                    "endAngle": 0.0,
                    "center": ["50%", "75%"],
                    "radius": "90%",
                    "min": 0.0,
                    "max": 1.0,
                    "splitNumber": 8.0,
                    "axisLine": [
                        "lineStyle": [
                            "width": 6.0,
                            "color": gaugeGradeBandColors
                        ] as [String: Any]
                    ] as [String: Any],
                    "pointer": [
                        "icon": "path://M12.8,0.7l12,40.1H0.7L12.8,0.7z",
                        "length": "12%",
                        "width": 20.0,
                        "offsetCenter": [0.0, "-60%"] as [Any],
                        "itemStyle": [
                            "color": "auto"
                        ] as [String: Any]
                    ] as [String: Any],
                    "axisTick": [
                        "length": 12.0,
                        "lineStyle": [
                            "color": "auto",
                            "width": 2.0
                        ] as [String: Any]
                    ] as [String: Any],
                    "splitLine": [
                        "length": 20.0,
                        "lineStyle": [
                            "color": "auto",
                            "width": 5.0
                        ] as [String: Any]
                    ] as [String: Any],
                    "axisLabel": [
                        "color": "#464646",
                        "fontSize": 20.0,
                        "distance": -60.0,
                        "rotate": "tangential",
                        "formatter": gaugeGradeAxisLabelFormatter as (Double) -> String
                    ] as [String: Any],
                    "title": [
                        "offsetCenter": [0.0, "-10%"] as [Any],
                        "fontSize": 20.0
                    ] as [String: Any],
                    "detail": [
                        "fontSize": 30.0,
                        "offsetCenter": [0.0, "-35%"] as [Any],
                        "valueAnimation": true,
                        "formatter": gaugeGradeDetailFormatter as (Double) -> String,
                        "color": "inherit"
                    ] as [String: Any],
                    "data": [
                        [
                            "value": 0.7,
                            "name": "Grade Rating"
                        ] as [String: Any]
                    ]
                ] as [String: Any]
            ]
        ])
}

// axisLine.lineStyle.color: [upper bound of the band (0…1), band colour] — the 4 grade bands.
private let gaugeGradeBandColors: [[Any]] = [
    [0.25, "#FF6E76"],
    [0.5, "#FDDD60"],
    [0.75, "#58D9F9"],
    [1.0, "#7CFFB2"]
]

private let gaugeGradeAxisLabelFormatter: (Double) -> String = { value in
    if abs(value - 0.875) < 1e-9 { return "Grade A" }
    if abs(value - 0.625) < 1e-9 { return "Grade B" }
    if abs(value - 0.375) < 1e-9 { return "Grade C" }
    if abs(value - 0.125) < 1e-9 { return "Grade D" }
    return ""
}

private let gaugeGradeDetailFormatter: (Double) -> String = { value in
    String(Int((value * 100).rounded()))
}
