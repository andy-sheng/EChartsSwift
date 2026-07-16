// official-matrix-mini-bar-data-collection — replica of
// https://echarts.apache.org/examples/zh/editor.html?c=matrix-mini-bar-data-collection
// title: Matrix Header Data Collection (Mini Bar) / titleCN: 矩阵坐标系表头数据自动收集（以微型条形图为例）
// A `matrix` coordinate system whose x/y header data is NOT declared: `matrix.x.data` / `matrix.y.data`
// are omitted, so echarts auto-COLLECTS them from the dimensions named by each series' `encode.x/y` on
// `dataset.source` (here: the dates in dim 0 become the rows, and the literal strings 'amount'/'file'/'Q'
// in dims 1/3/5 become the columns). Each of the three `custom` series then draws a mini bar + its value
// inside one matrix cell.
//
// DEVIATIONS from the official source:
//   - NATIVE PANE UNSUPPORTED (nativeSupported: false). All three series are `custom`, and the
//     `renderItem` closure returned by `makeRenderItem` IS the chart: it reads the cell rectangle via
//     `api.layout([xval, yval]).rect`, then emits a group of one `rect` (width = linearMap of the value
//     over [0, 10000]) plus one `text` of that value. A Swift [String: Any] cannot carry a JS function,
//     so dropping renderItem leaves the three series with nothing to draw — only the matrix headers would
//     survive. Everything else IS ported (dataset, matrix.x styling, the three series' type/
//     coordinateSystem/encode), so the option lights up the moment renderItem gains a native form.
//   - `makeRenderItem` / `linearMap` / `_dataExtent` are the example's own top-level helpers; they are
//     kept VERBATIM in the web pane (minus the TypeScript annotations — `: echarts.CustomSeriesRenderItem`,
//     `as number` and the `api.layout!` non-null assertion — which a classic script cannot parse) and have
//     no native counterpart for the reason above.
//   - Data inlined: none needed — the official source's `dataset.source` is already a literal.
import Foundation
import EChartsKit

private func miniBarNum(_ v: Any?) -> Double {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let n = v as? NSNumber { return n.doubleValue }
    if let s = v as? String { return Double(s) ?? .nan }
    return .nan
}
// JS `val + ''` number stringification for the label (whole → no trailing .0).
private func miniBarLabelStr(_ v: Any?) -> String {
    if let s = v as? String { return s }
    let n = miniBarNum(v)
    if n.isNaN { return "\(v ?? "")" }
    return n == n.rounded() ? String(Int(n)) : String(n)
}
// upstream: linearMap(val, domain, range) — the example's own helper (not zrender's).
private func miniBarLinearMap(_ val: Double, _ domain: [Double], _ range: [Double]) -> Double {
    let d0 = domain[0], d1 = domain[1], r0 = range[0], r1 = range[1]
    let subDomain = d1 - d0, subRange = r1 - r0
    if subDomain == 0 { return subRange == 0 ? r0 : (r0 + r1) / 2 }
    if val == d0 { return r0 }
    if val == d1 { return r1 }
    return (val - d0) / subDomain * subRange + r0
}
// upstream: makeRenderItem(xDim, yDim, valDim, dataExtent) — one group of {value-width mini bar + label}
//   per matrix cell, sized to `api.layout([xval, yval]).rect`.
private func makeMiniBarRenderItem(_ xDim: Double, _ yDim: Double, _ valDim: Double, _ dataExtent: [Double]) -> CustomSeriesRenderItem {
    return { _, api in
        let xval = api.value(xDim, nil)
        let yval = api.value(yDim, nil)
        let labelVal = api.value(valDim, nil)
        guard let rect = api.layout([xval, yval], nil)?.rect else { return nil }
        let height = rect.height * 0.2
        let barY = rect.y + (rect.height - height) / 4 * 3
        let barX = rect.x + rect.width * 0.15
        let widthMax = rect.width * 0.5
        let width = miniBarLinearMap(miniBarNum(labelVal), dataExtent, [0, widthMax])
        return [
            "type": "group",
            "children": [
                [
                    "type": "rect",
                    "shape": ["x": barX, "y": barY, "width": width, "height": height] as [String: Any],
                    "style": api.style(["fill": "#0ca8df"], nil)
                ] as [String: Any],
                [
                    "type": "text",
                    "x": barX,
                    "y": rect.y + rect.height / 4 * 1.5,
                    "style": ["text": miniBarLabelStr(labelVal), "fill": "#333", "align": "left", "verticalAlign": "middle"] as [String: Any]
                ] as [String: Any]
            ]
        ] as [String: Any]
    }
}

extension EChartsDemoRegistry {
    static let official_matrix_mini_bar_data_collection = EChartsDemo(
        name: "official-matrix-mini-bar-data-collection", category: "matrix",
        summary: "矩阵坐标系表头数据自动收集（以微型条形图为例） — Matrix Header Data Collection (Mini Bar)",
        width: 720, height: 460,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
/**
 * Each section contain some charts and components.
 */

function makeRenderItem(xDim, yDim, valDim, dataExtent) {
  return function (params, api) {
    const xval = api.value(xDim);
    const yval = api.value(yDim);
    const labelVal = api.value(valDim);
    const rect = api.layout([xval, yval]).rect;
    if (!rect) {
        return;
    }

    const height = rect.height * 0.2;
    const barY = rect.y + (rect.height - height) / 4 * 3;
    const barX = rect.x + rect.width * 0.15;
    const widthMax = rect.width * 0.5;
    const width = linearMap(labelVal, dataExtent, [0, widthMax])
    return {
        type: 'group',
        children: [{
            type: 'rect',
            shape: {x: barX, y: barY, width, height},
            style: api.style({
                fill: '#0ca8df',
            }),
        }, {
            type: 'text',
            x: barX,
            y: rect.y + rect.height / 4 * 1.5,
            style: {
                text: labelVal + '',
                fill: '#333',
                align: 'left',
                verticalAlign: 'middle',
            },
        }]
    };
  };
}

function linearMap(val, domain, range) {
    const d0 = domain[0];
    const d1 = domain[1];
    const r0 = range[0];
    const r1 = range[1];
    const subDomain = d1 - d0;
    const subRange = r1 - r0;

    return subDomain === 0 ? subRange === 0 ? r0 : (r0 + r1) / 2
        : val === d0 ? r0
        : val === d1 ? r1
        : (val - d0) / subDomain * subRange + r0;
}

const _dataExtent = [0, 10000];

option = {
    dataset: {
        source: [
            ['2021-02-01', 'amount', 1212, 'file', 2321, 'Q', 1412],
            ['2021-02-02', 'amount', 7181, 'file', 2114, 'Q', 1402],
            ['2021-02-03', 'amount', 2763, 'file', 4212, 'Q', 8172],
            ['2021-02-04', 'amount', 6122, 'file', 2942, 'Q', 6121],
            ['2021-02-05', 'amount', 4221, 'file', 3411, 'Q', 1987],
            ['2021-02-06', 'amount', 7221, 'file', 5121, 'Q', 1303],
            ['2021-02-07', 'amount', 5121, 'file', 4121, 'Q', 1819],
            ['2021-02-08', 'amount', 6121, 'file', 3121, 'Q', 2303],
            ['2021-02-09', 'amount', 7121, 'file', 2121, 'Q', 3303],
            ['2021-02-10', 'amount', 8121, 'file', 1121, 'Q', 4303],
        ]
    },
    matrix: {
      // matrix.x/y.data is not specified, which means they will be collected from
      // `dataset.source` (or `series.data`, if any).
      // All of values under the dimensions specified by `series.encode.x/y` will be
      // auto-collected as `matrix.x/y.data`.
      x: {levelSize: 50, itemStyle: {color: '#f0f8ff'}, label: {fontWeight: 'bold'}},
    },
    series: [{
        type: 'custom',
        coordinateSystem: 'matrix',
        encode: {x: 1, y: 0},
        renderItem: makeRenderItem(1, 0, 2, _dataExtent),
    }, {
        type: 'custom',
        coordinateSystem: 'matrix',
        encode: {x: 3, y: 0},
        renderItem: makeRenderItem(3, 0, 4, _dataExtent),
    }, {
        type: 'custom',
        coordinateSystem: 'matrix',
        encode: {x: 5, y: 0},
        renderItem: makeRenderItem(5, 0, 6, _dataExtent),
    }],
};
"""#,
        option: [
            "dataset": [
                "source": matrixMiniBarDataCollectionSource
            ] as [String: Any],
            // matrix.x/y.data is not specified, which means they will be collected from
            // `dataset.source` (or `series.data`, if any).
            "matrix": [
                "x": [
                    "levelSize": 50.0,
                    "itemStyle": ["color": "#f0f8ff"] as [String: Any],
                    "label": ["fontWeight": "bold"] as [String: Any]
                ] as [String: Any]
            ] as [String: Any],
            "series": [
                [
                    "type": "custom",
                    "coordinateSystem": "matrix",
                    "encode": ["x": 1.0, "y": 0.0] as [String: Any],
                    // renderItem ported: makeMiniBarRenderItem(1, 0, 2, [0, 10000]) — a value-width mini bar
                    // + label in each matrix cell (matrix categories auto-collected from the dataset).
                    "renderItem": makeMiniBarRenderItem(1.0, 0.0, 2.0, [0, 10000])
                ] as [String: Any],
                [
                    "type": "custom",
                    "coordinateSystem": "matrix",
                    "encode": ["x": 3.0, "y": 0.0] as [String: Any],
                    "renderItem": makeMiniBarRenderItem(3.0, 0.0, 4.0, [0, 10000])
                ] as [String: Any],
                [
                    "type": "custom",
                    "coordinateSystem": "matrix",
                    "encode": ["x": 5.0, "y": 0.0] as [String: Any],
                    "renderItem": makeMiniBarRenderItem(5.0, 0.0, 6.0, [0, 10000])
                ] as [String: Any]
            ]
        ])
}

// dataset.source: [date, 'amount', <v>, 'file', <v>, 'Q', <v>] per row. Dim 0 supplies the matrix ROWS
// (encode.y), dims 1/3/5 the matrix COLUMNS (encode.x) — both auto-collected, hence the example's point.
private let matrixMiniBarDataCollectionSource: [[Any]] = [
    ["2021-02-01", "amount", 1212.0, "file", 2321.0, "Q", 1412.0],
    ["2021-02-02", "amount", 7181.0, "file", 2114.0, "Q", 1402.0],
    ["2021-02-03", "amount", 2763.0, "file", 4212.0, "Q", 8172.0],
    ["2021-02-04", "amount", 6122.0, "file", 2942.0, "Q", 6121.0],
    ["2021-02-05", "amount", 4221.0, "file", 3411.0, "Q", 1987.0],
    ["2021-02-06", "amount", 7221.0, "file", 5121.0, "Q", 1303.0],
    ["2021-02-07", "amount", 5121.0, "file", 4121.0, "Q", 1819.0],
    ["2021-02-08", "amount", 6121.0, "file", 3121.0, "Q", 2303.0],
    ["2021-02-09", "amount", 7121.0, "file", 2121.0, "Q", 3303.0],
    ["2021-02-10", "amount", 8121.0, "file", 1121.0, "Q", 4303.0]
]
