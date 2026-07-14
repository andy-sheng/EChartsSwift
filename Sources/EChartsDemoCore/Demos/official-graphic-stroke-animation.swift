// official-graphic-stroke-animation — replica of https://echarts.apache.org/examples/zh/editor.html?c=graphic-stroke-animation
// title: Stroke Animation / titleCN: 关键帧描边动画
// A chart with NO series/axes at all: a single `graphic` text element ("Apache ECharts", 80px bold,
// transparent fill + 1px stroke) whose `keyframeAnimation` (3s, looping) sweeps `lineDash` /
// `lineDashOffset` from [0, 200] to [200, 0] so the glyph outlines draw themselves, dwells, then
// tweens the fill from transparent to black.
//
// DEVIATIONS from the official source:
//   - webOptionJS is the example VERBATIM. The official source is a single static `option` literal: no
//     data fetch, no assets, no closures, no `myChart` timeline (the animation lives INSIDE the option's
//     `keyframeAnimation`, which echarts itself drives), so no `drive` hook is needed — a `drive` closure
//     here would be inventing a timeline the example does not have.
//   - NATIVE PANE OFF (nativeSupported: false), and the gap is precisely `keyframeAnimation`. `graphic`
//     itself IS ported (component/graphic/{GraphicModel,GraphicView}.swift), and ZRenderKit's Text +
//     NativePainter honor stroke/lineDash/lineDashOffset — but GraphicView deliberately does NOT apply
//     keyframes (PORT-NOTE at component/graphic/GraphicView.swift:277 — "requires keyframe animation:
//     applyKeyframeAnimation(el, elOption.keyframeAnimation, graphicModel)"). This example is NOTHING BUT
//     that animation: with the keyframes dropped, the native pane renders the base style only — fill
//     'transparent' over a stroke dashed [0, 200] (zero-length dashes, 200px gaps) — i.e. a BLANK canvas,
//     which reads as a broken render rather than as an honest gap. So the pane says "N/A" instead of
//     pretending. The `option` below carries the keyframes verbatim and is expected to light up unchanged
//     the moment applyKeyframeAnimation lands.
extension EChartsDemoRegistry {
    static let official_graphic_stroke_animation = EChartsDemo(
        name: "official-graphic-stroke-animation", category: "graphic",
        summary: "关键帧描边动画 — Stroke Animation",
        width: 640, height: 420,
        nativeSupported: false,   // see header: GraphicView defers applyKeyframeAnimation, and the
                                  // keyframes ARE this example
        collection: .official,
        webOptionJS: #"""
option = {
  graphic: {
    elements: [
      {
        type: 'text',
        left: 'center',
        top: 'center',
        style: {
          text: 'Apache ECharts',
          fontSize: 80,
          fontWeight: 'bold',
          lineDash: [0, 200],
          lineDashOffset: 0,
          fill: 'transparent',
          stroke: '#000',
          lineWidth: 1
        },
        keyframeAnimation: {
          duration: 3000,
          loop: true,
          keyframes: [
            {
              percent: 0.7,
              style: {
                fill: 'transparent',
                lineDashOffset: 200,
                lineDash: [200, 0]
              }
            },
            {
              // Stop for a while.
              percent: 0.8,
              style: {
                fill: 'transparent'
              }
            },
            {
              percent: 1,
              style: {
                fill: 'black'
              }
            }
          ]
        }
      }
    ]
  }
};
"""#,
        option: [
            "graphic": [
                "elements": [
                    [
                        "type": "text",
                        "left": "center",
                        "top": "center",
                        "style": [
                            "text": "Apache ECharts",
                            "fontSize": 80.0,
                            "fontWeight": "bold",
                            "lineDash": [0.0, 200.0],
                            "lineDashOffset": 0.0,
                            "fill": "transparent",
                            "stroke": "#000",
                            "lineWidth": 1.0
                        ] as [String: Any],
                        // PORT-NOTE: nothing is dropped here — no key of this option is JS-function-valued,
                        // so the Swift option mirrors the JS one exactly. But `keyframeAnimation` is
                        // currently INERT natively: GraphicView reads elOption but never calls
                        // applyKeyframeAnimation (GraphicView.swift:277). Kept verbatim so the demo needs no
                        // edit once that lands; see the nativeSupported note in the header.
                        "keyframeAnimation": [
                            "duration": 3000.0,
                            "loop": true,
                            "keyframes": [
                                // Draw the glyph outlines: the dash sweeps from [0, 200] to [200, 0].
                                [
                                    "percent": 0.7,
                                    "style": [
                                        "fill": "transparent",
                                        "lineDashOffset": 200.0,
                                        "lineDash": [200.0, 0.0]
                                    ] as [String: Any]
                                ] as [String: Any],
                                // Stop for a while.
                                [
                                    "percent": 0.8,
                                    "style": [
                                        "fill": "transparent"
                                    ] as [String: Any]
                                ] as [String: Any],
                                // Then fill it in.
                                [
                                    "percent": 1.0,
                                    "style": [
                                        "fill": "black"
                                    ] as [String: Any]
                                ] as [String: Any]
                            ]
                        ] as [String: Any]
                    ] as [String: Any]
                ]
            ] as [String: Any]
        ])
}
