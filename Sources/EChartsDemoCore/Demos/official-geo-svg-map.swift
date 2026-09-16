// official-geo-svg-map — replica of https://echarts.apache.org/examples/zh/editor.html?c=geo-svg-map
// title: GEO SVG Map / titleCN: 地图（SVG）
// A pre-hellenic topographic map of Sicily, registered as a geo map from a raw SVG
// (`registerMap(name, { svg })`) and laid out with `layoutCenter`/`layoutSize`. Two of the SVG's named
// groups — `route1` / `route2` — are declared as `geo.regions` with their own select style + a static
// tooltip. Above the map, a `scatter` series with `symbolSize: 0` and label-only rendering (`encode:
// { label: 2 }`) fakes two clickable BUTTONS; clicking one selects the matching route on the geo.
//
// DEVIATIONS from the official source:
//   - The `$.get(ROOT_PATH + '/data/asset/geo/Sicily_prehellenic_topographic_map.svg', ...)` fetch is
//     dropped; the SVG is read from the repo asset assets/geo/Sicily_prehellenic_topographic_map.svg
//     (byte-identical to the official one) via Upstream.repoRoot, so `option` is assigned
//     unconditionally at the top level instead of inside the callback.
//   - `echarts.registerMap('sicily', { svg: svg })` is NOT called inside webOptionJS: it goes through
//     `mapRegistrations`, which WebPage.swift injects into the page before the option script, and which
//     the native pane registers via `ECharts.registerMap` (the same SVG string feeds both panes).
//   - The `myChart.on('selectchanged', ...)` handler — which turns a button click into a `geoSelect` +
//     `showTip` (or `hideTip` + deselect) dispatchAction on the geo component — is dropped: it is
//     interaction wiring on the chart instance, not option, and the gallery renders ONE static frame.
//     Nothing is selected in that frame, so the red `select.itemStyle` and the route tooltips never
//     appear; both panes show the unselected initial state.
//   - The TypeScript `(params: any)` annotations in the two tooltip formatters are stripped in
//     webOptionJS (the page runs classic JS, not TS); the closure bodies are otherwise verbatim.
// Everything else (tooltip, geo + regions, grid, xAxis, yAxis, series) is verbatim.
import Foundation
import EChartsKit

// The official Sicily SVG (assets/geo/Sicily_prehellenic_topographic_map.svg, ~3.7 MB). Read ONCE from
// the repo via the same #filePath-relative root the echarts.js dist uses (WebPage.swift), so it resolves
// on macOS and the iOS simulator alike. A read failure degrades to an empty SVG (blank geo pane) rather
// than crashing.
private let sicilySVG: String = {
    let url = Upstream.repoRoot.appendingPathComponent("assets/geo/Sicily_prehellenic_topographic_map.svg")
    guard let s = try? String(contentsOf: url, encoding: .utf8) else {
        return #"<svg xmlns="http://www.w3.org/2000/svg" width="1" height="1"></svg>"#
    }
    return s
}()

// The two fake "buttons": [x, y, label] on the tiny 80×20 grid above the map (`encode: { label: 2 }`
// renders dim 2 as the label; `symbolSize: 0` hides the scatter symbol itself).
private let geoSvgMapButtonData: [[Any]] = [
    [0.0, 0.0, "route1"],
    [1.0, 0.0, "route2"]
]

// The two route tooltips' formatters are plain STRINGS upstream (`[...].join('<br>')` evaluates at option
// build time, it is not a closure), so the native pane carries them too — pre-joined here.
private let geoSvgMapRoute1Tooltip = [
    "Route 1:",
    "xxxxxxxxxxxxxxxxxxxxxxxxxxx",
    "xxxxxxxxxxxxxxxxxxxxxxxxxxx",
    "xxxxxxxxxxxxxxxxxxxxxxxxxxx",
    "xxxxxxxxxxxxxxxxxxxxxxxxxxx",
    "xxxxxxxxxxxxxxxxxxxxxxxxxxx"
].joined(separator: "<br>")

private let geoSvgMapRoute2Tooltip = [
    "Route 2:",
    "xxxxxxxxxxxxxx",
    "xxxxxxxxxxxxxx",
    "xxxxxxxxxxxxxx",
    "xxxxxxxxxxxxxx",
    "xxxxxxxxxxxxxx",
    "xxxxxxxxxxxxxx",
    "xxxxxxxxxxxxxx",
    "xxxxxxxxxxxxxx"
].joined(separator: "<br>")

extension EChartsDemoRegistry {
    static let official_geo_svg_map = EChartsDemo(
        name: "official-geo-svg-map", category: "map",
        summary: "地图（SVG） — GEO SVG Map",
        width: 720, height: 460,
        nativeSupported: true,
        mapRegistrations: ["sicily": ["svg": sicilySVG] as [String: Any]],
        collection: .official,
        webOptionJS: #"""
option = {
  tooltip: {
    formatter: function (params) {
      console.log(params);
      return [
        params.name + ':',
        'xxxxxxxxxxxxxxxx',
        'xxxxxxxxxxxxxxxx',
        'xxxxxxxxxxxxxxxx'
      ].join('<br>');
    }
  },
  geo: [
    {
      map: 'sicily',
      roam: true,
      layoutCenter: ['50%', '50%'],
      layoutSize: '100%',
      selectedMode: 'single',
      tooltip: {
        show: true,
        confine: true,
        formatter: function (params) {
          return [
            'This is the introduction:',
            'xxxxxxxxxxxxxxxxxxxxx',
            'xxxxxxxxxxxxxxxxxxxxx',
            'xxxxxxxxxxxxxxxxxxxxx',
            'xxxxxxxxxxxxxxxxxxxxx',
            'xxxxxxxxxxxxxxxxxxxxx',
            'xxxxxxxxxxxxxxxxxxxxx',
            'xxxxxxxxxxxxxxxxxxxxx',
            'xxxxxxxxxxxxxxxxxxxxx',
            'xxxxxxxxxxxxxxxxxxxxx',
            'xxxxxxxxxxxxxxxxxxxxx'
          ].join('<br>');
        }
      },
      itemStyle: {
        color: undefined
      },
      emphasis: {
        label: {
          show: false
        }
      },
      select: {
        itemStyle: {
          color: '#b50205'
        },
        label: {
          show: false
        }
      },
      regions: [
        {
          name: 'route1',
          itemStyle: {
            borderWidth: 0
          },
          select: {
            itemStyle: {
              color: '#b5280d',
              borderWidth: 0
            }
          },
          tooltip: {
            position: 'right',
            alwaysShowContent: true,
            enterable: true,
            extraCssText: 'user-select: text',
            formatter: [
              'Route 1:',
              'xxxxxxxxxxxxxxxxxxxxxxxxxxx',
              'xxxxxxxxxxxxxxxxxxxxxxxxxxx',
              'xxxxxxxxxxxxxxxxxxxxxxxxxxx',
              'xxxxxxxxxxxxxxxxxxxxxxxxxxx',
              'xxxxxxxxxxxxxxxxxxxxxxxxxxx'
            ].join('<br>')
          }
        },
        {
          name: 'route2',
          itemStyle: {
            borderWidth: 0
          },
          select: {
            itemStyle: {
              color: '#b5280d',
              borderWidth: 0
            }
          },
          tooltip: {
            position: 'left',
            alwaysShowContent: true,
            enterable: true,
            extraCssText: 'user-select: text',
            formatter: [
              'Route 2:',
              'xxxxxxxxxxxxxx',
              'xxxxxxxxxxxxxx',
              'xxxxxxxxxxxxxx',
              'xxxxxxxxxxxxxx',
              'xxxxxxxxxxxxxx',
              'xxxxxxxxxxxxxx',
              'xxxxxxxxxxxxxx',
              'xxxxxxxxxxxxxx'
            ].join('<br>')
          }
        }
      ]
    }
  ],

  // -------------
  // Make buttons
  grid: {
    top: 10,
    left: 'center',
    width: 80,
    height: 20
  },
  xAxis: {
    axisLine: { show: false },
    splitLine: { show: false },
    axisLabel: { show: false },
    axisTick: { show: false }
  },
  yAxis: {
    axisLine: { show: false },
    splitLine: { show: false },
    axisLabel: { show: false },
    axisTick: { show: false }
  },
  series: {
    type: 'scatter',
    itemStyle: {},
    label: {
      show: true,
      borderColor: '#999',
      borderWidth: 1,
      borderRadius: 2,
      backgroundColor: '#fff',
      padding: [3, 5],
      fontSize: 18,
      opacity: 1,
      color: '#333'
    },
    encode: {
      label: 2
    },
    symbolSize: 0,
    tooltip: { show: false },
    selectedMode: 'single',
    select: {
      label: {
        color: '#fff',
        borderColor: '#555',
        backgroundColor: '#555'
      }
    },
    data: [
      [0, 0, 'route1'],
      [1, 0, 'route2']
    ]
  }
  // Make buttons end
  // -----------------
};
"""#,
        option: {
            // Register the Sicily SVG as a map before the option is consumed — upstream
            // `echarts.registerMap('sicily', { svg: svg })` inside the $.get callback.
            ECharts.registerMap("sicily", ["svg": sicilySVG] as [String: Any])
            return [
                // tooltip.formatter omitted — the JS closure console.log'd params and returned
                // `params.name + ':'` followed by three 'xxxxxxxxxxxxxxxx' lines joined by <br>.
                "tooltip": [:] as [String: Any],
                "geo": [
                    [
                        "map": "sicily",
                        "roam": true,
                        "layoutCenter": ["50%", "50%"],
                        "layoutSize": "100%",
                        "selectedMode": "single",
                        // geo[0].tooltip.formatter omitted — the JS closure returned a fixed
                        // 11-line 'This is the introduction:' / 'xxxxxxxxxxxxxxxxxxxxx' block joined by <br>.
                        "tooltip": [
                            "show": true,
                            "confine": true
                        ] as [String: Any],
                        // Upstream writes `color: undefined`, i.e. NO fill override — the region keeps the
                        // colour authored in the SVG itself. An empty dict is the Swift equivalent (an
                        // absent key); NSNull would be JS `null`, which is a different, explicit "no fill".
                        "itemStyle": [:] as [String: Any],
                        "emphasis": [
                            "label": ["show": false] as [String: Any]
                        ] as [String: Any],
                        "select": [
                            "itemStyle": ["color": "#b50205"] as [String: Any],
                            "label": ["show": false] as [String: Any]
                        ] as [String: Any],
                        "regions": [
                            [
                                "name": "route1",
                                "itemStyle": ["borderWidth": 0.0] as [String: Any],
                                "select": [
                                    "itemStyle": ["color": "#b5280d", "borderWidth": 0.0] as [String: Any]
                                ] as [String: Any],
                                "tooltip": [
                                    "position": "right",
                                    "alwaysShowContent": true,
                                    "enterable": true,
                                    "extraCssText": "user-select: text",
                                    "formatter": geoSvgMapRoute1Tooltip
                                ] as [String: Any]
                            ] as [String: Any],
                            [
                                "name": "route2",
                                "itemStyle": ["borderWidth": 0.0] as [String: Any],
                                "select": [
                                    "itemStyle": ["color": "#b5280d", "borderWidth": 0.0] as [String: Any]
                                ] as [String: Any],
                                "tooltip": [
                                    "position": "left",
                                    "alwaysShowContent": true,
                                    "enterable": true,
                                    "extraCssText": "user-select: text",
                                    "formatter": geoSvgMapRoute2Tooltip
                                ] as [String: Any]
                            ] as [String: Any]
                        ] as [Any]
                    ] as [String: Any]
                ] as [Any],
                // The two fake buttons: a naked 80×20 grid with every axis decoration switched off.
                "grid": [
                    "top": 10.0,
                    "left": "center",
                    "width": 80.0,
                    "height": 20.0
                ] as [String: Any],
                "xAxis": [
                    "axisLine": ["show": false] as [String: Any],
                    "splitLine": ["show": false] as [String: Any],
                    "axisLabel": ["show": false] as [String: Any],
                    "axisTick": ["show": false] as [String: Any]
                ] as [String: Any],
                "yAxis": [
                    "axisLine": ["show": false] as [String: Any],
                    "splitLine": ["show": false] as [String: Any],
                    "axisLabel": ["show": false] as [String: Any],
                    "axisTick": ["show": false] as [String: Any]
                ] as [String: Any],
                // Upstream `series` is a single OBJECT, not an array (echarts normalizes it) — kept verbatim.
                "series": [
                    "type": "scatter",
                    "itemStyle": [:] as [String: Any],
                    "label": [
                        "show": true,
                        "borderColor": "#999",
                        "borderWidth": 1.0,
                        "borderRadius": 2.0,
                        "backgroundColor": "#fff",
                        "padding": [3.0, 5.0],
                        "fontSize": 18.0,
                        "opacity": 1.0,
                        "color": "#333"
                    ] as [String: Any],
                    "encode": ["label": 2.0] as [String: Any],
                    "symbolSize": 0.0,
                    "tooltip": ["show": false] as [String: Any],
                    "selectedMode": "single",
                    "select": [
                        "label": [
                            "color": "#fff",
                            "borderColor": "#555",
                            "backgroundColor": "#555"
                        ] as [String: Any]
                    ] as [String: Any],
                    "data": geoSvgMapButtonData as [Any]
                ] as [String: Any]
            ]
        }())
}
