// official-matrix-confusion — replica of https://echarts.apache.org/examples/zh/editor.html?c=matrix-confusion
// title: Confusion Matrix / titleCN: 混淆矩阵
// A 2x2 confusion matrix on the `matrix` coordinate system: the matrix component draws the
// Positive/Negative column + row headers, and a `custom` series (coordinateSystem: 'matrix') fills each
// body cell with a rect — green on the diagonal (True Positive / True Negative), red off it — carrying a
// two-line rich label (`{name|...}\n{value|...}`). Two `graphic` texts label the axes ("True Class" across
// the top, "Predicted Class" rotated down the left).
//
// DEVIATIONS from the official source:
//   - NATIVE PANE UNSUPPORTED: the chart IS the renderItem closure. Every cell rect on screen comes from
//     JS (`api.value` / `api.layout([x, y]).rect` / `api.style`), and a Swift `[String: Any]` option cannot
//     carry a function — without it the `custom` series draws nothing and only the matrix backdrop plus the
//     two graphic texts would remain. Hence nativeSupported: false. The Swift option below still mirrors
//     every other key (see the notes for the two JS closures).
//   - GRAPHIC x: `window.innerWidth` → `myChart.getWidth()` (web pane) / a constant (native pane).
//     `graphic` x is in CHART-CANVAS pixels, and upstream reads `window.innerWidth` only because the
//     official preview gives the chart div the full window — there, chart width == window.innerWidth, and
//     `(window.innerWidth - 600) / 2` is the matrix's left edge (the matrix is `width: 600, left: 'center'`).
//     Our page puts the chart in a FIXED `demo.width` box inside an arbitrarily-sized, page-zoomed
//     WKWebView, so `window.innerWidth` there is the pane's width, not the chart's: verbatim, both texts
//     drift off the matrix (and "Predicted Class" off-canvas) at every pane size but one. `myChart.getWidth()`
//     IS the quantity upstream's expression stands for, so the web pane reproduces the official rendering at
//     any pane size. Swift has no viewport to read at all, so the native option evaluates the same
//     expressions against this demo's 720px canvas (left edge = 60): x = 60 + 600/6*4 = 460, x = 60 - 50 = 10
//     — the values `myChart.getWidth()` yields on a 720px chart. Everything else in the JS is verbatim.
//   - No other change: the source is a single static `option` literal with no data fetch and no timers, so
//     it needs no `drive`.
import Foundation
import EChartsKit

// upstream renderItem: one rect per confusion-matrix cell, filled green on the diagonal (x === y) / red
//   off it, sized to the cell rect from `api.layout([x, y]).rect` (the matrix coord's cell box).
private func matrixConfusionStr(_ v: Any?) -> String {
    if let s = v as? String { return s }
    if let n = v as? NSNumber { return n.stringValue }
    return String(describing: v)
}
private let matrixConfusionRenderItem: CustomSeriesRenderItem = { _, api in
    // `value` returns the ordinal store index (0/1) for matrix category dimensions. Upstream's JS
    // exposes the original category string here; use the port's explicit raw-ordinal accessor so the
    // label says Positive/Negative and so matrix `layout` receives the same locator as upstream.
    let x = api.ordinalRawValue(0.0, nil) ?? api.value(0.0, nil)
    let y = api.ordinalRawValue(1.0, nil) ?? api.value(1.0, nil)
    guard let rect = api.layout([x, y], nil)?.rect else { return nil }
    let isDiagonal = matrixConfusionStr(x) == matrixConfusionStr(y)
    let truth = matrixConfusionStr(y)
    let count = matrixConfusionStr(api.value(2.0, nil))
    let labelText = "{name|\(isDiagonal ? "True " : "False ")\(truth)}\n{value|\(count)}"
    return [
        "type": "rect",
        "shape": ["x": rect.x, "y": rect.y, "width": rect.width, "height": rect.height] as [String: Any],
        "style": api.style(["fill": isDiagonal ? "#8f8" : "#f88"], nil),
        "textConfig": ["position": "inside"] as [String: Any],
        "textContent": [
            "type": "text",
            "style": [
                "text": labelText,
                "align": "center",
                "verticalAlign": "middle",
                "rich": [
                    "name": [
                        "fill": "#fff",
                        "backgroundColor": "#999",
                        "stroke": "#333",
                        "lineWidth": 2.0,
                        "padding": 5.0,
                        "fontSize": 18.0
                    ] as [String: Any],
                    "value": [
                        "fill": "#444",
                        "lineWidth": 0.0,
                        "padding": 5.0,
                        "fontSize": 16.0,
                        "align": "center"
                    ] as [String: Any]
                ] as [String: Any]
            ] as [String: Any]
        ] as [String: Any]
    ] as [String: Any]
}

// Native equivalent of the official `label.formatter` closure. The shared data-format mixin invokes
// this typed callback with the raw [predicted class, true class, count] row.
private let matrixConfusionLabelFormatter: (CallbackDataParams) -> String = { params in
    guard let value = params.value as? [Any], value.count >= 3 else { return "" }
    let predicted = matrixConfusionStr(value[0])
    let truth = matrixConfusionStr(value[1])
    let count = matrixConfusionStr(value[2])
    return "{name|\(predicted == truth ? "True " : "False ")\(truth)}\n{value|\(count)}"
}

extension EChartsDemoRegistry {
    static let official_matrix_confusion = EChartsDemo(
        name: "official-matrix-confusion", category: "matrix",
        summary: "混淆矩阵 — Confusion Matrix",
        width: 720, height: 460,
        nativeSupported: true,   // renderItem ported (matrixConfusionRenderItem) — see header
        collection: .official,
        webOptionJS: #"""
const label = {
  fontSize: 16,
  color: '#555'
};
option = {
  matrix: {
    x: {
      data: ['Positive', 'Negative'],
      label
    },
    y: {
      data: ['Positive', 'Negative'],
      label
    },
    top: 80,
    width: 600,
    left: 'center'
  },
  series: {
    type: 'custom',
    coordinateSystem: 'matrix',
    data: [
      ['Positive', 'Positive', 10],
      ['Positive', 'Negative', 2],
      ['Negative', 'Positive', 3],
      ['Negative', 'Negative', 5]
    ],
    label: {
      show: true,
      formatter: (params) => {
        const value = params.value[2];
        return (
          '{name|' +
          (params.value[0] === params.value[1] ? 'True ' : 'False ') +
          params.value[1] +
          '}\n{value|' +
          value +
          '}'
        );
      },
      rich: {
        name: {
          color: '#fff',
          backgroundColor: '#999',
          textBorderColor: '#333',
          padding: 5,
          fontSize: 18
        },
        value: {
          color: '#444',
          textBorderWidth: 0,
          padding: 5,
          fontSize: 16,
          align: 'center'
        }
      }
    },
    renderItem: function (params, api) {
      const x = api.value(0);
      const y = api.value(1);
      const rect = api.layout([x, y]).rect;
      return {
        type: 'rect',
        shape: {
          x: rect.x,
          y: rect.y,
          width: rect.width,
          height: rect.height,
        },
        style: api.style({
          fill: x === y ? '#8f8' : '#f88'
        })
      };
    }
  },
  graphic: {
    elements: [
      {
        type: 'text',
        style: {
          text: 'True Class',
          fill: '#333',
          font: 'bold 24px serif',
          textAlign: 'center'
        },
        x: (myChart.getWidth() - 600) / 2 + (600 / 6) * 4,
        y: 40
      },
      {
        type: 'text',
        style: {
          text: 'Predicted Class',
          fill: '#333',
          font: 'bold 24px serif',
          textAlign: 'center'
        },
        x: (myChart.getWidth() - 600) / 2 - 50,
        y: 270,
        rotation: Math.PI / 2
      }
    ]
  }
};
"""#,
        option: [
            "matrix": [
                "x": [
                    "data": ["Positive", "Negative"],
                    "label": matrixConfusionLabel
                ] as [String: Any],
                "y": [
                    "data": ["Positive", "Negative"],
                    "label": matrixConfusionLabel
                ] as [String: Any],
                "top": 80.0,
                "width": 600.0,
                "left": "center"
            ] as [String: Any],
            "series": [
                "type": "custom",
                "coordinateSystem": "matrix",
                "renderItem": matrixConfusionRenderItem,
                "data": matrixConfusionData,
                "label": [
                    "show": true,
                    "formatter": matrixConfusionLabelFormatter,
                    "rich": [
                        "name": [
                            "color": "#fff",
                            "backgroundColor": "#999",
                            "textBorderColor": "#333",
                            "padding": 5.0,
                            "fontSize": 18.0
                        ] as [String: Any],
                        "value": [
                            "color": "#444",
                            "textBorderWidth": 0.0,
                            "padding": 5.0,
                            "fontSize": 16.0,
                            "align": "center"
                        ] as [String: Any]
                    ] as [String: Any]
                ] as [String: Any]
                // renderItem omitted — JS closure drawing each datum as one `rect` filling the
                // matrix body cell at [value(0), value(1)] (`api.layout([x, y]).rect`), filled '#8f8' on the
                // diagonal (x === y) and '#f88' off it, through api.style. Without it the `custom` series
                // draws nothing; hence nativeSupported: false.
            ] as [String: Any],
            "graphic": [
                "elements": [
                    [
                        "type": "text",
                        "style": [
                            "text": "True Class",
                            "fill": "#333",
                            "font": "bold 24px serif",
                            "textAlign": "center"
                        ] as [String: Any],
                        // upstream: (window.innerWidth - 600) / 2 + (600 / 6) * 4, against a 720px canvas.
                        "x": 460.0,
                        "y": 40.0
                    ] as [String: Any],
                    [
                        "type": "text",
                        "style": [
                            "text": "Predicted Class",
                            "fill": "#333",
                            "font": "bold 24px serif",
                            "textAlign": "center"
                        ] as [String: Any],
                        // upstream: (window.innerWidth - 600) / 2 - 50, against a 720px canvas.
                        "x": 10.0,
                        "y": 270.0,
                        "rotation": Double.pi / 2
                    ] as [String: Any]
                ]
            ] as [String: Any]
        ])
}

// The shared header-cell label style (upstream's `const label`, referenced by matrix.x and matrix.y).
private let matrixConfusionLabel: [String: Any] = [
    "fontSize": 16.0,
    "color": "#555"
]

// [predicted class, true class, count] — the four confusion-matrix cells.
private let matrixConfusionData: [[Any]] = [
    ["Positive", "Positive", 10.0],
    ["Positive", "Negative", 2.0],
    ["Negative", "Positive", 3.0],
    ["Negative", "Negative", 5.0]
]
