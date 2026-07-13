// official-bar-label-rotation — replica of https://echarts.apache.org/examples/zh/editor.html?c=bar-label-rotation
// title: Bar Label Rotation / titleCN: 柱状图标签旋转
// Four grouped bar series (Forest/Steppe/Desert/Wetland) over 2012–2016, each carrying the SAME
// label option: rotated 90°, positioned insideBottom, with a rich-text formatter '{c}  {name|{a}}'
// that prints the value followed by the series name.
//
// DEVIATIONS from the official source:
//   - `app.configParameters` / `app.config` (the official editor's live-config sliders for
//     rotate/align/verticalAlign/position/distance, plus its `onChange` re-setOption) are the editor
//     harness, not the chart — dropped. The label option in both panes is FROZEN at app.config's
//     initial values: rotate 90, align 'left', verticalAlign 'middle', position 'insideBottom',
//     distance 15. The `posList` const only fed `app.configParameters`, so it is dropped too.
//   - Consequently `labelOption` in webOptionJS has those five `app.config.*` reads substituted with
//     their literal defaults; everything else (formatter, fontSize, rich, toolbox, tooltip, legend,
//     emphasis, data) is verbatim.
//   - trailing `export {};` removed (a bare export is a SyntaxError in a classic script).
extension EChartsDemoRegistry {
    static let official_bar_label_rotation = EChartsDemo(
        name: "official-bar-label-rotation", category: "bar",
        summary: "柱状图标签旋转 — Bar Label Rotation",
        width: 640, height: 420,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
const labelOption = {
  show: true,
  position: 'insideBottom',
  distance: 15,
  align: 'left',
  verticalAlign: 'middle',
  rotate: 90,
  formatter: '{c}  {name|{a}}',
  fontSize: 16,
  rich: {
    name: {}
  }
};

option = {
  tooltip: {
    trigger: 'axis',
    axisPointer: {
      type: 'shadow'
    }
  },
  legend: {
    data: ['Forest', 'Steppe', 'Desert', 'Wetland']
  },
  toolbox: {
    show: true,
    orient: 'vertical',
    left: 'right',
    top: 'center',
    feature: {
      mark: { show: true },
      dataView: { show: true, readOnly: false },
      magicType: { show: true, type: ['line', 'bar', 'stack'] },
      restore: { show: true },
      saveAsImage: { show: true }
    }
  },
  xAxis: [
    {
      type: 'category',
      axisTick: { show: false },
      data: ['2012', '2013', '2014', '2015', '2016']
    }
  ],
  yAxis: [
    {
      type: 'value'
    }
  ],
  series: [
    {
      name: 'Forest',
      type: 'bar',
      barGap: 0,
      label: labelOption,
      emphasis: {
        focus: 'series'
      },
      data: [320, 332, 301, 334, 390]
    },
    {
      name: 'Steppe',
      type: 'bar',
      label: labelOption,
      emphasis: {
        focus: 'series'
      },
      data: [220, 182, 191, 234, 290]
    },
    {
      name: 'Desert',
      type: 'bar',
      label: labelOption,
      emphasis: {
        focus: 'series'
      },
      data: [150, 232, 201, 154, 190]
    },
    {
      name: 'Wetland',
      type: 'bar',
      label: labelOption,
      emphasis: {
        focus: 'series'
      },
      data: [98, 77, 101, 99, 40]
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
            "legend": [
                "data": ["Forest", "Steppe", "Desert", "Wetland"]
            ] as [String: Any],
            "toolbox": [
                "show": true,
                "orient": "vertical",
                "left": "right",
                "top": "center",
                "feature": [
                    "mark": ["show": true] as [String: Any],
                    "dataView": ["show": true, "readOnly": false] as [String: Any],
                    "magicType": ["show": true, "type": ["line", "bar", "stack"]] as [String: Any],
                    "restore": ["show": true] as [String: Any],
                    "saveAsImage": ["show": true] as [String: Any]
                ] as [String: Any]
            ] as [String: Any],
            "xAxis": [
                [
                    "type": "category",
                    "axisTick": ["show": false] as [String: Any],
                    "data": ["2012", "2013", "2014", "2015", "2016"]
                ] as [String: Any]
            ],
            "yAxis": [
                ["type": "value"] as [String: Any]
            ],
            "series": [
                [
                    "name": "Forest",
                    "type": "bar",
                    "barGap": 0.0,
                    "label": barLabelRotationLabelOption,
                    "emphasis": ["focus": "series"] as [String: Any],
                    "data": [320.0, 332.0, 301.0, 334.0, 390.0]
                ] as [String: Any],
                [
                    "name": "Steppe",
                    "type": "bar",
                    "label": barLabelRotationLabelOption,
                    "emphasis": ["focus": "series"] as [String: Any],
                    "data": [220.0, 182.0, 191.0, 234.0, 290.0]
                ] as [String: Any],
                [
                    "name": "Desert",
                    "type": "bar",
                    "label": barLabelRotationLabelOption,
                    "emphasis": ["focus": "series"] as [String: Any],
                    "data": [150.0, 232.0, 201.0, 154.0, 190.0]
                ] as [String: Any],
                [
                    "name": "Wetland",
                    "type": "bar",
                    "label": barLabelRotationLabelOption,
                    "emphasis": ["focus": "series"] as [String: Any],
                    "data": [98.0, 77.0, 101.0, 99.0, 40.0]
                ] as [String: Any]
            ]
        ])
}

// The one label option shared by all four series. In the official example its five geometry fields
// are live-bound to the editor's `app.config` sliders; here they are frozen at app.config's initial
// values (rotate 90 / align left / verticalAlign middle / position insideBottom / distance 15).
// `formatter` is a plain STRING template (not a closure), so it ports as-is: '{c}' is the value and
// '{name|{a}}' renders the series name through the `rich.name` style.
private let barLabelRotationLabelOption: [String: Any] = [
    "show": true,
    "position": "insideBottom",
    "distance": 15.0,
    "align": "left",
    "verticalAlign": "middle",
    "rotate": 90.0,
    "formatter": "{c}  {name|{a}}",
    "fontSize": 16.0,
    "rich": [
        "name": [:] as [String: Any]
    ] as [String: Any]
]
