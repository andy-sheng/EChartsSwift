// official-pie-roseType-simple — replica of https://echarts.apache.org/examples/zh/editor.html?c=pie-roseType-simple
// title: Nightingale Chart / titleCN: 基础南丁格尔玫瑰图
// An `area` roseType pie (equal angles, radius encodes value) with rounded item corners, a bottom
// legend and the standard toolbox (mark / dataView / restore / saveAsImage).
// DEVIATIONS:
//   - trailing `export {};` dropped (a bare export is a SyntaxError in the page's classic script).
//   - canvas is 640x560 rather than the gallery default: the option's outer `radius: 250` needs a
//     500px-tall box, so a 420px-high pane would clip the rose. The option itself is verbatim.
// No closures, no data fetch, no timers — both panes carry the same option.
extension EChartsDemoRegistry {
    static let official_pie_rosetype_simple = EChartsDemo(
        name: "official-pie-roseType-simple", category: "pie",
        summary: "基础南丁格尔玫瑰图 — Nightingale Chart",
        width: 640, height: 560,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
option = {
  legend: {
    top: 'bottom'
  },
  toolbox: {
    show: true,
    feature: {
      mark: { show: true },
      dataView: { show: true, readOnly: false },
      restore: { show: true },
      saveAsImage: { show: true }
    }
  },
  series: [
    {
      name: 'Nightingale Chart',
      type: 'pie',
      radius: [50, 250],
      center: ['50%', '50%'],
      roseType: 'area',
      itemStyle: {
        borderRadius: 8
      },
      data: [
        { value: 40, name: 'rose 1' },
        { value: 38, name: 'rose 2' },
        { value: 32, name: 'rose 3' },
        { value: 30, name: 'rose 4' },
        { value: 28, name: 'rose 5' },
        { value: 26, name: 'rose 6' },
        { value: 22, name: 'rose 7' },
        { value: 18, name: 'rose 8' }
      ]
    }
  ]
};
"""#,
        option: [
            "legend": [
                "top": "bottom"
            ] as [String: Any],
            "toolbox": [
                "show": true,
                "feature": [
                    "mark": ["show": true] as [String: Any],
                    "dataView": ["show": true, "readOnly": false] as [String: Any],
                    "restore": ["show": true] as [String: Any],
                    "saveAsImage": ["show": true] as [String: Any]
                ] as [String: Any]
            ] as [String: Any],
            "series": [
                [
                    "name": "Nightingale Chart",
                    "type": "pie",
                    "radius": [50.0, 250.0],
                    "center": ["50%", "50%"],
                    "roseType": "area",
                    "itemStyle": [
                        "borderRadius": 8.0
                    ] as [String: Any],
                    "data": pieRoseTypeSimpleData
                ] as [String: Any]
            ]
        ])
}

private let pieRoseTypeSimpleData: [[String: Any]] = [
    ["value": 40.0, "name": "rose 1"],
    ["value": 38.0, "name": "rose 2"],
    ["value": 32.0, "name": "rose 3"],
    ["value": 30.0, "name": "rose 4"],
    ["value": 28.0, "name": "rose 5"],
    ["value": 26.0, "name": "rose 6"],
    ["value": 22.0, "name": "rose 7"],
    ["value": 18.0, "name": "rose 8"]
]
