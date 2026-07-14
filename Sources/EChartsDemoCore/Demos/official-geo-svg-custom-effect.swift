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
//   - nativeSupported: false. The series IS its renderItem closure — the circles, the pin path and both
//     keyframeAnimations exist only inside that JS function, and a Swift [String: Any] option cannot
//     carry it. The geo SVG base map alone would render natively (see map-svg-basic), but with an empty
//     custom series that is a different, effect-less example, so the native pane says "N/A" instead of
//     pretending. The `option` below still carries the geo + series-minus-renderItem faithfully.
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

extension EChartsDemoRegistry {
    static let official_geo_svg_custom_effect = EChartsDemo(
        name: "official-geo-svg-custom-effect", category: "custom",
        summary: "自定义特效 — GEO SVG with Customized Effect",
        width: 720, height: 460,
        nativeSupported: false,
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
                    "data": geoSvgCustomEffectData as [Any]
                    // PORT-NOTE: series.renderItem omitted — a JS closure. It returned, per datum, a `group`
                    // translated to api.coord(value[0], value[1]) holding 5 stroked red circles (r:30,
                    // fill none, lineWidth 2), each looping a 4s ripple keyframeAnimation (scaleX/scaleY
                    // 0,0 → 1,0.4 and opacity 1 → 0) at delay (-i/4) * 4000 for i in 0...4 — i.e. phase
                    // offsets 0/-1000/-2000/-3000/-4000ms, so a ripple starts every 1000ms (the i=4 circle
                    // is a full period back and rides in phase with i=0). Over them sits a red map-pin
                    // `path` (the 'M16 0c-5.523...' SVG d, 20x40 at x:-10 y:-35) looping a 1s jump
                    // keyframeAnimation (y -10 cubicOut at 50%, y 0 bounceOut at 100%, Math.random()*1000
                    // delay, so each pin bounces out of step with the others).
                ] as [String: Any]
            ]
        }())
}
