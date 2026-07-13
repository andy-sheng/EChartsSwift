// official-geo-organ — replica of https://echarts.apache.org/examples/zh/editor.html?c=geo-organ
// title: Organ Data with SVG / titleCN: 内脏数据（SVG）
// An SVG anatomy diagram registered as a geo map (`registerMap(name, { svg })`) on the left, next to a
// cartesian bar chart of the same seven organs on the right. Selecting a geo region paints it red
// (`select.itemStyle.color`); hovering focuses one organ (`emphasis.focus: 'self'`, `itemStyle.color: null`
// keeping the authored SVG fill).
//
// DEVIATIONS from the official source:
//   - The `$.get(ROOT_PATH + '/data/asset/geo/Veins_Medical_Diagram_clip_art.svg', ...)` fetch is dropped;
//     the SVG is read from the repo asset assets/geo/Veins_Medical_Diagram_clip_art.svg (byte-identical to
//     the official one) via Upstream.repoRoot, so `option` is assigned unconditionally at the top level.
//   - `echarts.registerMap('organ_diagram', { svg })` is NOT called inside webOptionJS: it goes through
//     `mapRegistrations`, which WebPage.swift injects into the page before the option script, and which the
//     native pane registers via `ECharts.registerMap` (same SVG string, both panes).
//   - The two `myChart.on('mouseover'/'mouseout', { seriesIndex: 0 }, ...)` handlers — which bridge a bar
//     hover into a `highlight`/`downplay` dispatchAction on the geo component — are dropped: they are
//     interaction wiring on the chart instance, not option, and the gallery renders one static frame.
// Everything else (tooltip, geo, grid, xAxis, yAxis, series) is verbatim.
import Foundation
import EChartsKit

// The official anatomy SVG (assets/geo/Veins_Medical_Diagram_clip_art.svg). Read ONCE from the repo via the
// same #filePath-relative root the echarts.js dist uses (WebPage.swift), so it resolves on macOS and the iOS
// simulator alike. A read failure degrades to an empty SVG (blank geo pane) rather than crashing.
private let organSVG: String = {
    let url = Upstream.repoRoot.appendingPathComponent("assets/geo/Veins_Medical_Diagram_clip_art.svg")
    guard let s = try? String(contentsOf: url, encoding: .utf8) else {
        return #"<svg xmlns="http://www.w3.org/2000/svg" width="1" height="1"></svg>"#
    }
    return s
}()

extension EChartsDemoRegistry {
    static let official_geo_organ = EChartsDemo(
        name: "official-geo-organ", category: "map",
        summary: "内脏数据（SVG） — Organ Data with SVG",
        width: 720, height: 460,
        nativeSupported: true,
        mapRegistrations: ["organ_diagram": ["svg": organSVG] as [String: Any]],
        collection: .official,
        webOptionJS: #"""
option = {
  tooltip: {},
  geo: {
    left: 10,
    right: '50%',
    map: 'organ_diagram',
    selectedMode: 'multiple',
    emphasis: {
      focus: 'self',
      itemStyle: {
        color: null
      },
      label: {
        position: 'bottom',
        distance: 0,
        textBorderColor: '#fff',
        textBorderWidth: 2
      }
    },
    blur: {},
    select: {
      itemStyle: {
        color: '#b50205'
      },
      label: {
        show: false,
        textBorderColor: '#fff',
        textBorderWidth: 2
      }
    }
  },
  grid: {
    left: '60%',
    top: '20%',
    bottom: '20%'
  },
  xAxis: {},
  yAxis: {
    data: [
      'heart',
      'large-intestine',
      'small-intestine',
      'spleen',
      'kidney',
      'lung',
      'liver'
    ]
  },
  series: [
    {
      type: 'bar',
      emphasis: {
        focus: 'self'
      },
      data: [121, 321, 141, 52, 198, 289, 139]
    }
  ]
};
"""#,
        option: {
            // Register the organ SVG as a map before the option is consumed — upstream
            // `echarts.registerMap('organ_diagram', { svg: svg })` inside the $.get callback.
            ECharts.registerMap("organ_diagram", ["svg": organSVG] as [String: Any])
            return [
                "tooltip": [:] as [String: Any],
                "geo": [
                    "left": 10.0,
                    "right": "50%",
                    "map": "organ_diagram",
                    "selectedMode": "multiple",
                    "emphasis": [
                        "focus": "self",
                        // NSNull is the JS `null`: explicitly NO emphasis fill, so a hovered region keeps
                        // the colour authored in the SVG itself.
                        "itemStyle": ["color": NSNull()] as [String: Any],
                        "label": [
                            "position": "bottom",
                            "distance": 0.0,
                            "textBorderColor": "#fff",
                            "textBorderWidth": 2.0
                        ] as [String: Any]
                    ] as [String: Any],
                    "blur": [:] as [String: Any],
                    "select": [
                        "itemStyle": ["color": "#b50205"] as [String: Any],
                        "label": [
                            "show": false,
                            "textBorderColor": "#fff",
                            "textBorderWidth": 2.0
                        ] as [String: Any]
                    ] as [String: Any]
                ] as [String: Any],
                "grid": [
                    "left": "60%",
                    "top": "20%",
                    "bottom": "20%"
                ] as [String: Any],
                "xAxis": [:] as [String: Any],
                "yAxis": [
                    "data": ["heart", "large-intestine", "small-intestine", "spleen",
                             "kidney", "lung", "liver"]
                ] as [String: Any],
                "series": [
                    [
                        "type": "bar",
                        "emphasis": ["focus": "self"] as [String: Any],
                        "data": [121.0, 321.0, 141.0, 52.0, 198.0, 289.0, 139.0]
                    ] as [String: Any]
                ]
            ]
        }())
}
