// official-bar-drilldown — replica of https://echarts.apache.org/examples/zh/editor.html?c=bar-drilldown
// title: Bar Chart Drilldown Animation / titleCN: 柱状图下钻动画
// Three top-level bars (Animals / Fruits / Cars), each datum tagged with a `groupId`; clicking one
// re-setOptions the chart to that group's children, and `universalTransition: { divideShape: 'clone' }`
// morphs the clicked bar into the child bars.
//
// DEVIATIONS from the official source:
//   - The drilldown is an INTERACTION (`myChart.on('click', ...)` → a second `setOption` with the
//     sub-group data + a "Back" graphic text). The gallery renders ONE static frame with animation
//     forced off, so no click ever fires and the transition cannot be captured: both panes port the
//     INITIAL state only — the top-level 3-bar option. The click handler is therefore dropped from
//     webOptionJS (it would also throw: WebPage.swift creates `myChart` *after* the option script
//     runs, so `myChart` is still undefined there). `drilldownData` is kept verbatim as documentation
//     of the levels the example would drill into.
//   - TypeScript-only syntax removed for the JS pane: the `interface DataItem` declaration, the
//     `as DataItem[]` cast and the trailing `export {}` (a bare export is a SyntaxError in a classic
//     script and would blank the whole page).
//   - `universalTransition` / `animationDurationUpdate` / `dataGroupId` are carried through to both
//     panes unchanged even though a single static frame never exercises them.
extension EChartsDemoRegistry {
    static let official_bar_drilldown = EChartsDemo(
        name: "official-bar-drilldown", category: "bar",
        summary: "柱状图下钻动画 — Bar Chart Drilldown Animation",
        width: 640, height: 420,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
option = {
  xAxis: {
    data: ['Animals', 'Fruits', 'Cars']
  },
  yAxis: {},
  dataGroupId: '',
  animationDurationUpdate: 500,
  series: {
    type: 'bar',
    id: 'sales',
    data: [
      {
        value: 5,
        groupId: 'animals'
      },
      {
        value: 2,
        groupId: 'fruits'
      },
      {
        value: 4,
        groupId: 'cars'
      }
    ],
    universalTransition: {
      enabled: true,
      divideShape: 'clone'
    }
  }
};

// The children each top-level bar drills down into. Upstream a `myChart.on('click', ...)` handler
// looks the clicked bar's `groupId` up here and re-setOptions; the gallery's single static frame has
// no click, so the handler is omitted (see the header) and this stays as reference data.
const drilldownData = [
  {
    dataGroupId: 'animals',
    data: [
      ['Cats', 4],
      ['Dogs', 2],
      ['Cows', 1],
      ['Sheep', 2],
      ['Pigs', 1]
    ]
  },
  {
    dataGroupId: 'fruits',
    data: [
      ['Apples', 4],
      ['Oranges', 2]
    ]
  },
  {
    dataGroupId: 'cars',
    data: [
      ['Toyota', 4],
      ['Opel', 2],
      ['Volkswagen', 2]
    ]
  }
];
"""#,
        option: [
            "xAxis": [
                "data": ["Animals", "Fruits", "Cars"]
            ] as [String: Any],
            "yAxis": [:] as [String: Any],
            "dataGroupId": "",
            "animationDurationUpdate": 500.0,
            // Upstream declares `series` as a single object (not an array); echarts normalizes it, and
            // so does the port (GlobalModel's normalizeToComponentOptionList), so it is kept as-is.
            "series": [
                "type": "bar",
                "id": "sales",
                "data": barDrilldownTopLevelData,
                "universalTransition": [
                    "enabled": true,
                    "divideShape": "clone"
                ] as [String: Any]
            ] as [String: Any]
            // the click-driven drilldown `setOption` (and its "Back" `graphic` text with an
            // `onclick` closure) has no place in a static option — see the header DEVIATIONS.
        ])
}

// The three top-level bars. `groupId` is what the upstream click handler matches against
// `drilldownData[].dataGroupId`; it is inert in a static frame but kept for fidelity.
private let barDrilldownTopLevelData: [[String: Any]] = [
    ["value": 5.0, "groupId": "animals"],
    ["value": 2.0, "groupId": "fruits"],
    ["value": 4.0, "groupId": "cars"]
]
