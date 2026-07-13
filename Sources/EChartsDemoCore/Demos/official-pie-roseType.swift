// official-pie-roseType — replica of https://echarts.apache.org/examples/zh/editor.html?c=pie-roseType
// title: Nightingale Chart / titleCN: 南丁格尔玫瑰图
// Two rose (Nightingale) pies side by side over 8 slices each: `roseType: 'radius'` on the left (the
// central angle still shows the percentage, AND the radius shows the value) and `roseType: 'area'` on
// the right (all sectors share the SAME central angle; the value is shown only through the radius).
// Both use `itemStyle.borderRadius: 5`; the left one hides its labels until hover (`emphasis.label`).
//
// DEVIATIONS from the official source: none of substance — no data fetch, no timers, no closures.
//   - `tooltip.formatter` is a STRING template ('{a} <br/>{b} : {c} ({d}%)'), not a JS function, so
//     it survives the Swift port intact and both panes carry it.
//   - The upstream `legend.data` lists 'rose1'…'rose8' (no space) while the series data names are
//     'rose 1'…'rose 8' (with a space). That mismatch is UPSTREAM — the official example ships it,
//     so the legend shows eight entries that match no datum and the swatches stay unstyled. Kept
//     verbatim in BOTH panes; "fixing" it here would hide a real rendering difference.
//   - The trailing `export {};` is dropped (a bare export is a SyntaxError in a classic script).
extension EChartsDemoRegistry {
    static let official_pie_rosetype = EChartsDemo(
        name: "official-pie-roseType", category: "pie",
        summary: "南丁格尔玫瑰图 — Nightingale Chart",
        width: 640, height: 420,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
option = {
  title: {
    text: 'Nightingale Chart',
    subtext: 'Fake Data',
    left: 'center'
  },
  tooltip: {
    trigger: 'item',
    formatter: '{a} <br/>{b} : {c} ({d}%)'
  },
  legend: {
    left: 'center',
    top: 'bottom',
    data: [
      'rose1',
      'rose2',
      'rose3',
      'rose4',
      'rose5',
      'rose6',
      'rose7',
      'rose8'
    ]
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
      name: 'Radius Mode',
      type: 'pie',
      radius: [20, 140],
      center: ['25%', '50%'],
      roseType: 'radius',
      itemStyle: {
        borderRadius: 5
      },
      label: {
        show: false
      },
      emphasis: {
        label: {
          show: true
        }
      },
      data: [
        { value: 40, name: 'rose 1' },
        { value: 33, name: 'rose 2' },
        { value: 28, name: 'rose 3' },
        { value: 22, name: 'rose 4' },
        { value: 20, name: 'rose 5' },
        { value: 15, name: 'rose 6' },
        { value: 12, name: 'rose 7' },
        { value: 10, name: 'rose 8' }
      ]
    },
    {
      name: 'Area Mode',
      type: 'pie',
      radius: [20, 140],
      center: ['75%', '50%'],
      roseType: 'area',
      itemStyle: {
        borderRadius: 5
      },
      data: [
        { value: 30, name: 'rose 1' },
        { value: 28, name: 'rose 2' },
        { value: 26, name: 'rose 3' },
        { value: 24, name: 'rose 4' },
        { value: 22, name: 'rose 5' },
        { value: 20, name: 'rose 6' },
        { value: 18, name: 'rose 7' },
        { value: 16, name: 'rose 8' }
      ]
    }
  ]
};
"""#,
        option: [
            "title": [
                "text": "Nightingale Chart",
                "subtext": "Fake Data",
                "left": "center"
            ] as [String: Any],
            "tooltip": [
                "trigger": "item",
                "formatter": "{a} <br/>{b} : {c} ({d}%)"
            ] as [String: Any],
            "legend": [
                "left": "center",
                "top": "bottom",
                "data": pieRoseLegendData
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
                    "name": "Radius Mode",
                    "type": "pie",
                    "radius": [20.0, 140.0],
                    "center": ["25%", "50%"],
                    "roseType": "radius",
                    "itemStyle": ["borderRadius": 5.0] as [String: Any],
                    "label": ["show": false] as [String: Any],
                    "emphasis": [
                        "label": ["show": true] as [String: Any]
                    ] as [String: Any],
                    "data": pieRoseRadiusData
                ] as [String: Any],
                [
                    "name": "Area Mode",
                    "type": "pie",
                    "radius": [20.0, 140.0],
                    "center": ["75%", "50%"],
                    "roseType": "area",
                    "itemStyle": ["borderRadius": 5.0] as [String: Any],
                    "data": pieRoseAreaData
                ] as [String: Any]
            ]
        ])
}

// Upstream's legend names ('rose1'…) deliberately differ from the data names ('rose 1'…) — see header.
private let pieRoseLegendData: [String] = [
    "rose1", "rose2", "rose3", "rose4", "rose5", "rose6", "rose7", "rose8"
]

// roseType: 'radius' — central angle = percentage, radius = value.
private let pieRoseRadiusData: [[String: Any]] = [
    ["value": 40.0, "name": "rose 1"],
    ["value": 33.0, "name": "rose 2"],
    ["value": 28.0, "name": "rose 3"],
    ["value": 22.0, "name": "rose 4"],
    ["value": 20.0, "name": "rose 5"],
    ["value": 15.0, "name": "rose 6"],
    ["value": 12.0, "name": "rose 7"],
    ["value": 10.0, "name": "rose 8"]
]

// roseType: 'area' — every sector gets the same central angle; only the radius carries the value.
private let pieRoseAreaData: [[String: Any]] = [
    ["value": 30.0, "name": "rose 1"],
    ["value": 28.0, "name": "rose 2"],
    ["value": 26.0, "name": "rose 3"],
    ["value": 24.0, "name": "rose 4"],
    ["value": 22.0, "name": "rose 5"],
    ["value": 20.0, "name": "rose 6"],
    ["value": 18.0, "name": "rose 7"],
    ["value": 16.0, "name": "rose 8"]
]
