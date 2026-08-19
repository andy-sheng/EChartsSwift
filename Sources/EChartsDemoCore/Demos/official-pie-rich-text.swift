// official-pie-rich-text — replica of https://echarts.apache.org/examples/zh/editor.html?c=pie-rich-text
// title: Pie Special Label / titleCN: 富文本标签
//
// A 5-slice weather-statistics pie whose CityE datum carries a rich-text label: a bordered card whose
// rows are laid out with `rich` styles (a dark title bar, a hairline `hr`, and three rows whose leading
// cell is an IMAGE — the sunny / cloudy / showers weather icons — supplied as `rich.<name>.backgroundColor
// = { image: ... }`). `selectedMode: 'single'`, so clicking a slice offsets it.
//
// DEVIATIONS from the official source:
//   - The three weather icons are fetched upstream from `ROOT_PATH + '/data/asset/img/weather/*.png'`.
//     The gallery page has no network, so they are read from the repo (assets/img/{sunny,cloudy,
//     showers}_128.png via Upstream.repoRoot) and inlined as `data:image/png;base64,...` URIs — same
//     bytes, same three images, spliced into BOTH panes' options. Nothing else changed; the option is
//     otherwise verbatim.
//   - Rich token image backgrounds are carried as data URIs and rendered by the native image seam.
//     Their width is set explicitly to the same 30 px as their height so native layout does not depend
//     on the browser-only preloaded-image natural-size lookup; the source icons are square.
//
// PORT-NOTE (native option completeness): NOTHING is dropped from the Swift `option`. This example has
// no JS-function-valued keys at all — both formatters (`tooltip.formatter` and the CityE
// `label.formatter`) are ECharts STRING templates, and upstream's `[...].join('\n')` is evaluated at
// definition time into that same string. So the Swift `option` is a key-for-key mirror of webOptionJS.
import Foundation

// ---------------------------------------------------------------------------
// The three weather icons, base64'd from the repo at demo time (never a hardcoded path). A missing/
// unreadable asset degrades to an empty string: the pane then draws the rich rows without an icon
// rather than crashing.
// ---------------------------------------------------------------------------
private func weatherIconDataURI(_ file: String) -> String {
    let url = Upstream.repoRoot.appendingPathComponent("assets/img/\(file)")
    guard let data = try? Data(contentsOf: url) else { return "" }
    return "data:image/png;base64,\(data.base64EncodedString())"
}

private let sunnyIcon = weatherIconDataURI("sunny_128.png")
private let cloudyIcon = weatherIconDataURI("cloudy_128.png")
private let showersIcon = weatherIconDataURI("showers_128.png")

// The CityE label template — upstream's `[...].join('\n')`, which is a STRING formatter (not a JS
// closure), so the native option can carry it verbatim.
private let cityELabelFormatter: String = [
    "{title|{b}}{abg|}",
    "  {weatherHead|Weather}{valueHead|Days}{rateHead|Percent}",
    "{hr|}",
    "  {Sunny|}{value|202}{rate|55.3%}",
    "  {Cloudy|}{value|142}{rate|38.9%}",
    "  {Showers|}{value|21}{rate|5.8%}"
].joined(separator: "\n")

// The `rich` style map of the CityE label (upstream `series[0].data[0].label.rich`).
private let cityELabelRich: [String: Any] = [
    "title": [
        "color": "#eee",
        "align": "center"
    ] as [String: Any],
    "abg": [
        "backgroundColor": "#333",
        "width": "100%",
        "align": "right",
        "height": 25.0,
        "borderRadius": [4.0, 4.0, 0.0, 0.0]
    ] as [String: Any],
    "Sunny": [
        "height": 30.0,
        "width": 30.0,
        "align": "left",
        "backgroundColor": ["image": sunnyIcon] as [String: Any]
    ] as [String: Any],
    "Cloudy": [
        "height": 30.0,
        "width": 30.0,
        "align": "left",
        "backgroundColor": ["image": cloudyIcon] as [String: Any]
    ] as [String: Any],
    "Showers": [
        "height": 30.0,
        "width": 30.0,
        "align": "left",
        "backgroundColor": ["image": showersIcon] as [String: Any]
    ] as [String: Any],
    "weatherHead": [
        "color": "#333",
        "height": 24.0,
        "align": "left"
    ] as [String: Any],
    "hr": [
        "borderColor": "#777",
        "width": "100%",
        "borderWidth": 0.5,
        "height": 0.0
    ] as [String: Any],
    "value": [
        "width": 20.0,
        "padding": [0.0, 20.0, 0.0, 30.0],
        "align": "left"
    ] as [String: Any],
    "valueHead": [
        "color": "#333",
        "width": 20.0,
        "padding": [0.0, 20.0, 0.0, 30.0],
        "align": "center"
    ] as [String: Any],
    "rate": [
        "width": 40.0,
        "align": "right",
        "padding": [0.0, 10.0, 0.0, 0.0]
    ] as [String: Any],
    "rateHead": [
        "color": "#333",
        "width": 40.0,
        "align": "center",
        "padding": [0.0, 10.0, 0.0, 0.0]
    ] as [String: Any]
]

// The pie's five data items; only CityE carries the rich label.
private let pieRichTextData: [[String: Any]] = [
    [
        "value": 1548.0,
        "name": "CityE",
        "label": [
            "formatter": cityELabelFormatter,
            "backgroundColor": "#eee",
            "borderColor": "#777",
            "borderWidth": 1.0,
            "borderRadius": 4.0,
            "rich": cityELabelRich
        ] as [String: Any]
    ] as [String: Any],
    ["value": 735.0, "name": "CityC"] as [String: Any],
    ["value": 510.0, "name": "CityD"] as [String: Any],
    ["value": 434.0, "name": "CityB"] as [String: Any],
    ["value": 335.0, "name": "CityA"] as [String: Any]
]

extension EChartsDemoRegistry {
    static let official_pie_rich_text = EChartsDemo(
        name: "official-pie-rich-text", category: "rich",
        summary: "富文本标签 — Pie Special Label",
        width: 640, height: 420,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
const weatherIcons = {
  Sunny: '\#(sunnyIcon)',
  Cloudy: '\#(cloudyIcon)',
  Showers: '\#(showersIcon)'
};

option = {
  title: {
    text: 'Weather Statistics',
    subtext: 'Fake Data',
    left: 'center'
  },
  tooltip: {
    trigger: 'item',
    formatter: '{a} <br/>{b} : {c} ({d}%)'
  },
  legend: {
    bottom: 10,
    left: 'center',
    data: ['CityA', 'CityB', 'CityD', 'CityC', 'CityE']
  },
  series: [
    {
      type: 'pie',
      radius: '65%',
      center: ['50%', '50%'],
      selectedMode: 'single',
      data: [
        {
          value: 1548,
          name: 'CityE',
          label: {
            formatter: [
              '{title|{b}}{abg|}',
              '  {weatherHead|Weather}{valueHead|Days}{rateHead|Percent}',
              '{hr|}',
              '  {Sunny|}{value|202}{rate|55.3%}',
              '  {Cloudy|}{value|142}{rate|38.9%}',
              '  {Showers|}{value|21}{rate|5.8%}'
            ].join('\n'),
            backgroundColor: '#eee',
            borderColor: '#777',
            borderWidth: 1,
            borderRadius: 4,
            rich: {
              title: {
                color: '#eee',
                align: 'center'
              },
              abg: {
                backgroundColor: '#333',
                width: '100%',
                align: 'right',
                height: 25,
                borderRadius: [4, 4, 0, 0]
              },
              Sunny: {
                height: 30,
                width: 30,
                align: 'left',
                backgroundColor: {
                  image: weatherIcons.Sunny
                }
              },
              Cloudy: {
                height: 30,
                width: 30,
                align: 'left',
                backgroundColor: {
                  image: weatherIcons.Cloudy
                }
              },
              Showers: {
                height: 30,
                width: 30,
                align: 'left',
                backgroundColor: {
                  image: weatherIcons.Showers
                }
              },
              weatherHead: {
                color: '#333',
                height: 24,
                align: 'left'
              },
              hr: {
                borderColor: '#777',
                width: '100%',
                borderWidth: 0.5,
                height: 0
              },
              value: {
                width: 20,
                padding: [0, 20, 0, 30],
                align: 'left'
              },
              valueHead: {
                color: '#333',
                width: 20,
                padding: [0, 20, 0, 30],
                align: 'center'
              },
              rate: {
                width: 40,
                align: 'right',
                padding: [0, 10, 0, 0]
              },
              rateHead: {
                color: '#333',
                width: 40,
                align: 'center',
                padding: [0, 10, 0, 0]
              }
            }
          }
        },
        { value: 735, name: 'CityC' },
        { value: 510, name: 'CityD' },
        { value: 434, name: 'CityB' },
        { value: 335, name: 'CityA' }
      ],
      emphasis: {
        itemStyle: {
          shadowBlur: 10,
          shadowOffsetX: 0,
          shadowColor: 'rgba(0, 0, 0, 0.5)'
        }
      }
    }
  ]
};
"""#,
        option: [
            "title": [
                "text": "Weather Statistics",
                "subtext": "Fake Data",
                "left": "center"
            ] as [String: Any],
            "tooltip": [
                "trigger": "item",
                // Upstream's tooltip formatter is a STRING template, not a closure — ported verbatim.
                "formatter": "{a} <br/>{b} : {c} ({d}%)"
            ] as [String: Any],
            "legend": [
                "bottom": 10.0,
                "left": "center",
                "data": ["CityA", "CityB", "CityD", "CityC", "CityE"]
            ] as [String: Any],
            "series": [
                [
                    "type": "pie",
                    "radius": "65%",
                    "center": ["50%", "50%"],
                    "selectedMode": "single",
                    "data": pieRichTextData as [Any],
                    "emphasis": [
                        "itemStyle": [
                            "shadowBlur": 10.0,
                            "shadowOffsetX": 0.0,
                            "shadowColor": "rgba(0, 0, 0, 0.5)"
                        ] as [String: Any]
                    ] as [String: Any]
                ] as [String: Any]
            ]
        ])
}
