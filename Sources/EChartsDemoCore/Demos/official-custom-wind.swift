// official-custom-wind — replica of https://echarts.apache.org/examples/zh/editor.html?c=custom-wind
// title: Use custom series to draw wind vectors / titleCN: 使用自定义系列绘制风场
// A 360x181 global wind field (65,160 samples) on a `geo` world map: a `custom` series whose renderItem
// draws ONE hairline segment per sample, from (lon,lat) - v/5 to (lon,lat) + v/5, coloured by wind
// magnitude through a continuous `visualMap` on dimension 4. `progressive: 2000` streams the 65k marks.
//
// DEVIATIONS from the official source:
//  - NATIVE PANE UNSUPPORTED (nativeSupported: false): this example's CHART IS ITS `renderItem` CLOSURE.
//    Every visible mark — all 65,160 line segments — is produced by the JS function (it calls api.coord()
//    twice per datum and api.visual('color') for the stroke); a Swift `[String: Any]` option cannot carry
//    a closure, so the native pane has no geometry to draw. The full option is still ported below (geo,
//    visualMap, the computed 5-column data, progressive) so the gap is exactly the renderItem, nothing else.
//  - DATA INLINED: upstream does `$.getJSON(ROOT_PATH + '/data-gl/asset/data/winds.json', function (windData)
//    { ... })` and builds the option inside the callback. The page has no network, so the asset is vendored
//    at assets/data/winds.json (mirrored from echarts-examples' public/data-gl/asset/data/winds.json) and read
//    via Upstream.repoRoot: the web pane gets the raw JSON text spliced in as `var windData = ...` and then runs
//    the callback BODY verbatim (shuffle + the row-major (i,j) → [lon, lat, vx, vy, mag] loop + setOption);
//    the native pane gets the same bytes parsed and the same loop run in Swift.
//  - MAP REGISTRATION: the example registers nothing — the official editor auto-injects the map named by
//    `geo.map: 'world'`. We must be explicit: assets/geo/world.json is handed to BOTH panes via
//    `mapRegistrations` (WebPage.swift injects `echarts.registerMap('world', ...)` ahead of the option script)
//    and to the native pane via `ECharts.registerMap`. A parse failure degrades to an empty FeatureCollection.
//  - SHUFFLE: upstream's `shuffle(data)` is Math.random-driven (it only randomises the order in which the
//    `progressive` chunks reveal the field). The web pane keeps it verbatim; the native pane runs the SAME
//    Fisher-Yates with a seeded LCG instead, so the still-frame render stays reproducible run to run.
//  - `series` is a bare object upstream (`series: { type: 'custom', ... }`); the Swift option wraps it in the
//    equivalent one-element array. `visualMap.min/max` are the JS-computed min/max magnitude, recomputed here
//    from the same data rather than hardcoded.
//  - `renderItem` omitted from the native option — see the PORT-NOTE.
// NOTE on the still-frame snapshot: with `progressive: 2000` the reference pane paints the 65k marks over
// many frames, so a headless snapshot can catch a partially-drawn field; the live gallery pane shows it whole.
import Foundation
import EChartsKit

// The world map GeoJSON, parsed ONCE from the repo asset.
private let windWorldGeoJSON: [String: Any] = {
    let url = Upstream.repoRoot.appendingPathComponent("assets/geo/world.json")
    guard let data = try? Data(contentsOf: url),
          let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
        return ["type": "FeatureCollection", "features": [] as [Any]]
    }
    return obj
}()

private let windsAssetURL = Upstream.repoRoot.appendingPathComponent("assets/data/winds.json")

// The raw JSON text, spliced into webOptionJS so the reference pane runs the official callback body against
// the exact bytes the native pane parses. `{ nx: 360, ny: 181, max, data: [[vx, vy], ...] }` (65,160 samples).
private let windsJSONText: String =
    (try? String(contentsOf: windsAssetURL, encoding: .utf8)) ?? #"{"nx":0,"ny":0,"data":[]}"#

// The upstream callback body's loop, in Swift: the row-major (i, j) grid of wind vectors becomes a flat
// [longitude, latitude, vx, vy, magnitude] row per sample, then the whole thing is shuffled.
private let windFieldData: [[Double]] = {
    guard let data = try? Data(contentsOf: windsAssetURL),
          let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
          let nx = obj["nx"] as? Int, let ny = obj["ny"] as? Int, nx > 0, ny > 0,
          let raw = obj["data"] as? [[Double]] else { return [] }

    var rows: [[Double]] = []
    rows.reserveCapacity(nx * ny)
    var p = 0
    for j in 0..<ny {
        for i in 0..<nx {
            defer { p += 1 }
            guard p < raw.count, raw[p].count >= 2 else { continue }
            let vx = raw[p][0]
            let vy = raw[p][1]
            let mag = (vx * vx + vy * vy).squareRoot()
            // 数据是一个一维数组 [ [经度, 维度，向量经度方向的值，向量维度方向的值] ]
            rows.append([
                Double(i) / Double(nx) * 360 - 180,
                Double(j) / Double(ny) * 180 - 90,
                vx, vy, mag
            ])
        }
    }

    // upstream `shuffle(data)` — the same Fisher-Yates, but seeded (Math.random would make every render differ).
    var seed: UInt64 = 0x2545_F491_4F6C_DD1D
    func rnd() -> Double {                                  // LCG in [0, 1)
        seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Double(seed >> 11) / Double(UInt64(1) << 53)
    }
    var currentIndex = rows.count
    while currentIndex != 0 {
        let randomIndex = Int(rnd() * Double(currentIndex))
        currentIndex -= 1
        rows.swapAt(currentIndex, randomIndex)
    }
    return rows
}()

// JS: `maxMag = Math.max(mag, maxMag)` / `minMag = Math.min(mag, minMag)` over the same rows.
private let windMinMag: Double = windFieldData.map { $0[4] }.min() ?? 0
private let windMaxMag: Double = windFieldData.map { $0[4] }.max() ?? 0

// The visualMap's inRange colour ramp (verbatim).
private let windColorRamp: [String] = [
    "#313695", "#4575b4", "#74add1", "#abd9e9", "#e0f3f8", "#ffffbf",
    "#fee090", "#fdae61", "#f46d43", "#d73027", "#a50026"
]

// Numeric coercion for the renderItem api values (ParsedValue is Any; api.value may box Int or Double).
private func customWindNum(_ v: Any?) -> Double {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let n = v as? NSNumber { return n.doubleValue }
    return .nan
}

// upstream `renderItem`: per wind sample project two geo points (a short segment along the flow vector,
//   clamped to the lon/lat bounds) and draw a `line` between them, stroked with the visualMap colour.
private let customWindRenderItem: CustomSeriesRenderItem = { _, api in
    let x = customWindNum(api.value(0.0, nil))
    let y = customWindNum(api.value(1.0, nil))
    let dx = customWindNum(api.value(2.0, nil))
    let dy = customWindNum(api.value(3.0, nil))
    let start = api.coord([max(x - dx / 5, -180), max(y - dy / 5, -90)], nil)
    let end = api.coord([min(x + dx / 5, 180), min(y + dy / 5, 90)], nil)
    guard start.count >= 2, end.count >= 2 else { return nil }
    return [
        "type": "line",
        "shape": ["x1": start[0], "y1": start[1], "x2": end[0], "y2": end[1]] as [String: Any],
        "style": ["lineWidth": 0.5, "stroke": api.visual("color", nil) as Any] as [String: Any]
    ] as [String: Any]
}

extension EChartsDemoRegistry {
    static let official_custom_wind = EChartsDemo(
        name: "official-custom-wind", category: "custom",
        summary: "使用自定义系列绘制风场 — Use custom series to draw wind vectors",
        width: 720, height: 460,
        nativeSupported: true,
        mapRegistrations: ["world": windWorldGeoJSON],
        collection: .official,
        webOptionJS: #"""
function shuffle(array) {
  // https://stackoverflow.com/questions/2450954/how-to-randomize-shuffle-a-javascript-array
  var currentIndex = array.length;
  var temporaryValue;
  var randomIndex;

  // While there remain elements to shuffle...
  while (0 !== currentIndex) {
    // Pick a remaining element...
    randomIndex = Math.floor(Math.random() * currentIndex);
    currentIndex -= 1;

    // And swap it with the current element.
    temporaryValue = array[currentIndex];
    array[currentIndex] = array[randomIndex];
    array[randomIndex] = temporaryValue;
  }

  return array;
}

var windData = \#(windsJSONText);

var p = 0;
var maxMag = 0;
var minMag = Infinity;
var data = [];
for (var j = 0; j < windData.ny; j++) {
  for (var i = 0; i < windData.nx; i++, p++) {
    var vx = windData.data[p][0];
    var vy = windData.data[p][1];
    var mag = Math.sqrt(vx * vx + vy * vy);
    // 数据是一个一维数组
    // [ [经度, 维度，向量经度方向的值，向量维度方向的值] ]
    data.push([
      (i / windData.nx) * 360 - 180,
      (j / windData.ny) * 180 - 90,
      vx,
      vy,
      mag
    ]);
    maxMag = Math.max(mag, maxMag);
    minMag = Math.min(mag, minMag);
  }
}
shuffle(data);

myChart.setOption(
  (option = {
    backgroundColor: '#333',
    visualMap: {
      left: 'center',
      min: minMag,
      max: maxMag,
      dimension: 4,
      inRange: {
        // prettier-ignore
        color: ['#313695', '#4575b4', '#74add1', '#abd9e9', '#e0f3f8', '#ffffbf', '#fee090', '#fdae61', '#f46d43', '#d73027', '#a50026']
      },
      calculable: true,
      textStyle: {
        color: '#fff'
      },
      orient: 'horizontal'
    },
    geo: {
      map: 'world',
      left: 0,
      right: 0,
      top: 0,
      zoom: 1,
      silent: true,
      roam: true,
      itemStyle: {
        areaColor: '#323c48',
        borderColor: '#111'
      }
    },
    series: {
      type: 'custom',
      coordinateSystem: 'geo',
      data: data,
      encode: {
        x: 0,
        y: 0
      },
      renderItem: function (params, api) {
        const x = api.value(0);
        const y = api.value(1);
        const dx = api.value(2);
        const dy = api.value(3);
        const start = api.coord([
          Math.max(x - dx / 5, -180),
          Math.max(y - dy / 5, -90)
        ]);
        const end = api.coord([
          Math.min(x + dx / 5, 180),
          Math.min(y + dy / 5, 90)
        ]);
        return {
          type: 'line',
          shape: {
            x1: start[0],
            y1: start[1],
            x2: end[0],
            y2: end[1]
          },
          style: {
            lineWidth: 0.5,
            stroke: api.visual('color')
          }
        };
      },
      progressive: 2000
    }
  })
);
"""#,
        option: {
            // Upstream registers nothing (the editor injects the `world` map); the native pane must.
            ECharts.registerMap("world", windWorldGeoJSON)
            let opt: [String: Any] = [
                "backgroundColor": "#333",
                "visualMap": [
                    "left": "center",
                    "min": windMinMag,          // JS: min magnitude over the field
                    "max": windMaxMag,          // JS: max magnitude over the field
                    "dimension": 4.0,
                    "inRange": [
                        "color": windColorRamp
                    ] as [String: Any],
                    "calculable": true,
                    "textStyle": ["color": "#fff"] as [String: Any],
                    "orient": "horizontal"
                ] as [String: Any],
                "geo": [
                    "map": "world",
                    "left": 0.0,
                    "right": 0.0,
                    "top": 0.0,
                    "zoom": 1.0,
                    "silent": true,
                    "roam": true,
                    "itemStyle": [
                        "areaColor": "#323c48",
                        "borderColor": "#111"
                    ] as [String: Any]
                ] as [String: Any],
                "series": [
                    [
                        "type": "custom",
                        "coordinateSystem": "geo",
                        "data": windFieldData,
                        "encode": ["x": 0.0, "y": 0.0] as [String: Any],
                        // renderItem ported to Swift (customWindRenderItem, top of file): per sample, a `line`
                        // between two geo-projected points along the flow vector, stroked the visualMap colour.
                        "renderItem": customWindRenderItem,
                        "progressive": 2000.0
                    ] as [String: Any]
                ]
            ]
            return opt
        }())
}
