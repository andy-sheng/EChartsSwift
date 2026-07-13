// official-scatter-clustering — replica of https://echarts.apache.org/examples/zh/editor.html?c=scatter-clustering
// title: Clustering Process / titleCN: 数据聚合
// 60 2-D points run through a k-means dataset TRANSFORM that writes each point's cluster index into a
// third dimension; a piecewise visualMap keyed on that dimension (`dimension: 2`) colours the scatter
// into CLUSTER_COUNT = 6 groups.
//
// DEVIATIONS from the official source (both are forced by the same fact: the clustering lives in
// `ecStat`, the third-party echarts-stat plugin, which the official page loads from a CDN):
//   1. WEB pane — the reference page is offline and self-contained, so `ecStat` cannot be loaded and
//      `echarts.registerTransform(ecStat.transform.clustering)` would be a ReferenceError that kills the
//      whole page. That ONE line is replaced by an inline `echarts.registerTransform({ type:
//      'ecStat:clustering', transform: ... })` — a deterministic Lloyd k-means (centroids seeded with the
//      first 6 points) implementing the same `outputType: 'single'` contract: it appends the cluster index
//      at `config.outputClusterIndexDimension`. Everything else — the data, CLUSTER_COUNT, COLOR_ALL, the
//      `pieces` loop and the whole `option` (dataset chain, tooltip, piecewise visualMap, grid, series) —
//      is verbatim, so the real echarts dataset-transform → visualMap → scatter pipeline still runs.
//      (Cluster ASSIGNMENTS are identical to ecStat's here — the six blobs are well separated — but the
//      cluster NUMBERING, hence the colour each blob gets, is an artifact of the seeding and may differ
//      from the official screenshot.)
//   2. NATIVE pane — EChartsKit registers only the built-in `filter`/`sort` transforms, not
//      `ecStat:clustering`, and a Swift `option` cannot carry a transform closure. The native pane
//      therefore skips the transform: its single dataset's source is the SAME 60 points with the cluster
//      index PRECOMPUTED into dimension 2 by the same k-means (see scatterClusteringSource), i.e. exactly
//      the post-transform table the web pane's dataset[1] produces. visualMap/grid/axes/series are the
//      example's, unchanged, so the two panes are directly diffable.
// The official `export {};` trailer is dropped (a bare export is a SyntaxError in a classic script).
extension EChartsDemoRegistry {
    static let official_scatter_clustering = EChartsDemo(
        name: "official-scatter-clustering", category: "scatter",
        summary: "数据聚合 — Clustering Process",
        width: 640, height: 420,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
// See https://github.com/ecomfe/echarts-stat
// PORT: `ecStat` is a CDN-loaded third-party plugin and this page is offline, so the upstream
// `echarts.registerTransform(ecStat.transform.clustering)` is replaced by an equivalent inline
// transform: deterministic Lloyd k-means, `outputType: 'single'` (cluster index appended at
// config.outputClusterIndexDimension). The option below is verbatim.
echarts.registerTransform({
  type: 'ecStat:clustering',
  transform: function (params) {
    var config = params.config || {};
    var k = config.clusterCount;
    var dimIdx = config.outputClusterIndexDimension;
    var points = params.upstream.cloneRawData();
    var centroids = [];
    for (var i = 0; i < k; i++) {
      centroids.push([+points[i][0], +points[i][1]]);
    }
    var assign = new Array(points.length).fill(-1);
    for (var iter = 0; iter < 100; iter++) {
      var changed = false;
      for (var p = 0; p < points.length; p++) {
        var best = 0;
        var bestD = Infinity;
        for (var c = 0; c < k; c++) {
          var dx = points[p][0] - centroids[c][0];
          var dy = points[p][1] - centroids[c][1];
          var d = dx * dx + dy * dy;
          if (d < bestD) {
            bestD = d;
            best = c;
          }
        }
        if (assign[p] !== best) {
          assign[p] = best;
          changed = true;
        }
      }
      for (var c2 = 0; c2 < k; c2++) {
        var sx = 0;
        var sy = 0;
        var n = 0;
        for (var q = 0; q < points.length; q++) {
          if (assign[q] === c2) {
            sx += points[q][0];
            sy += points[q][1];
            n++;
          }
        }
        if (n > 0) {
          centroids[c2] = [sx / n, sy / n];
        }
      }
      if (!changed) {
        break;
      }
    }
    var out = points.map(function (item, idx) {
      var row = item.slice();
      row[dimIdx] = assign[idx];
      return row;
    });
    return { data: out };
  }
});

const data = [
  [3.275154, 2.957587],
  [-3.344465, 2.603513],
  [0.355083, -3.376585],
  [1.852435, 3.547351],
  [-2.078973, 2.552013],
  [-0.993756, -0.884433],
  [2.682252, 4.007573],
  [-3.087776, 2.878713],
  [-1.565978, -1.256985],
  [2.441611, 0.444826],
  [-0.659487, 3.111284],
  [-0.459601, -2.618005],
  [2.17768, 2.387793],
  [-2.920969, 2.917485],
  [-0.028814, -4.168078],
  [3.625746, 2.119041],
  [-3.912363, 1.325108],
  [-0.551694, -2.814223],
  [2.855808, 3.483301],
  [-3.594448, 2.856651],
  [0.421993, -2.372646],
  [1.650821, 3.407572],
  [-2.082902, 3.384412],
  [-0.718809, -2.492514],
  [4.513623, 3.841029],
  [-4.822011, 4.607049],
  [-0.656297, -1.449872],
  [1.919901, 4.439368],
  [-3.287749, 3.918836],
  [-1.576936, -2.977622],
  [3.598143, 1.97597],
  [-3.977329, 4.900932],
  [-1.79108, -2.184517],
  [3.914654, 3.559303],
  [-1.910108, 4.166946],
  [-1.226597, -3.317889],
  [1.148946, 3.345138],
  [-2.113864, 3.548172],
  [0.845762, -3.589788],
  [2.629062, 3.535831],
  [-1.640717, 2.990517],
  [-1.881012, -2.485405],
  [4.606999, 3.510312],
  [-4.366462, 4.023316],
  [0.765015, -3.00127],
  [3.121904, 2.173988],
  [-4.025139, 4.65231],
  [-0.559558, -3.840539],
  [4.376754, 4.863579],
  [-1.874308, 4.032237],
  [-0.089337, -3.026809],
  [3.997787, 2.518662],
  [-3.082978, 2.884822],
  [0.845235, -3.454465],
  [1.327224, 3.358778],
  [-2.889949, 3.596178],
  [-0.966018, -2.839827],
  [2.960769, 3.079555],
  [-3.275518, 1.577068],
  [0.639276, -3.41284]
];

var CLUSTER_COUNT = 6;
var DIENSIION_CLUSTER_INDEX = 2;
var COLOR_ALL = [
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
var pieces = [];
for (var i = 0; i < CLUSTER_COUNT; i++) {
  pieces.push({
    value: i,
    label: 'cluster ' + i,
    color: COLOR_ALL[i]
  });
}

option = {
  dataset: [
    {
      source: data
    },
    {
      transform: {
        type: 'ecStat:clustering',
        // print: true,
        config: {
          clusterCount: CLUSTER_COUNT,
          outputType: 'single',
          outputClusterIndexDimension: DIENSIION_CLUSTER_INDEX
        }
      }
    }
  ],
  tooltip: {
    position: 'top'
  },
  visualMap: {
    type: 'piecewise',
    top: 'middle',
    min: 0,
    max: CLUSTER_COUNT,
    left: 10,
    splitNumber: CLUSTER_COUNT,
    dimension: DIENSIION_CLUSTER_INDEX,
    pieces: pieces
  },
  grid: {
    left: 120
  },
  xAxis: {},
  yAxis: {},
  series: {
    type: 'scatter',
    encode: { tooltip: [0, 1] },
    symbolSize: 15,
    itemStyle: {
      borderColor: '#555'
    },
    datasetIndex: 1
  }
};
"""#,
        option: [
            // PORT-NOTE: dataset[1].transform ('ecStat:clustering') omitted — EChartsKit registers only
            // the built-in filter/sort transforms, and the clustering body is a JS closure a Swift option
            // cannot carry. The single dataset below IS that transform's output: the POST-transform table
            // (the web pane's dataset[1]), [x, y, clusterIndex], precomputed by the same k-means.
            "dataset": [
                ["source": scatterClusteringSource] as [String: Any]
            ],
            "tooltip": [
                "position": "top"
            ] as [String: Any],
            "visualMap": [
                "type": "piecewise",
                "top": "middle",
                "min": 0.0,
                "max": 6.0,                 // CLUSTER_COUNT
                "left": 10.0,
                "splitNumber": 6.0,         // CLUSTER_COUNT
                "dimension": 2.0,           // DIENSIION_CLUSTER_INDEX
                "pieces": scatterClusteringPieces
            ] as [String: Any],
            "grid": [
                "left": 120.0
            ] as [String: Any],
            "xAxis": [:] as [String: Any],
            "yAxis": [:] as [String: Any],
            "series": [
                [
                    "type": "scatter",
                    "encode": ["tooltip": [0.0, 1.0]] as [String: Any],
                    "symbolSize": 15.0,
                    "itemStyle": [
                        "borderColor": "#555"
                    ] as [String: Any],
                    "datasetIndex": 0.0     // upstream 1 — the native pane has no transform stage
                ] as [String: Any]
            ]
        ])
}

// One piece per cluster — the upstream `for (i < CLUSTER_COUNT) pieces.push({value, label, color})`
// loop unrolled (COLOR_ALL's first 6 entries).
private let scatterClusteringPieces: [[String: Any]] = [
    ["value": 0.0, "label": "cluster 0", "color": "#5070dd"] as [String: Any],
    ["value": 1.0, "label": "cluster 1", "color": "#b6d634"] as [String: Any],
    ["value": 2.0, "label": "cluster 2", "color": "#505372"] as [String: Any],
    ["value": 3.0, "label": "cluster 3", "color": "#ff994d"] as [String: Any],
    ["value": 4.0, "label": "cluster 4", "color": "#0ca8df"] as [String: Any],
    ["value": 5.0, "label": "cluster 5", "color": "#ffd10a"] as [String: Any]
]

// The example's 60 points, with dim 2 = the cluster index the web pane's transform computes
// (same deterministic k-means: 6 centroids seeded from the first 6 points, Lloyd to fixpoint).
private let scatterClusteringSource: [[Double]] = [
    [3.275154, 2.957587, 0],
    [-3.344465, 2.603513, 1],
    [0.355083, -3.376585, 2],
    [1.852435, 3.547351, 3],
    [-2.078973, 2.552013, 4],
    [-0.993756, -0.884433, 5],
    [2.682252, 4.007573, 3],
    [-3.087776, 2.878713, 1],
    [-1.565978, -1.256985, 5],
    [2.441611, 0.444826, 0],
    [-0.659487, 3.111284, 4],
    [-0.459601, -2.618005, 5],
    [2.17768, 2.387793, 3],
    [-2.920969, 2.917485, 1],
    [-0.028814, -4.168078, 2],
    [3.625746, 2.119041, 0],
    [-3.912363, 1.325108, 1],
    [-0.551694, -2.814223, 5],
    [2.855808, 3.483301, 3],
    [-3.594448, 2.856651, 1],
    [0.421993, -2.372646, 2],
    [1.650821, 3.407572, 3],
    [-2.082902, 3.384412, 4],
    [-0.718809, -2.492514, 5],
    [4.513623, 3.841029, 0],
    [-4.822011, 4.607049, 1],
    [-0.656297, -1.449872, 5],
    [1.919901, 4.439368, 3],
    [-3.287749, 3.918836, 1],
    [-1.576936, -2.977622, 5],
    [3.598143, 1.97597, 0],
    [-3.977329, 4.900932, 1],
    [-1.79108, -2.184517, 5],
    [3.914654, 3.559303, 0],
    [-1.910108, 4.166946, 4],
    [-1.226597, -3.317889, 5],
    [1.148946, 3.345138, 3],
    [-2.113864, 3.548172, 4],
    [0.845762, -3.589788, 2],
    [2.629062, 3.535831, 3],
    [-1.640717, 2.990517, 4],
    [-1.881012, -2.485405, 5],
    [4.606999, 3.510312, 0],
    [-4.366462, 4.023316, 1],
    [0.765015, -3.00127, 2],
    [3.121904, 2.173988, 0],
    [-4.025139, 4.65231, 1],
    [-0.559558, -3.840539, 2],
    [4.376754, 4.863579, 0],
    [-1.874308, 4.032237, 4],
    [-0.089337, -3.026809, 2],
    [3.997787, 2.518662, 0],
    [-3.082978, 2.884822, 1],
    [0.845235, -3.454465, 2],
    [1.327224, 3.358778, 3],
    [-2.889949, 3.596178, 1],
    [-0.966018, -2.839827, 5],
    [2.960769, 3.079555, 0],
    [-3.275518, 1.577068, 1],
    [0.639276, -3.41284, 2]
]
