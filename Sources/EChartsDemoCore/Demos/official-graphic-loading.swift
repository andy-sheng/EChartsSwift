// official-graphic-loading — replica of https://echarts.apache.org/examples/zh/editor.html?c=graphic-loading
// title: Customized Loading Animation / titleCN: 加载动画
// A chart with NO series: the whole picture is a `graphic` component — one centred group of 7 blue
// rects, each carrying a looping `keyframeAnimation` that squashes it to scaleY 0.3 (cubicIn) and back
// to 1 (cubicOut) over 1s, staggered by `delay: i * 200`, giving the classic "bouncing bars" spinner.
//
// DEVIATIONS from the official source:
//   - webOptionJS is the example VERBATIM. The example is a single static `option` literal: no data
//     fetch, no timers, no `myChart` driving, and no closure is STORED in the option (its
//     `new Array(7).fill(0).map(...)` merely builds the children array at parse time), so no `drive`
//     hook is needed — a `drive` closure here would be inventing a timeline the example does not have.
//     The native `option` unrolls that same `.map()` into `graphicLoadingBars`, one dict per i in 0..<7.
//   - NATIVE PANE: the bars render, the BOUNCE DOES NOT (yet). `graphic`, `type: 'group'` + `children`,
//     and `left/top: 'center'` (layout.positionElement) are all ported — but GraphicView deliberately
//     does NOT apply keyframes (note at component/graphic/GraphicView.swift:277 — "requires
//     keyframe animation: applyKeyframeAnimation(el, elOption.keyframeAnimation, graphicModel)"). So
//     the native pane draws the 7 bars in their base state (scaleY 1, full height): the spinner AT
//     REST, a legitimate frame of the example rather than a broken canvas — which is why this one
//     keeps `nativeSupported: true`, unlike the sibling official-graphic-stroke-animation, whose base
//     state (transparent fill over a [0, 200] dash) is a BLANK canvas. The keyframes are kept verbatim
//     in `option` and will light the demo up unchanged the moment applyKeyframeAnimation lands.
//   - the headless still-frame paths (`--render` / `--web-snapshot` / `--compare`) stay apples-to-
//     apples regardless: echartsHTMLPage(snapshot:) forces `animation: false` on the applied option,
//     and upstream's applyKeyframeAnimation early-returns on `!animatableModel.isAnimationEnabled()`
//     (animation/customGraphicKeyframeAnimation.ts:64), so the WEB snapshot freezes the bars at rest
//     too. Only the two LIVE panes differ today: web bounces, native stands still.
import Foundation

// The example's `new Array(7).fill(0).map((val, i) => ({ ... }))`, unrolled: bar i sits at x = i * 20
// and starts its 1s squash-and-stretch loop 200ms after bar i-1.
private let graphicLoadingBars: [[String: Any]] = (0..<7).map { i in
    [
        "type": "rect",
        "x": Double(i) * 20.0,
        "shape": [
            "x": 0.0,
            "y": -40.0,
            "width": 10.0,
            "height": 80.0
        ] as [String: Any],
        "style": [
            "fill": "#5470c6"
        ] as [String: Any],
        // nothing is dropped here — no key of this option is JS-function-valued, so the
        // Swift option mirrors the JS one exactly. But `keyframeAnimation` is currently INERT
        // natively: GraphicView reads elOption and never calls applyKeyframeAnimation
        // (GraphicView.swift:277). Kept verbatim so the demo needs no edit once that lands; the
        // native pane meanwhile shows the bars at rest (see the header).
        "keyframeAnimation": [
            "duration": 1000.0,
            "delay": Double(i) * 200.0,
            "loop": true,
            "keyframes": [
                [
                    "percent": 0.5,
                    "scaleY": 0.3,
                    "easing": "cubicIn"
                ] as [String: Any],
                [
                    "percent": 1.0,
                    "scaleY": 1.0,
                    "easing": "cubicOut"
                ] as [String: Any]
            ]
        ] as [String: Any]
    ] as [String: Any]
}

extension EChartsDemoRegistry {
    static let official_graphic_loading = EChartsDemo(
        name: "official-graphic-loading", category: "graphic",
        summary: "加载动画 — Customized Loading Animation",
        width: 640, height: 420,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
option = {
  graphic: {
    elements: [
      {
        type: 'group',
        left: 'center',
        top: 'center',
        children: new Array(7).fill(0).map((val, i) => ({
          type: 'rect',
          x: i * 20,
          shape: {
            x: 0,
            y: -40,
            width: 10,
            height: 80
          },
          style: {
            fill: '#5470c6'
          },
          keyframeAnimation: {
            duration: 1000,
            delay: i * 200,
            loop: true,
            keyframes: [
              {
                percent: 0.5,
                scaleY: 0.3,
                easing: 'cubicIn'
              },
              {
                percent: 1,
                scaleY: 1,
                easing: 'cubicOut'
              }
            ]
          }
        }))
      }
    ]
  }
};
"""#,
        option: [
            "graphic": [
                "elements": [
                    [
                        "type": "group",
                        "left": "center",
                        "top": "center",
                        "children": graphicLoadingBars
                    ] as [String: Any]
                ]
            ] as [String: Any]
        ])
}
