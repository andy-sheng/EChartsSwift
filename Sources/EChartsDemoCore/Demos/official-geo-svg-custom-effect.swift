// official-geo-svg-custom-effect — replica of https://echarts.apache.org/examples/zh/editor.html?c=geo-svg-custom-effect
// title: GEO SVG with Customized Effect / titleCN: 自定义特效
// An SVG-backed geo map of Iceland (registerMap('iceland_svg', { svg })) with a `custom` series pinned to
// the geo coordinate system: each of the 6 data points renders as a red map-pin path that bounce-jumps
// (keyframeAnimation, bounceOut) over 5 concentric circles rippling outward (scaleX/scaleY 0→1/0.4,
// opacity 1→0, staggered by delay: -i/4 * 4000). Everything drawn is built inside renderItem.
//
// DEVIATIONS from the official source:
//   - The `$.get(ROOT_PATH + '/data/asset/geo/Map_of_Iceland.svg', function (svg) {...})` fetch is dropped;
//     the SVG is read from the repo asset assets/geo/Map_of_Iceland.svg (Upstream.repoRoot) and handed to
//     BOTH panes through `mapRegistrations` — the web pane's registerMap is injected by WebPage.swift
//     before the option script, so the example's own `echarts.registerMap('iceland_svg', { svg: svg })`
//     line is the one thing removed from the otherwise-verbatim callback body. The TS-only
//     `as echarts.CustomSeriesRenderItemReturn` cast and the trailing `export {}` are dropped too
//     (a classic script cannot parse them).
//   - nativeSupported: true. `renderItem` IS ported (geoSvgCustomEffectRenderItem, below): per datum it
//     projects [x, y] through `api.coord`, then returns a `group` at that pixel holding 5 stroked red
//     circles (each looping a 4s ripple keyframeAnimation) and one red map-pin `path` (looping a 1s jump
//     keyframeAnimation) — CustomView's `applyKeyframeAnimation` already drives both per-child animations
//     (see official-custom-wind for the same geo-coordinateSystem renderItem pattern; keyframeAnimation on
//     renderItem children is exercised by official-graphic-loading/-stroke-animation's graphic-component
//     siblings). The geo SVG base map itself already renders natively (see official-geo-svg-scatter-simple).
//   - PIN DELAY NOT PINNED: upstream's pin keyframeAnimation `delay: Math.random() * 1000` is its own dice,
//     rolled once per renderItem call, and is not data — like official-bar-race's per-tick `Math.random()`,
//     it is deliberately left unpinned on the native side (`Double.random(in: 0..<1) * 1000`), so the two
//     panes' pin-bounce phases will differ run to run; that is upstream's own behavior, not a port gap.
import Foundation
import EChartsKit

// The Iceland SVG (assets/geo/Map_of_Iceland.svg — the official example's /data/asset/geo/ file, verbatim).
// Read once from the repo via the same #filePath-relative root the echarts.js dist uses (WebPage.swift);
// a read failure degrades to an empty SVG of the right viewBox rather than crashing.
// NOTE: file-scope `private` is fileprivate, but the name is still demo-specific on purpose —
// official-geo-svg-scatter-simple.swift reads the SAME asset into its own `icelandSVG`, and two
// module-scope `let icelandSVG`s would be a hard redeclaration the day either drops the modifier.
private let geoSvgCustomEffectIcelandSVG: String = {
    let url = Upstream.repoRoot.appendingPathComponent("assets/geo/Map_of_Iceland.svg")
    return (try? String(contentsOf: url, encoding: .utf8))
        ?? #"<svg width="1834px" height="1489px" viewBox="0 0 1834 1489"></svg>"#
}()

// [x, y, value] in the SVG's own coordinate space (the geo coordinate system for an SVG map).
private let geoSvgCustomEffectData: [[Double]] = [
    [488.2358421078053, 459.70913833075736, 100],
    [770.3415644319939, 757.9672194986475, 30],
    [1180.0329284196291, 743.6141808346214, 80],
    [894.03790632245, 1188.1985153835008, 61],
    [1372.98925630313, 477.3839988649537, 70],
    [1378.62251255796, 935.6708486282843, 81]
]

// Numeric coercion for the renderItem api values (ParsedValue is Any; api.value may box Int or Double).
private func geoSvgCustomEffectNum(_ v: Any?) -> Double {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let n = v as? NSNumber { return n.doubleValue }
    return .nan
}

// The red map-pin path `d`, verbatim from upstream's renderItem (a 32x32 pin glyph, drawn at x:-10 y:-35
// width:20 height:40 relative to the group origin).
private let geoSvgCustomEffectPinPath =
    "M16 0c-5.523 0-10 4.477-10 10 0 10 10 22 10 22s10-12 10-22c0-5.523-4.477-10-10-10zM16 16c-3.314 0-6-2.686-6-6s2.686-6 6-6 6 2.686 6 6-2.686 6-6 6z"

// upstream `renderItem`: project the datum through `api.coord`, then return a `group` at that pixel
// holding 5 stroked-circle "ripples" (each looping a 4s scale/opacity keyframeAnimation, staggered by
// `delay: (-i / 4) * 4000`) and one red map-pin `path` on top (looping a 1s "jump" keyframeAnimation:
// bounce up at 50% via cubicOut, settle back down at 100% via bounceOut).
private let geoSvgCustomEffectRenderItem: CustomSeriesRenderItem = { params, api in
    let x = geoSvgCustomEffectNum(api.value(0.0, params.dataIndex))
    let y = geoSvgCustomEffectNum(api.value(1.0, params.dataIndex))
    let coord = api.coord([x, y], nil)
    guard coord.count >= 2 else { return nil }

    var children: [[String: Any]] = []
    for i in 0..<5 {
        children.append([
            "type": "circle",
            "shape": ["cx": 0.0, "cy": 0.0, "r": 30.0] as [String: Any],
            "style": ["stroke": "red", "fill": "none", "lineWidth": 2.0] as [String: Any],
            // Ripple animation.
            "keyframeAnimation": [
                "duration": 4000.0,
                "loop": true,
                "delay": (-Double(i) / 4.0) * 4000.0,
                "keyframes": [
                    [
                        "percent": 0.0, "scaleX": 0.0, "scaleY": 0.0,
                        "style": ["opacity": 1.0] as [String: Any]
                    ] as [String: Any],
                    [
                        "percent": 1.0, "scaleX": 1.0, "scaleY": 0.4,
                        "style": ["opacity": 0.0] as [String: Any]
                    ] as [String: Any]
                ]
            ] as [String: Any]
        ] as [String: Any])
    }

    children.append([
        "type": "path",
        "shape": [
            "d": geoSvgCustomEffectPinPath,
            "x": -10.0, "y": -35.0, "width": 20.0, "height": 40.0
        ] as [String: Any],
        "style": ["fill": "red"] as [String: Any],
        // Jump animation. upstream: `delay: Math.random() * 1000` — its own dice, not pinned (see the
        // file header's DEVIATIONS note); rolled fresh each time this renderItem runs.
        "keyframeAnimation": [
            "duration": 1000.0,
            "loop": true,
            "delay": Double.random(in: 0..<1) * 1000.0,
            "keyframes": [
                ["y": -10.0, "percent": 0.5, "easing": "cubicOut"] as [String: Any],
                ["y": 0.0, "percent": 1.0, "easing": "bounceOut"] as [String: Any]
            ]
        ] as [String: Any]
    ] as [String: Any])

    return [
        "type": "group",
        "x": coord[0],
        "y": coord[1],
        "children": children
    ] as [String: Any]
}

extension EChartsDemoRegistry {
    static let official_geo_svg_custom_effect = EChartsDemo(
        name: "official-geo-svg-custom-effect", category: "custom",
        summary: "自定义特效 — GEO SVG with Customized Effect",
        width: 720, height: 460,
        nativeSupported: true,
        mapRegistrations: ["iceland_svg": ["svg": geoSvgCustomEffectIcelandSVG] as [String: Any]],
        collection: .official,
        webOptionJS: #"""
// echarts.registerMap('iceland_svg', { svg: svg }) — injected by the page from mapRegistrations.
option = {
  tooltip: {},
  geo: {
    tooltip: {
      show: true
    },
    map: 'iceland_svg',
    roam: true
  },
  series: {
    type: 'custom',
    coordinateSystem: 'geo',
    geoIndex: 0,
    zlevel: 1,
    data: [
      [488.2358421078053, 459.70913833075736, 100],
      [770.3415644319939, 757.9672194986475, 30],
      [1180.0329284196291, 743.6141808346214, 80],
      [894.03790632245, 1188.1985153835008, 61],
      [1372.98925630313, 477.3839988649537, 70],
      [1378.62251255796, 935.6708486282843, 81]
    ],
    renderItem(params, api) {
      const coord = api.coord([
        api.value(0, params.dataIndex),
        api.value(1, params.dataIndex)
      ]);

      const circles = [];
      for (let i = 0; i < 5; i++) {
        circles.push({
          type: 'circle',
          shape: {
            cx: 0,
            cy: 0,
            r: 30
          },
          style: {
            stroke: 'red',
            fill: 'none',
            lineWidth: 2
          },
          // Ripple animation
          keyframeAnimation: {
            duration: 4000,
            loop: true,
            delay: (-i / 4) * 4000,
            keyframes: [
              {
                percent: 0,
                scaleX: 0,
                scaleY: 0,
                style: {
                  opacity: 1
                }
              },
              {
                percent: 1,
                scaleX: 1,
                scaleY: 0.4,
                style: {
                  opacity: 0
                }
              }
            ]
          }
        });
      }
      return {
        type: 'group',
        x: coord[0],
        y: coord[1],
        children: [
          ...circles,
          {
            type: 'path',
            shape: {
              d: 'M16 0c-5.523 0-10 4.477-10 10 0 10 10 22 10 22s10-12 10-22c0-5.523-4.477-10-10-10zM16 16c-3.314 0-6-2.686-6-6s2.686-6 6-6 6 2.686 6 6-2.686 6-6 6z',
              x: -10,
              y: -35,
              width: 20,
              height: 40
            },
            style: {
              fill: 'red'
            },
            // Jump animation.
            keyframeAnimation: {
              duration: 1000,
              loop: true,
              delay: Math.random() * 1000,
              keyframes: [
                {
                  y: -10,
                  percent: 0.5,
                  easing: 'cubicOut'
                },
                {
                  y: 0,
                  percent: 1,
                  easing: 'bounceOut'
                }
              ]
            }
          }
        ]
      };
    }
  }
};

myChart.setOption(option);
"""#,
        option: {
            // Upstream `echarts.registerMap('iceland_svg', { svg: svg })`, inside the $.get callback.
            ECharts.registerMap("iceland_svg", ["svg": geoSvgCustomEffectIcelandSVG] as [String: Any])
            return [
                "tooltip": [:] as [String: Any],
                "geo": [
                    "tooltip": ["show": true] as [String: Any],
                    "map": "iceland_svg",
                    "roam": true
                ] as [String: Any],
                "series": [
                    "type": "custom",
                    "coordinateSystem": "geo",
                    "geoIndex": 0.0,
                    "zlevel": 1.0,
                    "data": geoSvgCustomEffectData as [Any],
                    // renderItem ported to Swift (geoSvgCustomEffectRenderItem, top of file): per datum, a
                    // `group` at api.coord([x, y]) holding 5 rippling circles and one bouncing map-pin path.
                    "renderItem": geoSvgCustomEffectRenderItem
                ] as [String: Any]
            ]
        }())
}
