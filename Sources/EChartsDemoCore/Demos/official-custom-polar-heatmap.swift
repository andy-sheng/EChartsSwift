// official-custom-polar-heatmap — replica of https://echarts.apache.org/examples/zh/editor.html?c=custom-polar-heatmap
// title: Polar Heatmap / titleCN: 极坐标热力图（自定义系列）
// A GitHub-style punch card (7 days x 24 hours) drawn on a `polar` coordinate system: the angle axis is
// the hour, the radius axis is the weekday, and each cell is a `custom` series `sector` whose fill comes
// from a continuous visualMap on dimension 2 (the commit count).
//
// DEVIATIONS from the official source:
//   - TypeScript stripped, and NOTHING ELSE. `api.size!([1, 1], values) as number[]` →
//     `api.size([1, 1], values)`, `(params.coordSys as any).cx` → `params.coordSys.cx` (same for `.cy`),
//     and the trailing `export {};` is dropped (a bare export is a SyntaxError in a classic script; the
//     `/* title: … */` editor-metadata block is likewise dropped — it is reproduced on line 2). `hours`,
//     `days`, `data`, the `maxValue` reduce and `renderItem` are verbatim. The example is STATIC (no
//     timer, no myChart calls), so there is no timeline to reproduce and no `drive` closure.
//   - The native pane runs the SAME renderItem (polarHeatmapRenderItem, below), ported statement for
//     statement, so BOTH panes draw the whole chart.
//
// WHY THE NATIVE renderItem IS MANDATORY (do not "simplify" it back out):
//   CustomView resolves the callback as `customSeries.getRenderItem() ?? getCustomSeries(subType)`
//   (CustomView.swift:739). A Swift [String: Any] CAN carry the closure — `getRenderItem()` is exactly
//   `self.get("renderItem") as? CustomSeriesRenderItem` (CustomSeries.swift:459). It is safe here because
//   WebPage.swift only JSON-serializes `option` when `webOptionJS` is nil, and we set `webOptionJS`.
//   Omitting it would NOT leave an inert series: the `?? getCustomSeries("custom")` fallback reaches the
//   GLOBAL registry, where Demos/custom-basic.swift registers its own bar renderItem under the "custom"
//   subType, and the native pane would silently draw THAT against this demo's [day, hour, count] rows.
//   Every piece the closure needs IS ported: `polarPrepareCustom` (coord/polar/prepareCustom.swift) hands
//   api.coord `[x, y, radius, angleRad]` and api.size `[radialBand, angularBandRad]` and puts cx/cy on
//   `params.coordSys`; `createEl` builds a `sector` (CustomView.swift:483/594); `api.visual('color')`
//   reads the fill the continuous visualMap stamped on dimension 2.
import Foundation
import EChartsKit

// MARK: - the example's data (verbatim)

// prettier-ignore
private let polarHeatmapHours: [String] = [
    "12a", "1a", "2a", "3a", "4a", "5a", "6a", "7a", "8a", "9a", "10a", "11a",
    "12p", "1p", "2p", "3p", "4p", "5p", "6p", "7p", "8p", "9p", "10p", "11p"
]

// prettier-ignore
private let polarHeatmapDays: [String] = [
    "Saturday", "Friday", "Thursday", "Wednesday", "Tuesday", "Monday", "Sunday"
]

/// `[dayIndex, hourIndex, commits]` — one entry per punch-card cell (7 x 24 = 168).
private let polarHeatmapData: [[Double]] = [
    [0, 0, 5], [0, 1, 1], [0, 2, 0], [0, 3, 0], [0, 4, 0], [0, 5, 0], [0, 6, 0], [0, 7, 0],
    [0, 8, 0], [0, 9, 0], [0, 10, 0], [0, 11, 2], [0, 12, 4], [0, 13, 1], [0, 14, 1], [0, 15, 3],
    [0, 16, 4], [0, 17, 6], [0, 18, 4], [0, 19, 4], [0, 20, 3], [0, 21, 3], [0, 22, 2], [0, 23, 5],
    [1, 0, 7], [1, 1, 0], [1, 2, 0], [1, 3, 0], [1, 4, 0], [1, 5, 0], [1, 6, 0], [1, 7, 0],
    [1, 8, 0], [1, 9, 0], [1, 10, 5], [1, 11, 2], [1, 12, 2], [1, 13, 6], [1, 14, 9], [1, 15, 11],
    [1, 16, 6], [1, 17, 7], [1, 18, 8], [1, 19, 12], [1, 20, 5], [1, 21, 5], [1, 22, 7], [1, 23, 2],
    [2, 0, 1], [2, 1, 1], [2, 2, 0], [2, 3, 0], [2, 4, 0], [2, 5, 0], [2, 6, 0], [2, 7, 0],
    [2, 8, 0], [2, 9, 0], [2, 10, 3], [2, 11, 2], [2, 12, 1], [2, 13, 9], [2, 14, 8], [2, 15, 10],
    [2, 16, 6], [2, 17, 5], [2, 18, 5], [2, 19, 5], [2, 20, 7], [2, 21, 4], [2, 22, 2], [2, 23, 4],
    [3, 0, 7], [3, 1, 3], [3, 2, 0], [3, 3, 0], [3, 4, 0], [3, 5, 0], [3, 6, 0], [3, 7, 0],
    [3, 8, 1], [3, 9, 0], [3, 10, 5], [3, 11, 4], [3, 12, 7], [3, 13, 14], [3, 14, 13], [3, 15, 12],
    [3, 16, 9], [3, 17, 5], [3, 18, 5], [3, 19, 10], [3, 20, 6], [3, 21, 4], [3, 22, 4], [3, 23, 1],
    [4, 0, 1], [4, 1, 3], [4, 2, 0], [4, 3, 0], [4, 4, 0], [4, 5, 1], [4, 6, 0], [4, 7, 0],
    [4, 8, 0], [4, 9, 2], [4, 10, 4], [4, 11, 4], [4, 12, 2], [4, 13, 4], [4, 14, 4], [4, 15, 14],
    [4, 16, 12], [4, 17, 1], [4, 18, 8], [4, 19, 5], [4, 20, 3], [4, 21, 7], [4, 22, 3], [4, 23, 0],
    [5, 0, 2], [5, 1, 1], [5, 2, 0], [5, 3, 3], [5, 4, 0], [5, 5, 0], [5, 6, 0], [5, 7, 0],
    [5, 8, 2], [5, 9, 0], [5, 10, 4], [5, 11, 1], [5, 12, 5], [5, 13, 10], [5, 14, 5], [5, 15, 7],
    [5, 16, 11], [5, 17, 6], [5, 18, 0], [5, 19, 5], [5, 20, 3], [5, 21, 4], [5, 22, 2], [5, 23, 0],
    [6, 0, 1], [6, 1, 0], [6, 2, 0], [6, 3, 0], [6, 4, 0], [6, 5, 0], [6, 6, 0], [6, 7, 0],
    [6, 8, 0], [6, 9, 0], [6, 10, 1], [6, 11, 0], [6, 12, 2], [6, 13, 1], [6, 14, 3], [6, 15, 4],
    [6, 16, 0], [6, 17, 0], [6, 18, 0], [6, 19, 0], [6, 20, 1], [6, 21, 2], [6, 22, 2], [6, 23, 6]
]

/// Upstream: `data.reduce((max, item) => Math.max(max, item[2]), -Infinity)` — the visualMap's upper bound.
private let polarHeatmapMaxValue: Double = polarHeatmapData.map { $0[2] }.max() ?? 0

// MARK: - the upstream renderItem, ported

/// Coerce a ParsedValue (Any: Double | Int | NSNumber) to Double — the recurring Int-vs-Double read trap.
private func polarHeatmapNum(_ v: Any?) -> Double {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let n = v as? NSNumber { return n.doubleValue }
    return 0
}

/// The official `renderItem`, statement for statement. Typed EXACTLY `CustomSeriesRenderItem` so
/// CustomView's `get("renderItem") as? CustomSeriesRenderItem` cast holds (see header).
///
/// One datum → one punch-card cell, as a `sector` centred on the polar origin. `api.coord(values)` on a
/// polar coord sys returns `[x, y, radius, angleRad]` — only [2] and [3] are used — and
/// `api.size([1, 1], values)` returns one cell's `[radialBand, angularBandRad]`. The cell therefore spans
/// half a band either side of its centre, and the angles are NEGATED because screen angles run clockwise.
private let polarHeatmapRenderItem: CustomSeriesRenderItem = { params, api in
    // JS: var values = [api.value(0), api.value(1)];   (dim 0 = day → radius, dim 1 = hour → angle)
    //   `api.value` takes a DimensionLoose (Any); a NUMERIC dim must be a Double — SeriesData
    //   .getDimensionIndex force-casts it `as! Double`, so an Int literal would crash.
    let values = [polarHeatmapNum(api.value(0.0, nil)), polarHeatmapNum(api.value(1.0, nil))]
    // JS: var coord = api.coord(values); var size = api.size([1, 1], values);
    let coord = api.coord(values, nil)
    guard coord.count >= 4,
          let size = api.size([1.0, 1.0], values) as? [Double], size.count >= 2 else { return nil }

    // JS: cx: params.coordSys.cx, cy: params.coordSys.cy — polarPrepareCustom puts both on the bag.
    let cx = (params.coordSys.extra["cx"] as? Double) ?? 0
    let cy = (params.coordSys.extra["cy"] as? Double) ?? 0

    // JS: style: api.style({ fill: api.visual('color') }) — the continuous visualMap's colour for dim 2.
    //   A nil visual would be JS `undefined`: leave the key ABSENT rather than writing NSNull, so the
    //   item's own style survives the merge.
    var userProps: [String: Any] = [:]
    if let color = api.visual("color", nil) { userProps["fill"] = color }
    let style = api.style(userProps, nil)

    // Built as explicitly-typed locals rather than inlined into the return literal: Swift's type-checker
    //   times out on large nested heterogeneous literals.
    let shape: [String: Any] = [
        "cx": cx,
        "cy": cy,
        "r0": coord[2] - size[0] / 2,
        "r": coord[2] + size[0] / 2,
        "startAngle": -(coord[3] + size[1] / 2),
        "endAngle": -(coord[3] - size[1] / 2)
    ]
    return [
        "type": "sector",
        "shape": shape,
        "style": style
    ] as [String: Any]
}

extension EChartsDemoRegistry {
    static let official_custom_polar_heatmap = EChartsDemo(
        name: "official-custom-polar-heatmap", category: "custom",
        summary: "极坐标热力图（自定义系列） — Polar Heatmap",
        width: 720, height: 460,
        nativeSupported: true,   // renderItem IS ported — see header
        collection: .official,
        webOptionJS: #"""
// prettier-ignore
const hours = ['12a', '1a', '2a', '3a', '4a', '5a', '6a', '7a', '8a', '9a', '10a', '11a', '12p', '1p', '2p', '3p', '4p', '5p', '6p', '7p', '8p', '9p', '10p', '11p'];
// prettier-ignore
const days = ['Saturday', 'Friday', 'Thursday', 'Wednesday', 'Tuesday', 'Monday', 'Sunday'];
// prettier-ignore
const data = [[0,0,5],[0,1,1],[0,2,0],[0,3,0],[0,4,0],[0,5,0],[0,6,0],[0,7,0],[0,8,0],[0,9,0],[0,10,0],[0,11,2],[0,12,4],[0,13,1],[0,14,1],[0,15,3],[0,16,4],[0,17,6],[0,18,4],[0,19,4],[0,20,3],[0,21,3],[0,22,2],[0,23,5],[1,0,7],[1,1,0],[1,2,0],[1,3,0],[1,4,0],[1,5,0],[1,6,0],[1,7,0],[1,8,0],[1,9,0],[1,10,5],[1,11,2],[1,12,2],[1,13,6],[1,14,9],[1,15,11],[1,16,6],[1,17,7],[1,18,8],[1,19,12],[1,20,5],[1,21,5],[1,22,7],[1,23,2],[2,0,1],[2,1,1],[2,2,0],[2,3,0],[2,4,0],[2,5,0],[2,6,0],[2,7,0],[2,8,0],[2,9,0],[2,10,3],[2,11,2],[2,12,1],[2,13,9],[2,14,8],[2,15,10],[2,16,6],[2,17,5],[2,18,5],[2,19,5],[2,20,7],[2,21,4],[2,22,2],[2,23,4],[3,0,7],[3,1,3],[3,2,0],[3,3,0],[3,4,0],[3,5,0],[3,6,0],[3,7,0],[3,8,1],[3,9,0],[3,10,5],[3,11,4],[3,12,7],[3,13,14],[3,14,13],[3,15,12],[3,16,9],[3,17,5],[3,18,5],[3,19,10],[3,20,6],[3,21,4],[3,22,4],[3,23,1],[4,0,1],[4,1,3],[4,2,0],[4,3,0],[4,4,0],[4,5,1],[4,6,0],[4,7,0],[4,8,0],[4,9,2],[4,10,4],[4,11,4],[4,12,2],[4,13,4],[4,14,4],[4,15,14],[4,16,12],[4,17,1],[4,18,8],[4,19,5],[4,20,3],[4,21,7],[4,22,3],[4,23,0],[5,0,2],[5,1,1],[5,2,0],[5,3,3],[5,4,0],[5,5,0],[5,6,0],[5,7,0],[5,8,2],[5,9,0],[5,10,4],[5,11,1],[5,12,5],[5,13,10],[5,14,5],[5,15,7],[5,16,11],[5,17,6],[5,18,0],[5,19,5],[5,20,3],[5,21,4],[5,22,2],[5,23,0],[6,0,1],[6,1,0],[6,2,0],[6,3,0],[6,4,0],[6,5,0],[6,6,0],[6,7,0],[6,8,0],[6,9,0],[6,10,1],[6,11,0],[6,12,2],[6,13,1],[6,14,3],[6,15,4],[6,16,0],[6,17,0],[6,18,0],[6,19,0],[6,20,1],[6,21,2],[6,22,2],[6,23,6]];
const maxValue = data.reduce(function (max, item) {
  return Math.max(max, item[2]);
}, -Infinity);

option = {
  legend: {
    data: ['Punch Card']
  },
  polar: {},
  tooltip: {},
  visualMap: {
    type: 'continuous',
    min: 0,
    max: maxValue,
    top: 'middle',
    dimension: 2,
    calculable: true
  },
  angleAxis: {
    type: 'category',
    data: hours,
    boundaryGap: false,
    splitLine: {
      show: true,
      lineStyle: {
        color: '#ddd',
        type: 'dashed'
      }
    },
    axisLine: {
      show: false
    }
  },
  radiusAxis: {
    type: 'category',
    data: days,
    z: 100
  },
  series: [
    {
      name: 'Punch Card',
      type: 'custom',
      coordinateSystem: 'polar',
      renderItem: function (params, api) {
        var values = [api.value(0), api.value(1)];
        var coord = api.coord(values);
        var size = api.size([1, 1], values);
        return {
          type: 'sector',
          shape: {
            cx: params.coordSys.cx,
            cy: params.coordSys.cy,
            r0: coord[2] - size[0] / 2,
            r: coord[2] + size[0] / 2,
            startAngle: -(coord[3] + size[1] / 2),
            endAngle: -(coord[3] - size[1] / 2)
          },
          style: api.style({
            fill: api.visual('color')
          })
        };
      },
      data: data
    }
  ]
};
"""#,
        option: [
            "legend": [
                "data": ["Punch Card"]
            ] as [String: Any],
            "polar": [:] as [String: Any],
            "tooltip": [:] as [String: Any],
            "visualMap": [
                "type": "continuous",
                "min": 0.0,
                "max": polarHeatmapMaxValue,
                "top": "middle",
                "dimension": 2.0,
                "calculable": true
            ] as [String: Any],
            "angleAxis": [
                "type": "category",
                "data": polarHeatmapHours,
                "boundaryGap": false,
                "splitLine": [
                    "show": true,
                    "lineStyle": [
                        "color": "#ddd",
                        "type": "dashed"
                    ] as [String: Any]
                ] as [String: Any],
                "axisLine": [
                    "show": false
                ] as [String: Any]
            ] as [String: Any],
            "radiusAxis": [
                "type": "category",
                "data": polarHeatmapDays,
                "z": 100.0
            ] as [String: Any],
            "series": [
                [
                    "name": "Punch Card",
                    "type": "custom",
                    "coordinateSystem": "polar",
                    // The per-series closure (see header: this key is what keeps the global custom-series
                    // registry's `getCustomSeries("custom")` fallback from hijacking this chart).
                    "renderItem": polarHeatmapRenderItem,
                    "data": polarHeatmapData
                ] as [String: Any]
            ]
        ])
}
