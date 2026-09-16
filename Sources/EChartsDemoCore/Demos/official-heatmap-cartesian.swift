// official-heatmap-cartesian — replica of https://echarts.apache.org/examples/zh/editor.html?c=heatmap-cartesian
// title: Heatmap on Cartesian / titleCN: 笛卡尔坐标系上的热力图
// A 24h × 7day "punch card" heatmap: category xAxis (hours) × category yAxis (days), cells colored by
// value through a continuous, calculable visualMap.
//
// DEVIATIONS from the official source:
//   - none in the web pane: the example's data is already inline (no $.get), so `webOptionJS` is the
//     source verbatim — byte-for-byte, `.map()` closure included — minus only the two non-code
//     wrappers, the leading `/* title: ... */` metadata block (folded into this demo's name/category/
//     summary) and the trailing `export {}` TS epilogue.
//   - native pane: the same `.map(item => [item[1], item[0], item[2] || '-'])` transform is applied in
//     Swift up-front (`heatmapCartesianData`), since the Swift option is data, not code. `'-'` (echarts'
//     empty-value marker, which the falsy-`||` produces for every 0) is preserved as the String "-";
//     dataValueHelper.parseDataValue coerces it to NaN, so those cells are skipped exactly as on the web.
//   - no note below: the option itself has NO function-valued key (no formatter/renderItem/etc.),
//     so the Swift `option` mirrors the JS one key-for-key with nothing dropped. `visualMap.type` is
//     omitted here because the official omits it — visualMap's typeDefaulter resolves it to
//     `continuous` (min/max + calculable), and spelling it out would be an unfaithful embellishment.
extension EChartsDemoRegistry {
    static let official_heatmap_cartesian = EChartsDemo(
        name: "official-heatmap-cartesian", category: "heatmap",
        summary: "笛卡尔坐标系上的热力图 — Heatmap on Cartesian",
        width: 640, height: 420,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
// prettier-ignore
const hours = [
  '12a', '1a', '2a', '3a', '4a', '5a', '6a',
  '7a', '8a', '9a','10a','11a',
  '12p', '1p', '2p', '3p', '4p', '5p',
  '6p', '7p', '8p', '9p', '10p', '11p'
];

// prettier-ignore
const days = [
  'Saturday', 'Friday', 'Thursday',
  'Wednesday', 'Tuesday', 'Monday', 'Sunday'
];

// prettier-ignore
const data = [[0,0,5],[0,1,1],[0,2,0],[0,3,0],[0,4,0],[0,5,0],[0,6,0],[0,7,0],[0,8,0],[0,9,0],[0,10,0],[0,11,2],[0,12,4],[0,13,1],[0,14,1],[0,15,3],[0,16,4],[0,17,6],[0,18,4],[0,19,4],[0,20,3],[0,21,3],[0,22,2],[0,23,5],[1,0,7],[1,1,0],[1,2,0],[1,3,0],[1,4,0],[1,5,0],[1,6,0],[1,7,0],[1,8,0],[1,9,0],[1,10,5],[1,11,2],[1,12,2],[1,13,6],[1,14,9],[1,15,11],[1,16,6],[1,17,7],[1,18,8],[1,19,12],[1,20,5],[1,21,5],[1,22,7],[1,23,2],[2,0,1],[2,1,1],[2,2,0],[2,3,0],[2,4,0],[2,5,0],[2,6,0],[2,7,0],[2,8,0],[2,9,0],[2,10,3],[2,11,2],[2,12,1],[2,13,9],[2,14,8],[2,15,10],[2,16,6],[2,17,5],[2,18,5],[2,19,5],[2,20,7],[2,21,4],[2,22,2],[2,23,4],[3,0,7],[3,1,3],[3,2,0],[3,3,0],[3,4,0],[3,5,0],[3,6,0],[3,7,0],[3,8,1],[3,9,0],[3,10,5],[3,11,4],[3,12,7],[3,13,14],[3,14,13],[3,15,12],[3,16,9],[3,17,5],[3,18,5],[3,19,10],[3,20,6],[3,21,4],[3,22,4],[3,23,1],[4,0,1],[4,1,3],[4,2,0],[4,3,0],[4,4,0],[4,5,1],[4,6,0],[4,7,0],[4,8,0],[4,9,2],[4,10,4],[4,11,4],[4,12,2],[4,13,4],[4,14,4],[4,15,14],[4,16,12],[4,17,1],[4,18,8],[4,19,5],[4,20,3],[4,21,7],[4,22,3],[4,23,0],[5,0,2],[5,1,1],[5,2,0],[5,3,3],[5,4,0],[5,5,0],[5,6,0],[5,7,0],[5,8,2],[5,9,0],[5,10,4],[5,11,1],[5,12,5],[5,13,10],[5,14,5],[5,15,7],[5,16,11],[5,17,6],[5,18,0],[5,19,5],[5,20,3],[5,21,4],[5,22,2],[5,23,0],[6,0,1],[6,1,0],[6,2,0],[6,3,0],[6,4,0],[6,5,0],[6,6,0],[6,7,0],[6,8,0],[6,9,0],[6,10,1],[6,11,0],[6,12,2],[6,13,1],[6,14,3],[6,15,4],[6,16,0],[6,17,0],[6,18,0],[6,19,0],[6,20,1],[6,21,2],[6,22,2],[6,23,6]]
    .map(function (item) {
        return [item[1], item[0], item[2] || '-'];
    });

option = {
  tooltip: {
    position: 'top'
  },
  grid: {
    height: '50%',
    top: '10%'
  },
  xAxis: {
    type: 'category',
    data: hours,
    splitArea: {
      show: true
    }
  },
  yAxis: {
    type: 'category',
    data: days,
    splitArea: {
      show: true
    }
  },
  visualMap: {
    min: 0,
    max: 10,
    calculable: true,
    orient: 'horizontal',
    left: 'center',
    bottom: '15%'
  },
  series: [
    {
      name: 'Punch Card',
      type: 'heatmap',
      data: data,
      label: {
        show: true
      },
      emphasis: {
        itemStyle: {
          shadowBlur: 10,
          shadowColor: 'rgba(0, 0, 0, 0.5)'
        }
      }
    }
  ]
};
"""#,
        option: [
            "tooltip": [
                "position": "top"
            ] as [String: Any],
            "grid": [
                "height": "50%",
                "top": "10%"
            ] as [String: Any],
            "xAxis": [
                "type": "category",
                "data": heatmapCartesianHours,
                "splitArea": ["show": true] as [String: Any]
            ] as [String: Any],
            "yAxis": [
                "type": "category",
                "data": heatmapCartesianDays,
                "splitArea": ["show": true] as [String: Any]
            ] as [String: Any],
            "visualMap": [
                "min": 0.0,
                "max": 10.0,
                "calculable": true,
                "orient": "horizontal",
                "left": "center",
                "bottom": "15%"
            ] as [String: Any],
            "series": [
                [
                    "name": "Punch Card",
                    "type": "heatmap",
                    "data": heatmapCartesianData,
                    "label": ["show": true] as [String: Any],
                    "emphasis": [
                        "itemStyle": [
                            "shadowBlur": 10.0,
                            "shadowColor": "rgba(0, 0, 0, 0.5)"
                        ] as [String: Any]
                    ] as [String: Any]
                ] as [String: Any]
            ]
        ])
}

// MARK: - data (hoisted: big literals blow up Swift's type-checker inline)

private let heatmapCartesianHours: [String] = [
    "12a", "1a", "2a", "3a", "4a", "5a", "6a",
    "7a", "8a", "9a", "10a", "11a",
    "12p", "1p", "2p", "3p", "4p", "5p",
    "6p", "7p", "8p", "9p", "10p", "11p"
]

private let heatmapCartesianDays: [String] = [
    "Saturday", "Friday", "Thursday",
    "Wednesday", "Tuesday", "Monday", "Sunday"
]

/// The example's raw [dayIndex, hourIndex, value] triples, before its `.map()`.
private let heatmapCartesianRaw: [[Double]] = [
    [0, 0, 5], [0, 1, 1], [0, 2, 0], [0, 3, 0], [0, 4, 0], [0, 5, 0], [0, 6, 0], [0, 7, 0], [0, 8, 0], [0, 9, 0], [0, 10, 0], [0, 11, 2], [0, 12, 4], [0, 13, 1], [0, 14, 1], [0, 15, 3], [0, 16, 4], [0, 17, 6], [0, 18, 4], [0, 19, 4], [0, 20, 3], [0, 21, 3], [0, 22, 2], [0, 23, 5],
    [1, 0, 7], [1, 1, 0], [1, 2, 0], [1, 3, 0], [1, 4, 0], [1, 5, 0], [1, 6, 0], [1, 7, 0], [1, 8, 0], [1, 9, 0], [1, 10, 5], [1, 11, 2], [1, 12, 2], [1, 13, 6], [1, 14, 9], [1, 15, 11], [1, 16, 6], [1, 17, 7], [1, 18, 8], [1, 19, 12], [1, 20, 5], [1, 21, 5], [1, 22, 7], [1, 23, 2],
    [2, 0, 1], [2, 1, 1], [2, 2, 0], [2, 3, 0], [2, 4, 0], [2, 5, 0], [2, 6, 0], [2, 7, 0], [2, 8, 0], [2, 9, 0], [2, 10, 3], [2, 11, 2], [2, 12, 1], [2, 13, 9], [2, 14, 8], [2, 15, 10], [2, 16, 6], [2, 17, 5], [2, 18, 5], [2, 19, 5], [2, 20, 7], [2, 21, 4], [2, 22, 2], [2, 23, 4],
    [3, 0, 7], [3, 1, 3], [3, 2, 0], [3, 3, 0], [3, 4, 0], [3, 5, 0], [3, 6, 0], [3, 7, 0], [3, 8, 1], [3, 9, 0], [3, 10, 5], [3, 11, 4], [3, 12, 7], [3, 13, 14], [3, 14, 13], [3, 15, 12], [3, 16, 9], [3, 17, 5], [3, 18, 5], [3, 19, 10], [3, 20, 6], [3, 21, 4], [3, 22, 4], [3, 23, 1],
    [4, 0, 1], [4, 1, 3], [4, 2, 0], [4, 3, 0], [4, 4, 0], [4, 5, 1], [4, 6, 0], [4, 7, 0], [4, 8, 0], [4, 9, 2], [4, 10, 4], [4, 11, 4], [4, 12, 2], [4, 13, 4], [4, 14, 4], [4, 15, 14], [4, 16, 12], [4, 17, 1], [4, 18, 8], [4, 19, 5], [4, 20, 3], [4, 21, 7], [4, 22, 3], [4, 23, 0],
    [5, 0, 2], [5, 1, 1], [5, 2, 0], [5, 3, 3], [5, 4, 0], [5, 5, 0], [5, 6, 0], [5, 7, 0], [5, 8, 2], [5, 9, 0], [5, 10, 4], [5, 11, 1], [5, 12, 5], [5, 13, 10], [5, 14, 5], [5, 15, 7], [5, 16, 11], [5, 17, 6], [5, 18, 0], [5, 19, 5], [5, 20, 3], [5, 21, 4], [5, 22, 2], [5, 23, 0],
    [6, 0, 1], [6, 1, 0], [6, 2, 0], [6, 3, 0], [6, 4, 0], [6, 5, 0], [6, 6, 0], [6, 7, 0], [6, 8, 0], [6, 9, 0], [6, 10, 1], [6, 11, 0], [6, 12, 2], [6, 13, 1], [6, 14, 3], [6, 15, 4], [6, 16, 0], [6, 17, 0], [6, 18, 0], [6, 19, 0], [6, 20, 1], [6, 21, 2], [6, 22, 2], [6, 23, 6]
]

/// The example's `.map(item => [item[1], item[0], item[2] || '-'])`: swap day/hour so x = hour,
/// y = day, and turn every falsy (0) count into echarts' empty-value marker `'-'`.
private let heatmapCartesianData: [[Any]] = heatmapCartesianRaw.map { item -> [Any] in
    if item[2] == 0 {
        let empty: [Any] = [item[1], item[0], "-"]
        return empty
    }
    let filled: [Any] = [item[1], item[0], item[2]]
    return filled
}
