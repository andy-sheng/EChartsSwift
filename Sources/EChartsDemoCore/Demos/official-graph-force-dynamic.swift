// official-graph-force-dynamic — replica of https://echarts.apache.org/examples/zh/editor.html?c=graph-force-dynamic
// title: Graph Dynamic / titleCN: 动态增加图节点
// A force-laid-out graph that GROWS: it starts as one node pinned (`fixed: true`) at the canvas
// centre, and every 200ms pushes a new node plus (usually) one edge between two random existing
// nodes, re-`setOption`ing the series. The force layout keeps re-settling as the graph accretes.
//
// THE 200ms GROWTH LOOP IS PORTED, on both panes. The web pane runs the example's own
// `setInterval(function () { ... myChart.setOption({ series: [{ roam: true, data, edges }] }); }, 200)`
// verbatim; the native pane replays the same timeline through `drive` (see EChartsDemoChart), pushing
// into its own `data`/`edges` arrays and merge-setOption-ing them back. The still-frame PNG paths
// capture the first frame on both sides (the web page neuters setInterval under `snapshot`, the
// headless native render never calls `drive`), so a snapshot is the lone seed node.
//
// DEVIATIONS from the official source:
//   - The TS type annotations (`const data: NonNullable<echarts.GraphSeriesOption['data']> = ...`) and
//     the trailing `export {}` are dropped from webOptionJS — a classic script cannot parse either.
//     Everything else, including the whole setInterval body, is verbatim.
//   - NATIVE PANE, seed node position: upstream pins it at `myChart.getWidth() / 2`,
//     `myChart.getHeight() / 2`. `EChartsDemoChart` exposes no size accessors, so the Swift option
//     hardcodes the demo's logical centre (360, 230) — i.e. exactly width/2, height/2 for this demo's
//     720x460 canvas. The web pane still calls getWidth()/getHeight() and lands on the same point.
//   - The random-like endpoint stream uses the same seeded 32-bit LCG in both panes. The official
//     example uses `Math.random()`, but independent runtime streams make an interaction diff flaky:
//     one pane can add an edge while the other skips it. A synchronized stream preserves the dynamic
//     topology while making each explicit logical interval tick directly comparable.
extension EChartsDemoRegistry {
    static let official_graph_force_dynamic = EChartsDemo(
        name: "official-graph-force-dynamic", category: "graph",
        summary: "动态增加图节点 — Graph Dynamic",
        width: 720, height: 460,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
const data = [
  {
    fixed: true,
    x: myChart.getWidth() / 2,
    y: myChart.getHeight() / 2,
    symbolSize: 20,
    id: '-1'
  }
];

const edges = [];
let randomState = 42;
function nextRandom() {
  randomState = (Math.imul(1664525, randomState) + 1013904223) >>> 0;
  return randomState / 4294967296;
}

option = {
  series: [
    {
      type: 'graph',
      layout: 'force',
      animation: false,
      data: data,
      force: {
        // initLayout: 'circular'
        // gravity: 0
        repulsion: 100,
        edgeLength: 5
      },
      edges: edges
    }
  ]
};

setInterval(function () {
  data.push({
    id: data.length + ''
  });
  var source = Math.round((data.length - 1) * nextRandom());
  var target = Math.round((data.length - 1) * nextRandom());
  if (source !== target) {
    edges.push({
      source: source,
      target: target
    });
  }
  myChart.setOption({
    series: [
      {
        roam: true,
        data: data,
        edges: edges
      }
    ]
  });

  // console.log('nodes: ' + data.length);
  // console.log('links: ' + data.length);
}, 200);
"""#,
        // The native pane's half of the same timeline: the example's `setInterval(..., 200)`, growing
        // the SAME two arrays and merge-applying them (upstream's setOption has no `true` second arg,
        // so this is a merge — `notMerge: false` — and the series' type/layout/force stay in place).
        drive: { chart in
            // Upstream's module-scope `data` / `edges`, mutated in place by the interval.
            var data: [[String: Any]] = [officialGraphForceDynamicSeedNode]
            var edges: [[String: Any]] = []
            var randomState: UInt32 = 42
            func nextRandom() -> Double {
                randomState = (1_664_525 &* randomState) &+ 1_013_904_223
                return Double(randomState) / 4_294_967_296.0
            }
            chart.every(0.2) {
                // `data.push({ id: data.length + '' })` — the id is the PRE-push length, so the ids
                // run '-1' (the seed), then '1', '2', '3', … (never '0').
                let nextId = String(data.count)
                data.append(["id": nextId])
                // `Math.round((data.length - 1) * Math.random())` — length is POST-push here, so both
                // endpoints index anywhere into the graph including the node just added.
                let source = Int((Double(data.count - 1) * nextRandom()).rounded())
                let target = Int((Double(data.count - 1) * nextRandom()).rounded())
                if source != target {
                    // Numeric endpoints are node INDICES (Graph.addEdge resolves a number through
                    // `nodes[i]`), exactly as upstream pushes them.
                    edges.append(["source": source, "target": target])
                }
                let update: [String: Any] = [
                    "series": [
                        [
                            "roam": true,
                            "data": data as [Any],
                            "edges": edges as [Any]
                        ] as [String: Any]
                    ]
                ]
                chart.setOption(update, notMerge: false)
            }
        },
        option: officialGraphForceDynamicOption)
}

// The one node the example starts with: pinned at the canvas centre so the force layout has an anchor.
// x/y are the demo's width/2, height/2 (see DEVIATIONS — upstream reads them off `myChart`).
private let officialGraphForceDynamicSeedNode: [String: Any] = [
    "fixed": true,
    "x": 360.0,
    "y": 230.0,
    "symbolSize": 20.0,
    "id": "-1"
]

// The example's initial `option` — one seed node, no edges, force layout with a short edgeLength.
private let officialGraphForceDynamicOption: [String: Any] = [
    "series": [
        [
            "type": "graph",
            "layout": "force",
            "animation": false,
            "data": [officialGraphForceDynamicSeedNode] as [Any],
            "force": [
                // upstream leaves `initLayout: 'circular'` and `gravity: 0` commented out.
                "repulsion": 100.0,
                "edgeLength": 5.0
            ] as [String: Any],
            "edges": [] as [Any]
        ] as [String: Any]
    ]
]
