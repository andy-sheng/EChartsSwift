// official-radar — replica of https://echarts.apache.org/examples/zh/editor.html?c=radar
// title: Basic Radar Chart / titleCN: 基础雷达图
// Two data items ('Allocated Budget' vs 'Actual Spending') on one 6-indicator radar coordinate
// system, with a title and a legend that toggles the two items.
// DEVIATIONS from the official source: none. The example has no data fetch, no closures, no
// animation/timer, and no map — webOptionJS is the source verbatim (only the trailing `export {}`,
// a TS-module artifact of the gallery's build, is dropped).
extension EChartsDemoRegistry {
    static let official_radar = EChartsDemo(
        name: "official-radar", category: "radar",
        summary: "基础雷达图 — Basic Radar Chart",
        width: 640, height: 420,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
option = {
  title: {
    text: 'Basic Radar Chart'
  },
  legend: {
    data: ['Allocated Budget', 'Actual Spending']
  },
  radar: {
    // shape: 'circle',
    indicator: [
      { name: 'Sales', max: 6500 },
      { name: 'Administration', max: 16000 },
      { name: 'Information Technology', max: 30000 },
      { name: 'Customer Support', max: 38000 },
      { name: 'Development', max: 52000 },
      { name: 'Marketing', max: 25000 }
    ]
  },
  series: [
    {
      name: 'Budget vs spending',
      type: 'radar',
      data: [
        {
          value: [4200, 3000, 20000, 35000, 50000, 18000],
          name: 'Allocated Budget'
        },
        {
          value: [5000, 14000, 28000, 26000, 42000, 21000],
          name: 'Actual Spending'
        }
      ]
    }
  ]
};
"""#,
        option: [
            "title": [
                "text": "Basic Radar Chart"
            ] as [String: Any],
            "legend": [
                "data": ["Allocated Budget", "Actual Spending"]
            ] as [String: Any],
            "radar": [
                // shape: 'circle' — commented out upstream too.
                "indicator": [
                    ["name": "Sales", "max": 6500.0] as [String: Any],
                    ["name": "Administration", "max": 16000.0] as [String: Any],
                    ["name": "Information Technology", "max": 30000.0] as [String: Any],
                    ["name": "Customer Support", "max": 38000.0] as [String: Any],
                    ["name": "Development", "max": 52000.0] as [String: Any],
                    ["name": "Marketing", "max": 25000.0] as [String: Any]
                ]
            ] as [String: Any],
            "series": [
                [
                    "name": "Budget vs spending",
                    "type": "radar",
                    "data": [
                        [
                            "value": [4200.0, 3000.0, 20000.0, 35000.0, 50000.0, 18000.0],
                            "name": "Allocated Budget"
                        ] as [String: Any],
                        [
                            "value": [5000.0, 14000.0, 28000.0, 26000.0, 42000.0, 21000.0],
                            "name": "Actual Spending"
                        ] as [String: Any]
                    ]
                ] as [String: Any]
            ]
        ])
}
