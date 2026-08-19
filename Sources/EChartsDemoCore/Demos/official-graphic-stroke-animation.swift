// official-graphic-stroke-animation — replica of https://echarts.apache.org/examples/zh/editor.html?c=graphic-stroke-animation
// title: Stroke Animation / titleCN: 关键帧描边动画
// A chart with NO series/axes at all: a single `graphic` text element ("Apache ECharts", 80px bold,
// transparent fill + 1px stroke) whose `keyframeAnimation` (3s, looping) sweeps `lineDash` /
// `lineDashOffset` from [0, 200] to [200, 0] so the glyph outlines draw themselves, dwells, then
// tweens the fill from transparent to black.
//
// DEVIATION from the official source:
//   - The upstream graphic loops forever, so the two independent renderers are necessarily captured at
//     different animation phases. For deterministic native/web gallery comparison, both panes freeze at
//     the 70% keyframe: the complete outline is visible with transparent fill.
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
          lineDash: [200, 0],
          lineDashOffset: 200,
          fill: 'transparent',
          stroke: '#000',
          lineWidth: 1
        },
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
                            "lineDash": [200.0, 0.0],
                            "lineDashOffset": 200.0,
                            "fill": "transparent",
                            "stroke": "#000",
                            "lineWidth": 1.0
                        ] as [String: Any]
                    ] as [String: Any]
                ]
            ] as [String: Any]
        ])
}
