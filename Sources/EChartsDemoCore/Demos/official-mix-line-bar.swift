// official-mix-line-bar — replica of https://echarts.apache.org/examples/zh/editor.html?c=mix-line-bar
// title: Mixed Line and Bar / titleCN: 折柱混合
// Two bar series (Evaporation, Precipitation) on the left value axis plus a line series
// (Temperature) bound to a second right-hand value axis, with a cross axisPointer, a legend and the
// full toolbox (dataView / magicType / restore / saveAsImage).
//
// DEVIATIONS from the official source:
//   - The official source is TypeScript: its `valueFormatter` bodies read `return value as number + ' ml'`
//     and the file ends with `export {};`. The web pane runs as a CLASSIC script, so the TS type
//     assertions (`as number`) and the trailing bare `export` are dropped — both are SyntaxErrors in
//     plain JS. Nothing else in webOptionJS is changed; the formatters themselves run verbatim.
//   - The native pane omits the three `series[].tooltip.valueFormatter` closures (see PORT-NOTEs);
//     Swift's `[String: Any]` option cannot carry a JS function. Everything else — including the
//     `axisLabel.formatter: '{value} ml'` STRING templates, which are not closures — is ported as-is.
//   - The example's own quirk is preserved: xAxis has 7 categories (Mon…Sun) while every series
//     carries 12 data points, so the tail of each series falls off the axis. That is what the
//     official example does; we do not "fix" it.
extension EChartsDemoRegistry {
    static let official_mix_line_bar = EChartsDemo(
        name: "official-mix-line-bar", category: "bar",
        summary: "折柱混合 — Mixed Line and Bar",
        width: 640, height: 420,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
option = {
  tooltip: {
    trigger: 'axis',
    axisPointer: {
      type: 'cross',
      crossStyle: {
        color: '#999'
      }
    }
  },
  toolbox: {
    feature: {
      dataView: { show: true, readOnly: false },
      magicType: { show: true, type: ['line', 'bar'] },
      restore: { show: true },
      saveAsImage: { show: true }
    }
  },
  legend: {
    data: ['Evaporation', 'Precipitation', 'Temperature']
  },
  xAxis: [
    {
      type: 'category',
      data: ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'],
      axisPointer: {
        type: 'shadow'
      }
    }
  ],
  yAxis: [
    {
      type: 'value',
      name: 'Precipitation',
      min: 0,
      max: 250,
      interval: 50,
      axisLabel: {
        formatter: '{value} ml'
      }
    },
    {
      type: 'value',
      name: 'Temperature',
      min: 0,
      max: 25,
      interval: 5,
      axisLabel: {
        formatter: '{value} °C'
      }
    }
  ],
  series: [
    {
      name: 'Evaporation',
      type: 'bar',
      tooltip: {
        valueFormatter: function (value) {
          return value + ' ml';
        }
      },
      data: [
        2.0, 4.9, 7.0, 23.2, 25.6, 76.7, 135.6, 162.2, 32.6, 20.0, 6.4, 3.3
      ]
    },
    {
      name: 'Precipitation',
      type: 'bar',
      tooltip: {
        valueFormatter: function (value) {
          return value + ' ml';
        }
      },
      data: [
        2.6, 5.9, 9.0, 26.4, 28.7, 70.7, 175.6, 182.2, 48.7, 18.8, 6.0, 2.3
      ]
    },
    {
      name: 'Temperature',
      type: 'line',
      yAxisIndex: 1,
      tooltip: {
        valueFormatter: function (value) {
          return value + ' °C';
        }
      },
      data: [2.0, 2.2, 3.3, 4.5, 6.3, 10.2, 20.3, 23.4, 23.0, 16.5, 12.0, 6.2]
    }
  ]
};
"""#,
        option: [
            "tooltip": [
                "trigger": "axis",
                "axisPointer": [
                    "type": "cross",
                    "crossStyle": [
                        "color": "#999"
                    ] as [String: Any]
                ] as [String: Any]
            ] as [String: Any],
            "toolbox": [
                "feature": [
                    "dataView": ["show": true, "readOnly": false] as [String: Any],
                    "magicType": ["show": true, "type": ["line", "bar"]] as [String: Any],
                    "restore": ["show": true] as [String: Any],
                    "saveAsImage": ["show": true] as [String: Any]
                ] as [String: Any]
            ] as [String: Any],
            "legend": [
                "data": ["Evaporation", "Precipitation", "Temperature"]
            ] as [String: Any],
            "xAxis": [
                [
                    "type": "category",
                    "data": ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"],
                    "axisPointer": [
                        "type": "shadow"
                    ] as [String: Any]
                ] as [String: Any]
            ],
            "yAxis": [
                [
                    "type": "value",
                    "name": "Precipitation",
                    "min": 0.0,
                    "max": 250.0,
                    "interval": 50.0,
                    "axisLabel": [
                        "formatter": "{value} ml"
                    ] as [String: Any]
                ] as [String: Any],
                [
                    "type": "value",
                    "name": "Temperature",
                    "min": 0.0,
                    "max": 25.0,
                    "interval": 5.0,
                    "axisLabel": [
                        "formatter": "{value} °C"
                    ] as [String: Any]
                ] as [String: Any]
            ],
            "series": [
                [
                    "name": "Evaporation",
                    "type": "bar",
                    // PORT-NOTE: series[0].tooltip.valueFormatter omitted — JS closure appending ' ml'
                    // to each tooltip value.
                    "data": mixLineBarEvaporationData
                ] as [String: Any],
                [
                    "name": "Precipitation",
                    "type": "bar",
                    // PORT-NOTE: series[1].tooltip.valueFormatter omitted — JS closure appending ' ml'
                    // to each tooltip value.
                    "data": mixLineBarPrecipitationData
                ] as [String: Any],
                [
                    "name": "Temperature",
                    "type": "line",
                    "yAxisIndex": 1.0,
                    // PORT-NOTE: series[2].tooltip.valueFormatter omitted — JS closure appending ' °C'
                    // to each tooltip value.
                    "data": mixLineBarTemperatureData
                ] as [String: Any]
            ]
        ])
}

// 12 points per series against a 7-category x-axis — verbatim from the official example.
private let mixLineBarEvaporationData: [Double] = [
    2.0, 4.9, 7.0, 23.2, 25.6, 76.7, 135.6, 162.2, 32.6, 20.0, 6.4, 3.3
]

private let mixLineBarPrecipitationData: [Double] = [
    2.6, 5.9, 9.0, 26.4, 28.7, 70.7, 175.6, 182.2, 48.7, 18.8, 6.0, 2.3
]

private let mixLineBarTemperatureData: [Double] = [
    2.0, 2.2, 3.3, 4.5, 6.3, 10.2, 20.3, 23.4, 23.0, 16.5, 12.0, 6.2
]
