// official-matrix-grid-layout — replica of
// https://echarts.apache.org/examples/zh/editor.html?c=matrix-grid-layout
// title: Responsive grid layout based on matrix / titleCN: 矩阵中响应式网格布局 (since echarts 6.0.0)
//
// A CSS-grid-style page layout built OUT OF a `matrix` coordinate system: an invisible matrix
// (`x/y.show: false`, no borders, zero padding) is the grid, and five "sections" — title, header,
// sidebar, main content area, footer — are placed into cell RANGES by giving each section's `title`
// and `grid` component `coordinateSystem: 'matrix'` + a `coord` (a `[col, row]` where either part may
// be a `[from, to]` span). Each non-title section carries a full cartesian chart (grid + xAxis +
// yAxis + line/bar series) inside its cell range. RESPONSIVENESS is `option.media`: below 500px canvas
// width the matrix collapses to 1 column x 10 rows and the sections stack; otherwise (the default
// media unit, no `query`) it is 4 columns x 10 rows and the sidebar sits beside the main area.
//
// DEVIATIONS from the official source:
//   - THE DATA IS RANDOM UPSTREAM. `generateSingleSeriesData` is a `Math.random()` walk, so two panes
//     loaded independently can never show the same curves. Both panes replace only that random source
//     with the same seeded xorshift32 generator. The walk algorithm, weekly steps, turn points and
//     inverseXY handling remain unchanged, while screenshots become reproducible and comparable.
//   - JS `Math.round` / `Number.toFixed(0)` tie-breaking (toward +inf) is not reproduced exactly;
//     `.rounded()` (ties away from zero) is used. Noise-level on random data.
//   - `echarts.time.format(xTime, '{yyyy}-{MM}-{dd}')` is called with NO `isUTC` argument, so the web
//     pane stamps each point's date in the BROWSER'S LOCAL timezone; `matrixGridDayFormatter` pins UTC
//     instead, on purpose — a local-time native pane would render differently per machine, and the
//     point of the seeded PRNG is determinism. West of UTC the two panes' date labels therefore differ
//     by one day (the first point is '2025-05-04' in the web pane, '2025-05-05' natively). Both axes
//     are `type: 'time'` and echarts parses a date-only string as UTC, so this only shifts the labels,
//     not the shape of the curves — and the curves already cannot match (the data is random).
//   - The source ASSEMBLES the option at runtime (`assembleIntoEChartsOption` walks
//     `_sectionDefinitionMap`, auto-generates each title's `id` off a `_idBase` counter, and pushes an
//     `{id, coord}` entry per matrix-placed component into every `media[i].option`). The Swift port
//     runs the same algorithm over the same section definitions, in the same order, and so emits the
//     same ids (`section_title_1_title_1` ... `section_footer_1_title_5`) and the same media units.
//     Not a semantic change — it is the same emitted option.
//   - `initFloatingControlPanel()` is kept verbatim in the web pane (it only fills `app.config` /
//     `app.configParameters`, which the page declares), but it is INERT here: the gallery has no
//     floating control panel, so its `onChange` — the `showMatrixGrid` toggle that re-`setOption`s
//     `matrix.body.itemStyle.borderColor` to 'red' — is never fired. Both panes therefore show the
//     example's initial state (borderColor 'none', i.e. the layout grid hidden). Nothing is dropped
//     from the Swift option: `onChange` is a JS closure on `app`, never a key of `option`.
//   - Canvas is 720x560 rather than the editor's default, so the 10 matrix rows have room. It stays
//     WIDER than 500px, so the default (4-column) media unit is the one that applies — the 1-column
//     branch is only reachable by resizing, which the still-frame render cannot do.
//
// NATIVE PANE IS PARTIAL — one real framework gap, not a port shortcut, and the SAME one
// official-matrix-sparkline hits: placing a `grid` (or a `title`) INSIDE a matrix cell needs the BOX
// COORDINATE SYSTEM branch of `layout.createBoxLayoutReference` (`model.boxCoordinateSystem` ->
// `matrix.dataToLayout(coord)`), still deferred in EChartsKit (note at
// Sources/EChartsKit/util/layout.swift:197 — it always returns the viewport rect). Until that lands,
// every section's grid resolves to the FULL VIEWPORT and the four charts stack on top of each other
// instead of tiling the matrix. The option is complete and correct; this is exactly the kind of gap
// the two panes exist to surface, so it stays `nativeSupported`.

import Foundation

// ---------------------------------------------------------------------------------------------
// The port of `generateSingleSeriesData(dayCount, inverseXY)`. Deterministic stand-in for
// Math.random() (see DEVIATIONS).
// ---------------------------------------------------------------------------------------------

/// xorshift32 — mirrored verbatim by the web pane so independently loaded panes receive identical data.
private struct MatrixGridRNG {
    private var state: UInt32
    init(seed: UInt32) { self.state = seed == 0 ? 1 : seed }
    /// Uniform in [0, 1), like `Math.random()`.
    mutating func next() -> Double {
        state ^= state << 13
        state ^= state >> 17
        state ^= state << 5
        return Double(state) / 4_294_967_296.0
    }
}

private let matrixGridDayFormatter: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = TimeZone(identifier: "UTC")
    f.dateFormat = "yyyy-MM-dd"    // the source's echarts.time.format(xTime, '{yyyy}-{MM}-{dd}')
    return f
}()

/// `generateSingleSeriesData(dayCount, inverseXY)`: a `dayCount`-step random walk, one point per week
/// from 2025-05-05 (a Monday). Returns `[[dateString, value]]`, or `[[value, dateString]]` when
/// `inverseXY` (the sidebar's time-on-y bar chart).
private func matrixGridSeriesData(_ dayCount: Int, inverseXY: Bool, rng: inout MatrixGridRNG) -> [[Any]] {
    let timeStart: Double = 1_746_403_200        // new Date('2025-05-05T00:00:00.000Z')
    let sevenDay: Double = 7 * 24 * 3600

    var seriesData: [[Any]] = []
    seriesData.reserveCapacity(dayCount)
    var lastVal = (rng.next() * 300).rounded()
    var turnCount: Int?
    var sign: Double = -1

    for idx in 0..<dayCount {
        if turnCount == nil || idx >= turnCount! {
            turnCount = idx + Int(((Double(dayCount) / 4) * ((rng.next() - 0.5) * 0.1)).rounded())
            sign = -sign
        }
        let deltaMag: Double = 50
        let delta = (rng.next() * deltaMag - deltaMag / 2 + (sign * deltaMag) / 3).rounded()
        lastVal += delta
        let val = max(0, lastVal)
        let xTime = timeStart + Double(idx) * sevenDay
        let dataXVal = matrixGridDayFormatter.string(from: Date(timeIntervalSince1970: xTime))
        seriesData.append(inverseXY ? [val, dataXVal] : [dataXVal, val])
    }
    return seriesData
}

// ---------------------------------------------------------------------------------------------
// The port of `_sectionDefinitionMap` + `_mediaDefinitionList` + `assembleIntoEChartsOption`.
//
// A section is a bag of components; the ones with `coordinateSystem: 'matrix'` (here: the `title` and
// the `grid`) get an `{id, coord}` entry pushed into EVERY media unit, which is what makes the layout
// responsive. Titles carry no id upstream, so `assembleIntoEChartsOption` mints one from the
// `_idBase` counter — reproduced below, in the same section order, for the same ids.
// ---------------------------------------------------------------------------------------------

private struct MatrixGridSection {
    let sectionId: String
    let title: [String: Any]        // no `id` — the builder mints `<sectionId>_title_<_idBase++>`
    let xAxis: [String: Any]?
    let yAxis: [String: Any]?
    let grid: [String: Any]?        // carries its own `id`; `coordinateSystem: 'matrix'`
    let series: [String: Any]?
    let coordNarrow: [Any]          // media[0] (`query: {maxWidth: 500}`) coord — 1 column
    let coordDefault: [Any]         // media[1] (no query, the default) coord — 4 columns
}

/// The `outerBounds` every section's grid shares.
private let matrixGridOuterBounds: [String: Any] = [
    "top": 30.0, "left": 20.0, "bottom": 20.0, "right": 20.0
]

private func matrixGridSections() -> [MatrixGridSection] {
    // Same call order as the source's `_sectionDefinitionMap` object literal, off one RNG — so each
    // series gets its own walk, exactly as the four sequential `Math.random()`-driven calls do.
    var rng = MatrixGridRNG(seed: 0x2025_0505)
    let headerData = matrixGridSeriesData(100, inverseXY: false, rng: &rng)
    let sidebarData = matrixGridSeriesData(10, inverseXY: true, rng: &rng)
    let mainData = matrixGridSeriesData(100, inverseXY: false, rng: &rng)
    let footerData = matrixGridSeriesData(10, inverseXY: false, rng: &rng)

    return [
        MatrixGridSection(
            sectionId: "section_title_1",
            title: [
                "coordinateSystem": "matrix",
                "text": "Resize the Canvas to Check the Responsiveness",
                "left": "center",
                "top": 10.0
            ],
            xAxis: nil, yAxis: nil, grid: nil, series: nil,
            coordNarrow: [0.0, 0.0],
            coordDefault: [[0.0, 3.0] as [Double], 0.0]
        ),
        MatrixGridSection(
            sectionId: "section_header_1",
            title: [
                "coordinateSystem": "matrix",
                "text": "Header Section",
                "textStyle": ["fontSize": 14.0] as [String: Any],
                "left": "center",
                "top": 5.0
            ],
            xAxis: [
                "type": "time",
                "id": "header_1",
                "gridId": "header_1",
                "axisLabel": ["formatter": "{MM}-{dd}"] as [String: Any]
            ],
            yAxis: [
                "id": "header_1",
                "gridId": "header_1",
                "splitNumber": 2.0,
                "splitLine": ["show": false] as [String: Any]
            ],
            grid: [
                "id": "header_1",
                "coordinateSystem": "matrix",
                "tooltip": ["trigger": "axis"] as [String: Any],
                "top": 30.0,
                "bottom": 10.0,
                "left": 10.0,
                "right": 10.0,
                "outerBounds": matrixGridOuterBounds
            ],
            series: [
                "type": "line",
                "id": "header_1",
                "xAxisId": "header_1",
                "yAxisId": "header_1",
                "symbol": "none",
                "data": headerData
            ],
            coordNarrow: [0.0, [1.0, 2.0] as [Double]],
            coordDefault: [[0.0, 3.0] as [Double], [1.0, 2.0] as [Double]]
        ),
        MatrixGridSection(
            sectionId: "section_sidebar_1",
            title: [
                "coordinateSystem": "matrix",
                "text": "Sidebar Section",
                "textStyle": ["fontSize": 14.0] as [String: Any],
                "left": "center",
                "top": 15.0
            ],
            xAxis: [
                "id": "sidebar_1",
                "gridId": "sidebar_1",
                "splitLine": ["show": false] as [String: Any],
                "axisLabel": ["hideOverlap": true] as [String: Any]
            ],
            yAxis: [
                "type": "time",
                "id": "sidebar_1",
                "gridId": "sidebar_1",
                "axisLabel": ["hideOverlap": true, "formatter": "{MM}-{dd}"] as [String: Any]
            ],
            grid: [
                "id": "sidebar_1",
                "coordinateSystem": "matrix",
                "tooltip": ["trigger": "axis"] as [String: Any],
                "top": 50.0,
                "bottom": 30.0,
                "left": 40.0,
                "right": 30.0,
                "outerBounds": matrixGridOuterBounds
            ],
            series: [
                "type": "bar",
                "id": "sidebar_1",
                "xAxisId": "sidebar_1",
                "yAxisId": "sidebar_1",
                "data": sidebarData
            ],
            coordNarrow: [0.0, [3.0, 4.0] as [Double]],
            coordDefault: [0.0, [3.0, 9.0] as [Double]]
        ),
        MatrixGridSection(
            sectionId: "section_main_content_area_1",
            title: [
                "text": "Main Content Area",
                "coordinateSystem": "matrix",
                "textStyle": ["fontSize": 14.0] as [String: Any],
                "left": "center",
                "top": 15.0
            ],
            xAxis: [
                "type": "time",
                "id": "main_content_area_1",
                "gridId": "main_content_area_1",
                "axisLabel": ["formatter": "{MM}-{dd}"] as [String: Any]
            ],
            yAxis: [
                "id": "main_content_area_1",
                "gridId": "main_content_area_1"
            ],
            grid: [
                "id": "main_content_area_1",
                "coordinateSystem": "matrix",
                "tooltip": ["trigger": "axis"] as [String: Any],
                "top": 50.0,
                "bottom": 10.0,
                "left": 10.0,
                "right": 10.0,
                "outerBounds": matrixGridOuterBounds
            ],
            series: [
                "type": "line",
                "id": "main_content_area_1",
                "xAxisId": "main_content_area_1",
                "yAxisId": "main_content_area_1",
                "symbol": "none",
                "data": mainData
            ],
            coordNarrow: [0.0, [5.0, 7.0] as [Double]],
            coordDefault: [[1.0, 3.0] as [Double], [3.0, 7.0] as [Double]]
        ),
        MatrixGridSection(
            sectionId: "section_footer_1",
            title: [
                "coordinateSystem": "matrix",
                "text": "Footer Section",
                "textStyle": ["fontSize": 14.0] as [String: Any],
                "left": "center",
                "top": 15.0
            ],
            xAxis: [
                "type": "time",
                "id": "footer_1",
                "gridId": "footer_1",
                "axisLabel": ["formatter": "{MM}-{dd}"] as [String: Any]
            ],
            yAxis: [
                "id": "footer_1",
                "gridId": "footer_1",
                "splitNumber": 2.0,
                "splitLine": ["show": false] as [String: Any]
            ],
            grid: [
                "id": "footer_1",
                "coordinateSystem": "matrix",
                "tooltip": ["trigger": "axis"] as [String: Any],
                "top": 50.0,
                "bottom": 10.0,
                "left": 20.0,
                "right": 20.0,
                "outerBounds": matrixGridOuterBounds
            ],
            series: [
                "type": "bar",
                "id": "footer_1",
                "xAxisId": "footer_1",
                "yAxisId": "footer_1",
                "data": footerData
            ],
            coordNarrow: [0.0, [8.0, 9.0] as [Double]],
            coordDefault: [[1.0, 3.0] as [Double], [8.0, 9.0] as [Double]]
        )
    ]
}

/// `Array(n).fill(null)` — n unnamed matrix columns / rows (NSNull is the JS `null`; MatrixDim reads
/// it as `{value: null}`, i.e. an anonymous cell).
private func matrixGridNulls(_ n: Int) -> [Any] {
    return [Any](repeating: NSNull(), count: n)
}

/// The source's `option` literal + `assembleIntoEChartsOption(option, _sectionDefinitionMap,
/// _mediaDefinitionList)`, run once.
private func matrixGridLayoutOption() -> [String: Any] {
    var titles: [[String: Any]] = []
    var xAxes: [[String: Any]] = []
    var yAxes: [[String: Any]] = []
    var grids: [[String: Any]] = []
    var seriesList: [[String: Any]] = []

    // Per media unit, the `{id, coord}` entries pushed for every matrix-placed component.
    var narrowTitleCoords: [[String: Any]] = []
    var narrowGridCoords: [[String: Any]] = []
    var defaultTitleCoords: [[String: Any]] = []
    var defaultGridCoords: [[String: Any]] = []

    var idBase = 1                       // the source's `let _idBase = 1`
    for section in matrixGridSections() {
        // ensureComponentId: only the titles lack an `id` upstream.
        let titleId = "\(section.sectionId)_title_\(idBase)"
        idBase += 1
        var title = section.title
        title["id"] = titleId
        titles.append(title)
        narrowTitleCoords.append(["id": titleId, "coord": section.coordNarrow] as [String: Any])
        defaultTitleCoords.append(["id": titleId, "coord": section.coordDefault] as [String: Any])

        if let xAxis = section.xAxis { xAxes.append(xAxis) }
        if let yAxis = section.yAxis { yAxes.append(yAxis) }
        if let series = section.series { seriesList.append(series) }
        if let grid = section.grid {
            grids.append(grid)
            let gridId = grid["id"] as? String ?? ""
            narrowGridCoords.append(["id": gridId, "coord": section.coordNarrow] as [String: Any])
            defaultGridCoords.append(["id": gridId, "coord": section.coordDefault] as [String: Any])
        }
    }

    return [
        // Use the matrix coordinate system to layout the charts and components.
        "matrix": [
            "x": ["show": false, "data": [] as [Any]] as [String: Any],
            "y": ["show": false, "data": [] as [Any]] as [String: Any],
            "body": [
                "itemStyle": ["borderColor": "none"] as [String: Any]
            ] as [String: Any],
            "backgroundStyle": ["borderColor": "none"] as [String: Any],
            "top": 0.0,
            "bottom": 0.0,
            "left": 0.0,
            "right": 0.0
        ] as [String: Any],
        "tooltip": [:] as [String: Any],
        "title": titles,
        "xAxis": xAxes,
        "yAxis": yAxes,
        "grid": grids,
        "series": seriesList,
        "media": [
            // When the canvas width is less than 500px: one column, sections stacked.
            [
                "query": ["maxWidth": 500.0] as [String: Any],
                "option": [
                    "matrix": [
                        "x": ["data": matrixGridNulls(1)] as [String: Any],
                        "y": ["data": matrixGridNulls(10)] as [String: Any]
                    ] as [String: Any],
                    "title": narrowTitleCoords,
                    "grid": narrowGridCoords
                ] as [String: Any]
            ] as [String: Any],
            // The default (with no `query`): four columns, sidebar beside the main content area.
            [
                "option": [
                    "matrix": [
                        "x": ["data": matrixGridNulls(4)] as [String: Any],
                        "y": ["data": matrixGridNulls(10)] as [String: Any]
                    ] as [String: Any],
                    "title": defaultTitleCoords,
                    "grid": defaultGridCoords
                ] as [String: Any]
            ] as [String: Any]
        ]
    ]
}

extension EChartsDemoRegistry {
    static let official_matrix_grid_layout = EChartsDemo(
        name: "official-matrix-grid-layout", category: "matrix",
        summary: "矩阵中响应式网格布局 — Responsive grid layout based on matrix",
        width: 720, height: 560,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
/**
 * Use a matrix coordinate system to layout multiple charts and components,
 * following the similar idea of CSS grid layout, and provide responsiveness
 * by media queries.
 */

let _idBase = 1;
let _matrixGridRandomState = 0x20250505 >>> 0;

const _mediaDefinitionList = [
  {
    // When the canvas width is less than 500px,
    query: { maxWidth: 500 },
    matrix: {
      // Define column and rows
      x: { data: Array(1).fill(null) },
      y: { data: Array(10).fill(null) }
    },
    // Place sections into the matrix cell determined by the coords.
    // key: sectionId, value: coord.
    sectionCoordMap: {
      'section_title_1': [0, 0],
      'section_header_1': [0, [1, 2]],
      'section_sidebar_1': [0, [3, 4]],
      'section_main_content_area_1': [0, [5, 7]],
      'section_footer_1': [0, [8, 9]],
    }
  },
  {
    // The default (with no `query`)
    matrix: {
      // Define column and rows
      x: { data: Array(4).fill(null) },
      y: { data: Array(10).fill(null) }
    },
    sectionCoordMap: {
      'section_title_1': [[0, 3], 0],
      'section_header_1': [[0, 3], [1, 2]],
      'section_sidebar_1': [0, [3, 9]],
      'section_main_content_area_1': [[1, 3], [3, 7]],
      'section_footer_1': [[1, 3], [8, 9]],
    }
  }
];

/**
 * Each section contains some charts and components.
 */
const _sectionDefinitionMap = {
  'section_title_1': {
    option: {
      title: [{
        coordinateSystem: 'matrix',
        text: 'Resize the Canvas to Check the Responsiveness',
        left: 'center',
        top: 10,
      }],
    }
  },
  'section_header_1': {
    option: {
      title: [{
        coordinateSystem: 'matrix',
        text: 'Header Section',
        textStyle: { fontSize: 14 },
        left: 'center',
        top: 5
      }],
      xAxis: {
        type: 'time',
        id: 'header_1',
        gridId: 'header_1',
        axisLabel: { formatter: '{MM}-{dd}' }
      },
      yAxis: {
        id: 'header_1',
        gridId: 'header_1',
        splitNumber: 2,
        splitLine: {show: false},
      },
      grid: {
        id: 'header_1',
        coordinateSystem: 'matrix',
        tooltip: {
          trigger: 'axis'
        },
        top: 30,
        bottom: 10,
        left: 10,
        right: 10,
        outerBounds: {
          top: 30,
          left: 20,
          bottom: 20,
          right: 20,
        }
      },
      series: {
        type: 'line',
        id: 'header_1',
        xAxisId: 'header_1',
        yAxisId: 'header_1',
        symbol: 'none',
        data: generateSingleSeriesData(100, false)
      }
    }
  },
  'section_sidebar_1': {
    option: {
      title: {
        coordinateSystem: 'matrix',
        text: 'Sidebar Section',
        textStyle: { fontSize: 14 },
        left: 'center',
        top: 15
      },
      xAxis: {
        id: 'sidebar_1',
        gridId: 'sidebar_1',
        splitLine: {show: false},
        axisLabel: {
          hideOverlap: true
        }
      },
      yAxis: {
        type: 'time',
        id: 'sidebar_1',
        gridId: 'sidebar_1',
        axisLabel: {
          hideOverlap: true,
          formatter: '{MM}-{dd}'
        }
      },
      grid: {
        id: 'sidebar_1',
        coordinateSystem: 'matrix',
        tooltip: {
          trigger: 'axis'
        },
        top: 50,
        bottom: 30,
        left: 40,
        right: 30,
        outerBounds: {
          top: 30,
          left: 20,
          bottom: 20,
          right: 20,
        }
      },
      series: {
        type: 'bar',
        id: 'sidebar_1',
        xAxisId: 'sidebar_1',
        yAxisId: 'sidebar_1',
        data: generateSingleSeriesData(10, true)
      }
    }
  },
  'section_main_content_area_1': {
    option: {
      title: {
        text: 'Main Content Area',
        coordinateSystem: 'matrix',
        textStyle: { fontSize: 14 },
        left: 'center',
        top: 15
      },
      xAxis: {
        type: 'time',
        id: 'main_content_area_1',
        gridId: 'main_content_area_1',
        axisLabel: { formatter: '{MM}-{dd}' }
      },
      yAxis: {
        id: 'main_content_area_1',
        gridId: 'main_content_area_1'
      },
      grid: {
        id: 'main_content_area_1',
        coordinateSystem: 'matrix',
        tooltip: {
          trigger: 'axis'
        },
        top: 50,
        bottom: 10,
        left: 10,
        right: 10,
        outerBounds: {
          top: 30,
          left: 20,
          bottom: 20,
          right: 20,
        }
      },
      series: {
        type: 'line',
        id: 'main_content_area_1',
        xAxisId: 'main_content_area_1',
        yAxisId: 'main_content_area_1',
        symbol: 'none',
        data: generateSingleSeriesData(100, false)
      }
    }
  },
  'section_footer_1': {
    option: {
      title: {
        coordinateSystem: 'matrix',
        text: 'Footer Section',
        textStyle: { fontSize: 14 },
        left: 'center',
        top: 15
      },
      xAxis: {
        type: 'time',
        id: 'footer_1',
        gridId: 'footer_1',
        axisLabel: { formatter: '{MM}-{dd}' }
      },
      yAxis: {
        id: 'footer_1',
        gridId: 'footer_1',
        splitNumber: 2,
        splitLine: {show: false},
      },
      grid: {
        id: 'footer_1',
        coordinateSystem: 'matrix',
        tooltip: {
          trigger: 'axis'
        },
        top: 50,
        bottom: 10,
        left: 20,
        right: 20,
        outerBounds: {
          top: 30,
          left: 20,
          bottom: 20,
          right: 20,
        }
      },
      series: {
        type: 'bar',
        id: 'footer_1',
        xAxisId: 'footer_1',
        yAxisId: 'footer_1',
        data: generateSingleSeriesData(10, false)
      }
    }
  }
};

option = {

  // Use the matrix coordinate system to layout the charts and components.
  matrix: {
    x: { show: false, data: [] },
    y: { show: false, data: [] },
    body: {
      itemStyle: { borderColor: 'none' }
    },
    backgroundStyle: { borderColor: 'none' },
    top: 0,
    bottom: 0,
    left: 0,
    right: 0
  },

  tooltip: {},

}; // End of option


initFloatingControlPanel();

assembleIntoEChartsOption(option, _sectionDefinitionMap, _mediaDefinitionList);

console.log(option);


/**
 * Merge those definitions into the single echarts option.
 * @param option The target echarts option to be written to.
 */
function assembleIntoEChartsOption(option, sectionDefinitionMap, mediaDefinitionList) {

  option.media = mediaDefinitionList.map(({query, matrix}) => {
    return {query, option: {matrix}};
  });

  Object.keys(sectionDefinitionMap).forEach(sectionId => {
    const section = sectionDefinitionMap[sectionId];
    const optionIdMapWillSetCoord = {};

    Object.keys(section.option).forEach((componentMainType) => {
      option[componentMainType] = normalizeToArray(option[componentMainType]);

      normalizeToArray(section.option[componentMainType]).forEach((component) => {
        component = ensureComponentId(component, sectionId, componentMainType);
        option[componentMainType].push(component);

        if (component.coordinateSystem === 'matrix') {
          optionIdMapWillSetCoord[componentMainType] = normalizeToArray(optionIdMapWillSetCoord[componentMainType]);
          optionIdMapWillSetCoord[componentMainType].push(
            component.id
          );
        }
      });
    });

    mediaDefinitionList.forEach(({query, matrix, sectionCoordMap}, mediaIdx) => {
      const optionInMedia = option.media[mediaIdx].option;
      const coord = sectionCoordMap[sectionId];
      if (!coord) {
        throw new Error(`Section with id "${sectionId}" not found in media definition index ${mediaIdx}.`);
      }
      Object.keys(optionIdMapWillSetCoord).forEach((componentMainType) => {
        optionIdMapWillSetCoord[componentMainType].forEach((id) => {
          optionInMedia[componentMainType] = normalizeToArray(optionInMedia[componentMainType]);
          optionInMedia[componentMainType].push({
            id: id,
            coord: coord
          });
        });
      });
    });
  });
}

/**
 * If no component id, generate one, and immutablely return a new component object.
 */
function ensureComponentId(component, sectionId, componentMainType) {
  if (component.id != null) {
    return component;
  }
  component = Object.assign({}, component);
  component.id = sectionId + '_' + componentMainType + '_' + _idBase++;
  return component;
}

/**
 * `{}` is converted to `[{}]`; null/undefined is converted to `[]`.
 */
function normalizeToArray(value) {
  return Array.isArray(value) ? value : value != null ? [value] : [];
}

/**
 * Generate some random data for a single series.
 */
function matrixGridRandom() {
  let x = _matrixGridRandomState;
  x ^= x << 13;
  x ^= x >>> 17;
  x ^= x << 5;
  _matrixGridRandomState = x >>> 0;
  return _matrixGridRandomState / 4294967296;
}

function generateSingleSeriesData(dayCount, inverseXY) {
  const dayStart = new Date('2025-05-05T00:00:00.000Z'); // Monday
  const timeStart = dayStart.getTime();
  const sevenDay = 7 * 1000 * 3600 * 24;
  const seriesData = [];
  let lastVal = +(matrixGridRandom() * 300).toFixed(0);

  let turnCount = null;
  let sign = -1;
  for (let idx = 0; idx < dayCount; idx++) {
    if (turnCount == null || idx >= turnCount) {
      turnCount =
        idx + Math.round((dayCount / 4) * ((matrixGridRandom() - 0.5) * 0.1));
      sign = -sign;
    }
    const deltaMag = 50;
    const delta = +(
      matrixGridRandom() * deltaMag -
      deltaMag / 2 +
      (sign * deltaMag) / 3
    ).toFixed(0);
    const val = Math.max(0, (lastVal += delta));
    const xTime = timeStart + idx * sevenDay;
    const dataXVal = echarts.time.format(xTime, '{yyyy}-{MM}-{dd}');
    const item = [dataXVal, val];
    if (inverseXY) {
      item.reverse();
    }
    seriesData.push(item);
  }

  return seriesData;
}

/**
 * Note: The floating control panel are not relevant to echarts API,
 *  just for illustration purposes.
 */
function initFloatingControlPanel() {
  app.config = {};
  app.configParameters = {};
  app.config.showMatrixGrid = false;
  app.configParameters.showMatrixGrid = { options: [false, true] };
  app.config.onChange = function () {
    myChart.setOption({
      matrix: {
        body: {itemStyle: {borderColor: app.config.showMatrixGrid ? 'red' : 'none'}}
      }
    });
  };
}
"""#,
        option: matrixGridLayoutOption())
}
