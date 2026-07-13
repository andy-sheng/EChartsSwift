// official-scatter-clustering-process — replica of https://echarts.apache.org/examples/zh/editor.html?c=scatter-clustering-process
// title: Clustering Process / titleCN: 聚合过程可视化
//
// Hierarchical k-means, one merge step per timeline tick. 60 2-D points; ecStat's
// `clustering.hierarchicalKMeans(..., { stepByStep: true })` generator is drained at option-build time
// into ONE timeline frame per step (6 frames: the raw data, then 5 steps up to clusterCount 6). Each
// frame is two `custom` series: `renderItemPoint` draws every datum as a circle coloured by its cluster
// index (with a shadow glow on the cluster born this step), `renderBoundary` draws the new cluster's
// dashed ellipse, sized in DATA units via `api.size()` and grown by a `renderProgress` transition.
//
// DEVIATIONS from the official source:
//   - ecStat IS NOT PART OF echarts. The official editor side-loads echarts-stat from a CDN; our
//     reference page has no network (WebPage.swift inlines only upstream/echarts/dist/echarts.js), so
//     webOptionJS splices the repo's vendored `upstream/echarts/test/lib/ecStat.min.js` (a UMD that
//     assigns the `ecStat` global when no module system is present — exactly how the upstream test page
//     upstream/echarts/test/custom-transition-ecStat.html loads it) in ABOVE the example. Everything
//     below that blob is the example VERBATIM. The clustering therefore really runs, in real JS, in the
//     reference pane.
//   - STATIC FRAME = TIMELINE STEP 0. The gallery snapshots one frame and upstream sets
//     `timeline.autoPlay: false`, so both this pane and the official editor show, on load, the FIRST
//     frame: the raw 60 points, every one still in cluster 0 (`colorAll[0]` = grey #bbb) and no boundary
//     ellipse yet. The clusters appear only as the playhead advances. Nothing was removed to get there —
//     all 6 frames are built and handed to echarts, we just never move the playhead.
//   - animation off: WebPage.swift's blanket `option.animation = false` is IGNORED by echarts when the
//     option carries a `baseOption` (only baseOption/options/timeline/media are read off the root), so
//     the harness's intent is restored inside `baseOption` — one line at the bottom of webOptionJS,
//     mirrored by `"animation": false` in the Swift option.
//   - NATIVE PANE OFF (nativeSupported: false). Two things the Swift option cannot carry: (1) the chart
//     IS its two `renderItem` closures — both series are `custom` and neither draws anything without
//     them (see the PORT-NOTEs); (2) the per-step data is produced by ecStat's `hierarchicalKMeans`
//     generator, a JS library with no Swift port, so only the step-0 frame (which is just the input data,
//     un-clustered) can be expressed at all. The `option` below is that frame, structurally faithful:
//     the same timeline / baseOption / options bundle, minus what JS alone can express.
import Foundation

// The 60 raw 2-D points (verbatim `originalData`). At timeline step 0 this IS the frame's series data:
// no cluster-index dim (2) and no centroid dims (3, 4) yet — ecStat appends those from step 1 on.
private let clusteringProcessData: [[Double]] = [
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
]

// echarts-stat (ecStat), read from the repo at demo time through the SAME #filePath-relative root the
// echarts dist is read from (WebPage.swift) — resolves on macOS and the iOS simulator alike. Spliced
// into the reference page's script so `ecStat.clustering.hierarchicalKMeans` exists there; on a read
// failure the example's own `var step = ecStat...` line throws, so degrade to a JS comment and let the
// pane fail loudly rather than half-render.
private let ecStatMinJS: String = {
    let url = Upstream.repoRoot.appendingPathComponent("upstream/echarts/test/lib/ecStat.min.js")
    guard let js = try? String(contentsOf: url, encoding: .utf8) else {
        return "/* ecStat.min.js NOT FOUND at upstream/echarts/test/lib/ — the example cannot run */"
    }
    return js
}()

extension EChartsDemoRegistry {
    static let official_scatter_clustering_process = EChartsDemo(
        name: "official-scatter-clustering-process", category: "scatter",
        summary: "聚合过程可视化 — Clustering Process",
        width: 640, height: 420,
        nativeSupported: false,
        collection: .official,
        webOptionJS: #"""
// --- vendored echarts-stat (upstream/echarts/test/lib/ecStat.min.js), inlined: the official example
// --- side-loads it from a CDN and this page has no network. Defines the `ecStat` global. ---
\#(ecStatMinJS)
// --- end ecStat; the official example follows, verbatim ---

var originalData = [
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

var DIM_CLUSTER_INDEX = 2;
var DATA_DIM_IDX = [0, 1];
var CENTER_DIM_IDX = [3, 4];

// See https://github.com/ecomfe/echarts-stat
var step = ecStat.clustering.hierarchicalKMeans(originalData, {
  clusterCount: 6,
  outputType: 'single',
  outputClusterIndexDimension: DIM_CLUSTER_INDEX,
  outputCentroidDimensions: CENTER_DIM_IDX,
  stepByStep: true
});

var colorAll = [
  '#bbb',
  '#37A2DA',
  '#e06343',
  '#37a354',
  '#b55dba',
  '#b5bd48',
  '#8378EA',
  '#96BFFF'
];
var ANIMATION_DURATION_UPDATE = 1500;

function renderItemPoint(params, api) {
  var coord = api.coord([api.value(0), api.value(1)]);
  var clusterIdx = api.value(2);
  if (clusterIdx == null || isNaN(clusterIdx)) {
    clusterIdx = 0;
  }
  var isNewCluster = clusterIdx === api.value(3);

  var extra = {
    transition: []
  };
  var contentColor = colorAll[clusterIdx];

  return {
    type: 'circle',
    x: coord[0],
    y: coord[1],
    shape: {
      cx: 0,
      cy: 0,
      r: 10
    },
    extra: extra,
    style: {
      fill: contentColor,
      stroke: '#333',
      lineWidth: 1,
      shadowColor: contentColor,
      shadowBlur: isNewCluster ? 12 : 0,
      transition: ['shadowBlur', 'fill']
    }
  };
}

function renderBoundary(params, api) {
  var xVal = api.value(0);
  var yVal = api.value(1);
  var maxDist = api.value(2);
  var center = api.coord([xVal, yVal]);
  var size = api.size([maxDist, maxDist]);

  return {
    type: 'ellipse',
    shape: {
      cx: isNaN(center[0]) ? 0 : center[0],
      cy: isNaN(center[1]) ? 0 : center[1],
      rx: isNaN(size[0]) ? 0 : size[0] + 15,
      ry: isNaN(size[1]) ? 0 : size[1] + 15
    },
    extra: {
      renderProgress: ++targetRenderProgress,
      enterFrom: {
        renderProgress: 0
      },
      transition: 'renderProgress'
    },
    style: {
      fill: null,
      stroke: 'rgba(0,0,0,0.2)',
      lineDash: [4, 4],
      lineWidth: 4
    }
  };
}

function makeStepOption(option, data, centroids) {
  var newCluIdx = centroids ? centroids.length - 1 : -1;
  var maxDist = 0;
  for (var i = 0; i < data.length; i++) {
    var line = data[i];
    if (line[DIM_CLUSTER_INDEX] === newCluIdx) {
      var dist0 = Math.pow(line[DATA_DIM_IDX[0]] - line[CENTER_DIM_IDX[0]], 2);
      var dist1 = Math.pow(line[DATA_DIM_IDX[1]] - line[CENTER_DIM_IDX[1]], 2);
      maxDist = Math.max(maxDist, dist0 + dist1);
    }
  }
  var boundaryData = centroids
    ? [[centroids[newCluIdx][0], centroids[newCluIdx][1], Math.sqrt(maxDist)]]
    : [];

  option.options.push({
    series: [
      {
        type: 'custom',
        encode: {
          tooltip: [0, 1]
        },
        renderItem: renderItemPoint,
        data: data
      },
      {
        type: 'custom',
        renderItem: renderBoundary,
        animationDuration: 3000,
        silent: true,
        data: boundaryData
      }
    ]
  });
}

var targetRenderProgress = 0;

option = {
  timeline: {
    top: 'center',
    right: 50,
    height: 300,
    width: 10,
    inverse: true,
    autoPlay: false,
    playInterval: 2500,
    symbol: 'none',
    orient: 'vertical',
    axisType: 'category',
    label: {
      formatter: 'step {value}',
      position: 10
    },
    checkpointStyle: {
      animationDuration: ANIMATION_DURATION_UPDATE
    },
    data: []
  },
  baseOption: {
    animationDurationUpdate: ANIMATION_DURATION_UPDATE,
    transition: ['shape'],
    tooltip: {},
    xAxis: {
      type: 'value'
    },
    yAxis: {
      type: 'value'
    },
    series: [
      {
        type: 'scatter'
      }
    ]
  },
  options: []
};

makeStepOption(option, originalData);
option.timeline.data.push('0');
for (var i = 1, stepResult; !(stepResult = step.next()).isEnd; i++) {
  makeStepOption(
    option,
    echarts.util.clone(stepResult.data),
    echarts.util.clone(stepResult.centroids)
  );
  option.timeline.data.push(i + '');
}

// DEVIATION (harness, not the chart): the gallery snapshots ONE deterministic frame, so WebPage.swift
// sets `option.animation = false` — but echarts ignores a root `animation` once `baseOption` exists.
// Restore the harness's intent where it is actually read. The playhead is left at its initial index
// (upstream autoPlay is already false), i.e. step 0: the raw points, un-clustered.
option.baseOption.animation = false;
"""#,
        option: [
            "timeline": [
                "top": "center",
                "right": 50.0,
                "height": 300.0,
                "width": 10.0,
                "inverse": true,
                "autoPlay": false,
                "playInterval": 2500.0,
                "symbol": "none",
                "orient": "vertical",
                "axisType": "category",
                "label": [
                    "formatter": "step {value}",   // a string template, not a closure — ports as-is
                    "position": 10.0
                ] as [String: Any],
                "checkpointStyle": [
                    "animationDuration": 1500.0
                ] as [String: Any],
                // PORT-NOTE: timeline.data is ['0' ... '5'] upstream (one label per hierarchicalKMeans
                // step). Steps 1…5 exist only as ecStat generator output — a JS library with no Swift
                // port — so the Swift option carries the one frame it can express, step 0, and the
                // timeline is trimmed to match (echarts pairs data[i] with options[i]).
                "data": ["0"]
            ] as [String: Any],
            "baseOption": [
                "animationDurationUpdate": 1500.0,
                "transition": ["shape"],
                // DEVIATION: see the header — the harness's `option.animation = false` cannot reach a
                // baseOption, so the static frame is pinned here instead.
                "animation": false,
                "tooltip": [:] as [String: Any],
                "xAxis": [
                    "type": "value"
                ] as [String: Any],
                "yAxis": [
                    "type": "value"
                ] as [String: Any],
                "series": [
                    [
                        "type": "scatter"
                    ] as [String: Any]
                ]
            ] as [String: Any],
            // The timeline frames. Only step 0 (`makeStepOption(option, originalData)`, no centroids →
            // empty boundary series) survives the port; see the timeline.data PORT-NOTE above.
            "options": [
                [
                    "series": [
                        [
                            "type": "custom",
                            "encode": [
                                "tooltip": [0.0, 1.0]
                            ] as [String: Any],
                            // PORT-NOTE: renderItem omitted — JS closure `renderItemPoint`, the chart
                            // itself: circle at api.coord([value(0), value(1)]), r 10, filled with
                            // colorAll[value(2) /* cluster index, 0 when absent */], stroke #333, and a
                            // shadowBlur 12 glow (transitioned) on the cluster created this step
                            // (value(2) === value(3)). Without it the series draws nothing.
                            "data": clusteringProcessData
                        ] as [String: Any],
                        [
                            "type": "custom",
                            // PORT-NOTE: renderItem omitted — JS closure `renderBoundary`: a dashed
                            // ellipse centred on the new centroid (api.coord) whose radii come from
                            // api.size([maxDist, maxDist]) + 15px, grown from 0 by an `extra
                            // .renderProgress` transition. Data is EMPTY at step 0 (no cluster has been
                            // born yet), so this series is a no-op in the frame we render either way.
                            "animationDuration": 3000.0,
                            "silent": true,
                            "data": [] as [Any]
                        ] as [String: Any]
                    ]
                ] as [String: Any]
            ]
        ])
}
