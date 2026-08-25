// official-graphic-stroke-animation — replica of https://echarts.apache.org/examples/zh/editor.html?c=graphic-stroke-animation
// title: Stroke Animation / titleCN: 关键帧描边动画
// A chart with NO series/axes at all: a single `graphic` text element ("Apache ECharts", 80px bold,
// transparent fill + 1px stroke) whose `keyframeAnimation` (3s, looping) sweeps `lineDash` /
// `lineDashOffset` from [0, 200] to [200, 0] so the glyph outlines draw themselves, dwells, then
// tweens the fill from transparent to black.
//
// The option is the official example verbatim. Its animation lives entirely in `keyframeAnimation`:
// there is no timer or `myChart` callback, so no native `drive` hook is needed. Deterministic animation
// comparisons must sample both panes at the same logical timestamps; replacing the option with a frozen
// keyframe would remove the behavior this example exists to demonstrate.
extension EChartsDemoRegistry {
    static let official_graphic_stroke_animation = EChartsDemo(
        name: "official-graphic-stroke-animation", category: "graphic",
        summary: "关键帧描边动画 — Stroke Animation",
        width: 640, height: 420,
        nativeSupported: true,   // keyframeAnimation is now ported (applyKeyframeAnimation, wired in
                                 // GraphicView); the glyph sweeps its lineDash/fill live. See header.
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
                        "keyframeAnimation": [
                            "duration": 3000.0,
                            "loop": true,
                            "keyframes": [
                                [
                                    "percent": 0.7,
                                    "style": [
                                        "fill": "transparent",
                                        "lineDashOffset": 200.0,
                                        "lineDash": [200.0, 0.0]
                                    ] as [String: Any]
                                ] as [String: Any],
                                [
                                    "percent": 0.8,
                                    "style": [
                                        "fill": "transparent"
                                    ] as [String: Any]
                                ] as [String: Any],
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
