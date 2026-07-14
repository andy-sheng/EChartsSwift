// official-custom-cartesian-polygon — replica of
// https://echarts.apache.org/examples/zh/editor.html?c=custom-cartesian-polygon
// title: Custom Cartesian Polygon / titleCN: 自定义多边形图
// Seven random [x, y] points on a plain value/value cartesian, drawn as ONE closed polygon by a
// `custom` series: renderItem short-circuits after the first datum (`params.context.rendered`), maps
// every row through `api.coord` and returns a single `polygon` element filled with the series' visual
// color and stroked with `echarts.color.lift(color, 0.1)`. `clip: true` plus a slider + inside dataZoom
// pair with `filterMode: 'none'` (the polygon keeps all its points while zooming and is clipped by the
// grid instead of being re-tessellated), and `transition: ['shape']` tweens the shape across zooms.
//
// DEVIATIONS from the official source:
//   1. RANDOM DATA, FIXED ON THE NATIVE SIDE: the example seeds `data` with 7 × `Math.random()` on every
//      load. The web pane keeps that loop VERBATIM (it is the example). A Swift `[String: Any]` option is
//      a static literal, so the native `option` carries one fixed draw of the same shape/ranges
//      (x ∈ [0,100], y ∈ [0,400]) — see `customCartesianPolygonData`. The two panes therefore hold
//      different point sets; that is the example's own nondeterminism, not a simplification. Compare the
//      panes for the FORM (one closed, self-intersecting polygon, clipped by the grid, axes auto-scaled
//      to the points, dataZoom + legend + tooltip), not for per-vertex values.
//   2. THE "RENDER ONCE" LATCH IS SPELLED DIFFERENTLY NATIVELY. Upstream gates the closure on
//      `params.context.rendered`, relying on one `context` object being SHARED across the render round.
//      The port rebuilds `CustomSeriesRenderItemParams` (a struct) per datum, so a `[String: Any]`
//      context cannot carry state between calls — the framework says so itself at CustomView.swift:796
//      ("the value-type `[:]` copies per datum, so that sharing is lost"). `dataIndexInside == 0` is the
//      exact behavioural equivalent: renderItem runs once per datum in ascending order, so call 0 is the
//      one upstream lets through and calls 1…6 are the ones it suppresses. Same one polygon, same pass.
//   3. `transition: ['shape']` is kept on the returned element for fidelity, but CustomView's transition
//      machinery is DEFERRED (CustomView.swift:522 — the group is rebuilt each render), so the native
//      polygon SNAPS between dataZoom frames where the web pane tweens its shape. Geometry is identical;
//      only the interpolation between frames is missing.
//   4. The TypeScript annotations (`const data: number[][]`, `let points: number[][]`, `as string`) and the
//      trailing `export {};` are dropped from the web JS — a classic script cannot parse them.
//   5. NOTHING ELSE. `renderItem` IS ported natively (customCartesianPolygonRenderItem, below), so BOTH
//      panes draw the actual chart.
//
// WHY THE NATIVE renderItem IS MANDATORY (do not "simplify" it back out):
//   CustomView resolves the callback as `customSeries.getRenderItem() ?? getCustomSeries(subType)`
//   (CustomView.swift:739) — a Swift [String: Any] CAN carry the closure. Omitting it would NOT leave an
//   inert series: the `?? getCustomSeries("custom")` fallback reaches the GLOBAL registry, where
//   Demos/custom-basic.swift registers ITS OWN bar renderItem under the "custom" subType, and the native
//   pane would silently draw THAT against this demo's [x, y] rows — a wrong chart, which is worse than a
//   missing one. Carrying the closure is safe because WebPage.swift only JSON-serializes `option` when
//   `webOptionJS` is nil, and we set `webOptionJS`.
import Foundation
import ZRenderKit
import EChartsKit

// One fixed draw of the example's `Math.random()` seeding: 7 rows of [x ∈ 0…100, y ∈ 0…400], deliberately
// unsorted in x (as the random original is), so the polygon self-intersects the same way.
private let customCartesianPolygonData: [[Double]] = [
    [62.4, 118.7],
    [17.9, 342.1],
    [88.3, 76.4],
    [41.2, 289.6],
    [95.7, 213.9],
    [8.6, 47.2],
    [53.8, 371.5]
]

// MARK: - the upstream renderItem, ported

/// The official `renderItem`, statement for statement. Typed EXACTLY `CustomSeriesRenderItem` so
/// CustomView's `get("renderItem") as? CustomSeriesRenderItem` cast holds (see header).
///
/// The whole chart is ONE element: the closure fires once per datum, short-circuits on every call but the
/// first, and that first call projects ALL SEVEN rows through `api.coord` into a single closed `polygon`.
/// Note it walks `customCartesianPolygonData` directly rather than `api.value(...)` — upstream likewise
/// closes over its module-level `data`, not the per-datum accessor.
private let customCartesianPolygonRenderItem: CustomSeriesRenderItem = { params, api in
    // upstream: if (params.context.rendered) { return; }
    //           params.context.rendered = true;
    //   See DEVIATION 2: `params.context` cannot latch across datums in the port, so gate on the datum
    //   index instead. Identical effect — emit the polygon on the first call of the round, nothing after.
    guard params.dataIndexInside == 0 else { return nil }

    // upstream: let points = []; for (i < data.length) points.push(api.coord(data[i]));
    var points: [[Double]] = []
    points.reserveCapacity(customCartesianPolygonData.count)
    for row in customCartesianPolygonData {
        points.append(api.coord([row[0], row[1]], nil))
    }

    // upstream: let color = api.visual('color');
    let colorVisual = api.visual("color", nil)

    // upstream: api.style({ fill: color, stroke: echarts.color.lift(color, 0.1) })
    //   `echarts.color.lift` is ZRenderKit's `color.lift` (Tool/color.swift) — same function, same
    //   signature. Qualified `ZRenderKit.color` because the enum's name collides with the local `color`
    //   the upstream statement above would otherwise introduce. `lift` is String-only and returns nil on
    //   an unparseable color, so both keys are written defensively rather than force-unwrapped.
    var userProps: [String: Any] = [:]
    if let c = colorVisual { userProps["fill"] = c }
    if let c = colorVisual as? String, let lifted = ZRenderKit.color.lift(c, 0.1) {
        userProps["stroke"] = lifted
    }

    return [
        "type": "polygon",
        // Kept for fidelity; CustomView's transition machinery is DEFERRED (see DEVIATION 3).
        "transition": ["shape"],
        "shape": [
            "points": points
        ] as [String: Any],
        "style": api.style(userProps, nil)
    ] as [String: Any]
}

extension EChartsDemoRegistry {
    static let official_custom_cartesian_polygon = EChartsDemo(
        name: "official-custom-cartesian-polygon", category: "custom",
        summary: "自定义多边形图 — Custom Cartesian Polygon",
        width: 720, height: 460,
        nativeSupported: true,    // renderItem IS the chart, and it IS ported — see header
        collection: .official,
        webOptionJS: #"""
const data = [];
const dataCount = 7;
for (let i = 0; i < dataCount; i++) {
  data.push([
    echarts.number.round(Math.random() * 100),
    echarts.number.round(Math.random() * 400)
  ]);
}

option = {
  tooltip: {
    trigger: 'axis'
  },
  legend: {
    data: ['bar', 'error']
  },
  dataZoom: [
    {
      type: 'slider',
      filterMode: 'none'
    },
    {
      type: 'inside',
      filterMode: 'none'
    }
  ],
  xAxis: {},
  yAxis: {},
  series: [
    {
      type: 'custom',
      renderItem: function (params, api) {
        if (params.context.rendered) {
          return;
        }
        params.context.rendered = true;

        let points = [];
        for (let i = 0; i < data.length; i++) {
          points.push(api.coord(data[i]));
        }
        let color = api.visual('color');

        return {
          type: 'polygon',
          transition: ['shape'],
          shape: {
            points: points
          },
          style: api.style({
            fill: color,
            stroke: echarts.color.lift(color, 0.1)
          })
        };
      },
      clip: true,
      data: data
    }
  ]
};
"""#,
        option: [
            "tooltip": [
                "trigger": "axis"
            ] as [String: Any],
            "legend": [
                // Upstream names two series ('bar', 'error') that the option never defines; kept verbatim.
                "data": ["bar", "error"]
            ] as [String: Any],
            "dataZoom": [
                [
                    "type": "slider",
                    "filterMode": "none"
                ] as [String: Any],
                [
                    "type": "inside",
                    "filterMode": "none"
                ] as [String: Any]
            ],
            "xAxis": [:] as [String: Any],
            "yAxis": [:] as [String: Any],
            "series": [
                [
                    "type": "custom",
                    // The per-series closure (see header: this key is also what keeps the global
                    // custom-series registry's `getCustomSeries("custom")` fallback — custom-basic.swift's
                    // bar renderItem — from hijacking this chart).
                    "renderItem": customCartesianPolygonRenderItem,
                    "clip": true,
                    "data": customCartesianPolygonData
                ] as [String: Any]
            ]
        ])
}
