// official-gauge-grade — replica of https://echarts.apache.org/examples/zh/editor.html?c=gauge-grade
// title: Grade Gauge / titleCN: 等级仪表盘
// A half gauge (startAngle 180 → endAngle 0) over 0…1, split into 4 coloured grade bands by a
// segmented `axisLine.lineStyle.color`; a triangular `path://` pointer, `color: 'auto'` ticks /
// splitLines, tangentially-rotated axis labels naming the grades, and a `detail` showing value×100.
//
// DEVIATIONS from the official source:
//   - webOptionJS is the example VERBATIM, minus the TypeScript `(value: number)` annotations and the
//     trailing `export {};` (a bare export is a SyntaxError in a classic script). Both formatters run.
//   - NATIVE pane: both JS formatters are omitted (see the PORT-NOTEs). GaugeView's `formatLabel`
//     implements only the STRING branch — a '{value}' template, which is what the portable gauge
//     demos (e.g. gauge-stage's '{value} km/h') use; its FUNCTION branch is a deferred PORT-NOTE
//     (GaugeView.swift:99) that keeps the raw numeric label. Neither closure here is expressible as
//     a '{value}' template (one maps four tick values to grade names, the other is value×100), so
//     leaving them in the option bag would render identically to dropping them. Consequence, visible
//     in the diff: the native gauge labels the axis with raw numbers (0, 0.125, …) instead of
//     "Grade A/B/C/D" — the official example prints an empty string for every non-grade tick — and
//     the detail reads `0.7` rather than `70`.
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
                        "rotate": "tangential"
                        // PORT-NOTE: axisLabel.formatter omitted — the JS closure mapped the four band
                        // midpoints to grade names (0.875→"Grade A", 0.625→"Grade B", 0.375→"Grade C",
                        // 0.125→"Grade D") and returned '' for every other tick. Not expressible as a
                        // '{value}' template, and GaugeView.formatLabel's function branch is deferred
                        // (GaugeView.swift:99), so the native pane labels all 9 ticks with their raw
                        // numeric value.
                    ] as [String: Any],
                    "title": [
                        "offsetCenter": [0.0, "-10%"] as [Any],
                        "fontSize": 20.0
                    ] as [String: Any],
                    "detail": [
                        "fontSize": 30.0,
                        "offsetCenter": [0.0, "-35%"] as [Any],
                        "valueAnimation": true,
                        "color": "inherit"
                        // PORT-NOTE: detail.formatter omitted — the JS closure rendered the 0…1 value as
                        // a percentage integer (`Math.round(value * 100) + ''`, i.e. "70"). Arithmetic,
                        // so no '{value}' template can express it, and GaugeView.formatLabel's function
                        // branch is deferred (GaugeView.swift:99); the native pane prints the raw value.
                        // `valueAnimation` above still rolls the readout, just over the raw 0…1 number.
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
