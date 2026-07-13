// official-pie-custom — replica of https://echarts.apache.org/examples/zh/editor.html?c=pie-custom
// title: Customized Pie / titleCN: 饼图自定义样式
// A dark-backgrounded Nightingale rose pie (roseType: 'radius') whose single itemStyle color '#c23531'
// is spread across the slices by a hidden continuous visualMap (inRange.colorLightness [0, 1]), with a
// heavy shadowBlur and translucent labels/labelLines.
// DEVIATIONS from the official source:
//   - series.data is pre-sorted ascending by value in the native pane (the official source calls
//     `.sort((a, b) => a.value - b.value)` on the literal); webOptionJS keeps the `.sort(...)` call
//     verbatim. Same resulting order: Video Ads, Union Ads, Email, Direct, Search Engine.
//   - series.animationDelay (a JS closure) is dropped from the native option — see PORT-NOTE. Both
//     panes render one static, animation-free frame anyway, so entry animation is not observable.
extension EChartsDemoRegistry {
    static let official_pie_custom = EChartsDemo(
        name: "official-pie-custom", category: "pie",
        summary: "饼图自定义样式 — Customized Pie",
        width: 640, height: 420,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
option = {
  backgroundColor: '#2c343c',

  title: {
    text: 'Customized Pie',
    left: 'center',
    top: 20,
    textStyle: {
      color: '#ccc'
    }
  },

  tooltip: {
    trigger: 'item'
  },

  visualMap: {
    show: false,
    min: 80,
    max: 600,
    inRange: {
      colorLightness: [0, 1]
    }
  },
  series: [
    {
      name: 'Access From',
      type: 'pie',
      radius: '55%',
      center: ['50%', '50%'],
      data: [
        { value: 335, name: 'Direct' },
        { value: 310, name: 'Email' },
        { value: 274, name: 'Union Ads' },
        { value: 235, name: 'Video Ads' },
        { value: 400, name: 'Search Engine' }
      ].sort(function (a, b) {
        return a.value - b.value;
      }),
      roseType: 'radius',
      label: {
        color: 'rgba(255, 255, 255, 0.3)'
      },
      labelLine: {
        lineStyle: {
          color: 'rgba(255, 255, 255, 0.3)'
        },
        smooth: 0.2,
        length: 10,
        length2: 20
      },
      itemStyle: {
        color: '#c23531',
        shadowBlur: 200,
        shadowColor: 'rgba(0, 0, 0, 0.5)'
      },

      animationType: 'scale',
      animationEasing: 'elasticOut',
      animationDelay: function (idx) {
        return Math.random() * 200;
      }
    }
  ]
};
"""#,
        option: [
            "backgroundColor": "#2c343c",
            "title": [
                "text": "Customized Pie",
                "left": "center",
                "top": 20.0,
                "textStyle": [
                    "color": "#ccc"
                ] as [String: Any]
            ] as [String: Any],
            "tooltip": [
                "trigger": "item"
            ] as [String: Any],
            "visualMap": [
                "show": false,
                "min": 80.0,
                "max": 600.0,
                "inRange": [
                    "colorLightness": [0.0, 1.0]
                ] as [String: Any]
            ] as [String: Any],
            "series": [
                [
                    "name": "Access From",
                    "type": "pie",
                    "radius": "55%",
                    "center": ["50%", "50%"],
                    "data": pieCustomData,
                    "roseType": "radius",
                    "label": [
                        "color": "rgba(255, 255, 255, 0.3)"
                    ] as [String: Any],
                    "labelLine": [
                        "lineStyle": [
                            "color": "rgba(255, 255, 255, 0.3)"
                        ] as [String: Any],
                        "smooth": 0.2,
                        "length": 10.0,
                        "length2": 20.0
                    ] as [String: Any],
                    "itemStyle": [
                        "color": "#c23531",
                        "shadowBlur": 200.0,
                        "shadowColor": "rgba(0, 0, 0, 0.5)"
                    ] as [String: Any],
                    "animationType": "scale",
                    "animationEasing": "elasticOut"
                    // PORT-NOTE: series.animationDelay omitted — the JS closure `function (idx) { return
                    // Math.random() * 200; }` staggered each slice's entry animation by a random 0–200ms.
                    // Not expressible as a Swift option value; the gallery renders a static frame regardless.
                ] as [String: Any]
            ]
        ])
}

// The official literal, already run through `.sort((a, b) => a.value - b.value)` (ascending by value).
private let pieCustomData: [[String: Any]] = [
    ["value": 235.0, "name": "Video Ads"],
    ["value": 274.0, "name": "Union Ads"],
    ["value": 310.0, "name": "Email"],
    ["value": 335.0, "name": "Direct"],
    ["value": 400.0, "name": "Search Engine"]
]
