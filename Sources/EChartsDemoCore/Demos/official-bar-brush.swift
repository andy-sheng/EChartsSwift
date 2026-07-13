// official-bar-brush — replica of https://echarts.apache.org/examples/zh/editor.html?c=bar-brush
// title: Brush Select on Column Chart / titleCN: 柱状图框选
// Four bar series in two stacks ('one' = bar+bar2, 'two' = bar3+bar4) over 10 'ClassN' categories,
// with a `brush` component (rect/polygon/lineX/lineY/keep/clear in its toolbox, brushing xAxisIndex 0),
// a toolbox exposing magicType:['stack'] + dataView, a shared tooltip, and a shadow emphasis itemStyle.
//
// DEVIATIONS from the official source:
//   - DATA INLINED. The example fills xAxisData/data1..data4 in a `for` loop from Math.random(), so
//     every reload draws a different chart — useless for a native-vs-web diff. Both panes now carry
//     ONE fixed sample drawn from the same distributions the loop uses (data1 = random*2, data2 =
//     random*5, data3 = random+0.3, data4 = random, each .toFixed(2)); xAxisData is unchanged
//     ('Class0'…'Class9').
//   - INTERACTION DROPPED. The trailing `myChart.on('brushSelected', ...)` handler — which re-setOptions
//     a black `title` listing the brushed data indices — is gone from both panes: the gallery renders one
//     static frame with no pointer input, so the handler could never fire, and `myChart` does not exist
//     at the time the option script runs. The rendered frame is the pre-brush initial state, which is
//     exactly what the official example shows before you drag a selection.
//   - `export {};` dropped (a bare export is a SyntaxError in the page's classic script).
extension EChartsDemoRegistry {
    static let official_bar_brush = EChartsDemo(
        name: "official-bar-brush", category: "bar",
        summary: "柱状图框选 — Brush Select on Column Chart",
        width: 640, height: 420,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
let xAxisData = ['Class0', 'Class1', 'Class2', 'Class3', 'Class4', 'Class5', 'Class6', 'Class7', 'Class8', 'Class9'];
let data1 = [1.24, 0.37, 1.82, 0.95, 1.51, 0.68, 1.09, 1.73, 0.42, 1.36];
let data2 = [3.41, 4.72, 1.85, 2.96, 0.63, 4.18, 2.27, 3.59, 1.04, 4.85];
let data3 = [0.87, 1.12, 0.44, 1.25, 0.61, 0.98, 1.19, 0.53, 0.76, 1.07];
let data4 = [0.62, 0.19, 0.88, 0.35, 0.71, 0.47, 0.93, 0.26, 0.58, 0.14];

var emphasisStyle = {
  itemStyle: {
    shadowBlur: 10,
    shadowColor: 'rgba(0,0,0,0.3)'
  }
};

option = {
  legend: {
    data: ['bar', 'bar2', 'bar3', 'bar4'],
    left: '10%'
  },
  brush: {
    toolbox: ['rect', 'polygon', 'lineX', 'lineY', 'keep', 'clear'],
    xAxisIndex: 0
  },
  toolbox: {
    feature: {
      magicType: {
        type: ['stack']
      },
      dataView: {}
    }
  },
  tooltip: {},
  xAxis: {
    data: xAxisData,
    name: 'X Axis',
    axisLine: { onZero: true },
    splitLine: { show: false },
    splitArea: { show: false }
  },
  yAxis: {},
  grid: {
    bottom: 100
  },
  series: [
    {
      name: 'bar',
      type: 'bar',
      stack: 'one',
      emphasis: emphasisStyle,
      data: data1
    },
    {
      name: 'bar2',
      type: 'bar',
      stack: 'one',
      emphasis: emphasisStyle,
      data: data2
    },
    {
      name: 'bar3',
      type: 'bar',
      stack: 'two',
      emphasis: emphasisStyle,
      data: data3
    },
    {
      name: 'bar4',
      type: 'bar',
      stack: 'two',
      emphasis: emphasisStyle,
      data: data4
    }
  ]
};
"""#,
        option: [
            "legend": [
                "data": ["bar", "bar2", "bar3", "bar4"],
                "left": "10%"
            ] as [String: Any],
            "brush": [
                "toolbox": ["rect", "polygon", "lineX", "lineY", "keep", "clear"],
                "xAxisIndex": 0.0
            ] as [String: Any],
            "toolbox": [
                "feature": [
                    "magicType": [
                        "type": ["stack"]
                    ] as [String: Any],
                    "dataView": [:] as [String: Any]
                ] as [String: Any]
            ] as [String: Any],
            "tooltip": [:] as [String: Any],
            "xAxis": [
                "data": barBrushCategories,
                "name": "X Axis",
                "axisLine": ["onZero": true] as [String: Any],
                "splitLine": ["show": false] as [String: Any],
                "splitArea": ["show": false] as [String: Any]
            ] as [String: Any],
            "yAxis": [:] as [String: Any],
            "grid": [
                "bottom": 100.0
            ] as [String: Any],
            "series": [
                [
                    "name": "bar",
                    "type": "bar",
                    "stack": "one",
                    "emphasis": barBrushEmphasisStyle,
                    "data": barBrushData1
                ] as [String: Any],
                [
                    "name": "bar2",
                    "type": "bar",
                    "stack": "one",
                    "emphasis": barBrushEmphasisStyle,
                    "data": barBrushData2
                ] as [String: Any],
                [
                    "name": "bar3",
                    "type": "bar",
                    "stack": "two",
                    "emphasis": barBrushEmphasisStyle,
                    "data": barBrushData3
                ] as [String: Any],
                [
                    "name": "bar4",
                    "type": "bar",
                    "stack": "two",
                    "emphasis": barBrushEmphasisStyle,
                    "data": barBrushData4
                ] as [String: Any]
            ]
        ])
}

// `var emphasisStyle` in the source — shared by all four series.
private let barBrushEmphasisStyle: [String: Any] = [
    "itemStyle": [
        "shadowBlur": 10.0,
        "shadowColor": "rgba(0,0,0,0.3)"
    ] as [String: Any]
]

// The loop-generated 'Class' + i labels, frozen.
private let barBrushCategories: [String] = [
    "Class0", "Class1", "Class2", "Class3", "Class4",
    "Class5", "Class6", "Class7", "Class8", "Class9"
]

// One fixed draw from each series' distribution (see DEVIATIONS): random*2 / random*5 /
// random+0.3 / random, all .toFixed(2).
private let barBrushData1: [Double] = [1.24, 0.37, 1.82, 0.95, 1.51, 0.68, 1.09, 1.73, 0.42, 1.36]
private let barBrushData2: [Double] = [3.41, 4.72, 1.85, 2.96, 0.63, 4.18, 2.27, 3.59, 1.04, 4.85]
private let barBrushData3: [Double] = [0.87, 1.12, 0.44, 1.25, 0.61, 0.98, 1.19, 0.53, 0.76, 1.07]
private let barBrushData4: [Double] = [0.62, 0.19, 0.88, 0.35, 0.71, 0.47, 0.93, 0.26, 0.58, 0.14]
