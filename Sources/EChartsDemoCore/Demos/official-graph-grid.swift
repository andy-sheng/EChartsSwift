// official-graph-grid — replica of https://echarts.apache.org/examples/zh/editor.html?c=graph-grid
// title: Graph on Cartesian / titleCN: 笛卡尔坐标系上的 Graph
// A `graph` series with `coordinateSystem: 'cartesian2d'` and `layout: 'none'`: 7 nodes sitting on a
// category x-axis (`boundaryGap: false`, so node i lands ON the i-th tick) at their own value as y,
// chained left-to-right by 6 directed edges (circle tail, arrow head).
//
// DEVIATIONS from the official source:
//   1. webOptionJS is the example VERBATIM (the `const axisData` / `const data` / `const links` /
//      `links.pop()` preamble included, so the reference pane really builds the option the way the
//      example does) minus the leading metadata comment block and the trailing `export {};` — a bare
//      export is a SyntaxError in the classic script the pane runs and would blank the page.
//   2. The node values are RANDOM (`Math.round(Math.random() * 1000 * (i + 1))`), regenerated on
//      every load — upstream ships no fixed dataset, so the two panes CANNOT show the same node
//      heights by construction. The native pane carries ONE fixed sample drawn from that same
//      recurrence (value i inside [0, 1000 * (i + 1)]), so its frame is at least stable across runs.
//      Compare the panes for LAYOUT — nodes on the category ticks, the y-scale fitted to the data,
//      the 6 chained edges with their circle/arrow end symbols, the node labels — not per-node
//      values (and see KNOWN NATIVE GAP below: today the native pane draws no nodes/edges at all,
//      so the web pane is the only one showing the graph). The `links` half is deterministic in both
//      panes: i → i + 1 for i in 0…5 (upstream builds one link per datum and `pop()`s the dangling
//      last one).
//   3. `tooltip: {}` is kept in both options but has no visible effect: the gallery renders one
//      static, non-interactive frame.
//   4. No `drive`: the example is static — no `setInterval`, no `dispatchAction`, no `myChart.*`.
//
// KNOWN NATIVE GAP (kept faithful on purpose — surfacing it is the point of this demo). This is the
// only official graph example that puts the series on an EXTERNAL coordinate system
// (`coordinateSystem: 'cartesian2d'`), and the port cannot honour that yet:
//   - `_coordSysMgr.create` DOES inject a `Cartesian2D` into this series (coord/cartesian/Grid.swift,
//     "Inject the coordinateSystems into seriesModel"), and `_coordSysMgr.update` runs before any
//     layout stage — so the axes ARE fitted to the node values (7 categories on x, ~0…max on y).
//   - But `createViewCoordSys` (chart/graph/createView.swift) then OVERWRITES
//     `seriesModel.coordinateSystem` with its stand-in `GraphViewCoordSys` (type `"view"`) for EVERY
//     graph series, unconditionally. Upstream gates that on the series option
//     (`injectCoordSysByOption({ coordSysType: 'view', isDefaultDataCoordSys: true })`), so a series
//     declaring `cartesian2d` keeps its Cartesian.
//   - Consequence: `graphSimpleLayout`'s external-coord-sys branch (`coordSys.type !== 'view'` →
//     `data.setItemLayout(i, coordSys.dataToPoint(value))`) is never taken. It falls through to
//     `simpleLayout(seriesModel)`, which reads each node's own `x`/`y` — absent here (the data are
//     plain numbers) — so every node's layout is `[+undefined, +undefined]` == `[NaN, NaN]`.
//   The native pane is therefore expected to draw the title and both axes but NO NODES and NO EDGES
//   (SymbolDraw skips non-finite symbol points) until `createViewCoordSys` is gated on the series'
//   `coordinateSystem` option. Rewriting this demo to `layout: 'none'` with hand-placed x/y nodes
//   would make the native pane "work" while hiding exactly the gap this example exists to expose, so
//   the option stays verbatim and `nativeSupported` stays true (same call as official-bar-large).
extension EChartsDemoRegistry {
    static let official_graph_grid = EChartsDemo(
        name: "official-graph-grid", category: "graph",
        summary: "笛卡尔坐标系上的 Graph — Graph on Cartesian",
        width: 720, height: 460,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
const axisData = ['Mon', 'Tue', 'Wed', 'Very Loooong Thu', 'Fri', 'Sat', 'Sun'];
const data = axisData.map(function (item, i) {
  return Math.round(Math.random() * 1000 * (i + 1));
});
const links = data.map(function (item, i) {
  return {
    source: i,
    target: i + 1
  };
});
links.pop();
option = {
  title: {
    text: 'Graph on Cartesian'
  },
  tooltip: {},
  xAxis: {
    type: 'category',
    boundaryGap: false,
    data: axisData
  },
  yAxis: {
    type: 'value'
  },
  series: [
    {
      type: 'graph',
      layout: 'none',
      coordinateSystem: 'cartesian2d',
      symbolSize: 40,
      label: {
        show: true
      },
      edgeSymbol: ['circle', 'arrow'],
      edgeSymbolSize: [4, 10],
      data: data,
      links: links,
      lineStyle: {
        color: '#2f4554'
      }
    }
  ]
};
"""#,
        option: [
            "title": [
                "text": "Graph on Cartesian"
            ] as [String: Any],
            "tooltip": [:] as [String: Any],
            "xAxis": [
                "type": "category",
                "boundaryGap": false,
                "data": graphGridAxisData
            ] as [String: Any],
            "yAxis": [
                "type": "value"
            ] as [String: Any],
            "series": [
                [
                    "type": "graph",
                    "layout": "none",
                    "coordinateSystem": "cartesian2d",
                    "symbolSize": 40.0,
                    "label": [
                        "show": true
                    ] as [String: Any],
                    "edgeSymbol": ["circle", "arrow"],
                    "edgeSymbolSize": [4.0, 10.0],
                    "data": graphGridData,
                    "links": graphGridLinks,
                    "lineStyle": [
                        "color": "#2f4554"
                    ] as [String: Any]
                ] as [String: Any]
            ]
        ])
}

// The upstream `axisData` — one category per node; node i is pinned to tick i (boundaryGap: false).
private let graphGridAxisData: [String] = [
    "Mon", "Tue", "Wed", "Very Loooong Thu", "Fri", "Sat", "Sun"
]

// One fixed sample of the upstream `axisData.map((item, i) => Math.round(Math.random() * 1000 * (i + 1)))`
// — see DEVIATION 2. Each value i lies inside the [0, 1000 * (i + 1)] band the recurrence produces.
private let graphGridData: [Double] = [
    612, 1385, 2074, 1108, 4318, 2593, 6157
]

// The upstream `data.map((item, i) => ({ source: i, target: i + 1 }))` with the dangling last link
// `pop()`ed: 6 edges chaining node 0 → 1 → … → 6. Numeric source/target are NODE INDICES.
private let graphGridLinks: [[String: Any]] = [
    ["source": 0.0, "target": 1.0],
    ["source": 1.0, "target": 2.0],
    ["source": 2.0, "target": 3.0],
    ["source": 3.0, "target": 4.0],
    ["source": 4.0, "target": 5.0],
    ["source": 5.0, "target": 6.0]
]
