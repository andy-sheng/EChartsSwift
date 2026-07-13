// official-custom-profile — replica of https://echarts.apache.org/examples/zh/editor.html?c=custom-profile
// title: Profile / titleCN: 性能分析图
//
// A custom-series Gantt/flame-style profile: one `custom` series whose `renderItem` draws each record as
// a rect spanning [start, end] on a time-ish value xAxis, on the record's category row (yAxis), clipped to
// the grid by echarts.graphic.clipRectByRect. A slider + inside dataZoom (filterMode 'weakFilter') pan/zoom
// the time range.
//
// DEVIATIONS from the official source:
//   - DATA INLINED / DETERMINISTIC. Upstream generates its 30 records at load time from `Math.random()`
//     with `startTime = +new Date()`, so no two runs — and no two panes — would show the same chart. We
//     pre-generated ONE dataset with the same generator (3 categories x 10 records, random type/color,
//     random duration <= 10000ms, random <= 2000ms gap) off a fixed `startTime = 1700000000000`, and
//     inlined it verbatim into BOTH panes. The generator loop and the now-unused `types` table are
//     therefore dropped from webOptionJS; everything else (renderItem, option) is verbatim.
//   - NATIVE PANE OFF (nativeSupported: false) — but NOT because a custom series is unportable. EChartsKit
//     DOES port the custom series (Sources/EChartsKit/chart/custom) and CAN carry a Swift `renderItem`:
//     CustomView resolves `customSeries.getRenderItem() ?? getCustomSeries(subType)`, so the closure may
//     ride directly on the series option under the "renderItem" key (safe for THIS demo — WebPage.swift
//     only JSON-serializes `option` when `webOptionJS` is nil, and we set it), or be registered globally
//     via `registerCustomSeries` (what Demos/custom-basic.swift does — though that one already owns the
//     global "custom" key, so the per-series key is the right door here). The flag is false only because
//     the chart needs more than the closure and none of it could be verified (this port was audited under
//     a no-build constraint): `api.style()` is an explicitly DEFERRED best-effort stub in CustomView (it
//     returns just the raw item-visual bag, so the per-item colors / itemStyle.opacity are unproven), the
//     rects want `echarts.graphic.clipRectByRect` which is NOT ported to Swift at all (it would have to be
//     inlined here), and the chart leans on a category yAxis + `weakFilter` dataZoom driving a custom
//     series. Lighting the native pane up is a real, tracked follow-up — not an impossibility. Until it is
//     actually run, the flag stays honest and only the echarts.js reference pane renders.
//   - The upstream data's `itemStyle: { normal: { color } }` is the ECharts-3 nesting that real echarts
//     still flattens via backwardCompat; the Swift option writes the flattened `itemStyle: { color }`.
import Foundation

// The 30 pre-generated records (see DEVIATIONS): value = [categoryIndex, start, end, duration(ms)].
private let profileData: [[String: Any]] = [
    ["name": "Nodes", "value": [0.0, 1700000000000.0, 1700000001508.0, 1508.0],
     "itemStyle": ["color": "#75d874"] as [String: Any]],
    ["name": "JS Heap", "value": [0.0, 1700000002810.0, 1700000008169.0, 5359.0],
     "itemStyle": ["color": "#7b9ce1"] as [String: Any]],
    ["name": "JS Heap", "value": [0.0, 1700000008900.0, 1700000013974.0, 5074.0],
     "itemStyle": ["color": "#7b9ce1"] as [String: Any]],
    ["name": "Nodes", "value": [0.0, 1700000014049.0, 1700000014748.0, 699.0],
     "itemStyle": ["color": "#75d874"] as [String: Any]],
    ["name": "Nodes", "value": [0.0, 1700000014929.0, 1700000023198.0, 8269.0],
     "itemStyle": ["color": "#75d874"] as [String: Any]],
    ["name": "Documents", "value": [0.0, 1700000023446.0, 1700000029720.0, 6274.0],
     "itemStyle": ["color": "#bd6d6c"] as [String: Any]],
    ["name": "Listeners", "value": [0.0, 1700000031615.0, 1700000035582.0, 3967.0],
     "itemStyle": ["color": "#e0bc78"] as [String: Any]],
    ["name": "JS Heap", "value": [0.0, 1700000037535.0, 1700000046120.0, 8585.0],
     "itemStyle": ["color": "#7b9ce1"] as [String: Any]],
    ["name": "Documents", "value": [0.0, 1700000046699.0, 1700000047877.0, 1178.0],
     "itemStyle": ["color": "#bd6d6c"] as [String: Any]],
    ["name": "GPU Memory", "value": [0.0, 1700000048494.0, 1700000050301.0, 1807.0],
     "itemStyle": ["color": "#dc77dc"] as [String: Any]],
    ["name": "Listeners", "value": [1.0, 1700000000000.0, 1700000003724.0, 3724.0],
     "itemStyle": ["color": "#e0bc78"] as [String: Any]],
    ["name": "JS Heap", "value": [1.0, 1700000004819.0, 1700000005415.0, 596.0],
     "itemStyle": ["color": "#7b9ce1"] as [String: Any]],
    ["name": "Listeners", "value": [1.0, 1700000005827.0, 1700000010103.0, 4276.0],
     "itemStyle": ["color": "#e0bc78"] as [String: Any]],
    ["name": "Listeners", "value": [1.0, 1700000010731.0, 1700000015263.0, 4532.0],
     "itemStyle": ["color": "#e0bc78"] as [String: Any]],
    ["name": "GPU Memory", "value": [1.0, 1700000015863.0, 1700000022853.0, 6990.0],
     "itemStyle": ["color": "#dc77dc"] as [String: Any]],
    ["name": "Listeners", "value": [1.0, 1700000023341.0, 1700000028593.0, 5252.0],
     "itemStyle": ["color": "#e0bc78"] as [String: Any]],
    ["name": "GPU Memory", "value": [1.0, 1700000030343.0, 1700000033222.0, 2879.0],
     "itemStyle": ["color": "#dc77dc"] as [String: Any]],
    ["name": "Documents", "value": [1.0, 1700000035182.0, 1700000039363.0, 4181.0],
     "itemStyle": ["color": "#bd6d6c"] as [String: Any]],
    ["name": "Documents", "value": [1.0, 1700000040877.0, 1700000045767.0, 4890.0],
     "itemStyle": ["color": "#bd6d6c"] as [String: Any]],
    ["name": "Listeners", "value": [1.0, 1700000045845.0, 1700000053491.0, 7646.0],
     "itemStyle": ["color": "#e0bc78"] as [String: Any]],
    ["name": "GPU Memory", "value": [2.0, 1700000000000.0, 1700000003137.0, 3137.0],
     "itemStyle": ["color": "#dc77dc"] as [String: Any]],
    ["name": "Listeners", "value": [2.0, 1700000004528.0, 1700000010327.0, 5799.0],
     "itemStyle": ["color": "#e0bc78"] as [String: Any]],
    ["name": "GPU Memory", "value": [2.0, 1700000011239.0, 1700000020686.0, 9447.0],
     "itemStyle": ["color": "#dc77dc"] as [String: Any]],
    ["name": "Listeners", "value": [2.0, 1700000021634.0, 1700000022241.0, 607.0],
     "itemStyle": ["color": "#e0bc78"] as [String: Any]],
    ["name": "Listeners", "value": [2.0, 1700000023644.0, 1700000033575.0, 9931.0],
     "itemStyle": ["color": "#e0bc78"] as [String: Any]],
    ["name": "Documents", "value": [2.0, 1700000035219.0, 1700000039077.0, 3858.0],
     "itemStyle": ["color": "#bd6d6c"] as [String: Any]],
    ["name": "JS Heap", "value": [2.0, 1700000040414.0, 1700000045031.0, 4617.0],
     "itemStyle": ["color": "#7b9ce1"] as [String: Any]],
    ["name": "Documents", "value": [2.0, 1700000045367.0, 1700000045957.0, 590.0],
     "itemStyle": ["color": "#bd6d6c"] as [String: Any]],
    ["name": "Documents", "value": [2.0, 1700000047493.0, 1700000049969.0, 2476.0],
     "itemStyle": ["color": "#bd6d6c"] as [String: Any]],
    ["name": "GPU Memory", "value": [2.0, 1700000050751.0, 1700000051557.0, 806.0],
     "itemStyle": ["color": "#dc77dc"] as [String: Any]]
]

// The fixed `startTime` the records (and xAxis.min) are anchored to — upstream's `+new Date()`.
// (Named `profile*`, not the JS's bare `startTime`/`categories`: these are top-level file-scoped symbols,
// and bare generic names invite a shadowing/collision trap with the other demo files in this directory.)
private let profileStartTime: Double = 1700000000000.0

private let profileCategories: [String] = ["categoryA", "categoryB", "categoryC"]

extension EChartsDemoRegistry {
    static let official_custom_profile = EChartsDemo(
        name: "official-custom-profile", category: "custom",
        summary: "性能分析图 — Profile",
        width: 720, height: 460,
        nativeSupported: false,
        collection: .official,
        webOptionJS: #"""
var startTime = 1700000000000;
var categories = ['categoryA', 'categoryB', 'categoryC'];

// Data pre-generated from the upstream Math.random() generator (see the file header) and inlined so
// both panes — and successive snapshots — show the SAME chart.
var data = [
  { name: 'Nodes', value: [0, 1700000000000, 1700000001508, 1508], itemStyle: { normal: { color: '#75d874' } } },
  { name: 'JS Heap', value: [0, 1700000002810, 1700000008169, 5359], itemStyle: { normal: { color: '#7b9ce1' } } },
  { name: 'JS Heap', value: [0, 1700000008900, 1700000013974, 5074], itemStyle: { normal: { color: '#7b9ce1' } } },
  { name: 'Nodes', value: [0, 1700000014049, 1700000014748, 699], itemStyle: { normal: { color: '#75d874' } } },
  { name: 'Nodes', value: [0, 1700000014929, 1700000023198, 8269], itemStyle: { normal: { color: '#75d874' } } },
  { name: 'Documents', value: [0, 1700000023446, 1700000029720, 6274], itemStyle: { normal: { color: '#bd6d6c' } } },
  { name: 'Listeners', value: [0, 1700000031615, 1700000035582, 3967], itemStyle: { normal: { color: '#e0bc78' } } },
  { name: 'JS Heap', value: [0, 1700000037535, 1700000046120, 8585], itemStyle: { normal: { color: '#7b9ce1' } } },
  { name: 'Documents', value: [0, 1700000046699, 1700000047877, 1178], itemStyle: { normal: { color: '#bd6d6c' } } },
  { name: 'GPU Memory', value: [0, 1700000048494, 1700000050301, 1807], itemStyle: { normal: { color: '#dc77dc' } } },
  { name: 'Listeners', value: [1, 1700000000000, 1700000003724, 3724], itemStyle: { normal: { color: '#e0bc78' } } },
  { name: 'JS Heap', value: [1, 1700000004819, 1700000005415, 596], itemStyle: { normal: { color: '#7b9ce1' } } },
  { name: 'Listeners', value: [1, 1700000005827, 1700000010103, 4276], itemStyle: { normal: { color: '#e0bc78' } } },
  { name: 'Listeners', value: [1, 1700000010731, 1700000015263, 4532], itemStyle: { normal: { color: '#e0bc78' } } },
  { name: 'GPU Memory', value: [1, 1700000015863, 1700000022853, 6990], itemStyle: { normal: { color: '#dc77dc' } } },
  { name: 'Listeners', value: [1, 1700000023341, 1700000028593, 5252], itemStyle: { normal: { color: '#e0bc78' } } },
  { name: 'GPU Memory', value: [1, 1700000030343, 1700000033222, 2879], itemStyle: { normal: { color: '#dc77dc' } } },
  { name: 'Documents', value: [1, 1700000035182, 1700000039363, 4181], itemStyle: { normal: { color: '#bd6d6c' } } },
  { name: 'Documents', value: [1, 1700000040877, 1700000045767, 4890], itemStyle: { normal: { color: '#bd6d6c' } } },
  { name: 'Listeners', value: [1, 1700000045845, 1700000053491, 7646], itemStyle: { normal: { color: '#e0bc78' } } },
  { name: 'GPU Memory', value: [2, 1700000000000, 1700000003137, 3137], itemStyle: { normal: { color: '#dc77dc' } } },
  { name: 'Listeners', value: [2, 1700000004528, 1700000010327, 5799], itemStyle: { normal: { color: '#e0bc78' } } },
  { name: 'GPU Memory', value: [2, 1700000011239, 1700000020686, 9447], itemStyle: { normal: { color: '#dc77dc' } } },
  { name: 'Listeners', value: [2, 1700000021634, 1700000022241, 607], itemStyle: { normal: { color: '#e0bc78' } } },
  { name: 'Listeners', value: [2, 1700000023644, 1700000033575, 9931], itemStyle: { normal: { color: '#e0bc78' } } },
  { name: 'Documents', value: [2, 1700000035219, 1700000039077, 3858], itemStyle: { normal: { color: '#bd6d6c' } } },
  { name: 'JS Heap', value: [2, 1700000040414, 1700000045031, 4617], itemStyle: { normal: { color: '#7b9ce1' } } },
  { name: 'Documents', value: [2, 1700000045367, 1700000045957, 590], itemStyle: { normal: { color: '#bd6d6c' } } },
  { name: 'Documents', value: [2, 1700000047493, 1700000049969, 2476], itemStyle: { normal: { color: '#bd6d6c' } } },
  { name: 'GPU Memory', value: [2, 1700000050751, 1700000051557, 806], itemStyle: { normal: { color: '#dc77dc' } } }
];

function renderItem(params, api) {
  var categoryIndex = api.value(0);
  var start = api.coord([api.value(1), categoryIndex]);
  var end = api.coord([api.value(2), categoryIndex]);
  var height = api.size([0, 1])[1] * 0.6;

  var rectShape = echarts.graphic.clipRectByRect(
    {
      x: start[0],
      y: start[1] - height / 2,
      width: end[0] - start[0],
      height: height
    },
    {
      x: params.coordSys.x,
      y: params.coordSys.y,
      width: params.coordSys.width,
      height: params.coordSys.height
    }
  );

  return (
    rectShape && {
      type: 'rect',
      transition: ['shape'],
      shape: rectShape,
      style: api.style()
    }
  );
}

option = {
  tooltip: {
    formatter: function (params) {
      return params.marker + params.name + ': ' + params.value[3] + ' ms';
    }
  },
  title: {
    text: 'Profile',
    left: 'center'
  },
  dataZoom: [
    {
      type: 'slider',
      filterMode: 'weakFilter',
      showDataShadow: false,
      top: 400,
      labelFormatter: ''
    },
    {
      type: 'inside',
      filterMode: 'weakFilter'
    }
  ],
  grid: {
    height: 300
  },
  xAxis: {
    min: startTime,
    scale: true,
    axisLabel: {
      formatter: function (val) {
        return Math.max(0, val - startTime) + ' ms';
      }
    }
  },
  yAxis: {
    data: categories
  },
  series: [
    {
      type: 'custom',
      renderItem: renderItem,
      itemStyle: {
        opacity: 0.8
      },
      encode: {
        x: [1, 2],
        y: 0
      },
      data: data
    }
  ]
};
"""#,
        option: [
            // PORT-NOTE: tooltip.formatter omitted — JS closure returning
            // `params.marker + params.name + ': ' + params.value[3] + ' ms'` (the record's duration).
            "tooltip": [:] as [String: Any],
            "title": [
                "text": "Profile",
                "left": "center"
            ] as [String: Any],
            "dataZoom": [
                [
                    "type": "slider",
                    "filterMode": "weakFilter",
                    "showDataShadow": false,
                    "top": 400.0,
                    "labelFormatter": ""
                ] as [String: Any],
                [
                    "type": "inside",
                    "filterMode": "weakFilter"
                ] as [String: Any]
            ],
            "grid": [
                "height": 300.0
            ] as [String: Any],
            "xAxis": [
                "min": profileStartTime,
                "scale": true,
                // PORT-NOTE: xAxis.axisLabel.formatter omitted — JS closure rendering each tick as
                // `Math.max(0, val - startTime) + ' ms'` (elapsed ms since startTime). Without it the
                // ticks would print the raw epoch millisecond values.
                "axisLabel": [:] as [String: Any]
            ] as [String: Any],
            "yAxis": [
                "data": profileCategories
            ] as [String: Any],
            "series": [
                [
                    "type": "custom",
                    // PORT-NOTE: series.renderItem omitted — the JS closure that IS this chart: it maps
                    // each datum to grid pixels (api.coord of [start, categoryIndex] and [end, ...]),
                    // takes 60% of a category band's height (api.size([0,1])[1] * 0.6), clips that rect to
                    // the coordSys via echarts.graphic.clipRectByRect, and returns a `rect` element with
                    // `transition: ['shape']` and `style: api.style()`.
                    // EChartsKit CAN express this (a `CustomSeriesRenderItem` closure under this "renderItem"
                    // key, or registerCustomSeries) — see the NATIVE PANE OFF note in the header for why the
                    // native pane is nonetheless left dark. This is a deliberate, unverified gap, not a
                    // framework limit.
                    "itemStyle": [
                        "opacity": 0.8
                    ] as [String: Any],
                    "encode": [
                        "x": [1.0, 2.0],
                        "y": 0.0
                    ] as [String: Any],
                    "data": profileData as [Any]
                ] as [String: Any]
            ]
        ])
}
