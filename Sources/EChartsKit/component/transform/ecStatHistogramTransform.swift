// ecStatHistogramTransform — faithful Swift port of echarts-stat (ecomfe/echarts-stat):
//   src/histogram.js (bin-count methods squareRoot/scott/freedmanDiaconis/sturges, the d3-tickStep-style
//   "nice" step chooser, the fixed-precision `range` builder, and the bisect-based bin assignment) +
//   src/transform/histogram.js (the `ecStat:histogram` registration) + src/util/dataProcess.js
//   (`dataPreprocess`) + src/util/isNumber.js (`quantityExponent`) + src/transform/helper.js
//   (`normalizeExistingDimensions`).
//
// echarts-stat is a SEPARATE plugin (not part of the echarts source tree the rest of this repo ports; see
// ecStatRegressionTransform.swift for the sibling `ecStat:regression` port and its own rationale). The
// official `bar-histogram` example declares `dataset[].transform: { type: 'ecStat:histogram', config }`.
// Without a Swift registration, `applyDataTransform` throws `Can not find transform on type
// "ecStat:histogram"` and the whole chart fails to build. This registers that external transform (via
// `transformInstall`) so the demo renders natively.
//
// SOURCE OF TRUTH: the vendored UMD bundle `upstream/echarts/test/lib/ecStat.min.js` (the exact build
// upstream's own test/data-transform-ecStat.html loads — same one this demo's web pane splices in). Every
// formula below was extracted from that bundle via
//   `node -e 'const e=require("./upstream/echarts/test/lib/ecStat.min.js"); console.log(e.histogram.toString())'`
// (module 7, the un-namespaced `histogram` core) plus the "nice step" (module 22) and `range` (module 21)
// helper modules dumped from the same file, and cross-checked by running `e.histogram(data, config)` in
// node against this Swift port's output on the demo's actual 31-point dataset (both dim 0 and dim 1) plus
// synthetic edge cases (all-equal values, two distinct values, negative ranges, values landing exactly on
// a bin threshold) — row-for-row identical bins/data/customData in every case.
//
// DEVIATIONS (both are dead paths for the shipped demo, which always supplies numeric data and never sets
// `config.method`):
//   - `config.method` naming an unrecognized method (upstream: `m[t.method]` is `undefined`, so calling it
//     throws a TypeError and the whole transform crashes) degrades to the `squareRoot` default here instead
//     of crashing — matches this port's general graceful-degrade convention (cf. ecSimpleTransformAggregate).
//   - All-non-numeric-input (empty `values`) short-circuits to an empty result instead of reproducing the
//     Infinity/NaN cascade upstream's `Math.min([])`/`Math.max([])` (`+Infinity`/`-Infinity`) would produce.
import Foundation

// MARK: - numeric / string coercions (JS `+value` / `''+value` equivalents for this transform's inputs)

private func histNum(_ v: Any?) -> Double? {
    switch v {
    case let d as Double: return d
    case let i as Int: return Double(i)
    case let n as NSNumber: return n.doubleValue
    case let s as String: return Double(s)
    default: return nil
    }
}

// JS `+x.toFixed(p)`: format to `p` decimals (as fixed-point) and parse back to a number. Used throughout
// histogramCore exactly where upstream calls `.toFixed(y)` — the same seam as the sibling transform files'
// `toFixedNumber` helpers (cf. MarkLineView.swift / PiecewiseModel.swift).
private func histToFixed(_ x: Double, _ p: Int) -> Double {
    let digits = Swift.max(0, p)
    let s = String(format: "%.\(digits)f", x)
    return Double(s) ?? x
}

// MARK: - src/util/isNumber.js `quantityExponent(n)` — floor(log10(n)), n===0 -> 0, with the +1 guard
//   against floating-point log() landing just under an exact power of ten.
private func histQuantityExponent(_ n: Double) -> Int {
    if n == 0 { return 0 }
    var r = Int(Foundation.floor(Foundation.log(n) / Foundation.log(10)))
    if n / Foundation.pow(10.0, Double(r)) >= 10 { r += 1 }
    return r
}

// MARK: - src/histogram.js's internal "nice step" helper (module 22 of the bundle) — a d3-tickStep-alike:
//   choose the {1,2,5,10} x 10^k step nearest `(max-min)/count` that "nicely" divides the range, plus the
//   decimal precision implied by that step.
private func histNiceStep(_ minV: Double, _ maxV: Double, _ count: Double) -> (step: Double, precision: Int) {
    let step0 = Swift.abs(maxV - minV) / count
    let expo = histQuantityExponent(step0)
    var a = Foundation.pow(10.0, Double(expo))
    let u = step0 / a
    if u >= Foundation.sqrt(50.0) { a *= 10 }
    else if u >= Foundation.sqrt(10.0) { a *= 5 }
    else if u >= Foundation.sqrt(2.0) { a *= 2 }
    let precision = expo < 0 ? -expo : 0
    let signedStep = maxV >= minV ? a : -a
    return (histToFixed(signedStep, precision), precision)
}

// MARK: - src/histogram.js's internal `range(start, stop, step, precision)` (module 21) — d3.range-alike,
//   every element rounded to `precision` decimals as it's generated (so `thresholds` never carries
//   floating-point step-accumulation drift).
private func histRange(_ start: Double, _ stop: Double, _ step: Double, _ precision: Int) -> [Double] {
    let count = Int(Foundation.ceil(histToFixed((stop - start) / step, precision)))
    guard count >= 0 else { return [] }
    var out: [Double] = []
    out.reserveCapacity(count + 1)
    for s in 0...count {
        out.append(histToFixed(start + Double(s) * step, precision))
    }
    return out
}

// MARK: - src/util/array.js `bisect(arr, val, lo, hi)` — binary search returning the right-biased
//   insertion index for `val` in the ascending array `arr` (thresholds are always strictly increasing, so
//   this is equivalent to a standard bisect-right).
private func histBisect(_ arr: [Double], _ val: Double, _ lo0: Int, _ hi0: Int) -> Int {
    var lo = lo0, hi = hi0
    while lo < hi {
        let mid = (lo + hi) / 2
        if arr[mid] > val { hi = mid }
        else if arr[mid] < val { lo = mid + 1 }
        else { return mid + 1 }
    }
    return lo
}

// MARK: - src/statistics/ helpers needed by the scott/freedmanDiaconis bin-count methods.

private func histMean(_ values: [Double]) -> Double {
    values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
}

// src/statistics/sampleVariance.js — sum((x-mean)^2) / (n-1), 0 when n<2.
private func histSampleVariance(_ values: [Double]) -> Double {
    if values.count < 2 { return 0 }
    let m = histMean(values)
    let sumSq = values.reduce(0.0) { $0 + ($1 - m) * ($1 - m) }
    return sumSq / Double(values.count - 1)
}

// src/statistics/deviation.js
private func histDeviation(_ values: [Double]) -> Double {
    Foundation.sqrt(histSampleVariance(values))
}

// src/statistics/quantile.js — linear-interpolation quantile over an ASCENDING array.
private func histQuantile(_ ascArr: [Double], _ p: Double) -> Double {
    let n = ascArr.count
    if n == 0 { return 0 }
    if p <= 0 || n < 2 { return ascArr[0] }
    if p >= 1 { return ascArr[n - 1] }
    let e = Double(n - 1) * p
    let o = Int(Foundation.floor(e))
    let lo = ascArr[o]
    let hi = ascArr[o + 1]
    return lo + (hi - lo) * (e - Double(o))
}

// MARK: - src/histogram.js `methods` map — bin-COUNT choosers, `(values, min, max) -> Int`.

private func histBinCountMethod(_ name: String?) -> (_ values: [Double], _ minV: Double, _ maxV: Double) -> Int {
    switch name {
    case "scott":
        return { values, minV, maxV in
            let sd = histDeviation(values)
            return Int(Foundation.ceil((maxV - minV) / (3.5 * sd * Foundation.pow(Double(values.count), -1.0 / 3.0))))
        }
    case "freedmanDiaconis":
        return { values, minV, maxV in
            let sorted = values.sorted()
            let q1 = histQuantile(sorted, 0.25)
            let q3 = histQuantile(sorted, 0.75)
            return Int(Foundation.ceil((maxV - minV) / (2 * (q3 - q1) * Foundation.pow(Double(values.count), -1.0 / 3.0))))
        }
    case "sturges":
        return { values, _, _ in
            Int(Foundation.ceil(Foundation.log(Double(values.count)) / Foundation.log(2.0))) + 1
        }
    // upstream default (method == null) AND the graceful-degrade path for an unrecognized method name
    // (see file header DEVIATIONS) both land on squareRoot, capped at 50.
    default:
        return { values, _, _ in
            Swift.min(Int(Foundation.ceil(Foundation.sqrt(Double(values.count)))), 50)
        }
    }
}

// MARK: - src/util/dataProcess.js `dataPreprocess(data, {dimensions, toOneDimensionArray: true})`.
//   `dims == nil` means "no dimension filter": every column of a row must be numeric for the row to
//   count, and dimension 0's value is what gets extracted. `dims != nil` means: every column named in
//   `dims` must be numeric, and `dims[0]`'s value is extracted (the histogram transform's `config.dimensions`
//   is always effectively a single-element selector in practice, but this stays faithful to the general
//   multi-dim filter upstream implements).
private func histDataPreprocess(_ data: [[Any]], dims: [Int]?) -> [Double] {
    guard !data.isEmpty else { return [] }
    let allowedSet: Set<Int>? = dims.map(Set.init)
    let targetDim = dims?.first ?? 0
    // upstream infers the "shape" (column count to check) from data[0].length when no dims filter is given.
    let columnsToCheck: [Int] = allowedSet.map { Array($0) } ?? Array(0..<(data[0].count))
    var out: [Double] = []
    out.reserveCapacity(data.count)
    for row in data {
        let rowValid = columnsToCheck.allSatisfy { p in p < row.count && histNum(row[p]) != nil }
        if rowValid, targetDim < row.count, let v = histNum(row[targetDim]) {
            out.append(v)
        }
    }
    return out
}

// MARK: - src/histogram.js core `histogram(data, options)` (the un-namespaced export module 7).

private struct HistogramComputeResult {
    var data: [[Any]]
    var customData: [[Any]]
}

private func histogramCompute(_ rawData: [[Any]], method: String?, dims: [Int]?) -> HistogramComputeResult {
    let methodFn = histBinCountMethod(method)
    let values = histDataPreprocess(rawData, dims: dims)
    // DEVIATION (see file header): empty input degrades to an empty result rather than reproducing
    //   upstream's +/-Infinity NaN cascade.
    guard let maxV = values.max(), let minV = values.min() else {
        return HistogramComputeResult(data: [], customData: [])
    }

    let binCount = methodFn(values, minV, maxV)
    let nice = histNiceStep(minV, maxV, Double(binCount))
    let step = nice.step
    let precision = nice.precision

    let niceMin = histToFixed(Foundation.ceil(minV / step) * step, precision)
    let niceMax = histToFixed(Foundation.floor(maxV / step) * step, precision)
    let thresholds = histRange(niceMin, niceMax, step, precision)
    let b = thresholds.count

    // upstream: D[E].x0 = E>0 ? w[E-1] : (w[E]-c===M ? c : w[E]-M)
    //           D[E].x1 = E<b ? w[E]   : (f-w[E-1]===M ? f : w[E-1]+M)
    // (b+1 bins, indices 0...b; the first/last bin's outer edge either snaps to the true min/max, when
    // that's exactly one step short of the first/last threshold, or extends one more step beyond it.)
    var x0s = [Double](repeating: 0, count: b + 1)
    var x1s = [Double](repeating: 0, count: b + 1)
    for e in 0...b {
        x0s[e] = e > 0 ? thresholds[e - 1] : ((thresholds[0] - minV == step) ? minV : thresholds[0] - step)
        x1s[e] = e < b ? thresholds[e] : ((maxV - thresholds[b - 1] == step) ? maxV : thresholds[b - 1] + step)
    }
    var counts = [Int](repeating: 0, count: b + 1)
    for v in values where minV <= v && v <= maxV {
        counts[histBisect(thresholds, v, 0, b)] += 1
    }

    var data: [[Any]] = []
    var customData: [[Any]] = []
    data.reserveCapacity(b + 1)
    customData.reserveCapacity(b + 1)
    for e in 0...b {
        let x0 = x0s[e], x1 = x1s[e], n = counts[e]
        let center = histToFixed((x0 + x1) / 2, precision)
        let label = number.jsNumberString(x0) + " - " + number.jsNumberString(x1)
        data.append([center, Double(n), x0, x1, label])
        customData.append([x0, x1, Double(n)])
    }
    return HistogramComputeResult(data: data, customData: customData)
}

// MARK: - src/transform/helper.js `normalizeExistingDimensions(params, dimsConfig)` fused with
//   src/util/dataProcess.js `normalizeDimensions` (which just wraps a bare number into a 1-element array):
//   resolves `config.dimensions` (nil / a single dim ref / an array of dim refs) against `upstream` to an
//   `[Int]?` of absolute dimension indices, or nil if `config.dimensions` was not supplied.
private func histNormalizeExistingDimensions(_ upstream: ExternalSource, _ dimsConfig: Any?) throws -> [Int]? {
    guard let dimsConfig = dimsConfig, !(dimsConfig is NSNull) else { return nil }
    if let arr = dimsConfig as? [Any] {
        var out: [Int] = []
        for entry in arr {
            guard let info = upstream.getDimensionInfo(entry) else {
                throw EChartsError(message: "Can not find dimension by \(entry)")
            }
            out.append(Int(info.index))
        }
        return out
    }
    guard let info = upstream.getDimensionInfo(dimsConfig) else {
        throw EChartsError(message: "Can not find dimension by \(dimsConfig)")
    }
    return [Int(info.index)]
}

// upstream src/transform/histogram.js:
//   type: 'ecStat:histogram',
//   transform: function (params) {
//     var result = histogram(params.upstream.cloneRawData(), {
//       method: (params.config || {}).method,
//       dimensions: normalizeExistingDimensions(params, (params.config || {}).dimensions)
//     });
//     return [
//       { dimensions: ['MeanOfV0V1', 'VCount', 'V0', 'V1', 'DisplayableName'], data: result.data },
//       { data: result.customData }
//     ];
//   }
let ecStatHistogramTransform = ExternalDataTransform(
    type: "ecStat:histogram",
    transform: { params in
        let upstream = params.upstream
        let config = (params.config as? [String: Any]) ?? [:]

        do {
            let dims = try histNormalizeExistingDimensions(upstream, config["dimensions"])
            let method = config["method"] as? String
            let raw = (try upstream.cloneRawData()) as? [[Any]] ?? []
            let result = histogramCompute(raw, method: method, dims: dims)

            let item0 = ExternalDataTransformResultItem(
                data: result.data,
                dimensions: ["MeanOfV0V1", "VCount", "V0", "V1", "DisplayableName"] as [DimensionDefinitionLoose]
            )
            let item1 = ExternalDataTransformResultItem(data: result.customData)
            return [item0, item1]
        }
        catch {
            // NOTE: the ExternalDataTransform closure is non-throwing (matches the other ported
            //   transforms' convention); a failure degrades to a single empty result rather than crashing
            //   the whole chart build.
            log.error("ecStat:histogram failed: \(error)")
            return [ExternalDataTransformResultItem(data: [[Any]]())]
        }
    }
)
