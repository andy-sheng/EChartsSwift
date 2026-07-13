// official-area-stack — replica of https://echarts.apache.org/examples/zh/editor.html?c=area-stack
// title: Stacked Area Chart / titleCN: 堆叠面积图
// Five `line` series sharing stack 'Total', each with `areaStyle: {}` and `emphasis.focus: 'series'`;
// cross axisPointer tooltip, legend, toolbox/saveAsImage; the top series ('Search Engine') labels its points.
// DEVIATIONS: none — the official source is a single static `option` literal (no data fetch, no
// closures, no timers). Only the leading `/* title: ... */` metadata block and the trailing
// `export {};` are dropped, as they are editor-harness boilerplate rather than option content.
extension EChartsDemoRegistry {
    static let official_area_stack = EChartsDemo(
        name: "official-area-stack", category: "line",
        summary: "堆叠面积图 — Stacked Area Chart",
        width: 640, height: 420,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
option = {
  title: {
    text: 'Stacked Area Chart'
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
    data: ['Email', 'Union Ads', 'Video Ads', 'Direct', 'Search Engine']
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
      name: 'Email',
      type: 'line',
      stack: 'Total',
      areaStyle: {},
      emphasis: {
        focus: 'series'
      },
      data: [120, 132, 101, 134, 90, 230, 210]
    },
    {
      name: 'Union Ads',
      type: 'line',
      stack: 'Total',
      areaStyle: {},
      emphasis: {
        focus: 'series'
      },
      data: [220, 182, 191, 234, 290, 330, 310]
    },
    {
      name: 'Video Ads',
      type: 'line',
      stack: 'Total',
      areaStyle: {},
      emphasis: {
        focus: 'series'
      },
      data: [150, 232, 201, 154, 190, 330, 410]
    },
    {
      name: 'Direct',
      type: 'line',
      stack: 'Total',
      areaStyle: {},
      emphasis: {
        focus: 'series'
      },
      data: [320, 332, 301, 334, 390, 330, 320]
    },
    {
      name: 'Search Engine',
      type: 'line',
      stack: 'Total',
      label: {
        show: true,
        position: 'top'
      },
      areaStyle: {},
      emphasis: {
        focus: 'series'
      },
      data: [820, 932, 901, 934, 1290, 1330, 1320]
    }
  ]
};
"""#,
        option: [
            "title": [
                "text": "Stacked Area Chart"
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
                "data": ["Email", "Union Ads", "Video Ads", "Direct", "Search Engine"]
            ] as [String: Any],
            "toolbox": [
                "feature": [
                    "saveAsImage": [:] as [String: Any]
                ] as [String: Any]
            ] as [String: Any],
            "xAxis": [
                [
                    "type": "category",
                    "boundaryGap": false,
                    "data": ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
                ] as [String: Any]
            ],
            "yAxis": [
                [
                    "type": "value"
                ] as [String: Any]
            ],
            "series": areaStackSeries
        ])
}

// One entry per stacked band, bottom → top; all share stack 'Total' and an empty `areaStyle`
// (empty = "fill with the series color, default opacity").
private let areaStackEmailData: [Double] = [120, 132, 101, 134, 90, 230, 210]
private let areaStackUnionAdsData: [Double] = [220, 182, 191, 234, 290, 330, 310]
private let areaStackVideoAdsData: [Double] = [150, 232, 201, 154, 190, 330, 410]
private let areaStackDirectData: [Double] = [320, 332, 301, 334, 390, 330, 320]
private let areaStackSearchEngineData: [Double] = [820, 932, 901, 934, 1290, 1330, 1320]

private let areaStackSeries: [[String: Any]] = [
    [
        "name": "Email",
        "type": "line",
        "stack": "Total",
        "areaStyle": [:] as [String: Any],
        "emphasis": ["focus": "series"] as [String: Any],
        "data": areaStackEmailData
    ] as [String: Any],
    [
        "name": "Union Ads",
        "type": "line",
        "stack": "Total",
        "areaStyle": [:] as [String: Any],
        "emphasis": ["focus": "series"] as [String: Any],
        "data": areaStackUnionAdsData
    ] as [String: Any],
    [
        "name": "Video Ads",
        "type": "line",
        "stack": "Total",
        "areaStyle": [:] as [String: Any],
        "emphasis": ["focus": "series"] as [String: Any],
        "data": areaStackVideoAdsData
    ] as [String: Any],
    [
        "name": "Direct",
        "type": "line",
        "stack": "Total",
        "areaStyle": [:] as [String: Any],
        "emphasis": ["focus": "series"] as [String: Any],
        "data": areaStackDirectData
    ] as [String: Any],
    [
        "name": "Search Engine",
        "type": "line",
        "stack": "Total",
        "label": [
            "show": true,
            "position": "top"
        ] as [String: Any],
        "areaStyle": [:] as [String: Any],
        "emphasis": ["focus": "series"] as [String: Any],
        "data": areaStackSearchEngineData
    ] as [String: Any]
]
