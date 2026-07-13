// official-line-y-category — replica of https://echarts.apache.org/examples/zh/editor.html?c=line-y-category
// title: Line Y Category / titleCN: 垂直折线图（Y轴为类目轴）
// A vertical line: the CATEGORY axis is the yAxis (altitude in km, boundaryGap false, axisLine.onZero
// false) and the VALUE axis is the xAxis (temperature in °C); smooth line with circle symbols and a
// shadowed lineStyle. Both axes use string-template axisLabel formatters, and the axis tooltip uses a
// string-template formatter too.
// DEVIATIONS: none — the official source is a single static `option` literal: no data fetch, no timers,
// and every `formatter` is a string TEMPLATE (not a JS closure), so the Swift option carries all of
// them and both panes are faithful.
extension EChartsDemoRegistry {
    static let official_line_y_category = EChartsDemo(
        name: "official-line-y-category", category: "line",
        summary: "垂直折线图（Y轴为类目轴） — Line Y Category",
        width: 640, height: 420,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
option = {
  legend: {
    data: ['Altitude (km) vs. temperature (°C)']
  },
  tooltip: {
    trigger: 'axis',
    formatter: 'Temperature : <br/>{b}km : {c}°C'
  },
  grid: {
    left: '3%',
    right: '4%',
    bottom: '3%',
    containLabel: true
  },
  xAxis: {
    type: 'value',
    axisLabel: {
      formatter: '{value} °C'
    }
  },
  yAxis: {
    type: 'category',
    axisLine: { onZero: false },
    axisLabel: {
      formatter: '{value} km'
    },
    boundaryGap: false,
    data: ['0', '10', '20', '30', '40', '50', '60', '70', '80']
  },
  series: [
    {
      name: 'Altitude (km) vs. temperature (°C)',
      type: 'line',
      symbolSize: 10,
      symbol: 'circle',
      smooth: true,
      lineStyle: {
        width: 3,
        shadowColor: 'rgba(0,0,0,0.3)',
        shadowBlur: 10,
        shadowOffsetY: 8
      },
      data: [15, -50, -56.5, -46.5, -22.1, -2.5, -27.7, -55.7, -76.5]
    }
  ]
};
"""#,
        option: [
            "legend": [
                "data": ["Altitude (km) vs. temperature (°C)"]
            ] as [String: Any],
            "tooltip": [
                "trigger": "axis",
                "formatter": "Temperature : <br/>{b}km : {c}°C"
            ] as [String: Any],
            "grid": [
                "left": "3%",
                "right": "4%",
                "bottom": "3%",
                "containLabel": true
            ] as [String: Any],
            "xAxis": [
                "type": "value",
                "axisLabel": [
                    "formatter": "{value} °C"
                ] as [String: Any]
            ] as [String: Any],
            "yAxis": [
                "type": "category",
                "axisLine": ["onZero": false] as [String: Any],
                "axisLabel": [
                    "formatter": "{value} km"
                ] as [String: Any],
                "boundaryGap": false,
                "data": lineYCategoryAltitudes
            ] as [String: Any],
            "series": [
                [
                    "name": "Altitude (km) vs. temperature (°C)",
                    "type": "line",
                    "symbolSize": 10.0,
                    "symbol": "circle",
                    "smooth": true,
                    "lineStyle": [
                        "width": 3.0,
                        "shadowColor": "rgba(0,0,0,0.3)",
                        "shadowBlur": 10.0,
                        "shadowOffsetY": 8.0
                    ] as [String: Any],
                    "data": lineYCategoryTemperatures
                ] as [String: Any]
            ]
        ])
}

// yAxis categories: altitude in km.
private let lineYCategoryAltitudes: [String] = [
    "0", "10", "20", "30", "40", "50", "60", "70", "80"
]

// Series values: temperature in °C at each altitude above.
private let lineYCategoryTemperatures: [Double] = [
    15, -50, -56.5, -46.5, -22.1, -2.5, -27.7, -55.7, -76.5
]
