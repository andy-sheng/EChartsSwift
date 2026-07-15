// official-pictorialBar-hill — replica of https://echarts.apache.org/examples/zh/editor.html?c=pictorialBar-hill
// title: Wish List and Mountain Height / titleCN: 圣诞愿望清单和山峰高度
//
// Two overlaid `pictorialBar` series on one category axis: the front series draws each bar out of a
// repeated image symbol (a stack of wish-list paper slips for "Christmas Wish List", a mountain
// photo for Qomolangma / Kilimanjaro, `symbolPosition: 'end'`), with a markLine at y = 8844; the
// back series (`barGap: '-100%'`, `z: -10`, silent) draws the dark elliptical "ground" under each.
//
// DEVIATIONS from the official source:
//   - ASSETS. The official example fetches its two mountain images over the network
//     (`'image://' + ROOT_PATH + '/data/asset/img/hill-Qomolangma.png'`, likewise Kilimanjaro). The
//     gallery page has no network, so both PNGs are read from the repo (assets/img/, via
//     Upstream.repoRoot) at demo time, base64'd into `data:image/png;base64,...` URIs and spliced
//     into webOptionJS. Pixels are unchanged.
//   - The example's third image, the wish-list paper slip, is ALREADY an inline base64 data URI in
//     the official source; it is kept verbatim as one Swift constant and interpolated into the JS
//     (same value, declared once instead of twice).
//   - ANIMATION. `animationEasing: 'elasticOut'` plus the per-datum `animationDelay` closure make the
//     bars spring up in sequence on load. The gallery renders ONE static frame with animation forced
//     off, so only the settled end state is visible; `animationDelay` (a JS function) is kept in
//     webOptionJS and omitted from the Swift option (see PORT-NOTE).
//   - Everything else — including the stray top-level `markLine: { z: -1 }` in the official source
//     (a no-op outside a series) — is carried over as-is.
//
// NATIVE PANE: nativeSupported: true. The `image://` picture symbols now render natively — the repeated
// paper slips (symbolRepeat) and BOTH mountain photos (symbolPosition:'end', clipped to bar height via
// symbolClip) draw as the actual images, pixel-faithful to the reference pane. This required porting the
// image-symbol seam: `symbol.createSymbol`'s image:// branch → `ToolPath.makeImage` (a ZRImage sized to
// the symbol rect), `ZRImage` conforming to `ECSymbol`, and `PictorialBarView`'s symbol pipeline widened
// from `Path` to `Displayable` so an image element flows through create/repeat/clip/updateCommon.
// Known minor deviations still surfaced by the pane (both SEPARATE from image symbols, hence ON to
// surface them, matching the sibling forest's precedent): the second series' `symbol:'circle'` ground
// ellipses and the y=8844 markLine are not drawn natively on this particular config.
import Foundation
import EChartsKit

// The two mountain photos, read from the repo and base64'd — the web pane cannot reach the filesystem.
// A missing/unreadable file degrades to an empty URI (that symbol renders blank rather than crashing).
private func hillPngDataURI(_ repoRelativePath: String) -> String {
    let url = Upstream.repoRoot.appendingPathComponent(repoRelativePath)
    guard let data = try? Data(contentsOf: url) else { return "" }
    return "data:image/png;base64," + data.base64EncodedString()
}

private let qomolangmaURI = hillPngDataURI("assets/img/hill-Qomolangma.png")
private let kilimanjaroURI = hillPngDataURI("assets/img/hill-Kilimanjaro.png")

// Verbatim from the official source: the wish-list paper slip, repeated up the first bar.
private let paperDataURI = "data:image/png;base64,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"

// series[0] — the picture bars. `value: '-'` is the deliberate empty slot between the wish list and
// the mountains (the xAxis' second category is the empty string ''), drawn with no symbol.
private let hillData: [[String: Any]] = [
    [
        "value": 13000.0,
        "symbol": "image://" + paperDataURI,
        "symbolRepeat": true,
        "symbolSize": ["130%", "20%"],
        "symbolOffset": [0.0, 10.0],
        "symbolMargin": "-30%"
        // PORT-NOTE: animationDelay omitted — JS closure `function (dataIndex, params) { return
        // params.index * 30; }`, staggering the repeated paper symbols 30ms apart as the bar grows in.
    ],
    [
        "value": "-",
        "symbol": "none"
    ],
    [
        "value": 8844.0,
        "symbol": "image://" + qomolangmaURI,
        "symbolSize": ["200%", "105%"],
        "symbolPosition": "end",
        "z": 10.0
    ],
    [
        "value": 5895.0,
        "symbol": "image://" + kilimanjaroURI,
        "symbolSize": ["200%", "105%"],
        "symbolPosition": "end"
    ]
]

// series[1] — the dark ellipse "ground" under each bar, drawn behind everything (z: -10).
private let hillGroundData: [[String: Any]] = [
    ["value": 1.0, "symbolSize": ["150%", 50.0] as [Any]],
    ["value": "-"],
    ["value": 1.0, "symbolSize": ["200%", 50.0] as [Any]],
    ["value": 1.0, "symbolSize": ["200%", 50.0] as [Any]]
]

extension EChartsDemoRegistry {
    static let official_pictorialbar_hill = EChartsDemo(
        name: "official-pictorialBar-hill", category: "pictorialBar",
        summary: "圣诞愿望清单和山峰高度 — Wish List and Mountain Height",
        width: 640, height: 420,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
var paperDataURI = '\#(paperDataURI)';
var qomolangmaDataURI = '\#(qomolangmaURI)';
var kilimanjaroDataURI = '\#(kilimanjaroURI)';

option = {
  backgroundColor: '#0f375f',
  tooltip: {},
  legend: {
    textStyle: { color: '#ddd' }
  },
  xAxis: [
    {
      data: ['Christmas Wish List', '', 'Qomolangma', 'Kilimanjaro'],
      axisTick: { show: false },
      axisLine: { show: false },
      axisLabel: {
        margin: 20,
        color: '#ddd',
        fontSize: 14
      }
    }
  ],
  yAxis: {
    splitLine: { show: false },
    axisTick: { show: false },
    axisLine: { show: false },
    axisLabel: { show: false }
  },
  markLine: {
    z: -1
  },
  animationEasing: 'elasticOut',
  series: [
    {
      type: 'pictorialBar',
      name: 'All',
      emphasis: {
        scale: true
      },
      label: {
        show: true,
        position: 'top',
        formatter: '{c} m',
        fontSize: 16,
        color: '#e54035'
      },
      data: [
        {
          value: 13000,
          symbol: 'image://' + paperDataURI,
          symbolRepeat: true,
          symbolSize: ['130%', '20%'],
          symbolOffset: [0, 10],
          symbolMargin: '-30%',
          animationDelay: function (dataIndex, params) {
            return params.index * 30;
          }
        },
        {
          value: '-',
          symbol: 'none'
        },
        {
          value: 8844,
          symbol: 'image://' + qomolangmaDataURI,
          symbolSize: ['200%', '105%'],
          symbolPosition: 'end',
          z: 10
        },
        {
          value: 5895,
          symbol: 'image://' + kilimanjaroDataURI,
          symbolSize: ['200%', '105%'],
          symbolPosition: 'end'
        }
      ],
      markLine: {
        symbol: ['none', 'none'],
        label: {
          show: false
        },
        lineStyle: {
          color: '#e54035',
          width: 2
        },
        data: [
          {
            yAxis: 8844
          }
        ]
      }
    },
    {
      name: 'All',
      type: 'pictorialBar',
      barGap: '-100%',
      symbol: 'circle',
      itemStyle: {
        color: '#185491'
      },
      silent: true,
      symbolOffset: [0, '50%'],
      z: -10,
      data: [
        {
          value: 1,
          symbolSize: ['150%', 50]
        },
        {
          value: '-'
        },
        {
          value: 1,
          symbolSize: ['200%', 50]
        },
        {
          value: 1,
          symbolSize: ['200%', 50]
        }
      ]
    }
  ]
};
"""#,
        option: [
            "backgroundColor": "#0f375f",
            "tooltip": [:] as [String: Any],
            "legend": [
                "textStyle": ["color": "#ddd"] as [String: Any]
            ] as [String: Any],
            "xAxis": [
                [
                    "data": ["Christmas Wish List", "", "Qomolangma", "Kilimanjaro"],
                    "axisTick": ["show": false] as [String: Any],
                    "axisLine": ["show": false] as [String: Any],
                    "axisLabel": [
                        "margin": 20.0,
                        "color": "#ddd",
                        "fontSize": 14.0
                    ] as [String: Any]
                ] as [String: Any]
            ],
            "yAxis": [
                "splitLine": ["show": false] as [String: Any],
                "axisTick": ["show": false] as [String: Any],
                "axisLine": ["show": false] as [String: Any],
                "axisLabel": ["show": false] as [String: Any]
            ] as [String: Any],
            // Verbatim from the official source: a top-level `markLine` is not a real ECharts option
            // (markLine only exists on a series) — kept so the two panes are fed the same thing.
            "markLine": ["z": -1.0] as [String: Any],
            "animationEasing": "elasticOut",
            "series": [
                [
                    "type": "pictorialBar",
                    "name": "All",
                    "emphasis": ["scale": true] as [String: Any],
                    "label": [
                        "show": true,
                        "position": "top",
                        "formatter": "{c} m",   // a template string, not a closure — portable as-is
                        "fontSize": 16.0,
                        "color": "#e54035"
                    ] as [String: Any],
                    "data": hillData as [Any],
                    "markLine": [
                        "symbol": ["none", "none"],
                        "label": ["show": false] as [String: Any],
                        "lineStyle": [
                            "color": "#e54035",
                            "width": 2.0
                        ] as [String: Any],
                        "data": [
                            ["yAxis": 8844.0] as [String: Any]
                        ] as [Any]
                    ] as [String: Any]
                ] as [String: Any],
                [
                    "name": "All",
                    "type": "pictorialBar",
                    "barGap": "-100%",
                    "symbol": "circle",
                    "itemStyle": ["color": "#185491"] as [String: Any],
                    "silent": true,
                    "symbolOffset": [0.0, "50%"] as [Any],
                    "z": -10.0,
                    "data": hillGroundData as [Any]
                ] as [String: Any]
            ]
        ])
}
