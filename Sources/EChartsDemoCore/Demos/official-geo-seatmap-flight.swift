// official-geo-seatmap-flight — replica of https://echarts.apache.org/examples/zh/editor.html?c=geo-seatmap-flight
// title: Flight Seatmap with SVG / titleCN: 航班选座（SVG）
// A geo component backed by an SVG (not a GeoJSON): every named <path>/<rect> in flight-seats.svg becomes a
// geo REGION, so the aircraft cabin plan is clickable seat-by-seat (`selectedMode: 'multiple'`, green select
// style). Seven already-taken seats are pre-styled dark red and made `silent` through `geo.regions`.
//
// DEVIATIONS from the official source:
//   - The `$.get(ROOT_PATH + '/data/asset/geo/flight-seats.svg', ...)` fetch is gone (the pane has no
//     network). The SAME asset is vendored at assets/geo/flight-seats.svg and read at demo time via
//     Upstream.repoRoot; the callback BODY is kept verbatim and `option` is assigned at the top level.
//   - `echarts.registerMap('flight-seats', { svg })` is NOT called inside webOptionJS: the SVG is declared
//     in `mapRegistrations`, so WebPage.swift injects registerMap into the page before the option script and
//     the native pane registers the identical map (see map-svg-basic.swift / map-bar-morph.swift).
//   - `myChart.on('geoselectchanged', ...)` (which console.logs the picked seats, minus the taken ones) is
//     dropped — the gallery renders ONE static frame and has no chart instance to bind to. Selection styling
//     is still exercised on hover/click in the live panes.
//   - webOptionJS strips the TS annotation `(takenSeatNames: string[])` — the page runs classic JS.
//   - Native pane: `emphasis.itemStyle.color: undefined` is omitted (Swift has no `undefined`; an absent key
//     is exactly what `undefined` means here — keep the region's own SVG/base fill on hover).
import Foundation
import EChartsKit

// The cabin plan, vendored from the official asset tree
// (echarts-examples/public/data/asset/geo/flight-seats.svg). Read ONCE from the repo; a read failure degrades
// to an empty SVG (the pane renders blank rather than crashing).
private let flightSeatsSVG: String = {
    let url = Upstream.repoRoot.appendingPathComponent("assets/geo/flight-seats.svg")
    return (try? String(contentsOf: url, encoding: .utf8))
        ?? #"<svg width="1" height="1" viewBox="0 0 1 1"></svg>"#
}()

// const takenSeatNames = ['26E', ...] — the seats already sold.
private let takenSeatNames: [String] = ["26E", "26D", "26C", "25D", "23C", "21A", "20F"]

// makeTakenRegions(takenSeatNames) — one `geo.regions` entry per taken seat: dark red, un-hoverable
// (`silent`), and pinned to that red even when the region is selected.
private let takenSeatRegions: [[String: Any]] = takenSeatNames.map { name in
    [
        "name": name,
        "silent": true,
        "itemStyle": ["color": "#bf0e08"] as [String: Any],
        "emphasis": [
            "itemStyle": ["borderColor": "#aaa", "borderWidth": 1.0] as [String: Any]
        ] as [String: Any],
        "select": [
            "itemStyle": ["color": "#bf0e08"] as [String: Any]
        ] as [String: Any]
    ] as [String: Any]
}

extension EChartsDemoRegistry {
    static let official_geo_seatmap_flight = EChartsDemo(
        name: "official-geo-seatmap-flight", category: "map",
        summary: "航班选座（SVG） — Flight Seatmap with SVG",
        width: 720, height: 460,
        nativeSupported: true,
        mapRegistrations: ["flight-seats": ["svg": flightSeatsSVG] as [String: Any]],
        collection: .official,
        webOptionJS: #"""
const takenSeatNames = ['26E', '26D', '26C', '25D', '23C', '21A', '20F'];

option = {
  tooltip: {},
  geo: {
    map: 'flight-seats',
    roam: true,
    selectedMode: 'multiple',
    layoutCenter: ['50%', '50%'],
    layoutSize: '95%',
    tooltip: {
      show: true
    },
    itemStyle: {
      color: '#fff'
    },
    emphasis: {
      itemStyle: {
        color: undefined,
        borderColor: 'green',
        borderWidth: 2
      },
      label: {
        show: false
      }
    },
    select: {
      itemStyle: {
        color: 'green'
      },
      label: {
        show: false,
        textBorderColor: '#fff',
        textBorderWidth: 2
      }
    },
    regions: makeTakenRegions(takenSeatNames)
  }
};

function makeTakenRegions(takenSeatNames) {
  var regions = [];
  for (var i = 0; i < takenSeatNames.length; i++) {
    regions.push({
      name: takenSeatNames[i],
      silent: true,
      itemStyle: {
        color: '#bf0e08'
      },
      emphasis: {
        itemStyle: {
          borderColor: '#aaa',
          borderWidth: 1
        }
      },
      select: {
        itemStyle: {
          color: '#bf0e08'
        }
      }
    });
  }
  return regions;
}
"""#,
        option: {
            // Register the cabin SVG before the option is consumed — upstream
            // `echarts.registerMap('flight-seats', { svg: svg })` inside the $.get callback.
            ECharts.registerMap("flight-seats", ["svg": flightSeatsSVG] as [String: Any])
            return [
                "tooltip": [:] as [String: Any],
                "geo": [
                    "map": "flight-seats",
                    "roam": true,
                    "selectedMode": "multiple",
                    "layoutCenter": ["50%", "50%"],
                    "layoutSize": "95%",
                    "tooltip": ["show": true] as [String: Any],
                    "itemStyle": ["color": "#fff"] as [String: Any],
                    "emphasis": [
                        // emphasis.itemStyle.color omitted — upstream sets it to `undefined`
                        // (an explicit "no emphasis fill override"), which in Swift is simply an absent key.
                        "itemStyle": ["borderColor": "green", "borderWidth": 2.0] as [String: Any],
                        "label": ["show": false] as [String: Any]
                    ] as [String: Any],
                    "select": [
                        "itemStyle": ["color": "green"] as [String: Any],
                        "label": [
                            "show": false,
                            "textBorderColor": "#fff",
                            "textBorderWidth": 2.0
                        ] as [String: Any]
                    ] as [String: Any],
                    // GeoModel reads this back as `[RegionOption]` (== [[String: Any]]), so keep the
                    // array's static element type — do NOT widen it to [Any].
                    "regions": takenSeatRegions
                ] as [String: Any]
            ]
        }())
}
