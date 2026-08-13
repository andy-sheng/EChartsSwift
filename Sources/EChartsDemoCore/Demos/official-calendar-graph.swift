// official-calendar-graph — replica of https://echarts.apache.org/examples/zh/editor.html?c=calendar-graph
// title: Calendar Graph / titleCN: 日历关系图
// A `graph` series laid out ON a calendar coordinate system (coordinateSystem: 'calendar'), stacked over a
// `heatmap` series on the SAME calendar: 7 yellow shadowed nodes sit on their dates (2017-02-01 … 2017-03-14)
// and are chained by 6 red arrow-headed edges (edgeSymbol: ['none', 'arrow'], links = i → i+1 with the last
// popped), while the heatmap paints every day cell of the range from a 2-stop piecewise visualMap that is
// scoped to `seriesIndex: [1]` so it never recolours the graph's nodes. The calendar is vertical, 40px cells,
// Chinese day/month names, centered.
//
// DEVIATIONS from the official source:
//   - DATA (heatmap): upstream fills series[1] with `getVirtualData('2017')`, which walks every day of 2017
//     (echarts.time.parse / echarts.time.format) and assigns `Math.floor(Math.random() * 1000)`. That is
//     NONDETERMINISTIC — the two panes would never agree, and no two renders of the same pane would agree
//     either, so the reference↔port diff would be meaningless. The 365 [date, value] rows are instead
//     generated ONCE in Swift by a seeded LCG (same shape: '{yyyy}-{MM}-{dd}' × 0…999) and the SAME array is
//     inlined into BOTH panes — spliced into webOptionJS as a JSON literal, and used verbatim as the native
//     `series[1].data`. This mirrors what official-calendar-vertical.swift does with the same generator.
//     (Upstream also formats its timestamps with `useUTC = false` while parsing them as UTC, so west-of-UTC
//     viewers actually get the year shifted a day; our rows are the clean one-per-calendar-day set.)
//   - `graphData`, `links` (the map/pop chain) and the rest of the option are VERBATIM — they are already
//     deterministic and the link derivation runs as real JS in the reference pane.
//   - `export {};` and the TS type annotations (`[string, number][]`, `year: string`) are dropped: a bare
//     export is a SyntaxError in the reference page's classic script, and TS types do not parse there.
//   - No `tooltip.formatter` / renderItem / symbolSize closure in this example, so the native option carries
//     every key the JS one does — nothing is omitted.
//
// CANVAS SIZE (a gallery knob, not part of the option): 720×560. The vertical calendar spans 9 week-rows
// (2017-01-30 … 2017-04-02, firstDay: 1) at cellSize 40 ⇒ 360px tall + the 30px year label and the bottom
// visualMap; a 460px-tall pane would collide the piecewise legend with the last week row.
import Foundation

// The rows `getVirtualData('2017')` would have produced, made deterministic: a fixed-seed LCG stands in for
// Math.random(). Element shape is the upstream `[string, number]` pair (2017 is not a leap year).
private let calendarGraphVirtualData: [[Any]] = {
    var seed: UInt64 = 2017_01_01
    func nextUnit() -> Double {          // deterministic stand-in for Math.random() → [0, 1)
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        return Double((seed >> 33) % 1_000_000) / 1_000_000.0
    }
    let monthDays = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
    var rows: [[Any]] = []
    for (i, days) in monthDays.enumerated() {
        for day in 1...days {
            rows.append([String(format: "2017-%02d-%02d", i + 1, day), (nextUnit() * 1000).rounded(.down)])
        }
    }
    return rows
}()

// The same rows as a JSON literal, spliced into the reference pane's JS (see \#( ... ) below).
private let calendarGraphVirtualDataJSON: String = {
    guard let data = try? JSONSerialization.data(withJSONObject: calendarGraphVirtualData, options: []),
          let json = String(data: data, encoding: .utf8) else { return "[]" }
    return json
}()

// The 7 graph nodes — [date, value], verbatim from the example.
private let calendarGraphNodeData: [[Any]] = [
    ["2017-02-01", 260.0],
    ["2017-02-04", 200.0],
    ["2017-02-09", 279.0],
    ["2017-02-13", 847.0],
    ["2017-02-18", 241.0],
    ["2017-02-23", 411.0],
    ["2017-03-14", 985.0]
]

// The JS builds these with `graphData.map((item, idx) => ({ source: idx, target: idx + 1 }))` and then
// `links.pop()` — i.e. a chain 0→1 … 5→6, one shorter than the node list. Numeric endpoints index the nodes.
private let calendarGraphLinks: [[String: Any]] = (0..<(calendarGraphNodeData.count - 1)).map {
    ["source": Double($0), "target": Double($0 + 1)] as [String: Any]
}

extension EChartsDemoRegistry {
    static let official_calendar_graph = EChartsDemo(
        name: "official-calendar-graph", category: "calendar",
        summary: "日历关系图 — Calendar Graph",
        width: 720, height: 560,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
const graphData = [
  ['2017-02-01', 260],
  ['2017-02-04', 200],
  ['2017-02-09', 279],
  ['2017-02-13', 847],
  ['2017-02-18', 241],
  ['2017-02-23', 411],
  ['2017-03-14', 985]
];

const links = graphData.map(function (item, idx) {
  return {
    source: idx,
    target: idx + 1
  };
});
links.pop();

// Upstream fills series[1] with getVirtualData('2017') (Math.random per day of 2017); the identical
// deterministic array the native pane uses is inlined here instead, so the two panes are diffable.
const virtualData = \#(calendarGraphVirtualDataJSON);

option = {
  tooltip: {},
  calendar: {
    top: 'middle',
    left: 'center',
    orient: 'vertical',
    cellSize: 40,
    yearLabel: {
      margin: 50,
      fontSize: 30
    },
    dayLabel: {
      firstDay: 1,
      nameMap: 'cn'
    },
    monthLabel: {
      nameMap: 'cn',
      margin: 15,
      fontSize: 20,
      color: '#999'
    },
    range: ['2017-02', '2017-03-31']
  },
  visualMap: {
    min: 0,
    max: 1000,
    type: 'piecewise',
    left: 'center',
    bottom: 20,
    inRange: {
      color: ['#5291FF', '#C7DBFF']
    },
    seriesIndex: [1],
    orient: 'horizontal'
  },
  series: [
    {
      type: 'graph',
      edgeSymbol: ['none', 'arrow'],
      coordinateSystem: 'calendar',
      links: links,
      symbolSize: 15,
      calendarIndex: 0,
      itemStyle: {
        color: 'yellow',
        shadowBlur: 9,
        shadowOffsetX: 1.5,
        shadowOffsetY: 3,
        shadowColor: '#555'
      },
      lineStyle: {
        color: '#D10E00',
        width: 1,
        opacity: 1
      },
      data: graphData,
      z: 20
    },
    {
      type: 'heatmap',
      coordinateSystem: 'calendar',
      data: virtualData
    }
  ]
};
"""#,
        option: [
            "tooltip": [:] as [String: Any],
            "calendar": [
                "top": "middle",
                "left": "center",
                "orient": "vertical",
                "cellSize": 40.0,
                "yearLabel": [
                    "margin": 50.0,
                    "fontSize": 30.0
                ] as [String: Any],
                "dayLabel": [
                    "firstDay": 1.0,
                    "nameMap": "ZH"
                ] as [String: Any],
                "monthLabel": [
                    "nameMap": "ZH",
                    "margin": 15.0,
                    "fontSize": 20.0,
                    "color": "#999"
                ] as [String: Any],
                "range": ["2017-02", "2017-03-31"]
            ] as [String: Any],
            "visualMap": [
                "min": 0.0,
                "max": 1000.0,
                "type": "piecewise",
                "left": "center",
                "bottom": 20.0,
                "inRange": [
                    "color": ["#5291FF", "#C7DBFF"]
                ] as [String: Any],
                "seriesIndex": [1.0],
                "orient": "horizontal"
            ] as [String: Any],
            "series": [
                [
                    "type": "graph",
                    "edgeSymbol": ["none", "arrow"],
                    "coordinateSystem": "calendar",
                    "links": calendarGraphLinks,
                    "symbolSize": 15.0,
                    "calendarIndex": 0.0,
                    "itemStyle": [
                        "color": "yellow",
                        "shadowBlur": 9.0,
                        "shadowOffsetX": 1.5,
                        "shadowOffsetY": 3.0,
                        "shadowColor": "#555"
                    ] as [String: Any],
                    "lineStyle": [
                        "color": "#D10E00",
                        "width": 1.0,
                        "opacity": 1.0
                    ] as [String: Any],
                    "data": calendarGraphNodeData,
                    "z": 20.0
                ] as [String: Any],
                [
                    "type": "heatmap",
                    "coordinateSystem": "calendar",
                    "data": calendarGraphVirtualData
                ] as [String: Any]
            ]
        ])
}
