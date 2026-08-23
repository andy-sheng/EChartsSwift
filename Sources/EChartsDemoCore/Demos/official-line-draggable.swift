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
//  - Native pane: the `drive` hook installs the same invisible draggable graphic circles through the
//    native coordinate-conversion and graphic-event seams. Its tooltip formatter is expressed as the
//    equivalent Swift callback.
import Foundation
import EChartsKit

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
        drive: installLineDraggableInteraction,
        option: [
            "title": [
                "text": "Try Dragging these Points",
                "left": "center"
            ] as [String: Any],
            "tooltip": [
                "triggerOn": "none",
                "formatter": { (params: CallbackDataParams) -> String in
                    let values = params.data as? [Any] ?? []
                    let x = values.count > 0 ? lineDraggableNumber(values[0]) : 0
                    let y = values.count > 1 ? lineDraggableNumber(values[1]) : 0
                    return String(format: "X: %.2f<br>Y: %.2f", x, y)
                }
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

@MainActor
private func installLineDraggableInteraction(_ chart: EChartsDemoChart) {
    var data = lineDraggableData

    func graphicElements() -> [[String: Any]] {
        data.enumerated().compactMap { dataIndex, item in
            guard let position = chart.convertToPixel("grid", item) as? [Double],
                  position.count >= 2 else { return nil }

            let ondrag: GraphicElementEventCallback = { element, _ in
                guard let converted = chart.convertFromPixel("grid", [element.x, element.y]) as? [Double],
                      converted.count >= 2 else { return }
                data[dataIndex] = [converted[0], converted[1]]
                chart.setOption([
                    "series": [["id": "a", "data": data] as [String: Any]]
                ], notMerge: false)
                // ZRender dispatches the element's mousemove before its global drag listener.
                // Refresh the programmatic tooltip after the series data changes so the text
                // follows the dragged point in the same frame, matching the browser result.
                chart.dispatch([
                    "type": "showTip", "seriesIndex": 0.0, "dataIndex": Double(dataIndex)
                ])
            }
            let onmousemove: GraphicElementEventCallback = { _, _ in
                chart.dispatch([
                    "type": "showTip", "seriesIndex": 0.0, "dataIndex": Double(dataIndex)
                ])
            }
            let onmouseout: GraphicElementEventCallback = { _, _ in
                chart.dispatch(["type": "hideTip"])
            }
            return [
                "id": "line-draggable-point-\(dataIndex)",
                "type": "circle",
                "position": position,
                "shape": ["cx": 0.0, "cy": 0.0, "r": lineDraggableSymbolSize / 2],
                // ZRenderKit Path has no implicit browser-canvas fill. Give the invisible hit area a
                // real fill so Circle.contain performs winding hit-testing; `invisible` still prevents
                // it from painting.
                "style": ["fill": "#000"],
                "invisible": true,
                "draggable": true,
                "ondrag": ondrag,
                "onmousemove": onmousemove,
                "onmouseout": onmouseout,
                "ignoreModelZ": true,
                "z": 100.0
            ] as [String: Any]
        }
    }

    func updatePosition() {
        chart.setOption(["graphic": graphicElements()], notMerge: false)
    }

    updatePosition()
    chart.on("dataZoom") { _ in updatePosition() }
}

private func lineDraggableNumber(_ value: Any) -> Double {
    if let value = value as? Double { return value }
    if let value = value as? Int { return Double(value) }
    if let value = value as? NSNumber { return value.doubleValue }
    return 0
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
