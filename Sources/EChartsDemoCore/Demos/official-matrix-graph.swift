// official-matrix-graph — replica of https://echarts.apache.org/examples/zh/editor.html?c=matrix-graph
// title: Graph Chart in Matrix / titleCN: 矩阵布局下的关系图
// A `graph` series on the MATRIX coordinate system (echarts 6.0+): every course node is placed at a
// (course-category column, year row) cell of the matrix; the arrow-headed links are the prerequisites.
// Two `graphic` text elements label the two matrix axes.
//
// DEVIATIONS from the official source:
//   - The source's `myChart.getWidth()/getHeight()` (the margin math, which in turn positions the two
//     `graphic` texts) cannot run in the reference pane: WebPage.swift creates `myChart` AFTER the
//     option script. webOptionJS substitutes the pane's literal canvas size — the same numbers the
//     example would have read back, so both panes lay out identically.
//   - Pane is 900x560 rather than the gallery default: the example hardcodes 150px top/bottom margins,
//     which at a 460px-tall canvas leaves only 160px of matrix body for 4 year-rows and the node labels
//     collide. Only the canvas size changes; every option value is the example's.
//   - NATIVE pane: `series[0].label.formatter` (a JS arrow fn) is dropped — see PORT-NOTE. Native node
//     labels therefore fall back to the default label text instead of the course name.
extension EChartsDemoRegistry {
    static let official_matrix_graph = EChartsDemo(
        name: "official-matrix-graph", category: "matrix",
        summary: "矩阵布局下的关系图 — Graph Chart in Matrix",
        width: matrixGraphCanvasW, height: matrixGraphCanvasH,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
const margin = [150, 80];
// gallery: the chart instance does not exist yet when this script runs (the page inits it right
// after), so the example's two chart-size reads are spliced in as the pane's canvas size — the
// same numbers they would have returned. See the file header.
const width = \#(Int(matrixGraphCanvasW)) - margin[1] * 2;
const height = \#(Int(matrixGraphCanvasH)) - margin[0] * 2;

option = {
  title: {
    text: 'Course Prerequisites'
  },
  matrix: {
    x: {
      data: ['Data Analysis', 'Programming', 'Algorithms']
    },
    y: {
      data: ['1st Year', '2nd Year', '3rd Year', '4th Year']
    },
    left: margin[1],
    right: margin[1],
    top: margin[0],
    bottom: margin[0]
  },
  series: [
    {
      type: 'graph',
      coordinateSystem: 'matrix',
      edgeSymbol: ['none', 'arrow'],
      symbolSize: 15,
      links: [
        {
          source: 1,
          target: 0
        },
        {
          source: 2,
          target: 0
        },
        {
          source: 3,
          target: 0
        },
        {
          source: 4,
          target: 3
        },
        {
          source: 4,
          target: 2
        },
        {
          source: 5,
          target: 1
        },
        {
          source: 6,
          target: 3
        }
      ],
      data: [
        ['Programming', '1st Year', 1, 'Intro to Computer Science'],
        ['Data Analysis', '2nd Year', 1, 'Intro to Data Analysis'],
        ['Algorithms', '2nd Year', 1, 'Intro to Algorithms'],
        ['Programming', '2nd Year', 1, 'Advanced Programming'],
        ['Algorithms', '4th Year', 1, 'Data Structures\nand Algorithms'],
        ['Data Analysis', '3rd Year', 1, 'Statistics for Data Analysis'],
        ['Programming', '3rd Year', 1, 'Software Development']
      ],
      label: {
        show: true,
        formatter: (params) => {
          return params.data[3];
        },
        color: '#555',
        borderWidth: 0,
        fontSize: 15,
        fontWeight: 'bold',
        offset: [0, -15],
        verticalAlign: 'bottom'
      },
      lineStyle: {
        color: '#9af',
        width: 2,
        opacity: 1
      }
    }
  ],
  graphic: {
    elements: [
      {
        type: 'text',
        x: (width / 4) * 2.5 + margin[1],
        y: margin[0] - 15,
        style: {
          text: 'Course Categories',
          textAlign: 'center',
          textVerticalAlign: 'bottom',
          fontSize: 18,
          fontWeight: 'bold',
          fill: '#333'
        }
      },
      {
        type: 'text',
        x: margin[1] - 15,
        y: (height / 5) * 3 + margin[0],
        style: {
          text: 'Course Categories',
          textAlign: 'center',
          textVerticalAlign: 'bottom',
          fontSize: 18,
          fontWeight: 'bold',
          fill: '#333'
        },
        rotation: Math.PI / 2
      }
    ]
  }
};
"""#,
        option: [
            "title": [
                "text": "Course Prerequisites"
            ] as [String: Any],
            "matrix": [
                "x": ["data": ["Data Analysis", "Programming", "Algorithms"] as [Any]] as [String: Any],
                "y": ["data": ["1st Year", "2nd Year", "3rd Year", "4th Year"] as [Any]] as [String: Any],
                "left": matrixGraphMarginX,
                "right": matrixGraphMarginX,
                "top": matrixGraphMarginY,
                "bottom": matrixGraphMarginY
            ] as [String: Any],
            "series": [
                [
                    "type": "graph",
                    "coordinateSystem": "matrix",
                    "edgeSymbol": ["none", "arrow"],
                    "symbolSize": 15.0,
                    "links": matrixGraphLinks,
                    "data": matrixGraphNodes,
                    "label": [
                        "show": true,
                        // PORT-NOTE: label.formatter omitted — the JS closure `(params) => params.data[3]`
                        // pulls the course name out of the 4th slot of each node's array value.
                        "color": "#555",
                        "borderWidth": 0.0,
                        "fontSize": 15.0,
                        "fontWeight": "bold",
                        "offset": [0.0, -15.0],
                        "verticalAlign": "bottom"
                    ] as [String: Any],
                    "lineStyle": [
                        "color": "#9af",
                        "width": 2.0,
                        "opacity": 1.0
                    ] as [String: Any]
                ] as [String: Any]
            ],
            "graphic": [
                "elements": [
                    // x = (width / 4) * 2.5 + margin[1], y = margin[0] - 15 (the source's arithmetic,
                    // evaluated against this pane's canvas size).
                    [
                        "type": "text",
                        "x": (matrixGraphBodyW / 4) * 2.5 + matrixGraphMarginX,
                        "y": matrixGraphMarginY - 15,
                        "style": [
                            "text": "Course Categories",
                            "textAlign": "center",
                            "textVerticalAlign": "bottom",
                            "fontSize": 18.0,
                            "fontWeight": "bold",
                            "fill": "#333"
                        ] as [String: Any]
                    ] as [String: Any],
                    [
                        "type": "text",
                        "x": matrixGraphMarginX - 15,
                        "y": (matrixGraphBodyH / 5) * 3 + matrixGraphMarginY,
                        "style": [
                            "text": "Course Categories",
                            "textAlign": "center",
                            "textVerticalAlign": "bottom",
                            "fontSize": 18.0,
                            "fontWeight": "bold",
                            "fill": "#333"
                        ] as [String: Any],
                        "rotation": Double.pi / 2
                    ] as [String: Any]
                ]
            ] as [String: Any]
        ])
}

// The example derives its layout from the chart's own size (`const margin = [150, 80]`, then
// `myChart.getWidth() - margin[1] * 2`). Both panes read these, so they cannot drift apart.
private let matrixGraphCanvasW: Double = 900
private let matrixGraphCanvasH: Double = 560
private let matrixGraphMarginY: Double = 150   // margin[0] — top/bottom
private let matrixGraphMarginX: Double = 80    // margin[1] — left/right
private let matrixGraphBodyW: Double = matrixGraphCanvasW - matrixGraphMarginX * 2
private let matrixGraphBodyH: Double = matrixGraphCanvasH - matrixGraphMarginY * 2

// Prerequisite edges, by node index (`edgeSymbol: ['none', 'arrow']` points target ← source).
private let matrixGraphLinks: [[String: Any]] = [
    ["source": 1.0, "target": 0.0],
    ["source": 2.0, "target": 0.0],
    ["source": 3.0, "target": 0.0],
    ["source": 4.0, "target": 3.0],
    ["source": 4.0, "target": 2.0],
    ["source": 5.0, "target": 1.0],
    ["source": 6.0, "target": 3.0]
]

// [matrix x-category (course area), matrix y-category (year), value, course name].
private let matrixGraphNodes: [[Any]] = [
    ["Programming", "1st Year", 1.0, "Intro to Computer Science"],
    ["Data Analysis", "2nd Year", 1.0, "Intro to Data Analysis"],
    ["Algorithms", "2nd Year", 1.0, "Intro to Algorithms"],
    ["Programming", "2nd Year", 1.0, "Advanced Programming"],
    ["Algorithms", "4th Year", 1.0, "Data Structures\nand Algorithms"],
    ["Data Analysis", "3rd Year", 1.0, "Statistics for Data Analysis"],
    ["Programming", "3rd Year", 1.0, "Software Development"]
]
