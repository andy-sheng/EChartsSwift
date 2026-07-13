// official-data-transform-multiple-pie — replica of https://echarts.apache.org/examples/zh/editor.html?c=data-transform-multiple-pie
// title: Partition Data to Pies / titleCN: 分割数据到数个饼图
// One source dataset (Product/Sales/Price/Year, 2011–2014) split by three `filter` transforms
// (Year 2011 / 2012 / 2013); each derived dataset feeds one pie via `datasetIndex`. `media` moves
// the three pies from a vertical stack to a horizontal row once the aspect ratio passes 1 — at this
// demo's 640x420 (ratio ≈ 1.52) the `minAspectRatio: 1` branch wins, so both panes show the row.
// DEVIATIONS: none — the official source is a single static `option` literal (no data fetch, no
// closures, no timers). The trailing `export {};` is dropped from webOptionJS (a bare export is a
// SyntaxError in a classic script).
extension EChartsDemoRegistry {
    static let official_data_transform_multiple_pie = EChartsDemo(
        name: "official-data-transform-multiple-pie", category: "dataset",
        summary: "分割数据到数个饼图 — Partition Data to Pies",
        width: 640, height: 420,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
option = {
  dataset: [
    {
      source: [
        ['Product', 'Sales', 'Price', 'Year'],
        ['Cake', 123, 32, 2011],
        ['Cereal', 231, 14, 2011],
        ['Tofu', 235, 5, 2011],
        ['Dumpling', 341, 25, 2011],
        ['Biscuit', 122, 29, 2011],
        ['Cake', 143, 30, 2012],
        ['Cereal', 201, 19, 2012],
        ['Tofu', 255, 7, 2012],
        ['Dumpling', 241, 27, 2012],
        ['Biscuit', 102, 34, 2012],
        ['Cake', 153, 28, 2013],
        ['Cereal', 181, 21, 2013],
        ['Tofu', 395, 4, 2013],
        ['Dumpling', 281, 31, 2013],
        ['Biscuit', 92, 39, 2013],
        ['Cake', 223, 29, 2014],
        ['Cereal', 211, 17, 2014],
        ['Tofu', 345, 3, 2014],
        ['Dumpling', 211, 35, 2014],
        ['Biscuit', 72, 24, 2014]
      ]
    },
    {
      transform: {
        type: 'filter',
        config: { dimension: 'Year', value: 2011 }
      }
    },
    {
      transform: {
        type: 'filter',
        config: { dimension: 'Year', value: 2012 }
      }
    },
    {
      transform: {
        type: 'filter',
        config: { dimension: 'Year', value: 2013 }
      }
    }
  ],
  series: [
    {
      type: 'pie',
      radius: 50,
      center: ['50%', '25%'],
      datasetIndex: 1
    },
    {
      type: 'pie',
      radius: 50,
      center: ['50%', '50%'],
      datasetIndex: 2
    },
    {
      type: 'pie',
      radius: 50,
      center: ['50%', '75%'],
      datasetIndex: 3
    }
  ],

  // Optional. Only for responsive layout:
  media: [
    {
      query: { minAspectRatio: 1 },
      option: {
        series: [
          { center: ['25%', '50%'] },
          { center: ['50%', '50%'] },
          { center: ['75%', '50%'] }
        ]
      }
    },
    {
      option: {
        series: [
          { center: ['50%', '25%'] },
          { center: ['50%', '50%'] },
          { center: ['50%', '75%'] }
        ]
      }
    }
  ]
};
"""#,
        option: [
            "dataset": [
                [
                    "source": dataTransformMultiplePieSource
                ] as [String: Any],
                [
                    "transform": [
                        "type": "filter",
                        "config": ["dimension": "Year", "value": 2011.0] as [String: Any]
                    ] as [String: Any]
                ] as [String: Any],
                [
                    "transform": [
                        "type": "filter",
                        "config": ["dimension": "Year", "value": 2012.0] as [String: Any]
                    ] as [String: Any]
                ] as [String: Any],
                [
                    "transform": [
                        "type": "filter",
                        "config": ["dimension": "Year", "value": 2013.0] as [String: Any]
                    ] as [String: Any]
                ] as [String: Any]
            ],
            "series": [
                [
                    "type": "pie",
                    "radius": 50.0,
                    "center": ["50%", "25%"],
                    "datasetIndex": 1.0
                ] as [String: Any],
                [
                    "type": "pie",
                    "radius": 50.0,
                    "center": ["50%", "50%"],
                    "datasetIndex": 2.0
                ] as [String: Any],
                [
                    "type": "pie",
                    "radius": 50.0,
                    "center": ["50%", "75%"],
                    "datasetIndex": 3.0
                ] as [String: Any]
            ],
            // Optional. Only for responsive layout:
            "media": [
                [
                    "query": ["minAspectRatio": 1.0] as [String: Any],
                    "option": [
                        "series": [
                            ["center": ["25%", "50%"]] as [String: Any],
                            ["center": ["50%", "50%"]] as [String: Any],
                            ["center": ["75%", "50%"]] as [String: Any]
                        ]
                    ] as [String: Any]
                ] as [String: Any],
                [
                    "option": [
                        "series": [
                            ["center": ["50%", "25%"]] as [String: Any],
                            ["center": ["50%", "50%"]] as [String: Any],
                            ["center": ["50%", "75%"]] as [String: Any]
                        ]
                    ] as [String: Any]
                ] as [String: Any]
            ]
        ])
}

// Header row + 20 rows of [Product, Sales, Price, Year]; the three `filter` transforms slice it by Year.
private let dataTransformMultiplePieSource: [[Any]] = [
    ["Product", "Sales", "Price", "Year"],
    ["Cake", 123.0, 32.0, 2011.0],
    ["Cereal", 231.0, 14.0, 2011.0],
    ["Tofu", 235.0, 5.0, 2011.0],
    ["Dumpling", 341.0, 25.0, 2011.0],
    ["Biscuit", 122.0, 29.0, 2011.0],
    ["Cake", 143.0, 30.0, 2012.0],
    ["Cereal", 201.0, 19.0, 2012.0],
    ["Tofu", 255.0, 7.0, 2012.0],
    ["Dumpling", 241.0, 27.0, 2012.0],
    ["Biscuit", 102.0, 34.0, 2012.0],
    ["Cake", 153.0, 28.0, 2013.0],
    ["Cereal", 181.0, 21.0, 2013.0],
    ["Tofu", 395.0, 4.0, 2013.0],
    ["Dumpling", 281.0, 31.0, 2013.0],
    ["Biscuit", 92.0, 39.0, 2013.0],
    ["Cake", 223.0, 29.0, 2014.0],
    ["Cereal", 211.0, 17.0, 2014.0],
    ["Tofu", 345.0, 3.0, 2014.0],
    ["Dumpling", 211.0, 35.0, 2014.0],
    ["Biscuit", 72.0, 24.0, 2014.0]
]
