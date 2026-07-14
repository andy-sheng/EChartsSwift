// official-pie-parliament-transition — replica of
// https://echarts.apache.org/examples/zh/editor.html?c=pie-parliament-transition
// title: Transition of Parliament and Pie Chart / titleCN: 自定义议会图与饼图过渡动画
// Six parties (A…F) drawn two ways, flipped every 2s: a plain `pie` and a `custom` series whose
// renderItem lays each party's seats out as a ring of circles (a parliament/hemicycle chart). Both
// series carry `id: 'distribution'` + `universalTransition: true` + `animationDurationUpdate: 1000`,
// so echarts MORPHS the pie sectors into the seat dots and back.
//
// THE 2s TOGGLE IS PORTED, on both panes. The web pane runs the example's own
// `setInterval(function () { myChart.setOption(currentOption); }, 2000)` verbatim; the native pane
// replays the same timeline through `drive` (see EChartsDemoChart), with `notMerge: false` because
// upstream calls the plain one-arg `setOption` (a MERGE), not `setOption(opt, true)`. The still-frame
// PNG paths capture the first frame — the pie — and neuter the timer, so a snapshot stays deterministic.
//
// DEVIATIONS from the official source:
//   - renderItem IS PORTED, natively. It is the one closure the demo cannot live without (it IS the
//     parliament half of the chart), and the port's CustomSeriesModel resolves
//     `get('renderItem') as? CustomSeriesRenderItem` straight off the option bag — so
//     `officialPieParliamentRenderItem` below is a line-by-line Swift port of the example's closure
//     (angles table, `parliamentLayout`, the group-of-circles return). It rides in `option` rather than
//     the global `registerCustomSeries` registry, which is keyed by subType ("custom") and is already
//     claimed by the port-tab `custom-basic` demo. Legal here only because `webOptionJS` is set:
//     WebPage.swift then never JSON-serializes `demo.option`, so a closure in the bag is safe.
//   - `coordinateSystem: undefined` → `"coordinateSystem": "none"`. Upstream relies on a JS quirk (a key
//     present with value `undefined` blocks echarts' `merge` from filling in the `cartesian2d` default),
//     which a Swift `[String: Any]` cannot express: omitting the key would hand the series a cartesian
//     with no axes. `'none'` is the option's own documented spelling for "do not depend on a coord sys"
//     (CustomSeries.swift defaultOption: `"coordinateSystem": "cartesian2d", // Can be set as 'none'`)
//     and resolves to the same nil coordSys.
//   - Upstream's parliament option writes `series` as a bare object (`series: { type: 'custom', ... }`);
//     echarts normalizes it to a one-element array. The Swift option carries the array form directly.
//   - The TS type annotations (`const pieOption: echarts.EChartsOption`, `let angles: number[]`, the
//     `parliamentLayout(startAngle: number, ...)` params, the trailing `as echarts.EChartsOption`) and
//     the trailing `export {}` are dropped from webOptionJS — a classic script cannot parse them.
//     Nothing else is touched; the IIFE, the layout math and the setInterval run verbatim.
import Foundation
import EChartsKit

// MARK: - the example's module-scope constants

private let officialPieParliamentData: [[String: Any]] = [
    ["value": 800.0, "name": "A"],
    ["value": 635.0, "name": "B"],
    ["value": 580.0, "name": "C"],
    ["value": 484.0, "name": "D"],
    ["value": 300.0, "name": "E"],
    ["value": 200.0, "name": "F"]
]

// echarts 6's default colour palette, spelled out so the custom series' dots can be filled by hand
// with the same colours the pie's sectors get from the theme.
private let officialPieParliamentPalette: [String] = [
    "#5070dd", "#b6d634", "#505372", "#ff994d", "#0ca8df",
    "#ffd10a", "#fb628b", "#785db0", "#3fbe95"
]

private let officialPieParliamentRadius: [String] = ["30%", "80%"]

/// `parseFloat(radius[i]) / 100` — the same two fractions renderItem derives from the strings above.
private let officialPieParliamentRadiusFraction: [Double] = officialPieParliamentRadius.map {
    (Double($0.replacingOccurrences(of: "%", with: "")) ?? 0) / 100
}

// MARK: - the parliament option's IIFE, ported

/// Sector boundaries, cumulative from -π/2, one per datum plus the closing angle — upstream's `angles`.
private let officialPieParliamentAngles: [Double] = {
    let sum = officialPieParliamentData.reduce(0.0) { $0 + (($1["value"] as? Double) ?? 0) }
    let startAngle = -Double.pi / 2
    var angles: [Double] = []
    var curAngle = startAngle
    for item in officialPieParliamentData {
        angles.append(curAngle)
        curAngle += (((item["value"] as? Double) ?? 0) / sum) * Double.pi * 2
    }
    angles.append(startAngle + Double.pi * 2)
    return angles
}()

/// Port of the example's `parliamentLayout`: walk concentric rings from r0 to r1, and on each ring
/// emit one seat every `newSize` arc-length between `startAngle` and `endAngle`.
private func officialPieParliamentLayout(
    _ startAngle: Double, _ endAngle: Double, _ totalAngle: Double,
    _ r0: Double, _ r1: Double, _ size: Double
) -> [[Double]] {
    let rowsCount = Int(((r1 - r0) / size).rounded(.up))   // Math.ceil((r1 - r0) / size)
    var points: [[Double]] = []

    var r = r0
    for _ in 0..<max(0, rowsCount) {
        // Recalculate size. (`totalAngle * r / size` is always positive here, so JS's
        // Math.round = floor(x + 0.5) and Swift's ties-away-from-zero agree.)
        let totalRingSeatsNumber = ((totalAngle * r) / size).rounded(.toNearestOrAwayFromZero)
        // JS would get newSize = Infinity here and the inner `k < NaN` test would be false; skipping
        // the ring outright is the same no-op without the NaN detour.
        guard totalRingSeatsNumber >= 1 else { r += size; continue }
        let newSize = (totalAngle * r) / totalRingSeatsNumber

        var k = ((startAngle * r) / newSize).rounded(.down) * newSize
        let limit = ((endAngle * r) / newSize).rounded(.down) * newSize - 1e-6
        while k < limit {
            let angle = k / r
            points.append([cos(angle) * r, sin(angle) * r])
            k += newSize
        }

        r += size
    }

    return points
}

/// The example's `renderItem`, as a Swift closure. Typed EXACTLY `CustomSeriesRenderItem` so
/// `CustomSeriesModel.getRenderItem()`'s `get("renderItem") as? CustomSeriesRenderItem` cast holds.
private let officialPieParliamentRenderItem: CustomSeriesRenderItem = { params, api in
    let idx = Int(params.dataIndex)
    guard idx >= 0, idx + 1 < officialPieParliamentAngles.count else { return nil }

    let viewSize = min(api.getWidth(), api.getHeight())
    let r0 = (officialPieParliamentRadiusFraction[0] * viewSize) / 2
    let r1 = (officialPieParliamentRadiusFraction[1] * viewSize) / 2
    let cx = api.getWidth() * 0.5
    let cy = api.getHeight() * 0.5
    let size = viewSize / 50

    let points = officialPieParliamentLayout(
        officialPieParliamentAngles[idx],
        officialPieParliamentAngles[idx + 1],
        Double.pi * 2,
        r0, r1, size + 3
    )

    let fill = officialPieParliamentPalette[idx % officialPieParliamentPalette.count]
    let children: [Any] = points.map { pt in
        [
            "type": "circle",
            "autoBatch": true,   // a zrender batching hint; the port ignores it, harmlessly
            "shape": [
                "cx": cx + pt[0],
                "cy": cy + pt[1],
                "r": size / 2
            ] as [String: Any],
            "style": ["fill": fill] as [String: Any]
        ] as [String: Any]
    }
    return ["type": "group", "children": children] as [String: Any]
}

extension EChartsDemoRegistry {
    static let official_pie_parliament_transition = EChartsDemo(
        name: "official-pie-parliament-transition", category: "custom",
        summary: "自定义议会图与饼图过渡动画 — Transition of Parliament and Pie Chart",
        width: 720, height: 460,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
const data = [
  { value: 800, name: 'A' },
  { value: 635, name: 'B' },
  { value: 580, name: 'C' },
  { value: 484, name: 'D' },
  { value: 300, name: 'E' },
  { value: 200, name: 'F' }
];

const defaultPalette = [
  '#5070dd',
  '#b6d634',
  '#505372',
  '#ff994d',
  '#0ca8df',
  '#ffd10a',
  '#fb628b',
  '#785db0',
  '#3fbe95'
];

const radius = ['30%', '80%'];

const pieOption = {
  series: [
    {
      type: 'pie',
      id: 'distribution',
      radius: radius,
      label: {
        show: false
      },
      universalTransition: true,
      animationDurationUpdate: 1000,
      data: data
    }
  ]
};

const parliamentOption = (function () {
  let sum = data.reduce(function (sum, cur) {
    return sum + cur.value;
  }, 0);

  let angles = [];
  let startAngle = -Math.PI / 2;
  let curAngle = startAngle;
  data.forEach(function (item) {
    angles.push(curAngle);
    curAngle += (item.value / sum) * Math.PI * 2;
  });
  angles.push(startAngle + Math.PI * 2);
  function parliamentLayout(startAngle, endAngle, totalAngle, r0, r1, size) {
    let rowsCount = Math.ceil((r1 - r0) / size);
    let points = [];

    let r = r0;
    for (let i = 0; i < rowsCount; i++) {
      // Recalculate size
      let totalRingSeatsNumber = Math.round((totalAngle * r) / size);
      let newSize = (totalAngle * r) / totalRingSeatsNumber;
      for (
        let k = Math.floor((startAngle * r) / newSize) * newSize;
        k < Math.floor((endAngle * r) / newSize) * newSize - 1e-6;
        k += newSize
      ) {
        let angle = k / r;
        let x = Math.cos(angle) * r;
        let y = Math.sin(angle) * r;
        points.push([x, y]);
      }

      r += size;
    }

    return points;
  }
  return {
    series: {
      type: 'custom',
      id: 'distribution',
      data: data,
      coordinateSystem: undefined,
      universalTransition: true,
      animationDurationUpdate: 1000,
      renderItem: function (params, api) {
        var idx = params.dataIndex;
        var viewSize = Math.min(api.getWidth(), api.getHeight());
        var r0 = ((parseFloat(radius[0]) / 100) * viewSize) / 2;
        var r1 = ((parseFloat(radius[1]) / 100) * viewSize) / 2;
        var cx = api.getWidth() * 0.5;
        var cy = api.getHeight() * 0.5;
        var size = viewSize / 50;

        var points = parliamentLayout(
          angles[idx],
          angles[idx + 1],
          Math.PI * 2,
          r0,
          r1,
          size + 3
        );

        return {
          type: 'group',
          children: points.map(function (pt) {
            return {
              type: 'circle',
              autoBatch: true,
              shape: {
                cx: cx + pt[0],
                cy: cy + pt[1],
                r: size / 2
              },
              style: {
                fill: defaultPalette[idx % defaultPalette.length]
              }
            };
          })
        };
      }
    }
  };
})();

let currentOption = (option = pieOption);

setInterval(function () {
  currentOption = currentOption === pieOption ? parliamentOption : pieOption;
  myChart.setOption(currentOption);
}, 2000);
"""#,
        // The native half of the same timeline: flip the two options every 2s. `notMerge: false` is
        // upstream's one-arg `myChart.setOption(currentOption)` — a MERGE, which is what lets the two
        // series match on `id: 'distribution'` and universal-transition into each other.
        drive: { chart in
            // Upstream keeps `currentOption` and compares by identity; a Bool says the same thing.
            var showingPie = true
            chart.every(2) {
                showingPie.toggle()
                chart.setOption(showingPie ? officialPieParliamentPieOption
                                           : officialPieParliamentParliamentOption,
                                notMerge: false)
            }
        },
        // Upstream's `let currentOption = (option = pieOption)` — the pie is the first frame.
        option: officialPieParliamentPieOption)
}

// MARK: - the two halves of the transition, as Swift options

private let officialPieParliamentPieOption: [String: Any] = [
    "series": [
        [
            "type": "pie",
            "id": "distribution",
            "radius": officialPieParliamentRadius,
            "label": ["show": false] as [String: Any],
            "universalTransition": true,
            "animationDurationUpdate": 1000.0,
            "data": officialPieParliamentData as [Any]
        ] as [String: Any]
    ]
]

private let officialPieParliamentParliamentOption: [String: Any] = [
    "series": [
        [
            "type": "custom",
            "id": "distribution",
            "data": officialPieParliamentData as [Any],
            // Upstream: `coordinateSystem: undefined` (see the header DEVIATION).
            "coordinateSystem": "none",
            "universalTransition": true,
            "animationDurationUpdate": 1000.0,
            "renderItem": officialPieParliamentRenderItem
        ] as [String: Any]
    ]
]
