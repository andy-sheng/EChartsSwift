// official-line-draggable — replica of https://echarts.apache.org/examples/zh/editor.html?c=line-draggable
// title: Draggable Points / titleCN: 可拖拽点
// A 5-point smooth line on a value/value grid (both axes `axisLine.onZero:false`), with x- and y-
// dataZoom (slider + inside, `filterMode:'none'`), and a `triggerOn:'none'` tooltip that the upstream
// example shows/hides imperatively while a point is dragged.
//
// DEVIATIONS from the official source:
//  - INTERACTION DROPPED (both panes). Upstream, a `setTimeout(..., 0)` overlays one INVISIBLE
//    draggable `graphic` circle per datum (positioned with `myChart.convertToPixel('grid', item)`),
//    and `ondrag`/`onmousemove`/`onmouseout` + `myChart.on('dataZoom', updatePosition)` +
//    `window.addEventListener('resize', ...)` write the dragged point back through
//    `convertFromPixel` and re-`setOption`. The gallery renders ONE static frame from a top-level
//    `option`: there is no `myChart` handle in the option script and no pointer to drag with, so all
//    of that is omitted and only the INITIAL state is ported. The circles are `invisible: true`, so
//    the rendered frame is unaffected — only the dragging is.
//  - The `option` literal itself (title/tooltip/grid/xAxis/yAxis/dataZoom/series) is verbatim in the
//    web pane, including the tooltip formatter closure.
//  - Native pane: `tooltip.formatter` is omitted (see PORT-NOTE) — a JS closure Swift cannot carry.
//    It is inert in a static frame anyway (`triggerOn: 'none'` means only a dispatched `showTip`
//    would surface it).
extension EChartsDemoRegistry {
    static let official_line_draggable = EChartsDemo(
        name: "official-line-draggable", category: "line",
        summary: "可拖拽点 — Draggable Points",
        width: 640, height: 420,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
const symbolSize = 20;
const data = [
  [40, -10],
  [-30, -5],
  [-76.5, 20],
  [-63.5, 40],
  [-22.1, 50]
];

option = {
  title: {
    text: 'Try Dragging these Points',
    left: 'center'
  },
  tooltip: {
    triggerOn: 'none',
    formatter: function (params) {
      return (
        'X: ' +
        params.data[0].toFixed(2) +
        '<br>Y: ' +
        params.data[1].toFixed(2)
      );
    }
  },
  grid: {
    top: '8%',
    bottom: '12%'
  },
  xAxis: {
    min: -100,
    max: 70,
    type: 'value',
    axisLine: { onZero: false }
  },
  yAxis: {
    min: -30,
    max: 60,
    type: 'value',
    axisLine: { onZero: false }
  },
  dataZoom: [
    {
      type: 'slider',
      xAxisIndex: 0,
      filterMode: 'none'
    },
    {
      type: 'slider',
      yAxisIndex: 0,
      filterMode: 'none'
    },
    {
      type: 'inside',
      xAxisIndex: 0,
      filterMode: 'none'
    },
    {
      type: 'inside',
      yAxisIndex: 0,
      filterMode: 'none'
    }
  ],
  series: [
    {
      id: 'a',
      type: 'line',
      smooth: true,
      symbolSize: symbolSize,
      data: data
    }
  ]
};
"""#,
        option: [
            "title": [
                "text": "Try Dragging these Points",
                "left": "center"
            ] as [String: Any],
            "tooltip": [
                "triggerOn": "none"
                // PORT-NOTE: tooltip.formatter omitted — the JS closure rendered the raw datum as
                // "X: <data[0].toFixed(2)><br>Y: <data[1].toFixed(2)>" while a point was dragged.
            ] as [String: Any],
            "grid": [
                "top": "8%",
                "bottom": "12%"
            ] as [String: Any],
            "xAxis": [
                "min": -100.0,
                "max": 70.0,
                "type": "value",
                "axisLine": ["onZero": false] as [String: Any]
            ] as [String: Any],
            "yAxis": [
                "min": -30.0,
                "max": 60.0,
                "type": "value",
                "axisLine": ["onZero": false] as [String: Any]
            ] as [String: Any],
            "dataZoom": [
                [
                    "type": "slider",
                    "xAxisIndex": 0.0,
                    "filterMode": "none"
                ] as [String: Any],
                [
                    "type": "slider",
                    "yAxisIndex": 0.0,
                    "filterMode": "none"
                ] as [String: Any],
                [
                    "type": "inside",
                    "xAxisIndex": 0.0,
                    "filterMode": "none"
                ] as [String: Any],
                [
                    "type": "inside",
                    "yAxisIndex": 0.0,
                    "filterMode": "none"
                ] as [String: Any]
            ],
            "series": [
                [
                    "id": "a",
                    "type": "line",
                    "smooth": true,
                    "symbolSize": lineDraggableSymbolSize,
                    "data": lineDraggableData
                ] as [String: Any]
            ]
        ])
}

// The draggable points, [x, y] on a value/value grid (upstream `const data`).
private let lineDraggableData: [[Double]] = [
    [40, -10],
    [-30, -5],
    [-76.5, 20],
    [-63.5, 40],
    [-22.1, 50]
]

// Upstream `const symbolSize = 20` — the series symbol size, and the diameter of the invisible
// drag-handle circles this port drops (see header).
private let lineDraggableSymbolSize: Double = 20
