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
//     below that blob is the example VERBATIM (plus one harness-only line, see RNG below). The clustering
//     therefore really runs, in real JS, in the reference pane.
//   - RNG: ecStat's centroid init (`clustering.js`'s `createRandCent`, called from `hierarchicalKMeans`'s
//     bisecting `kMeans` step) calls `Math.random()`, unseeded upstream — so even the OFFICIAL reference
//     page's own clustering is nondeterministic run to run. webOptionJS pins it to a small seeded LCG
//     (`state = state*1664525 + 1013904223 (mod 2^32)`, seed 1 — this repo's established convention, see
//     e.g. official-matrix-covariance.swift's `rnd()`), spliced in right after the ecStat blob. The
//     Swift-native pane below drives the IDENTICAL algorithm (EcStatHierarchicalKMeansStepper,
//     ecStatClusteringTransform.swift) over the IDENTICAL LCG (EcStatLCG(seed: 1)) — verified bit-for-bit
//     against a from-source (github.com/ecomfe/echarts-stat) run of this exact algorithm on this exact
//     60-point dataset. So both panes' clustering (steps 1-5) is expected to match exactly, not just "the
//     same shape" — though the STILL FRAME this gallery snapshots (see below) never actually reaches a
//     clustered step, so this only matters if the interactive gallery's timeline is scrubbed by hand.
//   - STATIC FRAME = TIMELINE STEP 0. The gallery snapshots one frame and upstream sets
//     `timeline.autoPlay: false`, so both this pane and the official editor show, on load, the FIRST
//     frame: the raw 60 points, every one still in cluster 0 (`colorAll[0]` = grey #bbb) and no boundary
//     ellipse yet. The clusters appear only as the playhead advances. Nothing was removed to get there —
//     all 6 frames are built and handed to echarts (natively too, now — see NATIVE PANE below), we just
//     never move the playhead.
//   - animation off: WebPage.swift's blanket `option.animation = false` is IGNORED by echarts when the
//     option carries a `baseOption` (only baseOption/options/timeline/media are read off the root), so
//     the harness's intent is restored inside `baseOption` — one line at the bottom of webOptionJS,
//     mirrored by `"animation": false` in the Swift option.
//   - NATIVE PANE ON (nativeSupported: true). Both former blockers are now closed:
//     (1) `renderItemPoint` / `renderBoundary` are ported to Swift `CustomSeriesRenderItem` closures
//         below (statement for statement, including the upstream `isNewCluster = clusterIdx ===
//         api.value(3)` comparison verbatim — see the closure's own note for why that's not a typo
//         fix), registered under the `"renderItem"` key on each frame's series (the same convention
//         official-custom-hexbin.swift and others use).
//     (2) ecStat's `hierarchicalKMeans` bisecting k-means is ported to Swift
//         (EcStatHierarchicalKMeansStepper, ecStatClusteringTransform.swift — also backs the general
//         `ecStat:clustering` dataset-transform registration) and driven step-by-step exactly like the
//         JS's `for (...; !(stepResult = step.next()).isEnd; ...)` loop, building all 6 timeline frames.
//     note (framework gap, out of scope here): CustomView's shape registry
//     (makeShapeElement/applyShape) doesn't have an `"ellipse"` case yet, so `renderBoundary`'s ellipse
//     renders as an empty path if invoked. This never affects the STILL FRAME this gallery diffs (step 0
//     has zero boundary-series rows, so renderBoundary is never called there) — it would only show up if
//     someone scrubs the interactive gallery's timeline to steps 1-5.
//     note 2 (framework gap, out of scope here): the verified target is the SCATTER FIELD — at step 0
//     both panes draw the identical 60 grey circles at identical positions (the renderItemPoint closure +
//     frame data ported here). The vertical Timeline CHROME still differs: SliderTimelineView lays a
//     vertical (`orient: 'vertical'`) timeline on the LEFT rather than honouring `right: 50`, and its
//     `formatter: 'step {value}'` renders as bare "step" (the `{value}` substitution isn't wired for the
//     vertical axis) instead of "step 0".."step 5". Both are pre-existing SliderTimelineView gaps shared by
//     the other native timeline demos, independent of the clustering/renderItem work landed here.
import Foundation
import EChartsKit

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

// NOT upstream (harness only): pins `Math.random()` to the SAME LCG the Swift-native pane uses (see the
// file header's RNG note), spliced in right after the ecStat blob and before the example's own code reads
// it. `Math.imul` does the JS-side 32-bit wraparound multiply; `>>> 0` keeps the state an unsigned 32-bit
// int, matching Swift's `UInt32` `&*`/`&+` in EcStatLCG (ecStatClusteringTransform.swift) bit for bit.
private let scatterClusteringProcessRngJS = #"""
var __rndState = 1;
Math.random = function () {
  __rndState = (Math.imul(__rndState, 1664525) + 1013904223) >>> 0;
  return __rndState / 4294967296;
};
"""#

// MARK: - native clustering (ports ecStat's hierarchicalKMeans generator, drained into 6 frames)

private let scatterClusteringProcessColorAll: [String] = [
    "#bbb", "#37A2DA", "#e06343", "#37a354", "#b55dba", "#b5bd48", "#8378EA", "#96BFFF"
]

// Coerce a ParsedValue (Double | Int | NSNumber | nil) to Double — the recurring Int-vs-Double read trap.
private func scatterClusteringProcessNum(_ v: Any?) -> Double {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let n = v as? NSNumber { return n.doubleValue }
    return .nan
}

// One `hierarchicalKMeans` step's data + centroids, or (step 0) the raw un-clustered input.
private let scatterClusteringProcessFrames: [(data: [[Any]], centroids: [[Double]]?)] = {
    var frames: [(data: [[Any]], centroids: [[Double]]?)] = []
    // Step 0: `makeStepOption(option, originalData)` — the raw data, no cluster/centroid dims yet.
    frames.append((data: clusteringProcessData.map { $0 as [Any] }, centroids: nil))

    // Steps 1...(clusterCount-1): drain `hierarchicalKMeans(originalData, { clusterCount: 6,
    // outputType: 'single', outputClusterIndexDimension: 2, outputCentroidDimensions: [3, 4],
    // stepByStep: true })`'s `.next()` exactly like the JS `for (...; !(stepResult = step.next()).isEnd;
    // ...)` loop — one hierarchical split per call, discarding the final isEnd-only result.
    let stepper = EcStatHierarchicalKMeansStepper(
        data: clusteringProcessData.map { $0 as [Any] },
        clusterCount: 6,
        outputClusterIndexDimension: 2,
        outputCentroidDimensions: [3, 4],
        dimensions: nil,
        rng: EcStatLCG(seed: 1)   // matches scatterClusteringProcessRngJS's seed — see file header RNG note.
    )
    var result = stepper.next()
    while !result.isEnd {
        frames.append((data: result.data, centroids: result.centroids))
        result = stepper.next()
    }
    return frames
}()

// upstream `renderItemPoint(params, api)` — one circle per datum, coloured by its cluster index (dim 2;
// missing/NaN before clustering runs -> 0, colorAll[0] = grey), with a shadow glow on the cluster born
// THIS step (`isNewCluster`).
// `isNewCluster = clusterIdx === api.value(3)` is copied VERBATIM from the official example.
// Dim 3 is CENTER_DIM_IDX[0] — this datum's own assigned-centroid X COORDINATE, not the new-cluster
// INDEX — so the comparison (a small int cluster index against a float centroid X) is essentially always
// false in real runs. Ported as written, quirk included, not "fixed": this pane must match what the web
// pane's identical JS actually does, bug or not.
private let scatterClusteringProcessRenderItemPoint: CustomSeriesRenderItem = { _, api in
    let x0 = scatterClusteringProcessNum(api.value(0.0, nil))
    let y0 = scatterClusteringProcessNum(api.value(1.0, nil))
    let coord = api.coord([x0, y0], nil)

    // upstream: `var clusterIdx = api.value(2); if (clusterIdx == null || isNaN(clusterIdx)) clusterIdx = 0;`
    let clusterIdxRaw = scatterClusteringProcessNum(api.value(2.0, nil))
    let clusterIdx = clusterIdxRaw.isNaN ? 0 : Int(clusterIdxRaw)

    // upstream: `var isNewCluster = clusterIdx === api.value(3);` (strict equality; see note above).
    let v3 = scatterClusteringProcessNum(api.value(3.0, nil))
    let isNewCluster = !v3.isNaN && Double(clusterIdx) == v3

    let contentColor = scatterClusteringProcessColorAll[clusterIdx % scatterClusteringProcessColorAll.count]

    return [
        "type": "circle",
        "x": coord.count > 0 ? coord[0] : 0.0,
        "y": coord.count > 1 ? coord[1] : 0.0,
        "shape": ["cx": 0.0, "cy": 0.0, "r": 10.0] as [String: Any],
        "extra": ["transition": [String]()] as [String: Any],
        "style": [
            "fill": contentColor,
            "stroke": "#333",
            "lineWidth": 1.0,
            "shadowColor": contentColor,
            "shadowBlur": isNewCluster ? 12.0 : 0.0,
            "transition": ["shadowBlur", "fill"]
        ] as [String: Any]
    ] as [String: Any]
}

// upstream `renderProgress: ++targetRenderProgress` — a module-scope counter incremented once per
// ACTUAL renderBoundary call (during rendering, not option-build time). A plain file-scope `var` mirrors
// the JS closure-captured mutable global (never invoked at step 0 — see the file header note).
private var scatterClusteringProcessRenderProgress = 0.0

// upstream `renderBoundary(params, api)` — a dashed ellipse centred on the new centroid, sized in DATA
// units via `api.size` + a fixed 15px pad, grown from 0 by an `extra.renderProgress` transition.
private let scatterClusteringProcessRenderBoundary: CustomSeriesRenderItem = { _, api in
    let xVal = scatterClusteringProcessNum(api.value(0.0, nil))
    let yVal = scatterClusteringProcessNum(api.value(1.0, nil))
    let maxDist = scatterClusteringProcessNum(api.value(2.0, nil))
    let center = api.coord([xVal, yVal], nil)
    let size = (api.size([maxDist, maxDist], nil) as? [Double]) ?? []

    let cx = (center.count > 0 && !center[0].isNaN) ? center[0] : 0.0
    let cy = (center.count > 1 && !center[1].isNaN) ? center[1] : 0.0
    let rx = (size.count > 0 && !size[0].isNaN) ? size[0] + 15.0 : 15.0
    let ry = (size.count > 1 && !size[1].isNaN) ? size[1] + 15.0 : 15.0

    scatterClusteringProcessRenderProgress += 1

    return [
        // "ellipse" isn't a registered CustomView shape type (framework gap, out of this
        // task's scope) — renders as an empty path if this closure is ever invoked. See file header.
        "type": "ellipse",
        "shape": ["cx": cx, "cy": cy, "rx": rx, "ry": ry] as [String: Any],
        "extra": [
            "renderProgress": scatterClusteringProcessRenderProgress,
            "enterFrom": ["renderProgress": 0.0] as [String: Any],
            "transition": "renderProgress"
        ] as [String: Any],
        "style": [
            "fill": NSNull(),   // upstream `fill: null` — explicit no-fill, not an omitted key (see the
                                 // hexbin demo's NBACourt for why that distinction matters here).
            "stroke": "rgba(0,0,0,0.2)",
            "lineDash": [4.0, 4.0],
            "lineWidth": 4.0
        ] as [String: Any]
    ] as [String: Any]
}

// upstream `makeStepOption(option, data, centroids)` — builds one timeline frame's two `custom` series.
private func scatterClusteringProcessMakeFrame(_ data: [[Any]], _ centroids: [[Double]]?) -> [String: Any] {
    let newCluIdx = centroids != nil ? centroids!.count - 1 : -1
    var maxDist = 0.0
    if centroids != nil, newCluIdx >= 0 {
        for line in data {
            let ci = line.count > 2 ? scatterClusteringProcessNum(line[2]) : Double.nan
            guard !ci.isNaN, Int(ci) == newCluIdx else { continue }
            let x = line.count > 0 ? scatterClusteringProcessNum(line[0]) : Double.nan
            let y = line.count > 1 ? scatterClusteringProcessNum(line[1]) : Double.nan
            let cx = line.count > 3 ? scatterClusteringProcessNum(line[3]) : Double.nan
            let cy = line.count > 4 ? scatterClusteringProcessNum(line[4]) : Double.nan
            let dist0 = (x - cx) * (x - cx)
            let dist1 = (y - cy) * (y - cy)
            maxDist = Swift.max(maxDist, dist0 + dist1)
        }
    }
    let boundaryData: [[Any]] = (centroids != nil && newCluIdx >= 0)
        ? [[centroids![newCluIdx][0], centroids![newCluIdx][1], maxDist.squareRoot()]]
        : []

    return [
        "series": [
            [
                "type": "custom",
                "encode": ["tooltip": [0.0, 1.0]] as [String: Any],
                "renderItem": scatterClusteringProcessRenderItemPoint,
                "data": data
            ] as [String: Any],
            [
                "type": "custom",
                "renderItem": scatterClusteringProcessRenderBoundary,
                "animationDuration": 3000.0,
                "silent": true,
                "data": boundaryData
            ] as [String: Any]
        ]
    ] as [String: Any]
}

extension EChartsDemoRegistry {
    static let official_scatter_clustering_process = EChartsDemo(
        name: "official-scatter-clustering-process", category: "scatter",
        summary: "聚合过程可视化 — Clustering Process",
        width: 640, height: 420,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
// --- vendored echarts-stat (upstream/echarts/test/lib/ecStat.min.js), inlined: the official example
// --- side-loads it from a CDN and this page has no network. Defines the `ecStat` global. ---
\#(ecStatMinJS)
// --- end ecStat ---

// --- harness only (NOT upstream): pins Math.random() so this pane's clustering is reproducible — see
// --- the file header's RNG note. The official example follows, verbatim, from here. ---
\#(scatterClusteringProcessRngJS)

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
                // upstream: timeline.data is ['0' ... '5'], one label per hierarchicalKMeans step (raw
                // data + 5 splits up to clusterCount 6) — `scatterClusteringProcessFrames.count` frames.
                "data": (0..<scatterClusteringProcessFrames.count).map { String($0) }
            ] as [String: Any],
            "baseOption": [
                "animationDurationUpdate": 1500.0,
                "transition": ["shape"],
                // DEVIATION: see the header — the harness's `option.animation = false` cannot reach a
                // baseOption, so the static frame is pinned here instead.
                "animation": false,
                "tooltip": [:] as [String: Any],
                // upstream doesn't declare a `grid` (echarts synthesizes a default one from xAxis/yAxis
                // alone). note: the port's default-grid auto-completion doesn't reach a series whose
                // axes/grid only exist inside `baseOption` (a `timeline`+`baseOption`+`options` option
                // tree) — `Grid.create` -> `injectCoordSysByOption` resolves an `AxisModel` whose `.axis`
                // was never assigned, a `nil`-unwrap crash (unrelated to the clustering/renderItem work
                // here; official-mix-timeline-finance.swift and official-scatter-life-expectancy-
                // timeline.swift, the only other native `baseOption` demos, route around the same gap by
                // both declaring `grid` explicitly). An empty grid is the SAME default box echarts would
                // otherwise synthesize, so this is a no-op visually — just spelled out to sidestep the gap.
                "grid": [:] as [String: Any],
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
            // The timeline frames — `makeStepOption(option, originalData)` for step 0, then one call per
            // drained `hierarchicalKMeans` step (see scatterClusteringProcessFrames / …MakeFrame above).
            "options": scatterClusteringProcessFrames.map { scatterClusteringProcessMakeFrame($0.data, $0.centroids) }
        ])
}
