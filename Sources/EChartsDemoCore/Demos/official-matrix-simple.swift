// official-matrix-simple — replica of https://echarts.apache.org/examples/zh/editor.html?c=matrix-simple
// title: Simple Matrix / titleCN: 简单的矩阵图 (since echarts 6.0.0)
//
// The `matrix` coordinate system (the 8th) driving a `heatmap` series: a TREE-structured x header
// ('A' spanning A1 / A2 / A3, and A3 itself spanning A31 / A32) against a flat y header (U / V), with
// each cell coloured by a continuous `visualMap` over the datum's 3rd dimension (dimension: 2).
//
// DEVIATIONS from the official source:
//   - NATIVE PANE IS PARTIAL (this is the one real gap; see note on `series` below). EChartsKit
//     registers the matrix coord + MatrixView, so the native pane draws the TABLE BACKDROP (the nested
//     x/y header cells and their labels, the dividers, the border) and the visualMap bar — but NOT the
//     heatmap cells themselves: `HeatmapView.render` only wires the cartesian2d / calendar / geo
//     branches, and a matrix coordSys falls into the `else` (group.removeAll() → nothing drawn). The
//     series still binds to the matrix coord and nothing crashes; the coloured cells are simply absent
//     until HeatmapView's `_renderOnGridLike` matrix branch lands. The web pane is fully correct.
//   - The official source writes `series` as a bare object; the Swift option uses the one-element array
//     echarts itself normalizes it to (webOptionJS keeps the object form verbatim). Not a semantic change.
// Everything else — the option's values, structure and key order — is the official example unchanged.
// No JS closures appear anywhere in this example, so no option keys are dropped from the Swift port.

// The x-header TREE, verbatim from the source: one root cell 'A' whose children are the leaves A1 / A2
// and the sub-branch A3 (itself spanning A31 / A32). Heterogeneous (String | dict) and nested, so it is
// hoisted with an explicit type — inline, Swift's type-checker chokes on it.
private let matrixSimpleXData: [Any] = [
    [
        "value": "A",
        "children": [
            "A1",
            "A2",
            [
                "value": "A3",
                "children": ["A31", "A32"]
            ] as [String: Any]
        ] as [Any]
    ] as [String: Any]
]

// Heatmap data: [xLocator, yLocator, value] triples. Note the source's last row keys the BRANCH cell
// 'A3' (not a leaf) — a merged/spanning cell — while the rest key leaves; that asymmetry is upstream's,
// kept as-is. Heterogeneous ([String, String, Double]), so likewise hoisted with an explicit type.
private let matrixSimpleData: [[Any]] = [
    ["A1", "U", 10.0],
    ["A1", "V", 20.0],
    ["A2", "U", 30.0],
    ["A2", "V", 40.0],
    ["A31", "U", 50.0],
    ["A3", "V", 60.0]
]

extension EChartsDemoRegistry {
    static let official_matrix_simple = EChartsDemo(
        name: "official-matrix-simple", category: "matrix",
        summary: "简单的矩阵图 — Simple Matrix",
        width: 640, height: 420,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
option = {
  matrix: {
    x: {
      data: [
        {
          value: 'A',
          children: [
            'A1',
            'A2',
            {
              value: 'A3',
              children: ['A31', 'A32']
            }
          ]
        }
      ]
    },
    y: {
      data: ['U', 'V']
    },
    top: 150,
    bottom: 150
  },
  visualMap: {
    type: 'continuous',
    min: 0,
    max: 80,
    top: 'middle',
    dimension: 2,
    calculable: true
  },
  series: {
    type: 'heatmap',
    coordinateSystem: 'matrix',
    data: [
      ['A1', 'U', 10],
      ['A1', 'V', 20],
      ['A2', 'U', 30],
      ['A2', 'V', 40],
      ['A31', 'U', 50],
      ['A3', 'V', 60]
    ],
    label: {
      show: true
    }
  }
};
"""#,
        option: [
            "matrix": [
                "x": ["data": matrixSimpleXData] as [String: Any],
                "y": ["data": ["U", "V"] as [Any]] as [String: Any],
                "top": 150.0,
                "bottom": 150.0
            ] as [String: Any],
            "visualMap": [
                "type": "continuous",
                "min": 0.0,
                "max": 80.0,
                "top": "middle",
                // The mapped dimension: index 2 of each datum, i.e. the value in [x, y, value].
                "dimension": 2.0,
                "calculable": true
            ] as [String: Any],
            "series": [
                // rendered as the matrix BACKDROP only today — HeatmapView.render has no
                // matrix branch (cartesian2d / calendar / geo only), so these six cells draw nothing on
                // the native pane. Option is complete and correct; it lights up when that branch lands.
                [
                    "type": "heatmap",
                    "coordinateSystem": "matrix",
                    "data": matrixSimpleData,
                    "label": ["show": true] as [String: Any]
                ] as [String: Any]
            ]
        ])
}
