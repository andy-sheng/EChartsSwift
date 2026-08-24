// official-custom-hexbin — replica of https://echarts.apache.org/examples/zh/editor.html?c=custom-hexbin
// title: Hexagonal Binning / titleCN: 六边形分箱图（自定义系列）
// Kawhi Leonard's 2016-17 regular-season shot chart: 1311 shots are hex-binned (d3-hexbin's algorithm,
// r = 1 geo unit) onto an NBA half-court `geo`; each bin is a `custom` polygon whose SIZE encodes shots
// attempted and whose COLOUR (continuous visualMap on dimension 3) encodes field-goal %. A second
// `custom` series strokes the court lines.
//
// DEVIATIONS from the official source:
//   - DATA INLINED. Upstream does `$.when($.getJSON(ROOT_PATH + '/data/asset/data/kawhi-leonard-16-17-
//     regular.json'), $.getJSON(ROOT_PATH + '/data/asset/data/nba-court.json')).done(...)`. The page has
//     no network, so both files are mirrored into assets/data/ and read at demo time via
//     Upstream.repoRoot; the callback BODY is kept and `option` is assigned at the top level. The web
//     pane gets the two files' RAW JSON text spliced in, so its closures see byte-identical inputs.
//     The callback's first two lines (`shotData = shotData[0]; nbaCourt = nbaCourt[0]`) unwrap jQuery's
//     `[data, statusText, jqXHR]` envelope; with the JSON spliced in directly there is no envelope, so
//     they go. Diffing the rest of webOptionJS against the official source is byte-for-byte clean.
//   - registerMap MOVED OUT. Upstream calls `echarts.registerMap('nbaCourt', nbaCourt.borderGeoJSON)`
//     inside the callback; here it is declared in `mapRegistrations` so WebPage.swift injects it into
//     the page before the option script and the native pane registers the same map.
//   - BOTH `renderItem` closures ARE ported natively (`hexbinRenderItemHexBin` / `hexbinRenderItemNBACourt`,
//     below), statement for statement, and registered on their series under the `"renderItem"` key —
//     `CustomView` resolves the callback as `customSeries.getRenderItem() ?? getCustomSeries(subType)`, and
//     a `[String: Any]` CAN carry a Swift closure (only `webOptionJS`'s JSON path could not), so both
//     panes draw the full chart: the hex-binned shot chart AND the court outline.
//   - `((made / len) * 100).toFixed(2)` yields a STRING in JS; the native data carries the same value as a
//     2-decimal Double (dimension 3 is a visualMap input, i.e. numeric).
//   - The upstream `maxBinLen` loop is buggy (`Math.max(maxBinLen, bins.length)` — it never reads
//     `bins[i].points.length`, so maxBinLen is just the BIN COUNT). Kept verbatim in the web pane; the
//     native `renderItem` reproduces the same buggy value as `hexbinMaxBinLen = hexbinSeriesData.count`
//     (one data row == one bin) rather than re-deriving it from a second loop.
//   - visualMap is scoped to seriesIndex 0. Without that constraint ECharts also targets the silent
//     one-dimensional court-outline custom series; dragging the calculable handle then makes the
//     upstream hover-link read dimension 3 from that series and throw. The colour dimension belongs
//     only to the hexbin series, so the explicit target preserves the intended interaction.
//   - The `legend: { data: ['bar', 'error'] }` entry is vestigial upstream (no series is named `bar` or
//     `error`); kept verbatim in both panes.
import Foundation
import EChartsKit

// MARK: - assets (mirrors of the official /data/asset/data/*.json, read from the repo)

private func hexbinAssetText(_ name: String, fallback: String) -> String {
    let url = Upstream.repoRoot.appendingPathComponent("assets/data/\(name)")
    return (try? String(contentsOf: url, encoding: .utf8)) ?? fallback
}

private func hexbinParse(_ text: String) -> [String: Any] {
    guard let data = text.data(using: .utf8),
          let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return [:] }
    return obj
}

/// Raw JSON text, spliced verbatim into webOptionJS (the page cannot reach the filesystem).
private let hexbinShotJSONText: String =
    hexbinAssetText("kawhi-leonard-16-17-regular.json", fallback: #"{"schema":[],"data":[]}"#)
private let hexbinCourtJSONText: String =
    hexbinAssetText("nba-court.json",
                    fallback: #"{"borderGeoJSON":{"type":"FeatureCollection","features":[]},"geometry":[]}"#)

private let hexbinShotJSON: [String: Any] = hexbinParse(hexbinShotJSONText)
private let hexbinCourtJSON: [String: Any] = hexbinParse(hexbinCourtJSONText)

/// The court outline registered as the `nbaCourt` map (upstream: `nbaCourt.borderGeoJSON`).
private let hexbinCourtGeoJSON: [String: Any] =
    (hexbinCourtJSON["borderGeoJSON"] as? [String: Any])
        ?? ["type": "FeatureCollection", "features": [] as [Any]]

/// `nbaCourt.geometry` — the entries `renderItemNBACourt` iterates (upstream: `nbaCourt.geometry.map(...)`).
private struct HexbinCourtGeometryItem {
    var type: String
    var points: [[Double]]
}

private let hexbinCourtGeometry: [HexbinCourtGeometryItem] = {
    guard let geometry = hexbinCourtJSON["geometry"] as? [[String: Any]] else { return [] }
    return geometry.compactMap { item -> HexbinCourtGeometryItem? in
        guard let type = item["type"] as? String,
              let rawPoints = item["points"] as? [[Any]] else { return nil }
        let points: [[Double]] = rawPoints.map { pt in pt.map { hexbinNum($0) } }
        return HexbinCourtGeometryItem(type: type, points: points)
    }
}()

// MARK: - hexBinStatistics (port of the example's d3-hexbin-derived binning)

private let hexbinRadiusInGeo: Double = 1
private let hexbinBackgroundColor = "#333"

// Coerce a ParsedValue (Any: Double | Int | NSNumber) to Double — the recurring Int-vs-Double read trap.
private func hexbinNum(_ v: Any?) -> Double {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let n = v as? NSNumber { return n.doubleValue }
    return .nan
}

private struct HexbinBin {
    var x: Double = 0
    var y: Double = 0
    var points: [[Double]] = []
}

/// `[x, y, shotsAttempted, fieldGoalPercent]` per bin — upstream's `data` array.
private let hexbinSeriesData: [[Double]] = {
    guard let schema = hexbinShotJSON["schema"] as? [String],
          let rows = hexbinShotJSON["data"] as? [[Any]],
          let xi = schema.firstIndex(of: "loc_x"),
          let yi = schema.firstIndex(of: "loc_y"),
          let mi = schema.firstIndex(of: "shot_made_flag") else { return [] }

    // shotData.data.map(...) → [loc_x, loc_y, made ? 1 : 0]
    let points: [[Double]] = rows.compactMap { row -> [Double]? in
        guard row.count > max(xi, yi, mi),
              let px = (row[xi] as? NSNumber)?.doubleValue,
              let py = (row[yi] as? NSNumber)?.doubleValue else { return nil }
        let made: Double = (row[mi] as? String) == "made" ? 1 : 0
        return [px, py, made]
    }

    let r: Double = hexbinRadiusInGeo
    let dx: Double = r * 2 * sin(Double.pi / 3)
    let dy: Double = r * 1.5
    // JS `Math.round` is floor(x + 0.5) (ties toward +∞); Swift's `.rounded()` ties away from zero,
    // which disagrees on negative halves — and half the court has a negative loc_x.
    func jsRound(_ v: Double) -> Int { Int((v + 0.5).rounded(.down)) }

    var binsById: [String: Int] = [:]
    var bins: [HexbinBin] = []

    for point in points {
        var px: Double = point[0]
        var py: Double = point[1]
        if px.isNaN || py.isNaN { continue }

        py = py / dy
        var pj: Int = jsRound(py)
        px = px / dx - Double(pj & 1) / 2
        var pi: Int = jsRound(px)
        let py1: Double = py - Double(pj)

        if abs(py1) * 3 > 1 {
            let px1: Double = px - Double(pi)
            let pi2: Double = Double(pi) + (px < Double(pi) ? -1 : 1) / 2
            let pj2: Int = pj + (py < Double(pj) ? -1 : 1)
            let px2: Double = px - pi2
            let py2: Double = py - Double(pj2)
            if px1 * px1 + py1 * py1 > px2 * px2 + py2 * py2 {
                // NB: reads the OLD pj, exactly as the JS does (pj is reassigned on the next line).
                pi = Int((pi2 + ((pj & 1) != 0 ? 1 : -1) / 2).rounded())
                pj = pj2
            }
        }

        let id = "\(pi)-\(pj)"
        if let idx = binsById[id] {
            bins[idx].points.append(point)
        } else {
            var bin = HexbinBin()
            bin.points = [point]
            bin.x = (Double(pi) + Double(pj & 1) / 2) * dx
            bin.y = Double(pj) * dy
            binsById[id] = bins.count
            bins.append(bin)
        }
    }

    return bins.map { bin -> [Double] in
        let made: Double = bin.points.reduce(0) { $0 + $1[2] }
        let count: Double = Double(bin.points.count)
        let percent: Double = (made / count * 100 * 100).rounded() / 100   // JS .toFixed(2)
        return [bin.x, bin.y, count, percent]
    }
}()

/// `hexBinResult.maxBinLen` — upstream's loop is buggy (`Math.max(maxBinLen, bins.length)`, never reads
/// `bins[i].points.length`), so it just ends up as the bin COUNT (see DEVIATIONS header note). One entry
/// of `hexbinSeriesData` == one bin, so the count is the same number here.
private let hexbinMaxBinLen: Double = Double(hexbinSeriesData.count)

// MARK: - renderItem (ported statement-for-statement from webOptionJS's renderItemHexBin/renderItemNBACourt)

/// `renderItemHexBin` — one bin -> a `group` of two hexagons: the data hexagon (radius encodes shots
/// attempted via a log/sqrt linearMap, filled by the visualMap-driven `api.visual('color')`) and a
/// z2:-19 full-radius backdrop hexagon.
private let hexbinRenderItemHexBin: CustomSeriesRenderItem = { _, api in
    let center = api.coord([hexbinNum(api.value(0.0, nil)), hexbinNum(api.value(1.0, nil))], nil)
    var points: [[Double]] = []
    var pointsBG: [[Double]] = []

    let maxViewRadius = (api.size([hexbinRadiusInGeo, 0.0], nil) as? [Double])?.first ?? 0
    let minViewRadius = Swift.min(maxViewRadius, 4)
    let extentMax = log(sqrt(hexbinMaxBinLen))
    let viewRadius = number.linearMap(
        log(sqrt(hexbinNum(api.value(2.0, nil)))),
        [0, extentMax],
        [minViewRadius, maxViewRadius]
    )

    var angle = Double.pi / 6
    for _ in 0..<6 {
        points.append([
            center[0] + viewRadius * cos(angle),
            center[1] + viewRadius * sin(angle)
        ])
        pointsBG.append([
            center[0] + maxViewRadius * cos(angle),
            center[1] + maxViewRadius * sin(angle)
        ])
        angle += Double.pi / 3
    }

    // JS: fill: api.visual('color') — a missing visual is `undefined` there (an absent key); Swift
    // cannot store that, so the key is simply not written when nil.
    var hexStyle: [String: Any] = ["stroke": "#ccc", "lineWidth": 1.0]
    if let color = api.visual("color", nil) { hexStyle["fill"] = color }

    return [
        "type": "group",
        "children": [
            [
                "type": "polygon",
                "shape": ["points": points] as [String: Any],
                "style": hexStyle
            ] as [String: Any],
            [
                "type": "polygon",
                "shape": ["points": pointsBG] as [String: Any],
                // JS: stroke: null, fill: 'rgba(0,0,0,0.5)', lineWidth: 0 — `stroke: null` omitted (a nil
                // "stroke" key coerces to no stroke exactly like the JS null does — polygon's own default
                // stroke is already nil, so there is no fill-less-shape default to fight, unlike below).
                "style": ["fill": "rgba(0,0,0,0.5)", "lineWidth": 0.0] as [String: Any],
                "z2": -19.0
            ] as [String: Any]
        ]
    ] as [String: Any]
}

/// `renderItemNBACourt` — one `polyline` per `nbaCourt.geometry` entry, its points projected through
/// `api.coord`.
private let hexbinRenderItemNBACourt: CustomSeriesRenderItem = { _, api in
    let children: [[String: Any]] = hexbinCourtGeometry.map { item in
        let points = item.points.map { api.coord($0, nil) }
        return [
            "type": item.type,
            // JS: stroke: '#aaa', fill: null, lineWidth: 1.5 — `fill: null` explicit (NOT the same as
            // omitting the key: Polyline's own no-fill default only wins over the generic filled-shape
            // default when the caller leaves "fill" unresolved — see the framework-gap fix in
            // CustomView.applyStyle — so NSNull() here documents the upstream literal 1:1, and would
            // still resolve correctly even without it).
            "style": ["stroke": "#aaa", "fill": NSNull(), "lineWidth": 1.5] as [String: Any],
            "shape": ["points": points] as [String: Any]
        ] as [String: Any]
    }
    return ["type": "group", "children": children] as [String: Any]
}

extension EChartsDemoRegistry {
    static let official_custom_hexbin = EChartsDemo(
        name: "official-custom-hexbin", category: "custom",
        summary: "六边形分箱图（自定义系列） — Hexagonal Binning",
        width: 720, height: 460,
        nativeSupported: true,
        mapRegistrations: ["nbaCourt": hexbinCourtGeoJSON],
        collection: .official,
        webOptionJS: #"""
var shotData = \#(hexbinShotJSONText);
var nbaCourt = \#(hexbinCourtJSONText);

// Hexbin statistics code based on [d3-hexbin](https://github.com/d3/d3-hexbin)
function hexBinStatistics(points, r) {
  var dx = r * 2 * Math.sin(Math.PI / 3);
  var dy = r * 1.5;
  var binsById = {};
  var bins = [];

  for (var i = 0, n = points.length; i < n; ++i) {
    var point = points[i];
    var px = point[0];
    var py = point[1];

    if (isNaN(px) || isNaN(py)) {
      continue;
    }

    var pj = Math.round((py = py / dy));
    var pi = Math.round((px = px / dx - (pj & 1) / 2));
    var py1 = py - pj;

    if (Math.abs(py1) * 3 > 1) {
      var px1 = px - pi;
      var pi2 = pi + (px < pi ? -1 : 1) / 2;
      var pj2 = pj + (py < pj ? -1 : 1);
      var px2 = px - pi2;
      var py2 = py - pj2;
      if (px1 * px1 + py1 * py1 > px2 * px2 + py2 * py2) {
        pi = pi2 + (pj & 1 ? 1 : -1) / 2;
        pj = pj2;
      }
    }

    var id = pi + '-' + pj;
    var bin = binsById[id];
    if (bin) {
      bin.points.push(point);
    } else {
      bins.push((bin = binsById[id] = { points: [point] }));
      bin.x = (pi + (pj & 1) / 2) * dx;
      bin.y = pj * dy;
    }
  }

  var maxBinLen = -Infinity;
  for (var i = 0; i < bins.length; i++) {
    maxBinLen = Math.max(maxBinLen, bins.length);
  }

  return {
    maxBinLen: maxBinLen,
    bins: bins
  };
}

var backgroundColor = '#333';
var hexagonRadiusInGeo = 1;

var hexBinResult = hexBinStatistics(
  shotData.data.map(function (item) {
    // "shot_made_flag" made missed
    var made = item[shotData.schema.indexOf('shot_made_flag')];
    return [
      item[shotData.schema.indexOf('loc_x')],
      item[shotData.schema.indexOf('loc_y')],
      made === 'made' ? 1 : 0
    ];
  }),
  hexagonRadiusInGeo
);

var data = hexBinResult.bins.map(function (bin) {
  var made = 0;
  bin.points.forEach(function (point) {
    made += point[2];
  });
  return [
    bin.x,
    bin.y,
    bin.points.length,
    ((made / bin.points.length) * 100).toFixed(2)
  ];
});

function renderItemHexBin(params, api) {
  var center = api.coord([api.value(0), api.value(1)]);
  var points = [];
  var pointsBG = [];

  var maxViewRadius = api.size([hexagonRadiusInGeo, 0])[0];
  var minViewRadius = Math.min(maxViewRadius, 4);
  var extentMax = Math.log(Math.sqrt(hexBinResult.maxBinLen));
  var viewRadius = echarts.number.linearMap(
    Math.log(Math.sqrt(api.value(2))),
    [0, extentMax],
    [minViewRadius, maxViewRadius]
  );

  var angle = Math.PI / 6;
  for (var i = 0; i < 6; i++, angle += Math.PI / 3) {
    points.push([
      center[0] + viewRadius * Math.cos(angle),
      center[1] + viewRadius * Math.sin(angle)
    ]);
    pointsBG.push([
      center[0] + maxViewRadius * Math.cos(angle),
      center[1] + maxViewRadius * Math.sin(angle)
    ]);
  }

  return {
    type: 'group',
    children: [
      {
        type: 'polygon',
        shape: {
          points: points
        },
        style: {
          stroke: '#ccc',
          fill: api.visual('color'),
          lineWidth: 1
        }
      },
      {
        type: 'polygon',
        shape: {
          points: pointsBG
        },
        style: {
          stroke: null,
          fill: 'rgba(0,0,0,0.5)',
          lineWidth: 0
        },
        z2: -19
      }
    ]
  };
}

function renderItemNBACourt(param, api) {
  return {
    type: 'group',
    children: nbaCourt.geometry.map(function (item) {
      return {
        type: item.type,
        style: {
          stroke: '#aaa',
          fill: null,
          lineWidth: 1.5
        },
        shape: {
          points: item.points.map(api.coord)
        }
      };
    })
  };
}

option = {
  backgroundColor: backgroundColor,
  tooltip: {
    backgroundColor: 'rgba(255,255,255,0.9)',
    textStyle: {
      color: '#333'
    }
  },
  animation: false,
  title: {
    text: 'Some Player',
    subtext: 'Regular Season',
    backgroundColor: backgroundColor,
    top: 10,
    left: 10,
    textStyle: {
      color: '#eee'
    }
  },
  legend: {
    data: ['bar', 'error']
  },
  geo: {
    left: 0,
    right: 0,
    top: 0,
    bottom: 0,
    roam: true,
    silent: true,
    itemStyle: {
      color: backgroundColor,
      borderWidth: 0
    },
    map: 'nbaCourt'
  },
  visualMap: {
    type: 'continuous',
    orient: 'horizontal',
    right: 30,
    top: 40,
    min: 0,
    max: 100,
    align: 'bottom',
    text: [null, 'FG:   '],
    dimension: 3,
    seriesIndex: 0,
    calculable: true,
    textStyle: {
      color: '#eee'
    },
    formatter: '{value} %',
    inRange: {
      // color: ['rgba(241,222,158, 0.3)', 'rgba(241,222,158, 1)']
      color: ['green', 'yellow']
    }
  },
  series: [
    {
      type: 'custom',
      coordinateSystem: 'geo',
      geoIndex: 0,
      renderItem: renderItemHexBin,
      dimensions: [
        null,
        null,
        'Field Goals Attempted (hexagon size)',
        'Field Goal Percentage (color)'
      ],
      encode: {
        tooltip: [2, 3]
      },
      data: data
    },
    {
      coordinateSystem: 'geo',
      type: 'custom',
      geoIndex: 0,
      renderItem: renderItemNBACourt,
      silent: true,
      data: [0]
    }
  ]
};

myChart.setOption(option);
"""#,
        option: {
            // Upstream: `echarts.registerMap('nbaCourt', nbaCourt.borderGeoJSON)` inside the $.when callback.
            ECharts.registerMap("nbaCourt", hexbinCourtGeoJSON)
            return [
                "backgroundColor": hexbinBackgroundColor,
                "tooltip": [
                    "backgroundColor": "rgba(255,255,255,0.9)",
                    "textStyle": ["color": "#333"] as [String: Any]
                ] as [String: Any],
                "animation": false,
                "title": [
                    "text": "Some Player",
                    "subtext": "Regular Season",
                    "backgroundColor": hexbinBackgroundColor,
                    "top": 10.0,
                    "left": 10.0,
                    "textStyle": ["color": "#eee"] as [String: Any]
                ] as [String: Any],
                "legend": [
                    "data": ["bar", "error"]
                ] as [String: Any],
                "geo": [
                    "left": 0.0,
                    "right": 0.0,
                    "top": 0.0,
                    "bottom": 0.0,
                    "roam": true,
                    "silent": true,
                    "itemStyle": [
                        "color": hexbinBackgroundColor,
                        "borderWidth": 0.0
                    ] as [String: Any],
                    "map": "nbaCourt"
                ] as [String: Any],
                "visualMap": [
                    "type": "continuous",
                    "orient": "horizontal",
                    "right": 30.0,
                    "top": 40.0,
                    "min": 0.0,
                    "max": 100.0,
                    "align": "bottom",
                    "text": [NSNull(), "FG:   "] as [Any],
                    "dimension": 3.0,
                    "seriesIndex": 0.0,
                    "calculable": true,
                    "textStyle": ["color": "#eee"] as [String: Any],
                    // PORT-NOTE: visualMap.formatter kept — '{value} %' is a template STRING upstream,
                    // not a closure, so it ports as-is.
                    "formatter": "{value} %",
                    "inRange": [
                        "color": ["green", "yellow"]
                    ] as [String: Any]
                ] as [String: Any],
                "series": [
                    [
                        "type": "custom",
                        "coordinateSystem": "geo",
                        "geoIndex": 0.0,
                        "renderItem": hexbinRenderItemHexBin,
                        "dimensions": [
                            NSNull(),
                            NSNull(),
                            "Field Goals Attempted (hexagon size)",
                            "Field Goal Percentage (color)"
                        ] as [Any],
                        "encode": [
                            "tooltip": [2.0, 3.0]
                        ] as [String: Any],
                        "data": hexbinSeriesData
                    ] as [String: Any],
                    [
                        "coordinateSystem": "geo",
                        "type": "custom",
                        "geoIndex": 0.0,
                        "renderItem": hexbinRenderItemNBACourt,
                        "silent": true,
                        "data": [0.0]
                    ] as [String: Any]
                ]
            ]
        }())
}
