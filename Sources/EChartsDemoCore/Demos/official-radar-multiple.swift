// official-radar-multiple — replica of https://echarts.apache.org/examples/zh/editor.html?c=radar-multiple
// title: Multiple Radar / titleCN: 多雷达图
// Three independent radar coordinate systems on one canvas (4-, 5- and 12-axis), each fed by its own
// `radar` series via `radarIndex`; a shared legend selects across all five data items.
// DEVIATIONS:
//   - The third radar's `indicator` is an IIFE in the official source (`for i in 1...12 → { text: i + '月' }`).
//     webOptionJS keeps that IIFE VERBATIM; the native pane expands it to the same 12 literal indicators,
//     since a Swift option cannot carry a JS closure — the produced data is identical either way.
//   - Nothing else changed: no data fetch, no timers, no formatters in the source.
extension EChartsDemoRegistry {
    static let official_radar_multiple = EChartsDemo(
        name: "official-radar-multiple", category: "radar",
        summary: "多雷达图 — Multiple Radar",
        width: 640, height: 420,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
option = {
  title: {
    text: 'Multiple Radar'
  },
  tooltip: {
    trigger: 'axis'
  },
  legend: {
    left: 'center',
    data: [
      'A Software',
      'A Phone',
      'Another Phone',
      'Precipitation',
      'Evaporation'
    ]
  },
  radar: [
    {
      indicator: [
        { text: 'Brand', max: 100 },
        { text: 'Content', max: 100 },
        { text: 'Usability', max: 100 },
        { text: 'Function', max: 100 }
      ],
      center: ['25%', '40%'],
      radius: 80
    },
    {
      indicator: [
        { text: 'Look', max: 100 },
        { text: 'Photo', max: 100 },
        { text: 'System', max: 100 },
        { text: 'Performance', max: 100 },
        { text: 'Screen', max: 100 }
      ],
      radius: 80,
      center: ['50%', '60%']
    },
    {
      indicator: (function () {
        var res = [];
        for (var i = 1; i <= 12; i++) {
          res.push({ text: i + '月', max: 100 });
        }
        return res;
      })(),
      center: ['75%', '40%'],
      radius: 80
    }
  ],
  series: [
    {
      type: 'radar',
      tooltip: {
        trigger: 'item'
      },
      areaStyle: {},
      data: [
        {
          value: [60, 73, 85, 40],
          name: 'A Software'
        }
      ]
    },
    {
      type: 'radar',
      radarIndex: 1,
      areaStyle: {},
      data: [
        {
          value: [85, 90, 90, 95, 95],
          name: 'A Phone'
        },
        {
          value: [95, 80, 95, 90, 93],
          name: 'Another Phone'
        }
      ]
    },
    {
      type: 'radar',
      radarIndex: 2,
      areaStyle: {},
      data: [
        {
          name: 'Precipitation',
          value: [
            2.6, 5.9, 9.0, 26.4, 28.7, 70.7, 75.6, 82.2, 48.7, 18.8, 6.0, 2.3
          ]
        },
        {
          name: 'Evaporation',
          value: [
            2.0, 4.9, 7.0, 23.2, 25.6, 76.7, 35.6, 62.2, 32.6, 20.0, 6.4, 3.3
          ]
        }
      ]
    }
  ]
};
"""#,
        option: [
            "title": [
                "text": "Multiple Radar"
            ] as [String: Any],
            "tooltip": [
                "trigger": "axis"
            ] as [String: Any],
            "legend": [
                "left": "center",
                "data": [
                    "A Software",
                    "A Phone",
                    "Another Phone",
                    "Precipitation",
                    "Evaporation"
                ]
            ] as [String: Any],
            "radar": [
                [
                    "indicator": radarMultipleProductIndicator,
                    "center": ["25%", "40%"],
                    "radius": 80.0
                ] as [String: Any],
                [
                    "indicator": radarMultiplePhoneIndicator,
                    "radius": 80.0,
                    "center": ["50%", "60%"]
                ] as [String: Any],
                [
                    // The official source builds these 12 in a JS IIFE; same values, expanded in Swift.
                    "indicator": radarMultipleMonthIndicator,
                    "center": ["75%", "40%"],
                    "radius": 80.0
                ] as [String: Any]
            ],
            "series": [
                [
                    "type": "radar",
                    "tooltip": [
                        "trigger": "item"
                    ] as [String: Any],
                    "areaStyle": [:] as [String: Any],
                    "data": [
                        [
                            "value": [60.0, 73.0, 85.0, 40.0],
                            "name": "A Software"
                        ] as [String: Any]
                    ]
                ] as [String: Any],
                [
                    "type": "radar",
                    "radarIndex": 1.0,
                    "areaStyle": [:] as [String: Any],
                    "data": [
                        [
                            "value": [85.0, 90.0, 90.0, 95.0, 95.0],
                            "name": "A Phone"
                        ] as [String: Any],
                        [
                            "value": [95.0, 80.0, 95.0, 90.0, 93.0],
                            "name": "Another Phone"
                        ] as [String: Any]
                    ]
                ] as [String: Any],
                [
                    "type": "radar",
                    "radarIndex": 2.0,
                    "areaStyle": [:] as [String: Any],
                    "data": [
                        [
                            "name": "Precipitation",
                            "value": radarMultiplePrecipitation
                        ] as [String: Any],
                        [
                            "name": "Evaporation",
                            "value": radarMultipleEvaporation
                        ] as [String: Any]
                    ]
                ] as [String: Any]
            ]
        ])
}

// --- radar 0: a software product, 4 axes ---
private let radarMultipleProductIndicator: [[String: Any]] = [
    ["text": "Brand", "max": 100.0],
    ["text": "Content", "max": 100.0],
    ["text": "Usability", "max": 100.0],
    ["text": "Function", "max": 100.0]
]

// --- radar 1: two phones, 5 axes ---
private let radarMultiplePhoneIndicator: [[String: Any]] = [
    ["text": "Look", "max": 100.0],
    ["text": "Photo", "max": 100.0],
    ["text": "System", "max": 100.0],
    ["text": "Performance", "max": 100.0],
    ["text": "Screen", "max": 100.0]
]

// --- radar 2: 12 months, the IIFE-generated axes ---
private let radarMultipleMonthIndicator: [[String: Any]] = (1...12).map {
    ["text": "\($0)月", "max": 100.0]
}

private let radarMultiplePrecipitation: [Double] = [
    2.6, 5.9, 9.0, 26.4, 28.7, 70.7, 75.6, 82.2, 48.7, 18.8, 6.0, 2.3
]

private let radarMultipleEvaporation: [Double] = [
    2.0, 4.9, 7.0, 23.2, 25.6, 76.7, 35.6, 62.2, 32.6, 20.0, 6.4, 3.3
]
