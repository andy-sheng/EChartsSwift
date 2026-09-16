// official-lines-airline — replica of https://echarts.apache.org/examples/zh/editor.html?c=lines-airline
// title: 65k+ Airline / titleCN: 65k+ 飞机航线
// 65,663 great-circle flight routes drawn as a `lines` series on a `geo` world map: every route is the
// (src airport, dst airport) coordinate pair from OpenFlights, rendered in `large` mode with a nearly
// transparent hairline stroke (opacity 0.05, width 0.5, curveness 0.3) and `blendMode: 'lighter'`, so the
// air-traffic density emerges where strokes pile up on the dark-navy (#003) globe.
//
// DEVIATIONS from the official source:
//  - DATA FETCH: the example wraps everything in `$.get(ROOT_PATH + '/data/asset/data/flights.json', ...)`
//    (plus myChart.showLoading()/hideLoading()). The page has no network, so the asset is mirrored into the
//    repo at assets/data/flights.json (8,107 airports + 65,663 routes) and read at demo time via
//    Upstream.repoRoot. The web pane gets the RAW JSON text spliced in as `var data = {...}` ahead of the
//    otherwise-verbatim callback body (getAirportCoord + routes .map + the option literal), so `option` is
//    assigned unconditionally at the top level. A read/parse failure degrades to empty airports/routes
//    (blank map, no crash).
//  - TS ANNOTATIONS: the official source is TypeScript (`function getAirportCoord(idx: number)`,
//    `function (airline: number[])`). The web pane runs a classic script, where those are a SyntaxError, so
//    the two type annotations are dropped. The bodies are unchanged.
//  - MAP REGISTRATION: the example registers nothing — the official editor auto-injects the map named by
//    `geo.map: 'world'`. We must be explicit: assets/geo/world.json is handed to BOTH panes via
//    `mapRegistrations` (WebPage.swift injects `echarts.registerMap('world', ...)` before the option script;
//    the native pane registers the same GeoJSON).
//  - In snapshot mode the Web pane holds `__echartsSnapshotReady` until the ZRender display list contains
//    all route-segment values, then waits two paint frames. This makes the progressive 65k-route capture
//    deterministic; both ECharts' public `finished` event and the scheduler's `unfinished` flag can briefly
//    report completion between progressive frames for this case and are not reliable gates by themselves.
// Everything else (title, backgroundColor, geo left/right/silent/roam/itemStyle, and the whole lines series
// incl. large/largeThreshold/lineStyle/blendMode) is carried verbatim by both panes.
import Foundation
import EChartsKit

// The world map GeoJSON, parsed ONCE from the repo asset.
private let linesAirlineWorldGeoJSON: [String: Any] = {
    let url = Upstream.repoRoot.appendingPathComponent("assets/geo/world.json")
    guard let data = try? Data(contentsOf: url),
          let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
        return ["type": "FeatureCollection", "features": [] as [Any]]
    }
    return obj
}()

// The upstream `$.get('/data/asset/data/flights.json')` payload. Kept as RAW TEXT for the web pane
// (spliced into webOptionJS below, where the example's own JS re-derives `routes` from it) and parsed
// once for the native pane.
private let flightsJSONText: String = {
    let url = Upstream.repoRoot.appendingPathComponent("assets/data/flights.json")
    return (try? String(contentsOf: url, encoding: .utf8)) ?? #"{"airports":[],"routes":[]}"#
}()

private let flightsData: [String: Any] = {
    guard let obj = (try? JSONSerialization.jsonObject(with: Data(flightsJSONText.utf8))) as? [String: Any] else {
        return ["airports": [] as [Any], "routes": [] as [Any]]
    }
    return obj
}()

// The native equivalent of the example's
//   `data.routes.map(a => [getAirportCoord(a[1]), getAirportCoord(a[2])])`
// — airports[i] is [name, city, country, longitude, latitude]; a route is [airlineIdx, srcIdx, dstIdx].
// 65,663 [[lon, lat], [lon, lat]] pairs. This is a pure data transform (not a JS closure the option
// carries), so it is pre-computed here rather than note'd away.
private let airlineRoutes: [[[Double]]] = {
    guard let airports = flightsData["airports"] as? [[Any]],
          let routes = flightsData["routes"] as? [[Any]] else { return [] }
    func airportCoord(_ idx: Int) -> [Double] {
        guard idx >= 0, idx < airports.count else { return [0, 0] }
        let a = airports[idx]
        guard a.count >= 5 else { return [0, 0] }
        let lon = (a[3] as? NSNumber)?.doubleValue ?? 0
        let lat = (a[4] as? NSNumber)?.doubleValue ?? 0
        return [lon, lat]
    }
    var out: [[[Double]]] = []
    out.reserveCapacity(routes.count)
    for r in routes where r.count >= 3 {
        guard let src = (r[1] as? NSNumber)?.intValue,
              let dst = (r[2] as? NSNumber)?.intValue else { continue }
        out.append([airportCoord(src), airportCoord(dst)])
    }
    return out
}()

// Native spelling of the official `tooltip.formatter(param)` closure. Callback closures are valid
// option values in EChartsKit, so the hovered global route index can resolve the same source/destination
// city names as the Web example instead of falling back to generic "-  -" markup.
private let airlineTooltipFormatter: (TooltipCallbackDataParams) -> String = { params in
    guard let airports = flightsData["airports"] as? [[Any]],
          let routes = flightsData["routes"] as? [[Any]] else { return "" }
    let routeIndex = Int(params.dataIndex)
    guard routeIndex >= 0, routeIndex < routes.count, routes[routeIndex].count >= 3,
          let sourceIndex = (routes[routeIndex][1] as? NSNumber)?.intValue,
          let destinationIndex = (routes[routeIndex][2] as? NSNumber)?.intValue,
          sourceIndex >= 0, sourceIndex < airports.count,
          destinationIndex >= 0, destinationIndex < airports.count else { return "" }
    let sourceCity = airports[sourceIndex].count > 1 ? String(describing: airports[sourceIndex][1]) : ""
    let destinationCity = airports[destinationIndex].count > 1
        ? String(describing: airports[destinationIndex][1]) : ""
    return "\(sourceCity) > \(destinationCity)"
}

extension EChartsDemoRegistry {
    static let official_lines_airline = EChartsDemo(
        name: "official-lines-airline", category: "map",
        summary: "65k+ 飞机航线 — 65k+ Airline",
        width: 720, height: 460,
        nativeSupported: true,
        mapRegistrations: ["world": linesAirlineWorldGeoJSON],
        collection: .official,
        webOptionJS: #"""
var data = \#(flightsJSONText);

function getAirportCoord(idx) {
  return [data.airports[idx][3], data.airports[idx][4]];
}
var routes = data.routes.map(function (airline) {
  return [getAirportCoord(airline[1]), getAirportCoord(airline[2])];
});

if (__snapshot) {
  window.__echartsSnapshotReady = false;
  setTimeout(function waitForAllRoutes() {
    // Do not force `updateDisplayList` while the incremental canvas is painting: rebuilding the
    // display list between progressive frames drops the retained additive layers from the snapshot.
    var displayList = myChart.getZr().storage.getDisplayList(false);
    var routeValueCount = 0;
    for (var i = 0; i < displayList.length; i++) {
      var segs = displayList[i] && displayList[i].shape && displayList[i].shape.segs;
      if (segs && typeof segs.length === 'number') {
        routeValueCount += segs.length;
      }
    }
    if (routeValueCount < routes.length * 4) {
      setTimeout(waitForAllRoutes, 100);
      return;
    }
    requestAnimationFrame(function () {
      requestAnimationFrame(function () {
        window.__echartsSnapshotReady = true;
      });
    });
  }, 0);
}

option = {
  title: {
    text: 'World Flights',
    left: 'center',
    textStyle: {
      color: '#eee'
    }
  },
  backgroundColor: '#003',
  tooltip: {
    formatter: function (param) {
      var route = data.routes[param.dataIndex];
      return data.airports[route[1]][1] + ' > ' + data.airports[route[2]][1];
    }
  },
  geo: {
    map: 'world',
    left: 0,
    right: 0,
    silent: true,
    roam: true,
    itemStyle: {
      borderColor: '#003',
      color: '#005'
    }
  },
  series: [
    {
      type: 'lines',
      coordinateSystem: 'geo',
      data: routes,
      large: true,
      largeThreshold: 100,
      lineStyle: {
        opacity: 0.05,
        width: 0.5,
        curveness: 0.3
      },
      blendMode: 'lighter'
    }
  ]
};
"""#,
        option: {
            // Upstream registers nothing (the editor injects the `world` map); the native pane must.
            ECharts.registerMap("world", linesAirlineWorldGeoJSON)
            let opt: [String: Any] = [
                "title": [
                    "text": "World Flights",
                    "left": "center",
                    "textStyle": ["color": "#eee"] as [String: Any]
                ] as [String: Any],
                "backgroundColor": "#003",
                "tooltip": ["formatter": airlineTooltipFormatter] as [String: Any],
                "geo": [
                    "map": "world",
                    "left": 0.0,
                    "right": 0.0,
                    "silent": true,
                    "roam": true,
                    "itemStyle": [
                        "borderColor": "#003",
                        "color": "#005"
                    ] as [String: Any]
                ] as [String: Any],
                "series": [
                    [
                        "type": "lines",
                        "coordinateSystem": "geo",
                        "data": airlineRoutes as [Any],
                        "large": true,
                        "largeThreshold": 100.0,
                        "lineStyle": [
                            "opacity": 0.05,
                            "width": 0.5,
                            "curveness": 0.3
                        ] as [String: Any],
                        "blendMode": "lighter"
                    ] as [String: Any]
                ]
            ]
            return opt
        }())
}
