// official-scatter-punchCard — replica of https://echarts.apache.org/examples/zh/editor.html?c=scatter-punchCard
// title: Punch Card of Github / titleCN: GitHub 打卡气泡图
// A 24h × 7d scatter grid (both axes `category`) where each bubble's radius encodes the commit count
// for that hour/day cell.
// DEVIATIONS from the official source:
//   - Canvas is 800×420 (not the gallery-default 640×420): 24 hour categories need the extra width or
//     the x labels collide.
//   - webOptionJS is the example verbatim except: the TS annotation in `function (params: any)` is
//     dropped (a classic script cannot parse it) and the trailing `export {};` is removed.
//   - `symbolSize` is carried as a native Swift closure (`SymbolSizeCallback`) mirroring the JS
//     `val => val[2] * 2` — symbolVisual.seriesSymbolTask evaluates function-valued symbol props per
//     datum, so the bubble-size encoding matches the web pane.
//   - NATIVE pane still omits the two JS closures with no native carrier (tooltip formatter,
//     animationDelay) — see the PORT-NOTEs. Neither affects the static frame.
//   - The `data` literal is pre-mapped in Swift ([day, hour, count] → [hour, day, count]) exactly as
//     the example's `.map` does at load time; the web pane still runs the original `.map`.
import EChartsKit

extension EChartsDemoRegistry {
    static let official_scatter_punchcard = EChartsDemo(
        name: "official-scatter-punchCard", category: "scatter",
        summary: "GitHub 打卡气泡图 — Punch Card of Github",
        width: 800, height: 420,
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
        return [item[1], item[0], item[2]];
    });

option = {
  title: {
    text: 'Punch Card of Github'
  },
  legend: {
    data: ['Punch Card'],
    left: 'right'
  },
  tooltip: {
    position: 'top',
    formatter: function (params) {
      return (
        params.value[2] +
        ' commits in ' +
        hours[params.value[0]] +
        ' of ' +
        days[params.value[1]]
      );
    }
  },
  grid: {
    left: 2,
    bottom: 10,
    right: 10,
    containLabel: true
  },
  xAxis: {
    type: 'category',
    data: hours,
    boundaryGap: false,
    splitLine: {
      show: true
    },
    axisLine: {
      show: false
    }
  },
  yAxis: {
    type: 'category',
    data: days,
    axisLine: {
      show: false
    }
  },
  series: [
    {
      name: 'Punch Card',
      type: 'scatter',
      symbolSize: function (val) {
        return val[2] * 2;
      },
      data: data,
      animationDelay: function (idx) {
        return idx * 5;
      }
    }
  ]
};
"""#,
        option: [
            "title": [
                "text": "Punch Card of Github"
            ] as [String: Any],
            "legend": [
                "data": ["Punch Card"],
                "left": "right"
            ] as [String: Any],
            "tooltip": [
                "position": "top"
                // PORT-NOTE: tooltip.formatter omitted — JS closure returning
                // "<count> commits in <hour> of <day>", indexing the hours/days label arrays with
                // params.value[0] / params.value[1].
            ] as [String: Any],
            "grid": [
                "left": 2.0,
                "bottom": 10.0,
                "right": 10.0,
                "containLabel": true
            ] as [String: Any],
            "xAxis": [
                "type": "category",
                "data": punchCardHours,
                "boundaryGap": false,
                "splitLine": ["show": true] as [String: Any],
                "axisLine": ["show": false] as [String: Any]
            ] as [String: Any],
            "yAxis": [
                "type": "category",
                "data": punchCardDays,
                "axisLine": ["show": false] as [String: Any]
            ] as [String: Any],
            "series": [
                [
                    "name": "Punch Card",
                    "type": "scatter",
                    // JS `symbolSize: val => val[2] * 2` — bubble diameter is twice the commit count.
                    "symbolSize": punchCardSymbolSize,
                    "data": punchCardData,
                    "animationDelay": ({ idx, _ in idx * 5 } as AnimationDelayCallback)
                ] as [String: Any]
            ]
        ])
}

// JS `symbolSize: function (val) { return val[2] * 2; }` — sized off the raw datum's third slot.
private let punchCardSymbolSize: SymbolSizeCallback<CallbackDataParams> = { rawValue, _ in
    let row = rawValue as? [Any] ?? []
    let count = (row.count > 2 ? row[2] : nil)
        .flatMap { ($0 as? Double) ?? ($0 as? Int).map(Double.init) } ?? 0
    return count * 2
}

private let punchCardHours: [String] = [
    "12a", "1a", "2a", "3a", "4a", "5a", "6a",
    "7a", "8a", "9a", "10a", "11a",
    "12p", "1p", "2p", "3p", "4p", "5p",
    "6p", "7p", "8p", "9p", "10p", "11p"
]

private let punchCardDays: [String] = [
    "Saturday", "Friday", "Thursday",
    "Wednesday", "Tuesday", "Monday", "Sunday"
]

// Source order is [dayIndex, hourIndex, commits]; the example remaps it to [hourIndex, dayIndex,
// commits] (x = hour, y = day) before handing it to the series. `punchCardData` is that mapped form.
private let punchCardRawData: [[Double]] = [
    [0, 0, 5], [0, 1, 1], [0, 2, 0], [0, 3, 0], [0, 4, 0], [0, 5, 0], [0, 6, 0], [0, 7, 0], [0, 8, 0], [0, 9, 0], [0, 10, 0], [0, 11, 2], [0, 12, 4], [0, 13, 1], [0, 14, 1], [0, 15, 3], [0, 16, 4], [0, 17, 6], [0, 18, 4], [0, 19, 4], [0, 20, 3], [0, 21, 3], [0, 22, 2], [0, 23, 5],
    [1, 0, 7], [1, 1, 0], [1, 2, 0], [1, 3, 0], [1, 4, 0], [1, 5, 0], [1, 6, 0], [1, 7, 0], [1, 8, 0], [1, 9, 0], [1, 10, 5], [1, 11, 2], [1, 12, 2], [1, 13, 6], [1, 14, 9], [1, 15, 11], [1, 16, 6], [1, 17, 7], [1, 18, 8], [1, 19, 12], [1, 20, 5], [1, 21, 5], [1, 22, 7], [1, 23, 2],
    [2, 0, 1], [2, 1, 1], [2, 2, 0], [2, 3, 0], [2, 4, 0], [2, 5, 0], [2, 6, 0], [2, 7, 0], [2, 8, 0], [2, 9, 0], [2, 10, 3], [2, 11, 2], [2, 12, 1], [2, 13, 9], [2, 14, 8], [2, 15, 10], [2, 16, 6], [2, 17, 5], [2, 18, 5], [2, 19, 5], [2, 20, 7], [2, 21, 4], [2, 22, 2], [2, 23, 4],
    [3, 0, 7], [3, 1, 3], [3, 2, 0], [3, 3, 0], [3, 4, 0], [3, 5, 0], [3, 6, 0], [3, 7, 0], [3, 8, 1], [3, 9, 0], [3, 10, 5], [3, 11, 4], [3, 12, 7], [3, 13, 14], [3, 14, 13], [3, 15, 12], [3, 16, 9], [3, 17, 5], [3, 18, 5], [3, 19, 10], [3, 20, 6], [3, 21, 4], [3, 22, 4], [3, 23, 1],
    [4, 0, 1], [4, 1, 3], [4, 2, 0], [4, 3, 0], [4, 4, 0], [4, 5, 1], [4, 6, 0], [4, 7, 0], [4, 8, 0], [4, 9, 2], [4, 10, 4], [4, 11, 4], [4, 12, 2], [4, 13, 4], [4, 14, 4], [4, 15, 14], [4, 16, 12], [4, 17, 1], [4, 18, 8], [4, 19, 5], [4, 20, 3], [4, 21, 7], [4, 22, 3], [4, 23, 0],
    [5, 0, 2], [5, 1, 1], [5, 2, 0], [5, 3, 3], [5, 4, 0], [5, 5, 0], [5, 6, 0], [5, 7, 0], [5, 8, 2], [5, 9, 0], [5, 10, 4], [5, 11, 1], [5, 12, 5], [5, 13, 10], [5, 14, 5], [5, 15, 7], [5, 16, 11], [5, 17, 6], [5, 18, 0], [5, 19, 5], [5, 20, 3], [5, 21, 4], [5, 22, 2], [5, 23, 0],
    [6, 0, 1], [6, 1, 0], [6, 2, 0], [6, 3, 0], [6, 4, 0], [6, 5, 0], [6, 6, 0], [6, 7, 0], [6, 8, 0], [6, 9, 0], [6, 10, 1], [6, 11, 0], [6, 12, 2], [6, 13, 1], [6, 14, 3], [6, 15, 4], [6, 16, 0], [6, 17, 0], [6, 18, 0], [6, 19, 0], [6, 20, 1], [6, 21, 2], [6, 22, 2], [6, 23, 6]
]

private let punchCardData: [[Double]] = punchCardRawData.map { [$0[1], $0[0], $0[2]] }
