// official-bar-waterfall — replica of https://echarts.apache.org/examples/zh/editor.html?c=bar-waterfall
// title: Waterfall Chart / titleCN: 瀑布图（柱状图模拟）
// A waterfall faked with two stacked bar series: a fully transparent "Placeholder" series lifts each
// visible "Life Cost" bar to its running-total baseline.
// DEVIATIONS:
//   - webOptionJS: the official source is TypeScript — its `function (params: any)` type annotation is
//     stripped (a classic <script> cannot parse it), and the trailing `export {};` is dropped. Nothing
//     else changed; no data fetch, no timers.
//   - native option: `tooltip.formatter` is a JS closure and cannot be expressed in Swift (see PORT-NOTE).
extension EChartsDemoRegistry {
    static let official_bar_waterfall = EChartsDemo(
        name: "official-bar-waterfall", category: "bar",
        summary: "瀑布图（柱状图模拟） — Waterfall Chart",
        width: 640, height: 420,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
option = {
  title: {
    text: 'Waterfall Chart',
    subtext: 'Living Expenses in Shenzhen'
  },
  tooltip: {
    trigger: 'axis',
    axisPointer: {
      type: 'shadow'
    },
    formatter: function (params) {
      var tar = params[1];
      return tar.name + '<br/>' + tar.seriesName + ' : ' + tar.value;
    }
  },
  grid: {
    left: '3%',
    right: '4%',
    bottom: '3%',
    containLabel: true
  },
  xAxis: {
    type: 'category',
    splitLine: { show: false },
    data: ['Total', 'Rent', 'Utilities', 'Transportation', 'Meals', 'Other']
  },
  yAxis: {
    type: 'value'
  },
  series: [
    {
      name: 'Placeholder',
      type: 'bar',
      stack: 'Total',
      itemStyle: {
        borderColor: 'transparent',
        color: 'transparent'
      },
      emphasis: {
        itemStyle: {
          borderColor: 'transparent',
          color: 'transparent'
        }
      },
      data: [0, 1700, 1400, 1200, 300, 0]
    },
    {
      name: 'Life Cost',
      type: 'bar',
      stack: 'Total',
      label: {
        show: true,
        position: 'inside'
      },
      data: [2900, 1200, 300, 200, 900, 300]
    }
  ]
};
"""#,
        option: [
            "title": [
                "text": "Waterfall Chart",
                "subtext": "Living Expenses in Shenzhen"
            ] as [String: Any],
            "tooltip": [
                "trigger": "axis",
                "axisPointer": [
                    "type": "shadow"
                ] as [String: Any]
                // PORT-NOTE: tooltip.formatter omitted — the JS closure took the axis-trigger params
                // array, picked params[1] (the visible "Life Cost" bar, skipping the transparent
                // placeholder) and rendered `<name><br/><seriesName> : <value>`.
            ] as [String: Any],
            "grid": [
                "left": "3%",
                "right": "4%",
                "bottom": "3%",
                "containLabel": true
            ] as [String: Any],
            "xAxis": [
                "type": "category",
                "splitLine": ["show": false] as [String: Any],
                "data": ["Total", "Rent", "Utilities", "Transportation", "Meals", "Other"]
            ] as [String: Any],
            "yAxis": [
                "type": "value"
            ] as [String: Any],
            "series": [
                [
                    "name": "Placeholder",
                    "type": "bar",
                    "stack": "Total",
                    "itemStyle": [
                        "borderColor": "transparent",
                        "color": "transparent"
                    ] as [String: Any],
                    "emphasis": [
                        "itemStyle": [
                            "borderColor": "transparent",
                            "color": "transparent"
                        ] as [String: Any]
                    ] as [String: Any],
                    "data": barWaterfallPlaceholderData
                ] as [String: Any],
                [
                    "name": "Life Cost",
                    "type": "bar",
                    "stack": "Total",
                    "label": [
                        "show": true,
                        "position": "inside"
                    ] as [String: Any],
                    "data": barWaterfallLifeCostData
                ] as [String: Any]
            ]
        ])
}

// The invisible baseline lifting each visible bar to its running total.
private let barWaterfallPlaceholderData: [Double] = [0, 1700, 1400, 1200, 300, 0]
// The visible bars: total, then the components that sum to it.
private let barWaterfallLifeCostData: [Double] = [2900, 1200, 300, 200, 900, 300]
