// official-pie-labelLine-adjust — replica of https://echarts.apache.org/examples/zh/editor.html?c=pie-labelLine-adjust
// title: Label Line Adjust / titleCN: 饼图引导线调整
// Three stacked pie series (one per third of the canvas), each with `alignTo: 'edge'` rich labels,
// a short label line (length 15 / length2 0 / maxSurfaceAngle 80) and a `labelLayout` closure that
// snaps the label line's end point to the label's inner edge (left half vs right half of the chart).
//
// DEVIATIONS from the official source:
//   - The TypeScript type assertion `params.labelLinePoints as number[][]` is dropped in webOptionJS
//     (a bare `as` cast is a SyntaxError in a classic script). The closure is otherwise verbatim, and
//     still reads the page's `myChart` global — WebPage.swift names the instance `myChart` too.
//   - Trailing `export {};` dropped (SyntaxError in a classic script).
//   - NATIVE pane: `series[].labelLayout` is a JS closure and cannot be expressed in the Swift
//     option, so it is omitted there. The pies still render; only the label-line end-point nudge
//     (the point of the example) is missing from the native pane — that is the diff we want to see.
//   - Canvas bumped to 640x560: three pies stacked at 33.33% each need the vertical room.
extension EChartsDemoRegistry {
    static let official_pie_labelline_adjust = EChartsDemo(
        name: "official-pie-labelLine-adjust", category: "pie",
        summary: "饼图引导线调整 — Label Line Adjust",
        width: 640, height: 560,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
var datas = [
  ////////////////////////////////////////
  [
    { name: '圣彼得堡来客', value: 5.6 },
    { name: '陀思妥耶夫斯基全集', value: 1 },
    { name: '史记精注全译（全6册）', value: 0.8 },
    { name: '加德纳艺术通史', value: 0.5 },
    { name: '表象与本质', value: 0.5 },
    { name: '其它', value: 3.8 }
  ],
  // ////////////////////////////////////////
  [
    { name: '银河帝国5：迈向基地', value: 3.8 },
    { name: '俞军产品方法论', value: 2.3 },
    { name: '艺术的逃难', value: 2.2 },
    { name: '第一次世界大战回忆录（全五卷）', value: 1.3 },
    { name: 'Scrum 精髓', value: 1.2 },
    { name: '其它', value: 5.7 }
  ],

  ////////////////////////////////////////
  [
    { name: '克莱因壶', value: 3.5 },
    { name: '投资最重要的事', value: 2.8 },
    { name: '简读中国史', value: 1.7 },
    { name: '你当像鸟飞往你的山', value: 1.4 },
    { name: '表象与本质', value: 0.5 },
    { name: '其它', value: 3.8 }
  ]
];

option = {
  title: {
    text: '阅读书籍分布',
    left: 'center',
    textStyle: {
      color: '#999',
      fontWeight: 'normal',
      fontSize: 14
    }
  },
  series: datas.map(function (data, idx) {
    var top = idx * 33.3;
    return {
      type: 'pie',
      radius: [20, 60],
      top: top + '%',
      height: '33.33%',
      left: 'center',
      width: 400,
      itemStyle: {
        borderColor: '#fff',
        borderWidth: 1
      },
      label: {
        alignTo: 'edge',
        formatter: '{name|{b}}\n{time|{c} 小时}',
        minMargin: 5,
        edgeDistance: 10,
        lineHeight: 15,
        rich: {
          time: {
            fontSize: 10,
            color: '#999'
          }
        }
      },
      labelLine: {
        length: 15,
        length2: 0,
        maxSurfaceAngle: 80
      },
      labelLayout: function (params) {
        const isLeft = params.labelRect.x < myChart.getWidth() / 2;
        const points = params.labelLinePoints;
        // Update the end point.
        points[2][0] = isLeft
          ? params.labelRect.x
          : params.labelRect.x + params.labelRect.width;

        return {
          labelLinePoints: points
        };
      },
      data: data
    };
  })
};
"""#,
        option: [
            "title": [
                "text": "阅读书籍分布",
                "left": "center",
                "textStyle": [
                    "color": "#999",
                    "fontWeight": "normal",
                    "fontSize": 14.0
                ] as [String: Any]
            ] as [String: Any],
            "series": pieLabelLineAdjustSeries
        ])
}

// The three pies' data, one array per third of the canvas (name / value = hours read).
private let pieLabelLineAdjustDatas: [[[String: Any]]] = [
    [
        ["name": "圣彼得堡来客", "value": 5.6],
        ["name": "陀思妥耶夫斯基全集", "value": 1.0],
        ["name": "史记精注全译（全6册）", "value": 0.8],
        ["name": "加德纳艺术通史", "value": 0.5],
        ["name": "表象与本质", "value": 0.5],
        ["name": "其它", "value": 3.8]
    ],
    [
        ["name": "银河帝国5：迈向基地", "value": 3.8],
        ["name": "俞军产品方法论", "value": 2.3],
        ["name": "艺术的逃难", "value": 2.2],
        ["name": "第一次世界大战回忆录（全五卷）", "value": 1.3],
        ["name": "Scrum 精髓", "value": 1.2],
        ["name": "其它", "value": 5.7]
    ],
    [
        ["name": "克莱因壶", "value": 3.5],
        ["name": "投资最重要的事", "value": 2.8],
        ["name": "简读中国史", "value": 1.7],
        ["name": "你当像鸟飞往你的山", "value": 1.4],
        ["name": "表象与本质", "value": 0.5],
        ["name": "其它", "value": 3.8]
    ]
]

// `top: idx * 33.3 + '%'`, as JS stringifies it.
private let pieLabelLineAdjustTops: [String] = ["0%", "33.3%", "66.6%"]

// The JS `datas.map(function (data, idx) { ... })`, unrolled.
private let pieLabelLineAdjustSeries: [[String: Any]] = {
    var series: [[String: Any]] = []
    for (idx, data) in pieLabelLineAdjustDatas.enumerated() {
        let label: [String: Any] = [
            "alignTo": "edge",
            "formatter": "{name|{b}}\n{time|{c} 小时}",
            "minMargin": 5.0,
            "edgeDistance": 10.0,
            "lineHeight": 15.0,
            "rich": [
                "time": [
                    "fontSize": 10.0,
                    "color": "#999"
                ] as [String: Any]
            ] as [String: Any]
        ]
        let one: [String: Any] = [
            "type": "pie",
            "radius": [20.0, 60.0],
            "top": pieLabelLineAdjustTops[idx],
            "height": "33.33%",
            "left": "center",
            "width": 400.0,
            "itemStyle": [
                "borderColor": "#fff",
                "borderWidth": 1.0
            ] as [String: Any],
            "label": label,
            "labelLine": [
                "length": 15.0,
                "length2": 0.0,
                "maxSurfaceAngle": 80.0
            ] as [String: Any],
            // PORT-NOTE: labelLayout omitted — the JS closure moved each label line's end point
            // (labelLinePoints[2][0]) to the label rect's inner edge: its left edge for labels in the
            // chart's left half, its right edge for labels in the right half. Not expressible in Swift.
            "data": data
        ]
        series.append(one)
    }
    return series
}()
