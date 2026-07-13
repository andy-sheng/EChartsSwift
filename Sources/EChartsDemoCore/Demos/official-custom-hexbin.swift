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
//   - registerMap MOVED OUT. Upstream calls `echarts.registerMap('nbaCourt', nbaCourt.borderGeoJSON)`
//     inside the callback; here it is declared in `mapRegistrations` so WebPage.swift injects it into
//     the page before the option script and the native pane registers the same map.
//   - NATIVE PANE UNSUPPORTED (nativeSupported: false). BOTH series are `custom`, and their `renderItem`
//     closures ARE the chart: one builds the 6-gon (+ its darker max-radius backdrop) per bin, the other
//     maps every court polyline through `api.coord`. A Swift [String: Any] cannot carry a JS function, so
//     dropping them leaves nothing to draw. Everything else IS ported (geo, visualMap, title, tooltip,
//     encode/dimensions, and the hexbin data — `hexBinStatistics` is ported to Swift below) so the option
//     lights up the moment renderItem gains a native form.
//   - `((made / len) * 100).toFixed(2)` yields a STRING in JS; the native data carries the same value as a
//     2-decimal Double (dimension 3 is a visualMap input, i.e. numeric).
//   - The upstream `maxBinLen` loop is buggy (`Math.max(maxBinLen, bins.length)` — it never reads
//     `bins[i].points.length`, so maxBinLen is just the BIN COUNT). Kept verbatim in the web pane; it only
//     feeds renderItem's `extentMax`, which the native option has no use for.
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

// MARK: - hexBinStatistics (port of the example's d3-hexbin-derived binning)

private let hexbinRadiusInGeo: Double = 1
private let hexbinBackgroundColor = "#333"

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

extension EChartsDemoRegistry {
    static let official_custom_hexbin = EChartsDemo(
        name: "official-custom-hexbin", category: "custom",
        summary: "六边形分箱图（自定义系列） — Hexagonal Binning",
        width: 720, height: 460,
        nativeSupported: false,
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
                        // PORT-NOTE: renderItem omitted — `renderItemHexBin` built, per bin, a `group` of two
                        // polygons: the data hexagon (6 vertices at `viewRadius` around `api.coord([x, y])`,
                        // radius = linearMap(log(sqrt(shots)), [0, log(sqrt(maxBinLen))], [min(maxR, 4), maxR])
                        // where maxR = api.size([1, 0])[0], filled with api.visual('color'), stroked '#ccc'),
                        // plus a z2:-19 backdrop hexagon at the full maxR filled 'rgba(0,0,0,0.5)'.
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
                        // PORT-NOTE: renderItem omitted — `renderItemNBACourt` returned a `group` of one
                        // 'polyline' per entry of nba-court.json's `geometry` (9 of them: paint, arcs, 3pt
                        // line, ...), each one's `points` mapped through `api.coord` into geo pixel space,
                        // stroked '#aaa' at lineWidth 1.5 with no fill.
                        "silent": true,
                        "data": [0.0]
                    ] as [String: Any]
                ]
            ]
        }())
}
