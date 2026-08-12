// official-bar-rich-text — replica of https://echarts.apache.org/examples/zh/editor.html?c=bar-rich-text
// title: Weather Statistics / titleCN: 天气统计（富文本）
// Horizontal grouped bar (value x-axis, inverted category y-axis: Sunny/Cloudy/Showers) for three cities.
// The point of the example is RICH TEXT: the y-axis labels are two-line rich strings whose first line is
// a `backgroundColor: { image: ... }` block (the weather icon PNG), and the first series' markPoint draws
// max/min callout cards built from three rich styles (a/b/c) with text shadows and text borders.
//
// DEVIATIONS from the official source:
//   - Assets inlined. Upstream fetches the three icons over the network
//     (ROOT_PATH + '/data/asset/img/weather/{sunny,cloudy,showers}_128.png'). The gallery page has no
//     network, so the PNGs are vendored under assets/img/weather/ and read at demo time via
//     Upstream.repoRoot, base64'd into `data:image/png;base64,...` URIs, and spliced into BOTH panes
//     (the web pane's `weatherIcons` map, the native pane's `rich` backgroundColors). A read failure
//     degrades to an empty URI — the icon block renders blank rather than crashing.
//   - TypeScript-isms dropped from the web pane: the `as const` annotations and the trailing
//     `export {};` (a bare export is a SyntaxError in a classic script and would kill the page).
//   - NATIVE pane: `yAxis.axisLabel.formatter` is a JS function and cannot cross into the Swift option,
//     so the native y-axis shows the plain category names and its `rich` blocks (which only apply to
//     text carrying `{Sunny| }` style tags) sit inert. Note the icons would NOT paint natively even if
//     the formatter were expressible: EChartsKit's `labelStyle._coerceTextBackgroundColor` accepts only
//     a color String (or an already-typed TextBackgroundColor), so the `{ image: ... }` object form of
//     `backgroundColor` coerces to nil and is silently dropped — ZRenderKit models the case
//     (`TextBackgroundColor.image`, Text.swift), but the option→style seam does not carry it, and
//     Text.swift's own rich-token layout leaves the bg-image sizing branch deferred. That is a real
//     framework gap this demo exposes, not a porting shortcut.
//     Everything else ports verbatim — the markPoint's `formatter` is a rich STRING template
//     ('{a|{a}\n}{b|{b} }{c|{c}}'), not a closure, so the max/min callout cards are fully expressible
//     and both panes carry them.
import Foundation
import EChartsKit

// The three weather icons, vendored from the official asset tree and inlined as data URIs (the pane
// cannot reach the filesystem). Read once from the repo asset; a read failure yields "".
private func barRichTextIconURI(_ file: String) -> String {
    let url = Upstream.repoRoot.appendingPathComponent("assets/img/weather/\(file)")
    guard let data = try? Data(contentsOf: url) else { return "" }
    return "data:image/png;base64," + data.base64EncodedString()
}

private let barRichTextSunnyIcon = barRichTextIconURI("sunny_128.png")
private let barRichTextCloudyIcon = barRichTextIconURI("cloudy_128.png")
private let barRichTextShowersIcon = barRichTextIconURI("showers_128.png")

private let barRichTextAxisFormatter: AxisLabelCategoryFormatter = { rawValue, _, _ in
    let value = String(describing: rawValue)
    return "{\(value)| }\n{value|\(value)}"
}

extension EChartsDemoRegistry {
    static let official_bar_rich_text = EChartsDemo(
        name: "official-bar-rich-text", category: "bar",
        summary: "天气统计（富文本） — Weather Statistics",
        width: 640, height: 420,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
const weatherIcons = {
  Sunny: '\#(barRichTextSunnyIcon)',
  Cloudy: '\#(barRichTextCloudyIcon)',
  Showers: '\#(barRichTextShowersIcon)'
};

const seriesLabel = {
  show: true
};

option = {
  title: {
    text: 'Weather Statistics'
  },
  tooltip: {
    trigger: 'axis',
    axisPointer: {
      type: 'shadow'
    }
  },
  legend: {
    data: ['City Alpha', 'City Beta', 'City Gamma']
  },
  grid: {
    left: 100
  },
  toolbox: {
    show: true,
    feature: {
      saveAsImage: {}
    }
  },
  xAxis: {
    type: 'value',
    name: 'Days',
    axisLabel: {
      formatter: '{value}'
    }
  },
  yAxis: {
    type: 'category',
    inverse: true,
    data: ['Sunny', 'Cloudy', 'Showers'],
    axisLabel: {
      formatter: function (value) {
        return '{' + value + '| }\n{value|' + value + '}';
      },
      margin: 20,
      rich: {
        value: {
          lineHeight: 30,
          align: 'center'
        },
        Sunny: {
          height: 40,
          align: 'center',
          backgroundColor: {
            image: weatherIcons.Sunny
          }
        },
        Cloudy: {
          height: 40,
          align: 'center',
          backgroundColor: {
            image: weatherIcons.Cloudy
          }
        },
        Showers: {
          height: 40,
          align: 'center',
          backgroundColor: {
            image: weatherIcons.Showers
          }
        }
      }
    }
  },
  series: [
    {
      name: 'City Alpha',
      type: 'bar',
      data: [165, 170, 30],
      label: seriesLabel,
      markPoint: {
        symbolSize: 1,
        symbolOffset: [0, '50%'],
        label: {
          formatter: '{a|{a}\n}{b|{b} }{c|{c}}',
          backgroundColor: 'rgb(242,242,242)',
          borderColor: '#aaa',
          borderWidth: 1,
          borderRadius: 4,
          padding: [4, 10],
          lineHeight: 26,
          // shadowBlur: 5,
          // shadowColor: '#000',
          // shadowOffsetX: 0,
          // shadowOffsetY: 1,
          position: 'right',
          distance: 20,
          rich: {
            a: {
              align: 'center',
              color: '#fff',
              fontSize: 18,
              textShadowBlur: 2,
              textShadowColor: '#000',
              textShadowOffsetX: 0,
              textShadowOffsetY: 1,
              textBorderColor: '#333',
              textBorderWidth: 2
            },
            b: {
              color: '#333'
            },
            c: {
              color: '#ff8811',
              textBorderColor: '#000',
              textBorderWidth: 1,
              fontSize: 22
            }
          }
        },
        data: [
          { type: 'max', name: 'max days: ' },
          { type: 'min', name: 'min days: ' }
        ]
      }
    },
    {
      name: 'City Beta',
      type: 'bar',
      label: seriesLabel,
      data: [150, 105, 110]
    },
    {
      name: 'City Gamma',
      type: 'bar',
      label: seriesLabel,
      data: [220, 82, 63]
    }
  ]
};
"""#,
        option: [
            "title": [
                "text": "Weather Statistics"
            ] as [String: Any],
            "tooltip": [
                "trigger": "axis",
                "axisPointer": [
                    "type": "shadow"
                ] as [String: Any]
            ] as [String: Any],
            "legend": [
                "data": ["City Alpha", "City Beta", "City Gamma"]
            ] as [String: Any],
            "grid": [
                "left": 100.0
            ] as [String: Any],
            "toolbox": [
                "show": true,
                "feature": [
                    "saveAsImage": [:] as [String: Any]
                ] as [String: Any]
            ] as [String: Any],
            "xAxis": [
                "type": "value",
                "name": "Days",
                "axisLabel": [
                    "formatter": "{value}"
                ] as [String: Any]
            ] as [String: Any],
            "yAxis": [
                "type": "category",
                "inverse": true,
                "data": ["Sunny", "Cloudy", "Showers"],
                "axisLabel": [
                    "formatter": (barRichTextAxisFormatter as AxisLabelCategoryFormatter),
                    "margin": 20.0,
                    "rich": barRichTextAxisLabelRich
                ] as [String: Any]
            ] as [String: Any],
            "series": [
                [
                    "name": "City Alpha",
                    "type": "bar",
                    "data": [165.0, 170.0, 30.0],
                    "label": ["show": true] as [String: Any],
                    "markPoint": [
                        "symbolSize": 1.0,
                        "symbolOffset": [0.0, "50%"] as [Any],
                        "label": [
                            // A rich-text STRING template (not a closure): series name on line 1, then the
                            // markPoint's name ('max days: ' / 'min days: ') and its value.
                            "formatter": "{a|{a}\n}{b|{b} }{c|{c}}",
                            "backgroundColor": "rgb(242,242,242)",
                            "borderColor": "#aaa",
                            "borderWidth": 1.0,
                            "borderRadius": 4.0,
                            "padding": [4.0, 10.0],
                            "lineHeight": 26.0,
                            "position": "right",
                            "distance": 20.0,
                            "rich": barRichTextMarkPointRich
                        ] as [String: Any],
                        "data": [
                            ["type": "max", "name": "max days: "] as [String: Any],
                            ["type": "min", "name": "min days: "] as [String: Any]
                        ]
                    ] as [String: Any]
                ] as [String: Any],
                [
                    "name": "City Beta",
                    "type": "bar",
                    "label": ["show": true] as [String: Any],
                    "data": [150.0, 105.0, 110.0]
                ] as [String: Any],
                [
                    "name": "City Gamma",
                    "type": "bar",
                    "label": ["show": true] as [String: Any],
                    "data": [220.0, 82.0, 63.0]
                ] as [String: Any]
            ]
        ])
}

// y-axis rich styles: one block per weather category, each painting its icon as a background image on a
// 40px-tall empty line, plus the `value` block for the name line underneath. Only reachable through the
// axisLabel formatter (omitted natively — see PORT-NOTE above); carried anyway so the option stays faithful.
private let barRichTextAxisLabelRich: [String: Any] = [
    "value": [
        "lineHeight": 30.0,
        "align": "center"
    ] as [String: Any],
    "Sunny": [
        "width": 40.0,
        "height": 40.0,
        "align": "center",
        "backgroundColor": ["image": barRichTextSunnyIcon] as [String: Any]
    ] as [String: Any],
    "Cloudy": [
        "width": 40.0,
        "height": 40.0,
        "align": "center",
        "backgroundColor": ["image": barRichTextCloudyIcon] as [String: Any]
    ] as [String: Any],
    "Showers": [
        "width": 40.0,
        "height": 40.0,
        "align": "center",
        "backgroundColor": ["image": barRichTextShowersIcon] as [String: Any]
    ] as [String: Any]
]

// markPoint callout-card rich styles: `a` the shadowed/outlined series name, `b` the grey label, `c` the
// big orange value. (The upstream shadowBlur/shadowColor/shadowOffset* on the label are commented out.)
private let barRichTextMarkPointRich: [String: Any] = [
    "a": [
        "align": "center",
        "color": "#fff",
        "fontSize": 18.0,
        "textShadowBlur": 2.0,
        "textShadowColor": "#000",
        "textShadowOffsetX": 0.0,
        "textShadowOffsetY": 1.0,
        "textBorderColor": "#333",
        "textBorderWidth": 2.0
    ] as [String: Any],
    "b": [
        "color": "#333"
    ] as [String: Any],
    "c": [
        "color": "#ff8811",
        "textBorderColor": "#000",
        "textBorderWidth": 1.0,
        "fontSize": 22.0
    ] as [String: Any]
]
