// official-line-draggable — replica of https://echarts.apache.org/examples/zh/editor.html?c=line-draggable
// title: Draggable Points / titleCN: 可拖拽点
// A 5-point smooth line on two value axes (x -100…70, y -30…60, both `axisLine.onZero: false`) with x-
// and y- dataZoom (slider + inside, all `filterMode: 'none'`). The example's POINT is the interaction:
// a `setTimeout(..., 0)` overlays one INVISIBLE draggable `graphic` circle per datum, placed with
// `myChart.convertToPixel('grid', item)`. Dragging one runs `convertFromPixel` and re-`setOption`s the
// series data; hovering one `dispatchAction`s a `showTip` (the tooltip is `triggerOn: 'none'`, so it
// only ever surfaces that way); `myChart.on('dataZoom', ...)` and a window `resize` listener re-place
// the handles when the grid moves under them.
//
// DEVIATIONS from the official source:
//  - Web pane: the source runs VERBATIM — graphic overlay, drag/hover handlers, dataZoom listener and
//    resize listener all included. Dropped only what a classic script cannot parse: the TypeScript
//    annotations (`params: any`, `dx: number, dy: number`, `dataIndex: number`, `pos: number[]`,
//    `(this as any)` → `this`) and the trailing `export {};`. Nothing is simplified.
//  - Native pane: no `drive`. The example's only timeline is that `setTimeout(..., 0)`, and every part
//    of what it installs is beyond a Swift option: the circles are POSITIONED by
//    `myChart.convertToPixel('grid', ...)` (EChartsDemoChart exposes no convertToPixel /
//    convertFromPixel), and their `ondrag` / `onmousemove` / `onmouseout` are JS closures, which an
//    option dictionary cannot carry at all. The handles are `invisible: true`, so the native STILL
//    FRAME loses no pixels — it loses the dragging. The panes agree on the initial render and diverge
//    the moment a point is grabbed: the web pane drags, the native one does not.
//  - Native pane: `tooltip.formatter` is a JS closure and is omitted (see PORT-NOTE). Moot in the still
//    frame anyway — `triggerOn: 'none'` means only the dropped drag handles' `showTip` would show it.
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

setTimeout(function () {
  // Add shadow circles (which is not visible) to enable drag.
  myChart.setOption({
    graphic: data.map(function (item, dataIndex) {
      return {
        type: 'circle',
        position: myChart.convertToPixel('grid', item),
        shape: {
          cx: 0,
          cy: 0,
          r: symbolSize / 2
        },
        invisible: true,
        draggable: true,
        ondrag: function (dx, dy) {
          onPointDragging(dataIndex, [this.x, this.y]);
        },
        onmousemove: function () {
          showTooltip(dataIndex);
        },
        onmouseout: function () {
          hideTooltip(dataIndex);
        },
        z: 100
      };
    })
  });
}, 0);

window.addEventListener('resize', updatePosition);

myChart.on('dataZoom', updatePosition);

function updatePosition() {
  myChart.setOption({
    graphic: data.map(function (item, dataIndex) {
      return {
        position: myChart.convertToPixel('grid', item)
      };
    })
  });
}

function showTooltip(dataIndex) {
  myChart.dispatchAction({
    type: 'showTip',
    seriesIndex: 0,
    dataIndex: dataIndex
  });
}

function hideTooltip(dataIndex) {
  myChart.dispatchAction({
    type: 'hideTip'
  });
}

function onPointDragging(dataIndex, pos) {
  data[dataIndex] = myChart.convertFromPixel('grid', pos);

  // Update data
  myChart.setOption({
    series: [
      {
        id: 'a',
        data: data
      }
    ]
  });
}
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
            // PORT-NOTE: the `graphic` overlay the example installs in its setTimeout is not ported —
            // its circles are positioned by myChart.convertToPixel('grid', ...) and carry ondrag /
            // onmousemove / onmouseout JS closures. See the DEVIATIONS block in the header.
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
// drag-handle circles the native pane cannot carry (see header).
private let lineDraggableSymbolSize: Double = 20
