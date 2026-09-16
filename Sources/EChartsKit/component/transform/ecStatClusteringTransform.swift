// ecStatClusteringTransform — faithful Swift port of echarts-stat (ecomfe/echarts-stat):
//   src/clustering.js (hierarchicalKMeans + its kMeans/distEuclid/createRandCent/meanInColumns/
//   calcExtents helpers) + src/transform/clustering.js (the `ecStat:clustering` dataset transform) +
//   src/transform/helper.js (normalizeNewDimensions/normalizeExistingDimensions) + src/util/dataProcess.js
//   (dataPreprocess/normalizeDimensions).
//
// echarts-stat is a SEPARATE plugin (not part of the echarts source tree the rest of this repo ports; see
// ecStatRegressionTransform.swift for the sibling `ecStat:regression` port and its own header). Its
// `ecStat:clustering` transform (hierarchical bisecting k-means: start from one cluster — the centroid of
// all points — and repeatedly split whichever cluster's 2-means split reduces total SSE the most, until
// `clusterCount` clusters exist) backs the official `scatter-clustering` example's `dataset[].transform`
// AND `scatter-clustering-process`'s direct `ecStat.clustering.hierarchicalKMeans(..., {stepByStep:true})`
// call (drained one split per timeline step). Verified byte-for-byte against the vendored
// upstream/echarts/test/lib/ecStat.min.js (`e.transform.clustering.transform`) by loading the unminified
// echarts-stat source (github.com/ecomfe/echarts-stat @ master) through a small AMD shim and diffing both
// under the SAME seeded Math.random() override on sample data — identical output.
//
// RANDOMNESS: `createRandCent` (candidate centroid init for each 2-means split) calls `Math.random()`,
// which the vendored ecStat.min.js does NOT seed — so even the official reference page's own clustering
// is nondeterministic run to run. A native still-frame render needs to be reproducible, so `EcStatLCG`
// below stands in for `Math.random()`: the same `state = state*1664525 + 1013904223 (mod 2^32)` generator
// this repo already uses elsewhere for reproducible "random" demos (e.g. official-matrix-covariance.swift's
// `rnd()`). official-scatter-clustering-process.swift ALSO splices the identical LCG over `Math.random` in
// its web pane's JS (ahead of the vendored ecStat blob), so both panes run the identical bisecting-kmeans
// arithmetic over the identical draw sequence — since both JS numbers and Swift `Double` are IEEE754
// binary64 and the algorithm below only uses +,-,*,/ and comparisons (no transcendental functions), the
// two panes' clustering is expected to match exactly, not just "the same shape".
import Foundation

// MARK: - seeded RNG (Math.random() stand-in)

/// `state = state*1664525 + 1013904223 (mod 2^32)`, returned scaled to `[0, 1)` — the same LCG this repo
/// splices into reference pages elsewhere (see file header). A `final class` (not a struct) so the SAME
/// generator instance's state threads through every `createRandCent` call during one clustering run,
/// mirroring a single shared `Math.random` stream.
public final class EcStatLCG {
    private var state: UInt32
    public init(seed: UInt32) { self.state = seed }
    public func next() -> Double {
        state = state &* 1664525 &+ 1013904223
        return Double(state) / 4294967296.0
    }
}

// MARK: - JS-ish coercions (mirrors util/number.js's `isNumber`, and JS unary `+value`)

// JS unary `+value` numeric coercion — permissive, NaN on failure.
private func cluToNum(_ v: Any?) -> Double {
    switch v {
    case let d as Double: return d
    case let i as Int: return Double(i)
    case let n as NSNumber: return n.doubleValue
    case let s as String: return Double(s) ?? Double.nan
    case let b as Bool: return b ? 1 : 0
    default: return Double.nan
    }
}

// upstream util/number.js `isNumber(value)`: `value = value===null?NaN:+value; typeof value==='number' && !isNaN(value)`.
private func cluIsNumber(_ v: Any?) -> Bool {
    if v == nil || v is NSNull { return false }
    return !cluToNum(v).isNaN
}

// A config number that participates in Swift `Optional` chaining (nil on failure, unlike `cluToNum`'s NaN).
private func cluConfigNumber(_ v: Any?) -> Double? {
    let n = cluToNum(v)
    return n.isNaN ? nil : n
}

// upstream: sparse-array assignment (`arr[idx] = value` past the end pads with `undefined` holes).
// NSNull() stands in for those holes, matching the convention already used by the sibling transform ports
// (ecSimpleTransformAggregate.swift).
private func cluSetAt(_ row: inout [Any], _ idx: Int, _ value: Any) {
    while row.count <= idx { row.append(NSNull()) }
    row[idx] = value
}

// MARK: - util/dataProcess.js

// upstream `dataPreprocess(data, {dimensions})` — only the 2-D-array branch is ported (clustering always
// feeds a 2-D `[[x, y, ...], ...]` table; the 1-D branch is dead code from this call site). Keeps
// non-target columns untouched, drops rows where any TARGET dimension isn't numeric.
private func cluDataPreprocess(_ data: [[Any]], _ dimensions: [Int]) -> [[Any]] {
    let dimSet = Set(dimensions)
    let colCount = data.first?.count ?? 0
    var predata: [[Any]] = []
    predata.reserveCapacity(data.count)
    for item in data {
        var isCorrect = true
        for j in 0..<colCount {
            guard dimSet.contains(j) else { continue }   // shouldBeNumberDimension(j)
            let val: Any? = j < item.count ? item[j] : nil
            if !cluIsNumber(val) { isCorrect = false; break }
        }
        if isCorrect { predata.append(item) }
    }
    return predata
}

// MARK: - src/clustering.js

private struct EcStatExtent { var min: Double = .infinity; var max: Double = -.infinity; var span: Double = 0 }

// upstream `calcExtents(dataSet, dimensions)`.
private func cluCalcExtents(_ dataSet: [[Any]], _ dimensions: [Int]) -> [EcStatExtent] {
    var extents = Array(repeating: EcStatExtent(), count: dimensions.count)
    for line in dataSet {
        for (j, dimIdx) in dimensions.enumerated() {
            let val = dimIdx < line.count ? cluToNum(line[dimIdx]) : Double.nan
            // upstream: `extentItem.min > val && (extentItem.min = val)` — a NaN comparison is false in
            // both JS and Swift (IEEE754), so a malformed value is silently skipped exactly like upstream.
            if extents[j].min > val { extents[j].min = val }
            if extents[j].max < val { extents[j].max = val }
        }
    }
    for j in 0..<dimensions.count { extents[j].span = extents[j].max - extents[j].min }
    return extents
}

// upstream `distEuclid(dataItem, centroid, dataMeta)` — normalizes each dimension's delta by
// `dataMeta.rawExtents[i].span` (the GLOBAL extents computed once at setup — NOT the local subset's
// extents `createRandCent` uses for centroid init; see `cluKMeans` below).
private func cluDistEuclid(_ dataItem: [Any], _ centroid: [Double], _ dimensions: [Int], _ rawExtents: [EcStatExtent]) -> Double {
    var powerSum = 0.0
    for i in 0..<dimensions.count {
        let span = rawExtents[i].span
        // upstream `if (span)` — falsy for 0 AND NaN.
        if span != 0, !span.isNaN {
            let dimIdx = dimensions[i]
            let itemVal = dimIdx < dataItem.count ? cluToNum(dataItem[dimIdx]) : Double.nan
            let centroidVal = i < centroid.count ? centroid[i] : Double.nan
            let dist = (itemVal - centroidVal) / span
            powerSum += dist * dist
        }
    }
    return powerSum
}

// upstream `meanInColumns(dataList, dataMeta)` — `sum / 0` (empty `dataList`) is NaN in both JS and Swift.
private func cluMeanInColumns(_ dataList: [[Any]], _ dimensions: [Int]) -> [Double] {
    var meanArray: [Double] = []
    meanArray.reserveCapacity(dimensions.count)
    for dimIdx in dimensions {
        var sum = 0.0
        for row in dataList { sum += dimIdx < row.count ? cluToNum(row[dimIdx]) : Double.nan }
        meanArray.append(sum / Double(dataList.count))
    }
    return meanArray
}

// upstream `createRandCent(k, extents)` — `extents` here is the CANDIDATE SUBSET's own extents (computed
// fresh per `kMeans` call), not the global `rawExtents` `distEuclid` uses. `Math.random()` -> `rng.next()`.
private func cluCreateRandCent(_ k: Int, _ extents: [EcStatExtent], _ rng: EcStatLCG) -> [[Double]] {
    var centroids = Array(repeating: [Double](repeating: 0, count: extents.count), count: k)
    for j in 0..<extents.count {
        let e = extents[j]
        for i in 0..<k {
            centroids[i][j] = e.min + e.span * rng.next()
        }
    }
    return centroids
}

// upstream `kMeans(data, k, dataMeta)` — plain (non-hierarchical) k-means, always called with k=2 from
// `hierarchicalKMeans`'s bisecting step. `clusterAssigned[i]` is `[clusterIndex, squaredDist]`.
private func cluKMeans(
    _ data: [[Any]], _ k: Int, _ dimensions: [Int], _ rawExtents: [EcStatExtent], _ rng: EcStatLCG
) -> (centroids: [[Double]], clusterAssigned: [[Double]]) {
    var clusterAssigned = Array(repeating: [Double](repeating: 0, count: 2), count: data.count)
    let localExtents = cluCalcExtents(data, dimensions)
    var centroids = cluCreateRandCent(k, localExtents, rng)
    var clusterChanged = true
    while clusterChanged {
        clusterChanged = false
        for i in 0..<data.count {
            var minDist = Double.infinity
            var minIndex = -1
            for j in 0..<k {
                let d = cluDistEuclid(data[i], centroids[j], dimensions, rawExtents)
                if d < minDist { minDist = d; minIndex = j }
            }
            if clusterAssigned[i][0] != Double(minIndex) { clusterChanged = true }
            clusterAssigned[i][0] = Double(minIndex)
            clusterAssigned[i][1] = minDist
        }
        for i in 0..<k {
            var ptsInClust: [[Any]] = []
            for j in 0..<clusterAssigned.count where clusterAssigned[j][0] == Double(i) {
                ptsInClust.append(data[j])
            }
            centroids[i] = cluMeanInColumns(ptsInClust, dimensions)
        }
    }
    return (centroids, clusterAssigned)
}

/// upstream `hierarchicalKMeans`'s per-step result — one entry per `next()` call, `outputType: 'single'`
/// shape only (see the class doc below for why `'multiple'` isn't ported).
public struct EcStatClusteringStepResult {
    public var data: [[Any]]
    public var centroids: [[Double]]
    public var isEnd: Bool
}

/// Faithful, `outputType: 'single'`-only port of echarts-stat's `hierarchicalKMeans` (src/clustering.js).
/// `'multiple'` output isn't ported: `transform/clustering.js` (the dataset-transform entry point) always
/// hardcodes `outputType: OutputType.SINGLE`, so that branch is dead code from the transform's perspective;
/// the direct-API caller (official-scatter-clustering-process.swift) also only needs SINGLE.
///
/// `next()` performs exactly one bisecting split — mirrors upstream's `stepByStep: true` generator
/// (`result.next = function () { oneStep(); setCentroidToResultData(result, dataMeta); return result; }`).
/// The ONE-SHOT `ecStat:clustering` transform below just drains `next()` in a loop until `isEnd`
/// (matching upstream's `stepByStep: false` path: `while (oneStep(), !result.isEnd);`).
public final class EcStatHierarchicalKMeansStepper {
    private let dimensions: [Int]
    private let rawExtents: [EcStatExtent]
    private let k: Int
    private let outputClusterIndexDimension: Int
    private let outputCentroidDimensions: [Int]?
    private let rng: EcStatLCG

    private var dataSet: [[Any]]
    private var outputSingleData: [[Any]]
    private var distances: [Double]     // upstream `clusterAssment[:, 1]` (internal SSE bookkeeping, distinct from the output rows)
    private var centList: [[Double]]
    private var index = 1
    private var isEnd = false

    /// - Parameters:
    ///   - data: raw `[[x, y, ...otherColumns]]` rows (upstream's `data` param, pre-`dataPreprocess`).
    ///   - dimensions: target dims (upstream `config.dimensions`); `nil` defaults to every column, like
    ///     upstream's `normalizeDimensions(undefined, defaultDimensions)`.
    public init(
        data: [[Any]],
        clusterCount: Int,
        outputClusterIndexDimension: Int,
        outputCentroidDimensions: [Int]? = nil,
        dimensions: [Int]? = nil,
        rng: EcStatLCG
    ) {
        let colCount = data.first?.count ?? 0
        let dims = dimensions ?? Array(0..<colCount)
        self.dimensions = dims
        // upstream `parseDataMeta` computes `rawExtents` from the RAW `data` param, BEFORE `dataPreprocess`
        // filters malformed rows.
        self.rawExtents = cluCalcExtents(data, dims)
        self.k = max(clusterCount, 2)
        self.outputClusterIndexDimension = outputClusterIndexDimension
        self.outputCentroidDimensions = outputCentroidDimensions
        self.rng = rng

        let filtered = cluDataPreprocess(data, dims)
        self.dataSet = filtered

        var out: [[Any]] = []
        out.reserveCapacity(filtered.count)
        var dist = [Double](repeating: 0, count: filtered.count)
        for i in 0..<filtered.count {
            var row = filtered[i]                              // upstream: outputSingleData.push(dataSet[i].slice())
            cluSetAt(&row, outputClusterIndexDimension, 0.0)    // setClusterIndex(i, 0)
            out.append(row)
            dist[i] = 0                                         // setDistance(i, 0)
        }
        self.outputSingleData = out
        self.distances = dist

        let centroid0 = cluMeanInColumns(filtered, dims)
        self.centList = [centroid0]
        for i in 0..<filtered.count {
            self.distances[i] = cluDistEuclid(filtered[i], centroid0, dims, self.rawExtents)
        }

        // upstream: the unconditional `setCentroidToResultData(result, dataMeta)` right after setup
        // (BEFORE any step — matches, since `applyCentroidsToOutput` is a no-op unless
        // `outputCentroidDimensions` is set, and cluster 0 owns every point at this point anyway).
        applyCentroidsToOutput()
    }

    private func getClusterIndex(_ i: Int) -> Int {
        Int(cluToNum(outputSingleData[i][outputClusterIndexDimension]))
    }
    private func setClusterIndex(_ i: Int, _ v: Int) {
        cluSetAt(&outputSingleData[i], outputClusterIndexDimension, Double(v))
    }

    // upstream `setCentroidToResultData(result, dataMeta)`.
    private func applyCentroidsToOutput() {
        guard let centroidDims = outputCentroidDimensions else { return }
        for i in 0..<outputSingleData.count {
            let clusterIndex = getClusterIndex(i)
            guard clusterIndex >= 0, clusterIndex < centList.count else { continue }
            let centroid = centList[clusterIndex]
            let dimLen = Swift.min(centroid.count, centroidDims.count)
            for j in 0..<dimLen {
                cluSetAt(&outputSingleData[i], centroidDims[j], centroid[j])
            }
        }
    }

    // upstream `oneStep()`.
    private func oneStep() {
        guard index < k else { isEnd = true; return }

        var lowestSSE = Double.infinity
        var centSplit = -1
        var newCentroid: [[Double]] = []
        var newClusterAss: [[Double]] = []

        for j in 0..<centList.count {
            var ptsInClust: [[Any]] = []
            var ptsNotClust: [Double] = []
            for i in 0..<dataSet.count {
                if getClusterIndex(i) == j {
                    ptsInClust.append(dataSet[i])
                } else {
                    ptsNotClust.append(distances[i])
                }
            }
            let clusterInfo = cluKMeans(ptsInClust, 2, dimensions, rawExtents, rng)
            let sseSplit = clusterInfo.clusterAssigned.reduce(0.0) { $0 + $1[1] }   // sumOfColumn(...,1)
            let sseNotSplit = ptsNotClust.reduce(0.0, +)                            // arraySum(...)
            if sseSplit + sseNotSplit < lowestSSE {
                lowestSSE = sseNotSplit + sseSplit
                centSplit = j
                newCentroid = clusterInfo.centroids
                newClusterAss = clusterInfo.clusterAssigned
            }
        }

        // note (defensive, not in upstream): `centSplit` only stays -1 if every candidate's SSE sum
        // is NaN, which requires every current cluster to be simultaneously empty — unreachable while
        // `dataSet` is non-empty (pigeonhole: some cluster owns every point). Guards a Swift crash (JS's
        // `centList[-1] = ...` would just silently no-op) rather than mirroring a literally unreachable path.
        guard centSplit >= 0 else { index += 1; return }

        for i in 0..<newClusterAss.count {
            if newClusterAss[i][0] == 0 { newClusterAss[i][0] = Double(centSplit) }
            else if newClusterAss[i][0] == 1 { newClusterAss[i][0] = Double(centList.count) }
        }

        centList[centSplit] = newCentroid[0]
        centList.append(newCentroid[1])

        var jIdx = 0
        for i in 0..<dataSet.count {
            if jIdx >= newClusterAss.count { break }
            if getClusterIndex(i) == centSplit {
                setClusterIndex(i, Int(newClusterAss[jIdx][0]))
                distances[i] = newClusterAss[jIdx][1]
                jIdx += 1
            }
        }

        index += 1
    }

    /// One hierarchical split (upstream `.next()`). Keep calling until `.isEnd` to fully drain, exactly
    /// like `makeStepOption`'s `for (...; !(stepResult = step.next()).isEnd; ...)` loop.
    @discardableResult
    public func next() -> EcStatClusteringStepResult {
        oneStep()
        applyCentroidsToOutput()
        return EcStatClusteringStepResult(data: outputSingleData, centroids: centList, isEnd: isEnd)
    }
}

// MARK: - src/transform/helper.js

// upstream `normalizeNewDimensions(dimensionsConfig)` — parses `outputClusterIndexDimension` /
// `outputCentroidDimensions` config values. Supports the shapes the two ported demos actually pass (a
// plain index, or an array of indices/`{name,index}` objects); `name` is carried along for the
// `resultDimsDef` bookkeeping below.
private struct EcStatNewDims { var indices: [Int]; var names: [Any] }

private func cluParseNewDimItem(_ cfg: Any) -> (Int, Any) {
    if let n = cluConfigNumber(cfg) { return (Int(n), NSNull()) }
    if let dict = cfg as? [String: Any], let n = cluConfigNumber(dict["index"]) {
        return (Int(n), dict["name"] ?? NSNull())
    }
    return (0, NSNull())   // upstream throws "Illegle new dimensions config."; degrade instead (see transform closure's error handling).
}

private func cluParseNewDims(_ cfg: Any?) -> EcStatNewDims? {
    guard let cfg = cfg, !(cfg is NSNull) else { return nil }
    if let arr = cfg as? [Any] {
        var indices: [Int] = []; var names: [Any] = []
        for item in arr {
            let (idx, name) = cluParseNewDimItem(item)
            indices.append(idx); names.append(name)
        }
        return EcStatNewDims(indices: indices, names: names)
    }
    let (idx, name) = cluParseNewDimItem(cfg)
    return EcStatNewDims(indices: [idx], names: [name])
}

// upstream `normalizeExistingDimensions(transformParams, dimensionsConfig)` — resolves `config.dimensions`
// (dim names/indices as the CALLER wrote them) to concrete store indices via `upstream.getDimensionInfo`.
private func cluNormalizeExistingDimensions(_ upstream: ExternalSource, _ dimensionsConfig: Any?) -> [Int]? {
    guard let cfg = dimensionsConfig, !(cfg is NSNull) else { return nil }
    if let arr = cfg as? [Any] {
        let result = arr.compactMap { upstream.getDimensionInfo($0).map { Int($0.index) } }
        return result.isEmpty ? nil : result
    }
    guard let dimInfo = upstream.getDimensionInfo(cfg) else { return nil }
    return [Int(dimInfo.index)]
}

// MARK: - src/transform/clustering.js

// upstream: export const clustering: DataTransformOption's transform (`type: 'ecStat:clustering'`).
let ecStatClusteringTransform = ExternalDataTransform(
    type: "ecStat:clustering",
    transform: { params in
        let config = (params.config as? [String: Any]) ?? [:]

        // NOTE: like the sibling ecStat/echarts-simple-transform ports, this closure is non-throwing —
        //   a malformed config degrades to an empty result (the page renders blank rather than crashing)
        //   instead of upstream's `throw new Error(...)`.
        guard let clusterCountNum = cluConfigNumber(config["clusterCount"]), clusterCountNum > 0 else {
            log.error("ecStat:clustering failed: config param \"clusterCount\" need to be specified as an interger greater than 1.")
            return ExternalDataTransformResultItem(data: [[Any]]())
        }
        let clusterCount = Int(clusterCountNum)

        if clusterCount == 1 {
            // upstream: `return [{}, {data: []}]` — the first item's `data` key is entirely absent, which
            //   downstream treats as a hard error ("Transform result data should be not be null or
            //   undefined"). Degrade to an empty result instead of mirroring that throw (this closure
            //   can't throw).
            return ExternalDataTransformResultItem(data: [[Any]]())
        }

        guard let clusterIdxDims = cluParseNewDims(config["outputClusterIndexDimension"]),
              let outputClusterIndexDimension = clusterIdxDims.indices.first
        else {
            log.error("ecStat:clustering failed: outputClusterIndexDimension is required as a number.")
            return ExternalDataTransformResultItem(data: [[Any]]())
        }
        let centroidDims = cluParseNewDims(config["outputCentroidDimensions"])

        let raw = (try? params.upstream.cloneRawData()) as? [[Any]] ?? []
        let dims = cluNormalizeExistingDimensions(params.upstream, config["dimensions"])

        let stepper = EcStatHierarchicalKMeansStepper(
            data: raw,
            clusterCount: clusterCount,
            outputClusterIndexDimension: outputClusterIndexDimension,
            outputCentroidDimensions: centroidDims?.indices,
            dimensions: dims,
            // NOTE (see file header): NOT seeded to match any particular web-pane run — echarts-stat's own
            //   `Math.random()` isn't seeded either. Fixed seed 1 just keeps THIS pane's own renders
            //   reproducible run to run, matching the repo's established "seed 1" LCG convention.
            rng: EcStatLCG(seed: 1)
        )
        var result = stepper.next()
        while !result.isEnd { result = stepper.next() }

        // upstream: resultDimsDef built from `upstream.cloneAllDimensionInfo()`, then the cluster-index /
        //   centroid dims' names spliced in (always, even if `name` is absent — the ARRAY LENGTH itself is
        //   what tells echarts "there is a cluster index dimension here").
        var resultDimsDef: [Any] = params.upstream.cloneAllDimensionInfo().map { ($0.name as Any?) ?? NSNull() }
        cluSetAt(&resultDimsDef, outputClusterIndexDimension, clusterIdxDims.names.first ?? NSNull())
        if let centroidDims = centroidDims {
            for i in 0..<centroidDims.indices.count where !(centroidDims.names[i] is NSNull) {
                cluSetAt(&resultDimsDef, centroidDims.indices[i], centroidDims.names[i])
            }
        }

        return [
            ExternalDataTransformResultItem(data: result.data, dimensions: resultDimsDef),
            ExternalDataTransformResultItem(data: result.centroids.map { $0 as [Any] })
        ]
    }
)
