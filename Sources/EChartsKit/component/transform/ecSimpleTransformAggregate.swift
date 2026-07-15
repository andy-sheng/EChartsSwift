// Ported from echarts-simple-transform's `aggregate` transform (upstream/echarts/test/lib/ecSimpleTransform.js,
// `exports.aggregate`) — keep in sync with that source. echarts-simple-transform is a separate JS plugin
// (github.com/apache/echarts-simple-transform), NOT part of the echarts source tree; it is ported here so the
// official `data-transform-aggregate` example builds natively. Registered under its own `ecSimpleTransform:`
// namespace (registerExternalTransform keeps the full "ecSimpleTransform:aggregate" type — only the official
// "echarts:" namespace is stripped), so a page references it as `transform: { type: 'ecSimpleTransform:aggregate' }`.
//
// Group the upstream rows by a `groupBy` dimension, then reduce each group's chosen source dimension to an
// aggregate (min / Q1 / median(=Q2) / Q3 / max / sum / count / first / average). Two passes exactly like the
// JS: a "collection" pass gathers the raw values that quantile/average need (sorted per group), then a "final"
// pass produces one output row per group.
import Foundation

// upstream: quantile(ascArr, p) — linear-interpolation quantile over an ascending numeric array.
private func aggQuantile(_ ascArr: [Double], _ p: Double) -> Double {
    let H = Double(ascArr.count - 1) * p + 1
    let h = floor(H)
    let v = ascArr[Int(h) - 1]
    let e = H - h
    return e != 0 ? v + e * (ascArr[Int(h)] - v) : v
}

// upstream JS unary `+value` numeric coercion (retrieveValue yields NSNumber/Double/Int/String).
private func aggToNum(_ v: Any?) -> Double {
    switch v {
    case let d as Double: return d
    case let i as Int: return Double(i)
    case let n as NSNumber: return n.doubleValue
    case let s as String: return Double(s) ?? Double.nan
    default: return Double.nan
    }
}

// upstream `groupByVal + ''` — the string key a group value maps to.
private func aggGroupStr(_ v: Any?) -> String {
    switch v {
    case let s as String: return s
    case let n as NSNumber: return n.stringValue
    case let d as Double: return d == d.rounded() ? String(Int(d)) : String(d)
    case let i as Int: return String(i)
    default: return "\(v ?? "")"
    }
}

private func aggIsNull(_ v: Any?) -> Bool {
    return v == nil || v is NSNull
}

// upstream: METHOD_INTERNAL / METHOD_NEEDS_COLLECT / METHOD_NEEDS_GATHER_VALUES / METHOD_ALIAS.
private let AGG_METHOD_INTERNAL: Set<String> = ["SUM", "COUNT", "FIRST", "AVERAGE", "Q1", "Q2", "Q3", "MIN", "MAX"]
private let AGG_METHOD_NEEDS_COLLECT: [String: [String]] = ["AVERAGE": ["COUNT"]]
private let AGG_METHOD_NEEDS_GATHER_VALUES: Set<String> = ["Q1", "Q2", "Q3"]
private let AGG_METHOD_ALIAS: [String: String] = ["MEDIAN": "Q2"]

// upstream: normalizeMethod(method) — null → 'FIRST', upper-case, resolve MEDIAN alias, validate.
private func aggNormalizeMethod(_ method: Any?) throws -> String {
    guard let m = method as? String else {
        // upstream: `if (method == null) return 'FIRST';`
        if aggIsNull(method) { return "FIRST" }
        throw EChartsError(message: "Illegal method \(String(describing: method)).")
    }
    var methodInternal = m.uppercased()
    if let alias = AGG_METHOD_ALIAS[methodInternal] { methodInternal = alias }
    if !AGG_METHOD_INTERNAL.contains(methodInternal) {
        throw EChartsError(message: "Illegal method \(m).")
    }
    return methodInternal
}

// upstream: class ResultDimInfoInternal — mutable per-result-dimension accumulator. A `final class` so the
//   `travel` output lines (which reference these via closures) share one instance, matching JS.
private final class AggResultDimInfo {
    var collectionInfoList: [(method: String, indexInLine: Int)] = []
    var gatheredValuesByGroup: [String: [Double]] = [:]
    var gatheredValuesNoGroup: [Double] = []
    var needGatherValues: Bool
    private var _collectionInfoMap: [String: Int] = [:]
    let method: String
    let name: String
    let index: Int
    let indexInUpstream: Int
    // upstream `__collectionResult` monkey-patched onto the dim info after the collection pass.
    var collectionResult: AggTravelResult?

    init(index: Int, indexInUpstream: Int, method: String, name: String, needGatherValues: Bool) {
        self.index = index
        self.indexInUpstream = indexInUpstream
        self.method = method
        self.name = name
        self.needGatherValues = needGatherValues
    }

    func addCollectionInfo(_ item: (method: String, indexInLine: Int)) {
        _collectionInfoMap[item.method] = collectionInfoList.count
        collectionInfoList.append(item)
    }

    func getCollectionInfo(_ method: String) -> (method: String, indexInLine: Int) {
        return collectionInfoList[_collectionInfoMap[method]!]
    }

    // upstream: gatherValue(groupByDimInfo, groupVal, value) — value = +value.
    func gatherValue(_ groupByDimInfo: ExternalDimensionDefinition?, _ groupVal: Any?, _ value: Any?) {
        let value = aggToNum(value)
        if groupByDimInfo != nil {
            if !aggIsNull(groupVal) {
                let groupValStr = aggGroupStr(groupVal)
                gatheredValuesByGroup[groupValStr, default: []].append(value)
            }
        }
        else {
            gatheredValuesNoGroup.append(value)
        }
    }
}

// upstream: a result "line" is a JS array (reference type). Swift `[Any?]` is a value type, so wrap it in a
//   `final class` — `travel`'s outList and mapByGroup must reference the SAME line so `doUpdate` mutations show
//   up in the output.
private final class AggLine {
    var cells: [Any?]
    init(_ n: Int) { cells = Array(repeating: nil, count: n) }
}

private struct AggTravelResult {
    var mapByGroup: [String: AggLine]?
    var outList: [AggLine]
}

// upstream: lineCreator[method](...) — the value for a freshly-created line cell.
private func aggLineCreate(
    _ method: String, _ upstream: ExternalSource, _ dataIndex: Int, _ dimInfo: AggResultDimInfo,
    _ groupByDimInfo: ExternalDimensionDefinition?, _ groupByVal: Any?
) -> Any? {
    switch method {
    case "SUM": return 0.0
    case "COUNT": return 1.0
    case "FIRST", "MIN", "MAX":
        return upstream.retrieveValue(Double(dataIndex), Double(dimInfo.indexInUpstream))
    case "AVERAGE":
        let collectLine = groupByDimInfo != nil
            ? dimInfo.collectionResult!.mapByGroup![aggGroupStr(groupByVal)]!
            : dimInfo.collectionResult!.outList[0]
        let count = aggToNum(collectLine.cells[dimInfo.getCollectionInfo("COUNT").indexInLine])
        return aggToNum(upstream.retrieveValue(Double(dataIndex), Double(dimInfo.indexInUpstream))) / count
    case "Q1": return aggLineCreatorForQ(0.25, dimInfo, groupByDimInfo, groupByVal)
    case "Q2": return aggLineCreatorForQ(0.5, dimInfo, groupByDimInfo, groupByVal)
    case "Q3": return aggLineCreatorForQ(0.75, dimInfo, groupByDimInfo, groupByVal)
    default: return nil
    }
}

// upstream: lineUpdater[method](val, ...) — fold `dataIndex`'s value into an existing line cell `val`.
private func aggLineUpdate(
    _ method: String, _ val: Any?, _ upstream: ExternalSource, _ dataIndex: Int, _ dimInfo: AggResultDimInfo,
    _ groupByDimInfo: ExternalDimensionDefinition?, _ groupByVal: Any?
) -> Any? {
    switch method {
    case "SUM":
        return aggToNum(val) + aggToNum(upstream.retrieveValue(Double(dataIndex), Double(dimInfo.indexInUpstream)))
    case "COUNT":
        return aggToNum(val) + 1
    case "FIRST":
        return val
    case "MIN":
        return Swift.min(aggToNum(val), aggToNum(upstream.retrieveValue(Double(dataIndex), Double(dimInfo.indexInUpstream))))
    case "MAX":
        return Swift.max(aggToNum(val), aggToNum(upstream.retrieveValue(Double(dataIndex), Double(dimInfo.indexInUpstream))))
    case "AVERAGE":
        let collectLine = groupByDimInfo != nil
            ? dimInfo.collectionResult!.mapByGroup![aggGroupStr(groupByVal)]!
            : dimInfo.collectionResult!.outList[0]
        let count = aggToNum(collectLine.cells[dimInfo.getCollectionInfo("COUNT").indexInLine])
        return aggToNum(val)
            + aggToNum(upstream.retrieveValue(Double(dataIndex), Double(dimInfo.indexInUpstream))) / count
    case "Q1", "Q2", "Q3":
        return val
    default:
        return val
    }
}

// upstream: lineCreatorForQ(percent, dimInfo, groupByDimInfo, groupByVal).
private func aggLineCreatorForQ(
    _ percent: Double, _ dimInfo: AggResultDimInfo,
    _ groupByDimInfo: ExternalDimensionDefinition?, _ groupByVal: Any?
) -> Any? {
    let gatheredValues = groupByDimInfo != nil
        ? (dimInfo.gatheredValuesByGroup[aggGroupStr(groupByVal)] ?? [])
        : dimInfo.gatheredValuesNoGroup
    return aggQuantile(gatheredValues, percent)
}

// upstream: isGroupByDimension(groupByDimInfo, targetDimInfo).
private func aggIsGroupByDimension(_ groupByDimInfo: ExternalDimensionDefinition?, _ targetDimInfo: AggResultDimInfo) -> Bool {
    guard let g = groupByDimInfo else { return false }
    return targetDimInfo.indexInUpstream == Int(g.index)
}

// upstream: travel(groupByDimInfo, upstream, resultDimInfoList, doCreate, doUpdate).
private func aggTravel(
    _ groupByDimInfo: ExternalDimensionDefinition?,
    _ upstream: ExternalSource,
    _ doCreate: (_ dataIndex: Int, _ groupByVal: Any?) -> AggLine,
    _ doUpdate: (_ dataIndex: Int, _ targetLine: AggLine, _ groupByVal: Any?) -> Void
) -> AggTravelResult {
    var outList: [AggLine] = []
    var mapByGroup: [String: AggLine]? = nil
    let len = Int(upstream.count())
    if let g = groupByDimInfo {
        var map: [String: AggLine] = [:]
        for dataIndex in 0..<len {
            let groupByVal = upstream.retrieveValue(Double(dataIndex), g.index)
            if aggIsNull(groupByVal) { continue }
            let groupByValStr = aggGroupStr(groupByVal)
            if let targetLine = map[groupByValStr] {
                doUpdate(dataIndex, targetLine, groupByVal)
            }
            else {
                let newLine = doCreate(dataIndex, groupByVal)
                outList.append(newLine)
                map[groupByValStr] = newLine
            }
        }
        mapByGroup = map
    }
    else if len > 0 {
        let targetLine = doCreate(0, nil)
        outList.append(targetLine)
        for dataIndex in 1..<len {
            doUpdate(dataIndex, targetLine, nil)
        }
    }
    return AggTravelResult(mapByGroup: mapByGroup, outList: outList)
}

// upstream: prepareGroupByDimInfo(config, upstream).
private func aggPrepareGroupByDimInfo(_ config: [String: Any], _ upstream: ExternalSource) throws -> ExternalDimensionDefinition? {
    guard let groupByConfig = config["groupBy"], !aggIsNull(groupByConfig) else { return nil }
    guard let groupByDimInfo = upstream.getDimensionInfo(groupByConfig) else {
        throw EChartsError(message: "Can not find dimension by `groupBy`: \(groupByConfig)")
    }
    return groupByDimInfo
}

// upstream: prepareDimensions(config, upstream, groupByDimInfo).
private func aggPrepareDimensions(
    _ config: [String: Any], _ upstream: ExternalSource, _ groupByDimInfo: ExternalDimensionDefinition?
) throws -> (finalResultDimInfoList: [AggResultDimInfo], collectionDimInfoList: [AggResultDimInfo], totalCollectionCells: Int) {
    let resultDimensionsConfig = (config["resultDimensions"] as? [[String: Any]]) ?? []
    var finalResultDimInfoList: [AggResultDimInfo] = []
    var collectionDimInfoList: [AggResultDimInfo] = []
    var gIndexInLine = 0
    for resultDimInfoConfig in resultDimensionsConfig {
        guard let dimInfoInUpstream = upstream.getDimensionInfo(resultDimInfoConfig["from"]) else {
            throw EChartsError(message: "Can not find dimension by `from`: \(String(describing: resultDimInfoConfig["from"]))")
        }
        let rawMethod = resultDimInfoConfig["method"]
        // upstream assert: a result dim ON the groupBy dimension must not carry a method.
        if let g = groupByDimInfo, Int(g.index) == Int(dimInfoInUpstream.index), !aggIsNull(rawMethod) {
            throw EChartsError(message: "Dimension \(dimInfoInUpstream.name ?? "") is the \"groupBy\" dimension, must not have any \"method\".")
        }
        let method = try aggNormalizeMethod(rawMethod)
        let name = (resultDimInfoConfig["name"] as? String) ?? (dimInfoInUpstream.name ?? "")
        let finalResultDimInfo = AggResultDimInfo(
            index: finalResultDimInfoList.count,
            indexInUpstream: Int(dimInfoInUpstream.index),
            method: method,
            name: name,
            needGatherValues: AGG_METHOD_NEEDS_GATHER_VALUES.contains(method)
        )
        finalResultDimInfoList.append(finalResultDimInfo)
        var needCollect = false
        if let collectionTargetMethods = AGG_METHOD_NEEDS_COLLECT[method] {
            needCollect = true
            for target in collectionTargetMethods {
                finalResultDimInfo.addCollectionInfo((method: target, indexInLine: gIndexInLine))
                gIndexInLine += 1
            }
        }
        if AGG_METHOD_NEEDS_GATHER_VALUES.contains(method) {
            needCollect = true
        }
        if needCollect {
            collectionDimInfoList.append(finalResultDimInfo)
        }
    }
    return (finalResultDimInfoList, collectionDimInfoList, gIndexInLine)
}

// upstream: export const aggregate: DataTransformOption's transform.
let ecSimpleTransformAggregate = ExternalDataTransform(
    type: "ecSimpleTransform:aggregate",
    transform: { params in
        let upstream = params.upstream
        let config = (params.config as? [String: Any]) ?? [:]

        // NOTE: aggregate throws on malformed config upstream; the ExternalDataTransform closure is
        //   non-throwing, so a failure degrades to an empty result (the page then renders blank rather
        //   than crashing) — matches how the other ported transforms guard.
        do {
            let groupByDimInfo = try aggPrepareGroupByDimInfo(config, upstream)
            let prepared = try aggPrepareDimensions(config, upstream, groupByDimInfo)
            let finalResultDimInfoList = prepared.finalResultDimInfoList
            let collectionDimInfoList = prepared.collectionDimInfoList
            let totalCollectionCells = prepared.totalCollectionCells

            // ---- collection pass (gather the raw values quantile/average need) ----
            var collectionResult: AggTravelResult? = nil
            if !collectionDimInfoList.isEmpty {
                let createCollectionLine: (Int, Any?) -> AggLine = { dataIndex, groupByVal in
                    let newLine = AggLine(totalCollectionCells)
                    for dimInfo in collectionDimInfoList {
                        for collectionInfo in dimInfo.collectionInfoList {
                            newLine.cells[collectionInfo.indexInLine] = aggToNum(
                                aggLineCreate(collectionInfo.method, upstream, dataIndex, dimInfo, groupByDimInfo, groupByVal))
                        }
                        if dimInfo.needGatherValues {
                            let val = upstream.retrieveValue(Double(dataIndex), Double(dimInfo.indexInUpstream))
                            dimInfo.gatherValue(groupByDimInfo, groupByVal, val)
                        }
                    }
                    return newLine
                }
                let updateCollectionLine: (Int, AggLine, Any?) -> Void = { dataIndex, targetLine, groupByVal in
                    for dimInfo in collectionDimInfoList {
                        for collectionInfo in dimInfo.collectionInfoList {
                            let idx = collectionInfo.indexInLine
                            targetLine.cells[idx] = aggToNum(
                                aggLineUpdate(collectionInfo.method, targetLine.cells[idx], upstream, dataIndex, dimInfo, groupByDimInfo, groupByVal))
                        }
                        if dimInfo.needGatherValues {
                            let val = upstream.retrieveValue(Double(dataIndex), Double(dimInfo.indexInUpstream))
                            dimInfo.gatherValue(groupByDimInfo, groupByVal, val)
                        }
                    }
                }
                collectionResult = aggTravel(groupByDimInfo, upstream, createCollectionLine, updateCollectionLine)
            }
            for dimInfo in collectionDimInfoList {
                dimInfo.collectionResult = collectionResult
                dimInfo.gatheredValuesNoGroup.sort()
                for key in dimInfo.gatheredValuesByGroup.keys {
                    dimInfo.gatheredValuesByGroup[key]?.sort()
                }
            }

            // ---- final pass (one output row per group) ----
            let createFinalLine: (Int, Any?) -> AggLine = { dataIndex, groupByVal in
                let newLine = AggLine(finalResultDimInfoList.count)
                for (i, dimInfo) in finalResultDimInfoList.enumerated() {
                    newLine.cells[i] = aggIsGroupByDimension(groupByDimInfo, dimInfo)
                        ? groupByVal
                        : aggLineCreate(dimInfo.method, upstream, dataIndex, dimInfo, groupByDimInfo, groupByVal)
                }
                return newLine
            }
            let updateFinalLine: (Int, AggLine, Any?) -> Void = { dataIndex, targetLine, groupByVal in
                for (i, dimInfo) in finalResultDimInfoList.enumerated() {
                    if aggIsGroupByDimension(groupByDimInfo, dimInfo) { continue }
                    targetLine.cells[i] = aggLineUpdate(dimInfo.method, targetLine.cells[i], upstream, dataIndex, dimInfo, groupByDimInfo, groupByVal)
                }
            }
            let finalResult = aggTravel(groupByDimInfo, upstream, createFinalLine, updateFinalLine)

            let dimensions: [Any] = finalResultDimInfoList.map { $0.name }
            let data: [[Any]] = finalResult.outList.map { line in line.cells.map { $0 ?? NSNull() } }
            return ExternalDataTransformResultItem(data: data, dimensions: dimensions)
        }
        catch {
            log.error("ecSimpleTransform:aggregate failed: \(error)")
            return ExternalDataTransformResultItem(data: [[Any]]())
        }
    }
)
