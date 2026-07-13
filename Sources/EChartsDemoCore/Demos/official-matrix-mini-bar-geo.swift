// official-matrix-mini-bar-geo — replica of
// https://echarts.apache.org/examples/zh/editor.html?c=matrix-mini-bar-geo
// title: Mini Bars and Geo in Matrix / titleCN: 矩阵坐标系下的微型条形图和地图
//
// A `matrix` coordinate system used as a table: 4 columns ('Region and Time', 'Data A', 'Data B',
// 'Location') × 10 rows (Swiss cantons). Column 0 is plain text in the matrix BODY; columns 1–2 each
// host one `grid` + `xAxis` + `yAxis` PER CELL (`coordinateSystem: 'matrix'`, `coord: [col, row]`)
// carrying two horizontal mini `bar` series (the 2021 / 2020 data sources, legend-linked); column 3
// hosts one `geo` per cell — the Swiss cantons map with that row's canton `selected` (highlighted).
//
// DEVIATIONS from the official source:
//   - The source is TypeScript (the official editor transpiles it). The reference pane is a CLASSIC
//     script, so webOptionJS carries the same code with the TS-only syntax stripped: the
//     `type DataSourceList` alias, the `: T` annotations, the `as number`/`as string` casts and the
//     `!` non-null assertions. Every statement, loop and value is otherwise verbatim.
//   - `fetchGeoJSON()` ($.get of ROOT_PATH + '/data/asset/geo/ch.geo.json' → registerMap →
//     createChart) is gone: the page has no network. The GeoJSON is read from assets/geo/ch.geo.json
//     (the upstream asset, byte-identical) and registered by BOTH panes through `mapRegistrations`
//     (WebPage.swift injects `echarts.registerMap` before the option script; the native pane calls
//     `ECharts.registerMap`). `createChart()` is therefore called unconditionally at top level, and
//     the `myChart.showLoading()/hideLoading()/setOption()` calls are dropped.
//   - Canvas is 720×560 rather than the editor's default so the 10 mini-bar rows have room.
//   - Native pane: NO option keys are omitted. The example's closures all run at BUILD time (the
//     `.map()`s / `forEach`s that assemble `option`), none survives into the emitted option itself —
//     so the Swift pane just runs the same algorithm over the same data and gets an equivalent
//     option (40 bar series, 20 grids + axis pairs, 10 geos, 10 matrix body cells).
import Foundation
import EChartsKit

// The Swiss cantons GeoJSON (26 features), upstream `/data/asset/geo/ch.geo.json`. Parsed ONCE from
// the repo asset; a parse failure degrades to an empty FeatureCollection (blank map, no crash).
private let chGeoJSON: [String: Any] = {
    let url = Upstream.repoRoot.appendingPathComponent("assets/geo/ch.geo.json")
    guard let data = try? Data(contentsOf: url),
          let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
        return ["type": "FeatureCollection", "features": [] as [Any]]
    }
    return obj
}()

// ---------------------------------------------------------------------------------------------
// The example's module-scope data (`_colHeaders`, `_dataSourceList`, `_colorList`), typed for Swift.
// ---------------------------------------------------------------------------------------------

private let matrixMiniColHeaders: [String] = ["Region and Time", "Data A", "Data B", "Location"]
private let matrixMiniRegionColIdx = 0
private let matrixMiniGeoColIdx = 3

// Column 0 of every `_dataSourceList[i].data` row — identical across sources (the example assumes so).
private let matrixMiniRegions: [String] = [
    "Valais", "Ticino", "Graubünden", "Uri", "Lucerne",
    "Neuchâtel", "Jura", "Vaud", "Thurgau", "Schwyz"
]

private let matrixMiniSourceNames: [String] = ["2021", "2020"]

// `_dataSourceList[srcIdx].data[rowIdx]` columns 1..2 — [Data A, Data B] per canton, per source.
private let matrixMiniSourceValues: [[[Double]]] = [
    // 2021
    [[1212, 2321], [7181, 2114], [2763, 4212], [6122, 2942], [4221, 3411],
     [7221, 5121], [5121, 4121], [6121, 3121], [7121, 2121], [8121, 1121]],
    // 2020
    [[1010, 2221], [7040, 1810], [2313, 4011], [6011, 2749], [3329, 3015],
     [7116, 4822], [4968, 3820], [6027, 2928], [7011, 1725], [7311, 825]]
]

private let matrixMiniColorList: [String] = [
    "#ffd10a", "#0ca8df", "#b6d634", "#3fbe95", "#5070dd",
    "#ff994d", "#505372", "#fb628b", "#785db0"
]

/// `calculateDataExtentOnCol` — [min, max] of data column `colIdx` (1 or 2) across ALL data sources.
private func matrixMiniExtent(onCol colIdx: Int) -> [Double] {
    var minV = Double.infinity
    var maxV = -Double.infinity
    for source in matrixMiniSourceValues {
        for row in source {
            let v = row[colIdx - 1]   // source rows hold columns 1..2 only
            if v < minV { minV = v }
            if v > maxV { maxV = v }
        }
    }
    return [minV, maxV]
}

/// The Swift twin of `createChart()`: the same nested col/row loop, dispatching to the plain-text /
/// mini-bar / mini-geo cell builders.
private func matrixMiniBarGeoOption() -> [String: Any] {
    var matrixXData: [[String: Any]] = []
    for (colIdx, header) in matrixMiniColHeaders.enumerated() {
        var item: [String: Any] = ["value": header]
        if colIdx == matrixMiniGeoColIdx { item["size"] = "15%" }
        else if colIdx == matrixMiniRegionColIdx { item["size"] = 120.0 }
        matrixXData.append(item)   // `size: undefined` for the data columns → key omitted
    }

    var bodyData: [[String: Any]] = []
    var grids: [[String: Any]] = []
    var xAxes: [[String: Any]] = []
    var yAxes: [[String: Any]] = []
    var geos: [[String: Any]] = []
    var series: [[String: Any]] = []

    let rowCount = matrixMiniRegions.count
    // 47° is Switzerland's approximate latitude.
    let aspectScale = cos(47.0 * Double.pi / 180.0)

    for colIdx in 0..<matrixMiniColHeaders.count {
        let extent: [Double]? =
            (colIdx == matrixMiniRegionColIdx || colIdx == matrixMiniGeoColIdx)
            ? nil : matrixMiniExtent(onCol: colIdx)

        for rowIdx in 0..<rowCount {
            let coord: [Double] = [Double(colIdx), Double(rowIdx)]

            if colIdx == matrixMiniRegionColIdx {
                // addCellPlainText
                bodyData.append([
                    "value": matrixMiniRegions[rowIdx],
                    "coord": coord
                ] as [String: Any])

            } else if colIdx == matrixMiniGeoColIdx {
                // addCellMiniGeo
                geos.append([
                    "id": "mini-geo-\(rowIdx)",
                    "map": "target_map",
                    "animation": false,
                    "aspectScale": aspectScale,
                    "coordinateSystem": "matrix",
                    "coord": coord,
                    "roam": false,
                    "selectedMode": false,
                    "tooltip": ["show": false] as [String: Any],
                    "regions": [
                        [
                            "name": matrixMiniRegions[rowIdx],
                            "selected": true,
                            "select": [
                                "itemStyle": ["color": "#0a41e6"] as [String: Any]
                            ] as [String: Any]
                        ] as [String: Any]
                    ],
                    "select": [
                        "label": ["show": false] as [String: Any]
                    ] as [String: Any]
                ] as [String: Any])

            } else {
                // addCellMiniBar — one grid + xAxis + yAxis per cell, one bar series per data source.
                let id = "mini-bar-\(colIdx)-\(rowIdx)"
                grids.append([
                    "id": id,
                    "coordinateSystem": "matrix",
                    "coord": coord,
                    "top": "15%",
                    "bottom": "15%"
                ] as [String: Any])

                var xAxis: [String: Any] = [
                    "id": id,
                    "gridId": id,
                    "type": "value",
                    "min": 0.0,
                    "scale": false,
                    "axisLine": ["show": false] as [String: Any],
                    "axisTick": ["show": false] as [String: Any],
                    "splitLine": ["show": false] as [String: Any],
                    "axisLabel": ["show": false] as [String: Any]
                ]
                if let extent { xAxis["max"] = extent[1] }   // `max: undefined` otherwise
                xAxes.append(xAxis)

                yAxes.append([
                    "id": id,
                    "gridId": id,
                    "type": "category",
                    "boundaryGap": false,
                    "inverse": true,
                    "axisLine": ["show": false] as [String: Any],
                    "axisTick": ["show": false] as [String: Any],
                    "splitLine": ["show": false] as [String: Any],
                    "axisLabel": ["show": false] as [String: Any]
                ] as [String: Any])

                for (srcIdx, srcName) in matrixMiniSourceNames.enumerated() {
                    let value = matrixMiniSourceValues[srcIdx][rowIdx][colIdx - 1]
                    series.append([
                        "type": "bar",
                        "name": srcName,           // collected into the legend
                        "xAxisId": id,
                        "yAxisId": id,
                        "label": ["show": true, "position": "insideLeft"] as [String: Any],
                        "barMinHeight": 2.0,
                        "barGap": "40%",
                        "barWidth": "40%",
                        "itemStyle": [
                            "color": matrixMiniColorList[srcIdx % matrixMiniColorList.count]
                        ] as [String: Any],
                        "encode": ["label": 0.0] as [String: Any],
                        // Same Y value ('') for both sources → they share one bar layout slot.
                        "data": [[value, ""] as [Any]]
                    ] as [String: Any])
                }
            }
        }
    }

    return [
        "matrix": [
            "x": [
                "levelSize": 40.0,
                "data": matrixXData,
                "itemStyle": ["color": "#f0f8ff"] as [String: Any],
                "label": ["fontWeight": "bold"] as [String: Any]
            ] as [String: Any],
            "y": [
                // Any value is fine here, as we will not use it.
                "data": [String](repeating: "_", count: rowCount),
                "show": false
            ] as [String: Any],
            "body": ["data": bodyData] as [String: Any],
            "top": 25.0
        ] as [String: Any],
        "legend": [:] as [String: Any],
        "tooltip": [:] as [String: Any],
        "grid": grids,
        "xAxis": xAxes,
        "yAxis": yAxes,
        "geo": geos,
        "series": series
    ]
}

extension EChartsDemoRegistry {
    static let official_matrix_mini_bar_geo = EChartsDemo(
        name: "official-matrix-mini-bar-geo", category: "matrix",
        summary: "矩阵坐标系下的微型条形图和地图 — Mini Bars and Geo in Matrix",
        width: 720, height: 560,
        nativeSupported: true,
        mapRegistrations: ["target_map": chGeoJSON],
        collection: .official,
        webOptionJS: #"""
var _colHeaders = ['Region and Time', 'Data A', 'Data B', 'Location'];
var _regionColIdx = 0;
var _geoColIdx = 3;
var _dataSourceList = [
  {
    name: '2021',
    data: [
      // 'Region', 'Data A', 'Data B'
      ['Valais', 1212, 2321],
      ['Ticino', 7181, 2114],
      ['Graubünden', 2763, 4212],
      ['Uri', 6122, 2942],
      ['Lucerne', 4221, 3411],
      ['Neuchâtel', 7221, 5121],
      ['Jura', 5121, 4121],
      ['Vaud', 6121, 3121],
      ['Thurgau', 7121, 2121],
      ['Schwyz', 8121, 1121],
    ]
  },
  {
    name: '2020',
    data: [
      // 'Region', 'Data A', 'Data B'
      ['Valais', 1010, 2221],
      ['Ticino', 7040, 1810],
      ['Graubünden', 2313, 4011],
      ['Uri', 6011, 2749],
      ['Lucerne', 3329, 3015],
      ['Neuchâtel', 7116, 4822],
      ['Jura', 4968, 3820],
      ['Vaud', 6027, 2928],
      ['Thurgau', 7011, 1725],
      ['Schwyz', 7311, 825],
    ]
  }
];

var _colorList = [
    '#ffd10a',
    '#0ca8df',
    '#b6d634',
    '#3fbe95',
    '#5070dd',
    '#ff994d',
    '#505372',
    '#fb628b',
    '#785db0',
];

function createChart() {
  option = {
    matrix: {
      x: {
        levelSize: 40,
        data: _colHeaders.map(function (item, colIdx) {
          return {
            value: item,
            size: colIdx === _geoColIdx ? '15%'
              : colIdx === _regionColIdx ? 120
              : undefined
          };
        }),
        itemStyle: {color: '#f0f8ff'},
        label: { fontWeight: 'bold' }
      },
      y: {
        data: _dataSourceList[0].data.map(function () {
          return '_'; // Any value is fine here, as we will not use it.
        }),
        show: false,
      },
      body: {
        data: []
      },
      top: 25
    },
    legend: {},
    tooltip: {},
    grid: [],
    xAxis: [],
    yAxis: [],
    geo: [],
    series: []
  };

  // Assume every dataSourceList[i] has the same length; just for simplicity in this demo.
  var rowCount = _dataSourceList[0].data.length;

  for (var dataColIdx = 0; dataColIdx < _colHeaders.length; ++dataColIdx) {
    var dataExtentOnCol = (dataColIdx === _regionColIdx || dataColIdx === _geoColIdx)
      ? null
      : calculateDataExtentOnCol(_dataSourceList, dataColIdx);
    for (var dataRowIdx = 0; dataRowIdx < rowCount; ++dataRowIdx) {
      if (dataColIdx === _regionColIdx) {
        addCellPlainText(
          option, _dataSourceList, dataColIdx, dataRowIdx
        );
      }
      else if (dataColIdx === _geoColIdx) {
        addCellMiniGeo(
          option, _dataSourceList, dataColIdx, dataRowIdx
        );
      }
      else {
        addCellMiniBar(
          option, _dataSourceList, dataColIdx, dataRowIdx, dataExtentOnCol
        );
      }
    }
  }
}

function calculateDataExtentOnCol(dataSourceList, colIdx) {
  var min = Infinity;
  var max = -Infinity;
  dataSourceList.forEach(dataSource => {
    dataSource.data.forEach(dataRow => {
      var val = dataRow[colIdx];
      if (val < min) { min = val; }
      if (val > max) { max = val; }
    });
  });
  return [min, max];
}

function addCellPlainText(
  option,
  dataSourceList,
  dataColIdx,
  dataRowIdx
) {
  // Assume every dataSourceList[i] has the same region names; just for simplicity in this demo.
  var dataSource = dataSourceList[0];
  option.matrix.body.data.push({
    value: dataSource.data[dataRowIdx][dataColIdx],
    coord: [dataColIdx, dataRowIdx], // coord in matrix, happens to be the same as `dataColIdx` here.
  });
}

function addCellMiniBar(
  option,
  dataSourceList,
  dataColIdx,
  dataRowIdx,
  dataExtentOnCol
) {
  var id = 'mini-bar-' + dataColIdx + '-' + dataRowIdx;
  option.grid.push({
    id: id,
    coordinateSystem: 'matrix',
    coord: [dataColIdx, dataRowIdx], // coord in matrix, happens to be the same as `dataColIdx` here.
    top: '15%',
    bottom: '15%',
  });
  option.xAxis.push({
    id: id,
    gridId: id,
    type: 'value',
    min: 0,
    max: dataExtentOnCol ? dataExtentOnCol[1] : undefined,
    scale: false,
    axisLine: {show: false},
    axisTick: {show: false},
    splitLine: {show: false},
    axisLabel: {show: false}
  });
  option.yAxis.push({
    id: id,
    gridId: id,
    type: 'category',
    boundaryGap: false,
    inverse: true,
    axisLine: {show: false},
    axisTick: {show: false},
    splitLine: {show: false},
    axisLabel: {show: false}
  });
  dataSourceList.forEach((dataSource, dataSourceIdx) => {
    option.series.push({
      type: 'bar',
      // `name` will be collected to legend.
      name: dataSource.name,
      xAxisId: id,
      yAxisId: id,
      label: {show: true, position: 'insideLeft'},
      barMinHeight: 2,
      barGap: '40%',
      barWidth: '40%',
      itemStyle: {
        color: _colorList[dataSourceIdx % _colorList.length]
      },
      encode: {label: 0},
      // Make sure 2021 and 2020 have the same Y value (we use '' here) for better bar series layout.
      data: [[dataSource.data[dataRowIdx][dataColIdx], '']]
    });
  });

  return option;
}

function addCellMiniGeo(
  option,
  dataSourceList,
  dataColIdx,
  dataRowIdx
) {
  var id = 'mini-geo-' + dataRowIdx;
  var regionName = dataSourceList[0].data[dataRowIdx][_regionColIdx];

  option.geo.push({
    id: id,
    map: 'target_map',
    animation: false,
    aspectScale: Math.cos(47 * Math.PI / 180), // 47 is Switzerland's approximate latitude.
    coordinateSystem: 'matrix',
    coord: [dataColIdx, dataRowIdx], // coord in matrix, happens to be the same as `dataColIdx` here.
    roam: false,
    selectedMode: false,
    tooltip: {show: false},
    regions: [{
      name: regionName,
      selected: true,
      select: {
        itemStyle: {color: '#0a41e6'}
      }
    }],
    select: {
      label: {show: false},
    },
  });
}

// The geo JSON is registered into the page by the gallery (mapRegistrations), so the upstream
// `fetchGeoJSON()` / `$.get(ROOT_PATH + '/data/asset/geo/ch.geo.json', ...)` wrapper is dropped and
// only its callback body survives: register the map, then build the option.
createChart();
"""#,
        option: {
            // Upstream: `echarts.registerMap('target_map', geoJSON)` inside the $.get callback.
            ECharts.registerMap("target_map", chGeoJSON)
            return matrixMiniBarGeoOption()
        }())
}
