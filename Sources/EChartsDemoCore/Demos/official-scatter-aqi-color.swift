// official-scatter-aqi-color — replica of https://echarts.apache.org/examples/zh/editor.html?c=scatter-aqi-color
// title: Scatter Aqi Color / titleCN: AQI 气泡图
// One month of air-quality readings for 北京 / 上海 / 广州 as three scatter series (x = day, y = AQI index),
// with two continuous `visualMap`s stacked at the right: dimension 2 (PM2.5) driving `symbolSize` [10,70],
// and dimension 6 (SO2) driving `colorLightness` [0.9,0.5] — so each bubble's size and shade encode two
// further dimensions on top of the series colour.
//
// DEVIATIONS from the official source:
//   - The TypeScript parameter annotation (`param: any`) is dropped from the web pane's tooltip formatter:
//     the page is a classic script, and an annotation there is a SyntaxError. The closure body is verbatim.
//   - The trailing `export {};` is dropped (a bare export is a SyntaxError in a classic script).
//   - Native pane: the JS tooltip closure is represented by the typed native callback seam. Its HTML
//     header styling is flattened to rich text while preserving the same header and seven data lines.
//   - Data is inlined in both panes exactly as upstream inlines it — no fetch, no timers, no animated
//     re-setOption; the official example is a single static frame already.
import Foundation
import EChartsKit

extension EChartsDemoRegistry {
    static let official_scatter_aqi_color = EChartsDemo(
        name: "official-scatter-aqi-color", category: "scatter",
        summary: "AQI 气泡图 — Scatter Aqi Color",
        width: 640, height: 420,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
const dataBJ = [
  [1, 55, 9, 56, 0.46, 18, 6, '良'],
  [2, 25, 11, 21, 0.65, 34, 9, '优'],
  [3, 56, 7, 63, 0.3, 14, 5, '良'],
  [4, 33, 7, 29, 0.33, 16, 6, '优'],
  [5, 42, 24, 44, 0.76, 40, 16, '优'],
  [6, 82, 58, 90, 1.77, 68, 33, '良'],
  [7, 74, 49, 77, 1.46, 48, 27, '良'],
  [8, 78, 55, 80, 1.29, 59, 29, '良'],
  [9, 267, 216, 280, 4.8, 108, 64, '重度污染'],
  [10, 185, 127, 216, 2.52, 61, 27, '中度污染'],
  [11, 39, 19, 38, 0.57, 31, 15, '优'],
  [12, 41, 11, 40, 0.43, 21, 7, '优'],
  [13, 64, 38, 74, 1.04, 46, 22, '良'],
  [14, 108, 79, 120, 1.7, 75, 41, '轻度污染'],
  [15, 108, 63, 116, 1.48, 44, 26, '轻度污染'],
  [16, 33, 6, 29, 0.34, 13, 5, '优'],
  [17, 94, 66, 110, 1.54, 62, 31, '良'],
  [18, 186, 142, 192, 3.88, 93, 79, '中度污染'],
  [19, 57, 31, 54, 0.96, 32, 14, '良'],
  [20, 22, 8, 17, 0.48, 23, 10, '优'],
  [21, 39, 15, 36, 0.61, 29, 13, '优'],
  [22, 94, 69, 114, 2.08, 73, 39, '良'],
  [23, 99, 73, 110, 2.43, 76, 48, '良'],
  [24, 31, 12, 30, 0.5, 32, 16, '优'],
  [25, 42, 27, 43, 1, 53, 22, '优'],
  [26, 154, 117, 157, 3.05, 92, 58, '中度污染'],
  [27, 234, 185, 230, 4.09, 123, 69, '重度污染'],
  [28, 160, 120, 186, 2.77, 91, 50, '中度污染'],
  [29, 134, 96, 165, 2.76, 83, 41, '轻度污染'],
  [30, 52, 24, 60, 1.03, 50, 21, '良'],
  [31, 46, 5, 49, 0.28, 10, 6, '优']
];

const dataGZ = [
  [1, 26, 37, 27, 1.163, 27, 13, '优'],
  [2, 85, 62, 71, 1.195, 60, 8, '良'],
  [3, 78, 38, 74, 1.363, 37, 7, '良'],
  [4, 21, 21, 36, 0.634, 40, 9, '优'],
  [5, 41, 42, 46, 0.915, 81, 13, '优'],
  [6, 56, 52, 69, 1.067, 92, 16, '良'],
  [7, 64, 30, 28, 0.924, 51, 2, '良'],
  [8, 55, 48, 74, 1.236, 75, 26, '良'],
  [9, 76, 85, 113, 1.237, 114, 27, '良'],
  [10, 91, 81, 104, 1.041, 56, 40, '良'],
  [11, 84, 39, 60, 0.964, 25, 11, '良'],
  [12, 64, 51, 101, 0.862, 58, 23, '良'],
  [13, 70, 69, 120, 1.198, 65, 36, '良'],
  [14, 77, 105, 178, 2.549, 64, 16, '良'],
  [15, 109, 68, 87, 0.996, 74, 29, '轻度污染'],
  [16, 73, 68, 97, 0.905, 51, 34, '良'],
  [17, 54, 27, 47, 0.592, 53, 12, '良'],
  [18, 51, 61, 97, 0.811, 65, 19, '良'],
  [19, 91, 71, 121, 1.374, 43, 18, '良'],
  [20, 73, 102, 182, 2.787, 44, 19, '良'],
  [21, 73, 50, 76, 0.717, 31, 20, '良'],
  [22, 84, 94, 140, 2.238, 68, 18, '良'],
  [23, 93, 77, 104, 1.165, 53, 7, '良'],
  [24, 99, 130, 227, 3.97, 55, 15, '良'],
  [25, 146, 84, 139, 1.094, 40, 17, '轻度污染'],
  [26, 113, 108, 137, 1.481, 48, 15, '轻度污染'],
  [27, 81, 48, 62, 1.619, 26, 3, '良'],
  [28, 56, 48, 68, 1.336, 37, 9, '良'],
  [29, 82, 92, 174, 3.29, 0, 13, '良'],
  [30, 106, 116, 188, 3.628, 101, 16, '轻度污染'],
  [31, 118, 50, 0, 1.383, 76, 11, '轻度污染']
];

const dataSH = [
  [1, 91, 45, 125, 0.82, 34, 23, '良'],
  [2, 65, 27, 78, 0.86, 45, 29, '良'],
  [3, 83, 60, 84, 1.09, 73, 27, '良'],
  [4, 109, 81, 121, 1.28, 68, 51, '轻度污染'],
  [5, 106, 77, 114, 1.07, 55, 51, '轻度污染'],
  [6, 109, 81, 121, 1.28, 68, 51, '轻度污染'],
  [7, 106, 77, 114, 1.07, 55, 51, '轻度污染'],
  [8, 89, 65, 78, 0.86, 51, 26, '良'],
  [9, 53, 33, 47, 0.64, 50, 17, '良'],
  [10, 80, 55, 80, 1.01, 75, 24, '良'],
  [11, 117, 81, 124, 1.03, 45, 24, '轻度污染'],
  [12, 99, 71, 142, 1.1, 62, 42, '良'],
  [13, 95, 69, 130, 1.28, 74, 50, '良'],
  [14, 116, 87, 131, 1.47, 84, 40, '轻度污染'],
  [15, 108, 80, 121, 1.3, 85, 37, '轻度污染'],
  [16, 134, 83, 167, 1.16, 57, 43, '轻度污染'],
  [17, 79, 43, 107, 1.05, 59, 37, '良'],
  [18, 71, 46, 89, 0.86, 64, 25, '良'],
  [19, 97, 71, 113, 1.17, 88, 31, '良'],
  [20, 84, 57, 91, 0.85, 55, 31, '良'],
  [21, 87, 63, 101, 0.9, 56, 41, '良'],
  [22, 104, 77, 119, 1.09, 73, 48, '轻度污染'],
  [23, 87, 62, 100, 1, 72, 28, '良'],
  [24, 168, 128, 172, 1.49, 97, 56, '中度污染'],
  [25, 65, 45, 51, 0.74, 39, 17, '良'],
  [26, 39, 24, 38, 0.61, 47, 17, '优'],
  [27, 39, 24, 39, 0.59, 50, 19, '优'],
  [28, 93, 68, 96, 1.05, 79, 29, '良'],
  [29, 188, 143, 197, 1.66, 99, 51, '中度污染'],
  [30, 174, 131, 174, 1.55, 108, 50, '中度污染'],
  [31, 187, 143, 201, 1.39, 89, 53, '中度污染']
];

const schema = [
  { name: 'date', index: 0, text: '日' },
  { name: 'AQIindex', index: 1, text: 'AQI指数' },
  { name: 'PM25', index: 2, text: 'PM2.5' },
  { name: 'PM10', index: 3, text: 'PM10' },
  { name: 'CO', index: 4, text: '一氧化碳（CO）' },
  { name: 'NO2', index: 5, text: '二氧化氮（NO2）' },
  { name: 'SO2', index: 6, text: '二氧化硫（SO2）' }
];

const itemStyle = {
  opacity: 0.8,
  shadowBlur: 10,
  shadowOffsetX: 0,
  shadowOffsetY: 0,
  shadowColor: 'rgba(0,0,0,0.3)'
};

option = {
  color: ['#dd4444', '#fec42c', '#80F1BE'],
  legend: {
    top: 10,
    data: ['北京', '上海', '广州'],
    textStyle: {
      fontSize: 16
    }
  },
  grid: {
    left: '10%',
    right: 150,
    top: '18%',
    bottom: '10%'
  },
  tooltip: {
    backgroundColor: 'rgba(255,255,255,0.7)',
    formatter: function (param) {
      var value = param.value;
      // prettier-ignore
      return '<div style="border-bottom: 1px solid rgba(255,255,255,.3); font-size: 18px;padding-bottom: 7px;margin-bottom: 7px">'
        + param.seriesName + ' ' + value[0] + '日：'
        + value[7]
        + '</div>'
        + schema[1].text + '：' + value[1] + '<br>'
        + schema[2].text + '：' + value[2] + '<br>'
        + schema[3].text + '：' + value[3] + '<br>'
        + schema[4].text + '：' + value[4] + '<br>'
        + schema[5].text + '：' + value[5] + '<br>'
        + schema[6].text + '：' + value[6] + '<br>';
    }
  },
  xAxis: {
    type: 'value',
    name: '日期',
    nameGap: 16,
    nameTextStyle: {
      fontSize: 16
    },
    max: 31,
    splitLine: {
      show: false
    }
  },
  yAxis: {
    type: 'value',
    name: 'AQI指数',
    nameLocation: 'end',
    nameGap: 20,
    nameTextStyle: {
      fontSize: 16
    },
    splitLine: {
      show: false
    }
  },
  visualMap: [
    {
      left: 'right',
      top: '10%',
      dimension: 2,
      min: 0,
      max: 250,
      itemWidth: 30,
      itemHeight: 120,
      calculable: true,
      precision: 0.1,
      text: ['圆形大小：PM2.5'],
      textGap: 30,
      inRange: {
        symbolSize: [10, 70]
      },
      outOfRange: {
        symbolSize: [10, 70],
        color: ['rgba(255,255,255,0.4)']
      },
      controller: {
        inRange: {
          color: ['#c23531']
        },
        outOfRange: {
          color: ['#999']
        }
      }
    },
    {
      left: 'right',
      bottom: '5%',
      dimension: 6,
      min: 0,
      max: 50,
      itemHeight: 120,
      text: ['明暗：二氧化硫'],
      textGap: 30,
      inRange: {
        colorLightness: [0.9, 0.5]
      },
      outOfRange: {
        color: ['rgba(255,255,255,0.4)']
      },
      controller: {
        inRange: {
          color: ['#c23531']
        },
        outOfRange: {
          color: ['#999']
        }
      }
    }
  ],
  series: [
    {
      name: '北京',
      type: 'scatter',
      itemStyle: itemStyle,
      data: dataBJ
    },
    {
      name: '上海',
      type: 'scatter',
      itemStyle: itemStyle,
      data: dataSH
    },
    {
      name: '广州',
      type: 'scatter',
      itemStyle: itemStyle,
      data: dataGZ
    }
  ]
};
"""#,
        option: [
            "color": ["#dd4444", "#fec42c", "#80F1BE"],
            "legend": [
                "top": 10.0,
                "data": ["北京", "上海", "广州"],
                "textStyle": [
                    "fontSize": 16.0
                ] as [String: Any]
            ] as [String: Any],
            "grid": [
                "left": "10%",
                "right": 150.0,
                "top": "18%",
                "bottom": "10%"
            ] as [String: Any],
            "tooltip": [
                "backgroundColor": "rgba(255,255,255,0.7)",
                "formatter": scatterAqiColorTooltipFormatter
            ] as [String: Any],
            "xAxis": [
                "type": "value",
                "name": "日期",
                "nameGap": 16.0,
                "nameTextStyle": [
                    "fontSize": 16.0
                ] as [String: Any],
                "max": 31.0,
                "splitLine": [
                    "show": false
                ] as [String: Any]
            ] as [String: Any],
            "yAxis": [
                "type": "value",
                "name": "AQI指数",
                "nameLocation": "end",
                "nameGap": 20.0,
                "nameTextStyle": [
                    "fontSize": 16.0
                ] as [String: Any],
                "splitLine": [
                    "show": false
                ] as [String: Any]
            ] as [String: Any],
            "visualMap": [
                [
                    "left": "right",
                    "top": "10%",
                    "dimension": 2.0,
                    "min": 0.0,
                    "max": 250.0,
                    "itemWidth": 30.0,
                    "itemHeight": 120.0,
                    "calculable": true,
                    "precision": 0.1,
                    "text": ["圆形大小：PM2.5"],
                    "textGap": 30.0,
                    "inRange": [
                        "symbolSize": [10.0, 70.0]
                    ] as [String: Any],
                    "outOfRange": [
                        "symbolSize": [10.0, 70.0],
                        "color": ["rgba(255,255,255,0.4)"]
                    ] as [String: Any],
                    "controller": [
                        "inRange": [
                            "color": ["#c23531"]
                        ] as [String: Any],
                        "outOfRange": [
                            "color": ["#999"]
                        ] as [String: Any]
                    ] as [String: Any]
                ] as [String: Any],
                [
                    "left": "right",
                    "bottom": "5%",
                    "dimension": 6.0,
                    "min": 0.0,
                    "max": 50.0,
                    "itemHeight": 120.0,
                    "text": ["明暗：二氧化硫"],
                    "textGap": 30.0,
                    "inRange": [
                        "colorLightness": [0.9, 0.5]
                    ] as [String: Any],
                    "outOfRange": [
                        "color": ["rgba(255,255,255,0.4)"]
                    ] as [String: Any],
                    "controller": [
                        "inRange": [
                            "color": ["#c23531"]
                        ] as [String: Any],
                        "outOfRange": [
                            "color": ["#999"]
                        ] as [String: Any]
                    ] as [String: Any]
                ] as [String: Any]
            ],
            "series": [
                [
                    "name": "北京",
                    "type": "scatter",
                    "itemStyle": scatterAqiColorItemStyle,
                    "data": scatterAqiColorDataBJ
                ] as [String: Any],
                [
                    "name": "上海",
                    "type": "scatter",
                    "itemStyle": scatterAqiColorItemStyle,
                    "data": scatterAqiColorDataSH
                ] as [String: Any],
                [
                    "name": "广州",
                    "type": "scatter",
                    "itemStyle": scatterAqiColorItemStyle,
                    "data": scatterAqiColorDataGZ
                ] as [String: Any]
            ]
        ])
}

private func scatterAqiColorValueText(_ value: Any?) -> String {
    if let value = value as? String { return value }
    if let value = value as? Double {
        return value.rounded() == value ? String(Int(value)) : String(value)
    }
    if let value = value as? Int { return String(value) }
    if let value = value as? NSNumber {
        let number = value.doubleValue
        return number.rounded() == number ? String(Int(number)) : String(number)
    }
    return ""
}

private let scatterAqiColorTooltipFormatter: (TooltipCallbackDataParams) -> String = { params in
    guard let value = params.value as? [Any], value.count > 7 else { return "" }
    return "\(params.seriesName ?? "") \(scatterAqiColorValueText(value[0]))日："
        + "\(scatterAqiColorValueText(value[7]))<br>"
        + "AQI指数：\(scatterAqiColorValueText(value[1]))<br>"
        + "PM2.5：\(scatterAqiColorValueText(value[2]))<br>"
        + "PM10：\(scatterAqiColorValueText(value[3]))<br>"
        + "一氧化碳（CO）：\(scatterAqiColorValueText(value[4]))<br>"
        + "二氧化氮（NO2）：\(scatterAqiColorValueText(value[5]))<br>"
        + "二氧化硫（SO2）：\(scatterAqiColorValueText(value[6]))<br>"
}

// Shared by all three series upstream (the `itemStyle` const).
private let scatterAqiColorItemStyle: [String: Any] = [
    "opacity": 0.8,
    "shadowBlur": 10.0,
    "shadowOffsetX": 0.0,
    "shadowOffsetY": 0.0,
    "shadowColor": "rgba(0,0,0,0.3)"
]

// Rows are [日, AQI指数, PM2.5, PM10, CO, NO2, SO2, 级别] — dimension 2 drives symbolSize, 6 drives
// colorLightness, and 0/1 are the x/y coordinates. Heterogeneous (the trailing 级别 is a string), so [[Any]].
private let scatterAqiColorDataBJ: [[Any]] = [
    [1.0, 55.0, 9.0, 56.0, 0.46, 18.0, 6.0, "良"],
    [2.0, 25.0, 11.0, 21.0, 0.65, 34.0, 9.0, "优"],
    [3.0, 56.0, 7.0, 63.0, 0.3, 14.0, 5.0, "良"],
    [4.0, 33.0, 7.0, 29.0, 0.33, 16.0, 6.0, "优"],
    [5.0, 42.0, 24.0, 44.0, 0.76, 40.0, 16.0, "优"],
    [6.0, 82.0, 58.0, 90.0, 1.77, 68.0, 33.0, "良"],
    [7.0, 74.0, 49.0, 77.0, 1.46, 48.0, 27.0, "良"],
    [8.0, 78.0, 55.0, 80.0, 1.29, 59.0, 29.0, "良"],
    [9.0, 267.0, 216.0, 280.0, 4.8, 108.0, 64.0, "重度污染"],
    [10.0, 185.0, 127.0, 216.0, 2.52, 61.0, 27.0, "中度污染"],
    [11.0, 39.0, 19.0, 38.0, 0.57, 31.0, 15.0, "优"],
    [12.0, 41.0, 11.0, 40.0, 0.43, 21.0, 7.0, "优"],
    [13.0, 64.0, 38.0, 74.0, 1.04, 46.0, 22.0, "良"],
    [14.0, 108.0, 79.0, 120.0, 1.7, 75.0, 41.0, "轻度污染"],
    [15.0, 108.0, 63.0, 116.0, 1.48, 44.0, 26.0, "轻度污染"],
    [16.0, 33.0, 6.0, 29.0, 0.34, 13.0, 5.0, "优"],
    [17.0, 94.0, 66.0, 110.0, 1.54, 62.0, 31.0, "良"],
    [18.0, 186.0, 142.0, 192.0, 3.88, 93.0, 79.0, "中度污染"],
    [19.0, 57.0, 31.0, 54.0, 0.96, 32.0, 14.0, "良"],
    [20.0, 22.0, 8.0, 17.0, 0.48, 23.0, 10.0, "优"],
    [21.0, 39.0, 15.0, 36.0, 0.61, 29.0, 13.0, "优"],
    [22.0, 94.0, 69.0, 114.0, 2.08, 73.0, 39.0, "良"],
    [23.0, 99.0, 73.0, 110.0, 2.43, 76.0, 48.0, "良"],
    [24.0, 31.0, 12.0, 30.0, 0.5, 32.0, 16.0, "优"],
    [25.0, 42.0, 27.0, 43.0, 1.0, 53.0, 22.0, "优"],
    [26.0, 154.0, 117.0, 157.0, 3.05, 92.0, 58.0, "中度污染"],
    [27.0, 234.0, 185.0, 230.0, 4.09, 123.0, 69.0, "重度污染"],
    [28.0, 160.0, 120.0, 186.0, 2.77, 91.0, 50.0, "中度污染"],
    [29.0, 134.0, 96.0, 165.0, 2.76, 83.0, 41.0, "轻度污染"],
    [30.0, 52.0, 24.0, 60.0, 1.03, 50.0, 21.0, "良"],
    [31.0, 46.0, 5.0, 49.0, 0.28, 10.0, 6.0, "优"]
]

private let scatterAqiColorDataSH: [[Any]] = [
    [1.0, 91.0, 45.0, 125.0, 0.82, 34.0, 23.0, "良"],
    [2.0, 65.0, 27.0, 78.0, 0.86, 45.0, 29.0, "良"],
    [3.0, 83.0, 60.0, 84.0, 1.09, 73.0, 27.0, "良"],
    [4.0, 109.0, 81.0, 121.0, 1.28, 68.0, 51.0, "轻度污染"],
    [5.0, 106.0, 77.0, 114.0, 1.07, 55.0, 51.0, "轻度污染"],
    [6.0, 109.0, 81.0, 121.0, 1.28, 68.0, 51.0, "轻度污染"],
    [7.0, 106.0, 77.0, 114.0, 1.07, 55.0, 51.0, "轻度污染"],
    [8.0, 89.0, 65.0, 78.0, 0.86, 51.0, 26.0, "良"],
    [9.0, 53.0, 33.0, 47.0, 0.64, 50.0, 17.0, "良"],
    [10.0, 80.0, 55.0, 80.0, 1.01, 75.0, 24.0, "良"],
    [11.0, 117.0, 81.0, 124.0, 1.03, 45.0, 24.0, "轻度污染"],
    [12.0, 99.0, 71.0, 142.0, 1.1, 62.0, 42.0, "良"],
    [13.0, 95.0, 69.0, 130.0, 1.28, 74.0, 50.0, "良"],
    [14.0, 116.0, 87.0, 131.0, 1.47, 84.0, 40.0, "轻度污染"],
    [15.0, 108.0, 80.0, 121.0, 1.3, 85.0, 37.0, "轻度污染"],
    [16.0, 134.0, 83.0, 167.0, 1.16, 57.0, 43.0, "轻度污染"],
    [17.0, 79.0, 43.0, 107.0, 1.05, 59.0, 37.0, "良"],
    [18.0, 71.0, 46.0, 89.0, 0.86, 64.0, 25.0, "良"],
    [19.0, 97.0, 71.0, 113.0, 1.17, 88.0, 31.0, "良"],
    [20.0, 84.0, 57.0, 91.0, 0.85, 55.0, 31.0, "良"],
    [21.0, 87.0, 63.0, 101.0, 0.9, 56.0, 41.0, "良"],
    [22.0, 104.0, 77.0, 119.0, 1.09, 73.0, 48.0, "轻度污染"],
    [23.0, 87.0, 62.0, 100.0, 1.0, 72.0, 28.0, "良"],
    [24.0, 168.0, 128.0, 172.0, 1.49, 97.0, 56.0, "中度污染"],
    [25.0, 65.0, 45.0, 51.0, 0.74, 39.0, 17.0, "良"],
    [26.0, 39.0, 24.0, 38.0, 0.61, 47.0, 17.0, "优"],
    [27.0, 39.0, 24.0, 39.0, 0.59, 50.0, 19.0, "优"],
    [28.0, 93.0, 68.0, 96.0, 1.05, 79.0, 29.0, "良"],
    [29.0, 188.0, 143.0, 197.0, 1.66, 99.0, 51.0, "中度污染"],
    [30.0, 174.0, 131.0, 174.0, 1.55, 108.0, 50.0, "中度污染"],
    [31.0, 187.0, 143.0, 201.0, 1.39, 89.0, 53.0, "中度污染"]
]

private let scatterAqiColorDataGZ: [[Any]] = [
    [1.0, 26.0, 37.0, 27.0, 1.163, 27.0, 13.0, "优"],
    [2.0, 85.0, 62.0, 71.0, 1.195, 60.0, 8.0, "良"],
    [3.0, 78.0, 38.0, 74.0, 1.363, 37.0, 7.0, "良"],
    [4.0, 21.0, 21.0, 36.0, 0.634, 40.0, 9.0, "优"],
    [5.0, 41.0, 42.0, 46.0, 0.915, 81.0, 13.0, "优"],
    [6.0, 56.0, 52.0, 69.0, 1.067, 92.0, 16.0, "良"],
    [7.0, 64.0, 30.0, 28.0, 0.924, 51.0, 2.0, "良"],
    [8.0, 55.0, 48.0, 74.0, 1.236, 75.0, 26.0, "良"],
    [9.0, 76.0, 85.0, 113.0, 1.237, 114.0, 27.0, "良"],
    [10.0, 91.0, 81.0, 104.0, 1.041, 56.0, 40.0, "良"],
    [11.0, 84.0, 39.0, 60.0, 0.964, 25.0, 11.0, "良"],
    [12.0, 64.0, 51.0, 101.0, 0.862, 58.0, 23.0, "良"],
    [13.0, 70.0, 69.0, 120.0, 1.198, 65.0, 36.0, "良"],
    [14.0, 77.0, 105.0, 178.0, 2.549, 64.0, 16.0, "良"],
    [15.0, 109.0, 68.0, 87.0, 0.996, 74.0, 29.0, "轻度污染"],
    [16.0, 73.0, 68.0, 97.0, 0.905, 51.0, 34.0, "良"],
    [17.0, 54.0, 27.0, 47.0, 0.592, 53.0, 12.0, "良"],
    [18.0, 51.0, 61.0, 97.0, 0.811, 65.0, 19.0, "良"],
    [19.0, 91.0, 71.0, 121.0, 1.374, 43.0, 18.0, "良"],
    [20.0, 73.0, 102.0, 182.0, 2.787, 44.0, 19.0, "良"],
    [21.0, 73.0, 50.0, 76.0, 0.717, 31.0, 20.0, "良"],
    [22.0, 84.0, 94.0, 140.0, 2.238, 68.0, 18.0, "良"],
    [23.0, 93.0, 77.0, 104.0, 1.165, 53.0, 7.0, "良"],
    [24.0, 99.0, 130.0, 227.0, 3.97, 55.0, 15.0, "良"],
    [25.0, 146.0, 84.0, 139.0, 1.094, 40.0, 17.0, "轻度污染"],
    [26.0, 113.0, 108.0, 137.0, 1.481, 48.0, 15.0, "轻度污染"],
    [27.0, 81.0, 48.0, 62.0, 1.619, 26.0, 3.0, "良"],
    [28.0, 56.0, 48.0, 68.0, 1.336, 37.0, 9.0, "良"],
    [29.0, 82.0, 92.0, 174.0, 3.29, 0.0, 13.0, "良"],
    [30.0, 106.0, 116.0, 188.0, 3.628, 101.0, 16.0, "轻度污染"],
    [31.0, 118.0, 50.0, 0.0, 1.383, 76.0, 11.0, "轻度污染"]
]
