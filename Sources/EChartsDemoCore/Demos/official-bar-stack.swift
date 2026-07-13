// official-bar-stack — replica of https://echarts.apache.org/examples/zh/editor.html?c=bar-stack
// title: Stacked Column Chart / titleCN: 堆叠柱状图
// Nine bar series over a 7-day category axis, grouped into three columns per tick: an unstacked
// 'Direct', a three-series 'Ad' stack, and 'Search Engine' (unstacked, carrying a dashed min→max
// markLine) plus its four-series 'Search Engine' stack (of which 'Baidu' pins barWidth: 5).
// `emphasis.focus: 'series'` on every series; axis tooltip with a shadow axisPointer.
// DEVIATIONS: none of substance — the official source is a single static `option` literal with no
// data fetch, no closures and no timers, so both panes carry it verbatim. Only the trailing
// `export {};` is dropped (a bare export is a SyntaxError in the reference pane's classic script).
extension EChartsDemoRegistry {
    static let official_bar_stack = EChartsDemo(
        name: "official-bar-stack", category: "bar",
        summary: "堆叠柱状图 — Stacked Column Chart",
        width: 640, height: 420,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
option = {
  tooltip: {
    trigger: 'axis',
    axisPointer: {
      type: 'shadow'
    }
  },
  legend: {},
  xAxis: [
    {
      type: 'category',
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
      name: 'Direct',
      type: 'bar',
      emphasis: {
        focus: 'series'
      },
      data: [320, 332, 301, 334, 390, 330, 320]
    },
    {
      name: 'Email',
      type: 'bar',
      stack: 'Ad',
      emphasis: {
        focus: 'series'
      },
      data: [120, 132, 101, 134, 90, 230, 210]
    },
    {
      name: 'Union Ads',
      type: 'bar',
      stack: 'Ad',
      emphasis: {
        focus: 'series'
      },
      data: [220, 182, 191, 234, 290, 330, 310]
    },
    {
      name: 'Video Ads',
      type: 'bar',
      stack: 'Ad',
      emphasis: {
        focus: 'series'
      },
      data: [150, 232, 201, 154, 190, 330, 410]
    },
    {
      name: 'Search Engine',
      type: 'bar',
      data: [862, 1018, 964, 1026, 1679, 1600, 1570],
      emphasis: {
        focus: 'series'
      },
      markLine: {
        lineStyle: {
          type: 'dashed'
        },
        data: [[{ type: 'min' }, { type: 'max' }]]
      }
    },
    {
      name: 'Baidu',
      type: 'bar',
      barWidth: 5,
      stack: 'Search Engine',
      emphasis: {
        focus: 'series'
      },
      data: [620, 732, 701, 734, 1090, 1130, 1120]
    },
    {
      name: 'Google',
      type: 'bar',
      stack: 'Search Engine',
      emphasis: {
        focus: 'series'
      },
      data: [120, 132, 101, 134, 290, 230, 220]
    },
    {
      name: 'Bing',
      type: 'bar',
      stack: 'Search Engine',
      emphasis: {
        focus: 'series'
      },
      data: [60, 72, 71, 74, 190, 130, 110]
    },
    {
      name: 'Others',
      type: 'bar',
      stack: 'Search Engine',
      emphasis: {
        focus: 'series'
      },
      data: [62, 82, 91, 84, 109, 110, 120]
    }
  ]
};
"""#,
        option: [
            "tooltip": [
                "trigger": "axis",
                "axisPointer": [
                    "type": "shadow"
                ] as [String: Any]
            ] as [String: Any],
            "legend": [:] as [String: Any],
            "xAxis": [
                [
                    "type": "category",
                    "data": barStackDays
                ] as [String: Any]
            ],
            "yAxis": [
                [
                    "type": "value"
                ] as [String: Any]
            ],
            "series": [
                [
                    "name": "Direct",
                    "type": "bar",
                    "emphasis": ["focus": "series"] as [String: Any],
                    "data": barStackDirect
                ] as [String: Any],
                [
                    "name": "Email",
                    "type": "bar",
                    "stack": "Ad",
                    "emphasis": ["focus": "series"] as [String: Any],
                    "data": barStackEmail
                ] as [String: Any],
                [
                    "name": "Union Ads",
                    "type": "bar",
                    "stack": "Ad",
                    "emphasis": ["focus": "series"] as [String: Any],
                    "data": barStackUnionAds
                ] as [String: Any],
                [
                    "name": "Video Ads",
                    "type": "bar",
                    "stack": "Ad",
                    "emphasis": ["focus": "series"] as [String: Any],
                    "data": barStackVideoAds
                ] as [String: Any],
                [
                    "name": "Search Engine",
                    "type": "bar",
                    "data": barStackSearchEngine,
                    "emphasis": ["focus": "series"] as [String: Any],
                    "markLine": [
                        "lineStyle": ["type": "dashed"] as [String: Any],
                        // one line segment: from the series' min data point to its max.
                        "data": [
                            [
                                ["type": "min"] as [String: Any],
                                ["type": "max"] as [String: Any]
                            ]
                        ]
                    ] as [String: Any]
                ] as [String: Any],
                [
                    "name": "Baidu",
                    "type": "bar",
                    "barWidth": 5.0,
                    "stack": "Search Engine",
                    "emphasis": ["focus": "series"] as [String: Any],
                    "data": barStackBaidu
                ] as [String: Any],
                [
                    "name": "Google",
                    "type": "bar",
                    "stack": "Search Engine",
                    "emphasis": ["focus": "series"] as [String: Any],
                    "data": barStackGoogle
                ] as [String: Any],
                [
                    "name": "Bing",
                    "type": "bar",
                    "stack": "Search Engine",
                    "emphasis": ["focus": "series"] as [String: Any],
                    "data": barStackBing
                ] as [String: Any],
                [
                    "name": "Others",
                    "type": "bar",
                    "stack": "Search Engine",
                    "emphasis": ["focus": "series"] as [String: Any],
                    "data": barStackOthers
                ] as [String: Any]
            ]
        ])
}

private let barStackDays: [String] = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

private let barStackDirect: [Double] = [320, 332, 301, 334, 390, 330, 320]
private let barStackEmail: [Double] = [120, 132, 101, 134, 90, 230, 210]
private let barStackUnionAds: [Double] = [220, 182, 191, 234, 290, 330, 310]
private let barStackVideoAds: [Double] = [150, 232, 201, 154, 190, 330, 410]
private let barStackSearchEngine: [Double] = [862, 1018, 964, 1026, 1679, 1600, 1570]
private let barStackBaidu: [Double] = [620, 732, 701, 734, 1090, 1130, 1120]
private let barStackGoogle: [Double] = [120, 132, 101, 134, 290, 230, 220]
private let barStackBing: [Double] = [60, 72, 71, 74, 190, 130, 110]
private let barStackOthers: [Double] = [62, 82, 91, 84, 109, 110, 120]
