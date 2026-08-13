// official-graph-force2 — replica of https://echarts.apache.org/examples/zh/editor.html?c=graph-force2
// title: Force Layout / titleCN: 力引导布局
// A 4x4 grid of 16 independent force-layout `graph` series, each laid out in its own 25%x25% cell:
// series N is a ring of N+2 nodes (2..17) wired i -> (i+1) % count, so the force layout settles each
// one into a polygon. `animation: false` and force { repulsion: 60, edgeLength: 2 } on every series.
// DEVIATIONS:
//   - web pane: the example's JS verbatim, minus the TypeScript parameter annotations
//     (`count: number` -> `count`) and the trailing `export {};` (a bare export is a SyntaxError in a
//     classic script). The two builder functions and the `datas` loop still run in the page.
//   - native pane: the same 16 series, but built by Swift (`graphForce2Series`) instead of the JS
//     `datas.map(...)`. Same values, no closure in the option.
//   - no data fetch, no timers, no formatters in the source, so there is nothing else to strip. No
//     `drive` either, and that is correct rather than a simplification: the settling you see in the
//     browser is echarts' OWN per-frame layout iteration (GraphView), not example code — the example
//     never touches `myChart` and never schedules a timer, so it has no timeline to reproduce.
//
// NOT PIXEL-COMPARABLE — a property of force layout, not of this port. Do not "fix" it here:
//   - with `initLayout` commented out (as the official source leaves it) and no node positions given,
//     upstream seeds every node's start position with `Math.random()` (forceHelper.ts, "Init position").
//     The port bans Math.random and substitutes a deterministic index-seeded scatter (`detScatter` in
//     forceHelper.swift): same intent (a spread cloud around the center), different start state.
//   - `force.layoutAnimation` defaults true and is read independently of the series' `animation: false`
//     (GraphView.ts), so the WEB pane settles over frames; the native still frame instead runs the
//     simulation synchronously to completion (`graphForceLayout`, 1500-iteration cap) so it renders a
//     SETTLED graph rather than a noisy first step.
//   Both panes therefore show 16 settled rings, but each ring's rotation/reflection differs between the
//   panes — and run-to-run on the web pane. Judge this demo on topology (a ring of idx+2 nodes per cell,
//   4x4 grid), not on a pixel diff. Pinning it (initLayout / a fixed seed) would deviate from the example.
extension EChartsDemoRegistry {
    static let official_graph_force2 = EChartsDemo(
        name: "official-graph-force2", category: "graph",
        summary: "力引导布局 — Force Layout",
        width: 720, height: 460,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
function createNodes(count) {
  var nodes = [];
  for (var i = 0; i < count; i++) {
    nodes.push({
      id: i + ''
    });
  }
  return nodes;
}

function createEdges(count) {
  var edges = [];
  if (count === 2) {
    return [[0, 1]];
  }
  for (var i = 0; i < count; i++) {
    edges.push([i, (i + 1) % count]);
  }
  return edges;
}

var datas = [];
for (var i = 0; i < 16; i++) {
  datas.push({
    nodes: createNodes(i + 2),
    edges: createEdges(i + 2)
  });
}

option = {
  series: datas.map(function (item, idx) {
    return {
      type: 'graph',
      layout: 'force',
      animation: false,
      data: item.nodes,
      left: (idx % 4) * 25 + '%',
      top: Math.floor(idx / 4) * 25 + '%',
      width: '25%',
      height: '25%',
      force: {
        initLayout: 'circular',
        layoutAnimation: false,
        // gravity: 0
        repulsion: 60,
        edgeLength: 2
      },
      edges: item.edges.map(function (e) {
        return {
          source: e[0] + '',
          target: e[1] + ''
        };
      })
    };
  })
};
"""#,
        option: [
            "series": graphForce2Series
        ])
}

// The Swift counterpart of the example's `createNodes` / `createEdges` / `datas.map(...)`: 16 graph
// series, cell (idx % 4, idx / 4) of a 4x4 grid, series idx being a ring of idx + 2 nodes.
private let graphForce2Series: [[String: Any]] = (0..<16).map { idx -> [String: Any] in
    let count = idx + 2
    let nodes: [[String: Any]] = (0..<count).map { ["id": "\($0)"] as [String: Any] }
    // createEdges: a ring i -> (i + 1) % count; the 2-node case is the single edge 0 -> 1.
    let pairs: [(Int, Int)] = count == 2 ? [(0, 1)] : (0..<count).map { ($0, ($0 + 1) % count) }
    let edges: [[String: Any]] = pairs.map {
        ["source": "\($0.0)", "target": "\($0.1)"] as [String: Any]
    }
    return [
        "type": "graph",
        "layout": "force",
        "animation": false,
        "data": nodes,
        "left": "\((idx % 4) * 25)%",
        "top": "\((idx / 4) * 25)%",
        "width": "25%",
        "height": "25%",
        "force": [
            "initLayout": "circular",
            "layoutAnimation": false,
            "repulsion": 60.0,
            "edgeLength": 2.0
        ] as [String: Any],
        "edges": edges
    ] as [String: Any]
}
