// official-themeRiver-lastfm — replica of https://echarts.apache.org/examples/zh/editor.html?c=themeRiver-lastfm
// title: ThemeRiver Lastfm / titleCN: Lastfm 主题河流图
// A stream graph of last.fm listening counts: 24 raw rows x 20 time steps, flattened into
// `[time, value, name]` triples on a single axis (`max: 'dataMax'`), layer labels off.
// DEVIATIONS:
//   - none in the web pane: the official JS runs verbatim (only the TS annotation on `let data`
//     and the trailing `export {};` are dropped — neither is parseable by a classic script).
//   - the native pane rebuilds the same `[time, value, name]` triples in Swift with the SAME loop.
//     Upstream's `rawData` has 24 rows but `labels` only 20, so rows 20–23 push items whose name is
//     `undefined`; `NSNull()` stands in for `undefined` there, which ThemeRiverSeriesModel
//     .getInitialData filters out exactly as real echarts' `dataItem[2] !== undefined` filter does.
//     Both panes therefore draw 20 layers, not 24.
//   - the two `B\xc3\xa9la Fleck` labels are mojibake in the official source (UTF-8 bytes of "é"
//     read as latin-1); Swift reproduces the same two characters (U+00C3 U+00A9), so the tooltip
//     reads "BÃ©la Fleck" in BOTH panes, as it does on the website.
import Foundation   // NSNull — stands in for the `undefined` name on rawData rows 20–23.

extension EChartsDemoRegistry {
    static let official_themeriver_lastfm = EChartsDemo(
        name: "official-themeRiver-lastfm", category: "themeRiver",
        summary: "Lastfm 主题河流图 — ThemeRiver Lastfm",
        width: 720, height: 460,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
// From https://github.com/jsundram/streamgraph.js/blob/master/examples/data/lastfm.js
let rawData = [
  [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
  [0, 49, 67, 16, 0, 19, 19, 0, 0, 1, 10, 5, 6, 1, 1, 0, 25, 0, 0, 0],
  [0, 6, 3, 34, 0, 16, 1, 0, 0, 1, 6, 0, 1, 56, 0, 2, 0, 2, 0, 0],
  [0, 8, 13, 15, 0, 12, 23, 0, 0, 1, 0, 1, 0, 0, 6, 0, 0, 1, 0, 1],
  [0, 9, 28, 0, 91, 6, 1, 0, 0, 0, 7, 18, 0, 9, 16, 0, 1, 0, 0, 0],
  [0, 3, 42, 36, 21, 0, 1, 0, 0, 0, 0, 16, 30, 1, 4, 62, 55, 1, 0, 0],
  [0, 7, 13, 12, 64, 5, 0, 0, 0, 8, 17, 3, 72, 1, 1, 53, 1, 0, 0, 0],
  [1, 14, 13, 7, 8, 8, 7, 0, 1, 1, 14, 6, 44, 8, 7, 17, 21, 1, 0, 0],
  [0, 6, 14, 2, 14, 1, 0, 0, 0, 0, 2, 2, 7, 15, 6, 3, 0, 0, 0, 0],
  [0, 9, 11, 3, 0, 8, 0, 0, 14, 2, 0, 1, 1, 1, 7, 13, 2, 1, 0, 0],
  [0, 7, 5, 10, 8, 21, 0, 0, 130, 1, 2, 18, 6, 1, 5, 1, 4, 1, 0, 7],
  [0, 2, 15, 1, 5, 5, 0, 0, 6, 0, 0, 0, 4, 1, 3, 1, 17, 0, 0, 9],
  [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
  [6, 27, 26, 1, 0, 11, 1, 0, 0, 0, 1, 1, 2, 0, 0, 9, 1, 0, 0, 0],
  [31, 81, 11, 6, 11, 0, 0, 0, 0, 0, 0, 0, 3, 2, 0, 3, 14, 0, 0, 12],
  [19, 53, 6, 20, 0, 4, 37, 0, 30, 86, 43, 7, 5, 7, 17, 19, 2, 0, 0, 5],
  [0, 22, 14, 6, 10, 24, 18, 0, 13, 21, 5, 2, 13, 35, 7, 1, 8, 0, 0, 1],
  [0, 56, 5, 0, 0, 0, 0, 0, 7, 24, 0, 17, 7, 0, 0, 3, 0, 0, 0, 8],
  [18, 29, 3, 6, 11, 0, 15, 0, 12, 42, 37, 0, 3, 3, 13, 8, 0, 0, 0, 1],
  [32, 39, 37, 3, 33, 21, 6, 0, 4, 17, 0, 11, 8, 2, 3, 0, 23, 0, 0, 17],
  [72, 15, 28, 0, 0, 0, 0, 0, 1, 3, 0, 35, 0, 9, 17, 1, 9, 1, 0, 8],
  [11, 15, 4, 2, 0, 18, 10, 0, 20, 3, 0, 0, 2, 0, 0, 2, 2, 30, 0, 0],
  [14, 29, 19, 3, 2, 17, 13, 0, 7, 12, 2, 0, 6, 0, 0, 1, 1, 34, 0, 1],
  [1, 1, 7, 6, 1, 1, 15, 1, 1, 2, 1, 3, 1, 1, 9, 1, 1, 25, 1, 72]
];

let labels = [
  'The Sea and Cake',
  'Andrew Bird',
  'Laura Veirs',
  'Brian Eno',
  'Christopher Willits',
  'Wilco',
  'Edgar Meyer',
  'B\xc3\xa9la Fleck',
  'Fleet Foxes',
  'Kings of Convenience',
  'Brett Dennen',
  'Psapp',
  'The Bad Plus',
  'Feist',
  'Battles',
  'Avishai Cohen',
  'Rachael Yamagata',
  'Norah Jones',
  'B\xc3\xa9la Fleck and the Flecktones',
  'Joshua Redman'
];

let data = [];
for (let i = 0; i < rawData.length; i++) {
  for (let j = 0; j < rawData[i].length; j++) {
    let label = labels[i];
    data.push([j, rawData[i][j], label]);
  }
}

option = {
  singleAxis: {
    max: 'dataMax'
  },
  series: [
    {
      type: 'themeRiver',
      data: data,
      label: {
        show: false
      }
    }
  ]
};
"""#,
        option: [
            "singleAxis": [
                "max": "dataMax"
            ] as [String: Any],
            "series": [
                [
                    "type": "themeRiver",
                    "data": themeRiverLastfmData,
                    "label": [
                        "show": false
                    ] as [String: Any]
                ] as [String: Any]
            ]
        ])
}

// From https://github.com/jsundram/streamgraph.js/blob/master/examples/data/lastfm.js
// 24 rows x 20 columns of play counts.
private let themeRiverLastfmRawData: [[Double]] = [
    [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
    [0, 49, 67, 16, 0, 19, 19, 0, 0, 1, 10, 5, 6, 1, 1, 0, 25, 0, 0, 0],
    [0, 6, 3, 34, 0, 16, 1, 0, 0, 1, 6, 0, 1, 56, 0, 2, 0, 2, 0, 0],
    [0, 8, 13, 15, 0, 12, 23, 0, 0, 1, 0, 1, 0, 0, 6, 0, 0, 1, 0, 1],
    [0, 9, 28, 0, 91, 6, 1, 0, 0, 0, 7, 18, 0, 9, 16, 0, 1, 0, 0, 0],
    [0, 3, 42, 36, 21, 0, 1, 0, 0, 0, 0, 16, 30, 1, 4, 62, 55, 1, 0, 0],
    [0, 7, 13, 12, 64, 5, 0, 0, 0, 8, 17, 3, 72, 1, 1, 53, 1, 0, 0, 0],
    [1, 14, 13, 7, 8, 8, 7, 0, 1, 1, 14, 6, 44, 8, 7, 17, 21, 1, 0, 0],
    [0, 6, 14, 2, 14, 1, 0, 0, 0, 0, 2, 2, 7, 15, 6, 3, 0, 0, 0, 0],
    [0, 9, 11, 3, 0, 8, 0, 0, 14, 2, 0, 1, 1, 1, 7, 13, 2, 1, 0, 0],
    [0, 7, 5, 10, 8, 21, 0, 0, 130, 1, 2, 18, 6, 1, 5, 1, 4, 1, 0, 7],
    [0, 2, 15, 1, 5, 5, 0, 0, 6, 0, 0, 0, 4, 1, 3, 1, 17, 0, 0, 9],
    [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
    [6, 27, 26, 1, 0, 11, 1, 0, 0, 0, 1, 1, 2, 0, 0, 9, 1, 0, 0, 0],
    [31, 81, 11, 6, 11, 0, 0, 0, 0, 0, 0, 0, 3, 2, 0, 3, 14, 0, 0, 12],
    [19, 53, 6, 20, 0, 4, 37, 0, 30, 86, 43, 7, 5, 7, 17, 19, 2, 0, 0, 5],
    [0, 22, 14, 6, 10, 24, 18, 0, 13, 21, 5, 2, 13, 35, 7, 1, 8, 0, 0, 1],
    [0, 56, 5, 0, 0, 0, 0, 0, 7, 24, 0, 17, 7, 0, 0, 3, 0, 0, 0, 8],
    [18, 29, 3, 6, 11, 0, 15, 0, 12, 42, 37, 0, 3, 3, 13, 8, 0, 0, 0, 1],
    [32, 39, 37, 3, 33, 21, 6, 0, 4, 17, 0, 11, 8, 2, 3, 0, 23, 0, 0, 17],
    [72, 15, 28, 0, 0, 0, 0, 0, 1, 3, 0, 35, 0, 9, 17, 1, 9, 1, 0, 8],
    [11, 15, 4, 2, 0, 18, 10, 0, 20, 3, 0, 0, 2, 0, 0, 2, 2, 30, 0, 0],
    [14, 29, 19, 3, 2, 17, 13, 0, 7, 12, 2, 0, 6, 0, 0, 1, 1, 34, 0, 1],
    [1, 1, 7, 6, 1, 1, 15, 1, 1, 2, 1, 3, 1, 1, 9, 1, 1, 25, 1, 72],
]

// 20 names for 24 rows — see the header: rows 20–23 are deliberately left nameless.
// "B\u{C3}\u{A9}la Fleck" reproduces the official source's `'B\xc3\xa9la Fleck'` byte-for-byte.
private let themeRiverLastfmLabels: [String] = [
    "The Sea and Cake",
    "Andrew Bird",
    "Laura Veirs",
    "Brian Eno",
    "Christopher Willits",
    "Wilco",
    "Edgar Meyer",
    "B\u{C3}\u{A9}la Fleck",
    "Fleet Foxes",
    "Kings of Convenience",
    "Brett Dennen",
    "Psapp",
    "The Bad Plus",
    "Feist",
    "Battles",
    "Avishai Cohen",
    "Rachael Yamagata",
    "Norah Jones",
    "B\u{C3}\u{A9}la Fleck and the Flecktones",
    "Joshua Redman"
]

// The example's flattening loop, verbatim:
//   for (i) for (j) data.push([j, rawData[i][j], labels[i]]);
// `labels[i]` is `undefined` for i >= 20 -> NSNull() (dropped by ThemeRiverSeriesModel.getInitialData).
private let themeRiverLastfmData: [[Any]] = {
    var data: [[Any]] = []
    for i in 0..<themeRiverLastfmRawData.count {
        for j in 0..<themeRiverLastfmRawData[i].count {
            var label: Any = NSNull()   // JS `labels[i]` === undefined for i >= 20
            if i < themeRiverLastfmLabels.count { label = themeRiverLastfmLabels[i] }
            data.append([Double(j), themeRiverLastfmRawData[i][j], label])
        }
    }
    return data
}()
