// Ported from echarts/src/coord/axisStatistics.ts — keep in sync with upstream

import Foundation
import ZRenderKit

// import { assert, createHashMap, each, HashMap, retrieve2 } from 'zrender/src/core/util';
//   -> `util.assert`/`util.each`/`util.retrieve2` (ZRenderKit); `createHashMap`/`HashMap`
//      are the top-level shim in util/model.swift (ZRenderKit has not ported them yet).
// import type GlobalModel from '../model/Global';                 -> GlobalModel (model/Global.swift)
// import type SeriesModel from '../model/Series';                 -> SeriesModel (model/Series.swift)
// import { makeCallOnlyOnce, makeInner } from '../util/model';    -> model.makeCallOnlyOnce / model.makeInner
// import { ComponentSubType, NullUndefined } from '../util/types';-> ComponentSubType (types.swift); NullUndefined -> nil (CONVENTIONS §6)
// import type Axis from './Axis';                                 -> PORT-TODO placeholder below (coord/Axis.ts not yet ported)
// import type { AxisBaseModel } from './AxisBaseModel';           -> PORT-TODO placeholder below (coord/AxisBaseModel.ts not yet ported)
// import { EChartsExtensionInstallRegisters } from '../extension';-> PORT-TODO stub below (extension registrar is Phase 6b)
// import type ComponentModel from '../model/Component';           -> ComponentModel (model/Component.swift); ComponentModel['uid'] = String
// import { getCachePerECFullUpdate, getCachePerECPrepare, GlobalModelCachePerECFullUpdate,
//          GlobalModelCachePerECPrepare } from '../util/cycleCache';
//   -> PORT-TODO placeholders below (util/cycleCache.ts not yet ported)
// import { CoordinateSystem } from './CoordinateSystem';          -> `CoordinateSystem['type']` modeled as String (coord/CoordinateSystem.ts not yet ported)
//
// NOTE: upstream is a named-import free-function module, so it is ported as top-level free
//   functions/types (call sites stay identical, e.g. `associateSeriesWithAxis(...)`), matching
//   the consumer `axisStatisticsMetricsImpl.swift`.

// ============================================================================
// PORT-TODO: type-only / stub placeholders for not-yet-ported coord & infra siblings.
//   These mirror only the upstream surface used across this coord phase and MUST be removed when
//   the real modules land (coord/Axis.ts, coord/AxisBaseModel.ts, coord/CoordinateSystem.ts,
//   util/cycleCache.ts, extension.ts). axisStatistics is the base coordinate-pipeline dependency
//   (see `@see scaleRawExtentInfoCreate`), so it owns the shared `Axis` placeholder for this phase —
//   sibling coord files (axisStatisticsMetricsImpl, scaleRawExtentInfo, axisBand, Grid) reference it
//   rather than redefining it.
// ----------------------------------------------------------------------------

// '../coord/Axis' — the real `Axis` class (coord/Axis.swift) and `AxisBaseModel` (coord/AxisBaseModel.swift)
//   now supply `model`/`scale`/`dim`/`onBand`/`getExtent` and `uid`/`ecModel`. The former PORT-TODO
//   placeholder protocols (`Axis`, `AxisModelForAxisStat`) were removed when those real modules landed.

// '../util/cycleCache' — nominal per-cycle cache hosts + accessors.
//   The real impl is cleared at the beginning of each EC_FULL_UPDATE / EC_PREPARE by echarts.ts.
//   This placeholder keeps one stable host per `ecModel` (no per-cycle reset) so `makeInner`
//   caching stays coherent; replace with the real util/cycleCache.swift when it lands.
public final class GlobalModelCachePerECFullUpdate { public init() {} }    // PORT-TODO
public final class GlobalModelCachePerECPrepare { public init() {} }       // PORT-TODO
private final class CycleCacheHolderStub {                                 // PORT-TODO
    let fullUpdate = GlobalModelCachePerECFullUpdate()
    let prepare = GlobalModelCachePerECPrepare()
}
private let _cycleCacheInnerStub: (GlobalModel) -> CycleCacheHolderStub    // PORT-TODO
    = model.makeInner { CycleCacheHolderStub() }
public func getCachePerECFullUpdate(_ ecModel: GlobalModel) -> GlobalModelCachePerECFullUpdate { // PORT-TODO
    return _cycleCacheInnerStub(ecModel).fullUpdate
}
public func getCachePerECPrepare(_ ecModel: GlobalModel) -> GlobalModelCachePerECPrepare {       // PORT-TODO
    return _cycleCacheInnerStub(ecModel).prepare
}

// '../extension' — EChartsExtensionInstallRegisters (processor registrar). Phase 6b.
public struct AxisStatProcessorRegistration {                              // PORT-TODO: minimal processor-registration shape (upstream `StageHandler`)
    public var overallReset: (GlobalModel) -> Void
    public init(overallReset: @escaping (GlobalModel) -> Void) { self.overallReset = overallReset }
}
public struct ECPriorityProcessorStub { public let AXIS_STATISTICS: Double = 0 } // PORT-TODO
public struct ECPriorityStub { public let PROCESSOR = ECPriorityProcessorStub() } // PORT-TODO
open class EChartsExtensionInstallRegisters {                              // PORT-TODO: stub registrar (Phase 6b)
    open var PRIORITY: ECPriorityStub { ECPriorityStub() }
    open func registerProcessor(_ priority: Double, _ processor: AxisStatProcessorRegistration) {}
    public init() {}
}
// ============================================================================

private let callOnlyOnce: (EChartsExtensionInstallRegisters, () -> Void) -> Void
    = model.makeCallOnlyOnce()
// Ensure that it never appears in internal generated uid and pre-defined coordSysType.
public let AXIS_STAT_KEY_DELIMITER = "|&"

// makeInner record: full-update cache. All fields lazily populated (upstream `{}` default).
final class EcModelCacheFullUpdate {

    // It stores all <axis, series> pairs, aggregated by axis, based on which axis scale extent is calculated.
    // NOTICE: series that has been filtered out are included.
    // It is unrelated to `AxisStatKeyedClient`.
    var axSer: HashMap<[SeriesModel]>?

    // AxisStatKey based statistics records.
    // Only `AxisStatKeyedClient` concerned <axis, series> pairs are collected, based on which
    // statistics are calculated.
    var keyed: AxisStatKeyed?
    // `keys` is only used to quick travel.
    var keys: AxisStatKeys?

    // Only used in dev mode for duplication checking.
    var axSerPairCheck: HashMap<Double>?

    init() {}
}
private let ecModelCacheFullUpdateInner: (GlobalModelCachePerECFullUpdate) -> EcModelCacheFullUpdate
    = model.makeInner { EcModelCacheFullUpdate() }

// type AxisStatKeys = HashMap<AxisStatKey[], ComponentModel['uid']>;
typealias AxisStatKeys = HashMap<[AxisStatKey]>
// type AxisStatKeyed = HashMap<AxisStatPerKey | NullUndefined, AxisStatKey>;
typealias AxisStatKeyed = HashMap<AxisStatPerKey>
// type AxisStatPerKey = HashMap<AxisStatPerKeyPerAxis | NullUndefined, AxisBaseModel['uid']>;
typealias AxisStatPerKey = HashMap<AxisStatPerKeyPerAxis>

public final class AxisStatPerKeyPerAxis {
    public var axis: Axis

    // This is series use this axis as base axis and need to be laid out.
    // The order is determined by the client and must be respected.
    // Never be null/undefined; Never be length === 0;
    // series filtered out is included.
    public var sers: [SeriesModel]
    // For query. The array index is series index.
    // PORT-TODO: upstream is a JS sparse array indexed by `seriesIndex`; modeled as `[SeriesModel?]`
    //   (holes are `nil`), grown on write (see `setSparse`/`getSparse`).
    public var serByIdx: [SeriesModel?]

    // Minimal positive gap of values (in the linear space) of all relevant series (e.g. per `BaseBarSeriesSubType`)
    // on this axis.
    public var liPosMinGap:
        // Can only be a positive number rather than zero.
        // In this case a positive min gap can not be calculated -> LINEAR_POSITIVE_MIN_GAP_SINGLE_VALID_VALUE
        // In this case a positive min gap can not be calculated -> LINEAR_POSITIVE_MIN_GAP_NO_VALID_VALUE
        // Be `null`/`undefined` if this metric is not required.
        Double?

    // metrics corresponds to this record.
    public var metrics: AxisStatMetrics?

    public init(axis: Axis, sers: [SeriesModel], serByIdx: [SeriesModel?]) {
        self.axis = axis
        self.sers = sers
        self.serByIdx = serByIdx
    }
}

// In this case, there are one or multiple valid data value but all the same.
public let LINEAR_POSITIVE_MIN_GAP_SINGLE_VALID_VALUE: Double = -2
public let LINEAR_POSITIVE_MIN_GAP_NO_VALID_VALUE: Double = -1

// makeInner record: prepare cache.
final class EcModelCachePrepare {
    var keyed: AxisStatECPrepareCacheKeyed?
    init() {}
}
private let ecModelCachePrepareInner: (GlobalModelCachePerECPrepare) -> EcModelCachePrepare
    = model.makeInner { EcModelCachePrepare() }

// type AxisStatECPrepareCacheKeyed = HashMap<AxisStatECPrepareCachePerKey | NullUndefined, AxisStatKey>;
typealias AxisStatECPrepareCacheKeyed = HashMap<AxisStatECPrepareCachePerKey>
// type AxisStatECPrepareCachePerKey = HashMap<AxisStatECPrepareCachePerKeyPerAxis | NullUndefined, AxisBaseModel['uid']>;
typealias AxisStatECPrepareCachePerKey = HashMap<AxisStatECPrepareCachePerKeyPerAxis>
// Pick<AxisStatPerKeyPerAxis, 'liPosMinGap'> & { serUids?: HashMap<1, ComponentModel['uid']> }
public final class AxisStatECPrepareCachePerKeyPerAxis {
    public var liPosMinGap: Double?
    // Used for cache validity.
    public var serUids: HashMap<Double>?
    public init() {}
}

public struct AxisStatKeyedClient {

    // A key for retrieving result.
    public var key: AxisStatKey

    // Only the specific `seriesType` is covered.
    public var seriesType: ComponentSubType
    // `true` by default - the <axis, series> pair is collected only if series's base axis is that axis.
    public var baseAxis: Bool?
    // `NullUndefined` by default - all coordinate systems are covered.
    // PORT-TODO: upstream `CoordinateSystem['type'] | NullUndefined`; modeled as `String?`.
    public var coordSysType: String?

    // `NullUndefined` return indicates this axis should be omitted.
    public var getMetrics: (Axis) -> AxisStatMetrics?

    public init(
        key: AxisStatKey,
        seriesType: ComponentSubType,
        baseAxis: Bool? = nil,
        coordSysType: String? = nil,
        getMetrics: @escaping (Axis) -> AxisStatMetrics?
    ) {
        self.key = key
        self.seriesType = seriesType
        self.baseAxis = baseAxis
        self.coordSysType = coordSysType
        self.getMetrics = getMetrics
    }
}

/**
 * Within each individual axis, different groups of relevant series and statistics are
 * designated by a `AxisStatKey`.
 *
 * `AxisStatKey` is a static definition.
 *  In most case a `seriesType` is used as a `AxisStatKey` (See `makeAxisStatKey`).
 *  Sometimes a `seriesType`+`coordSysType` is used as a `AxisStatKey` (See `makeAxisStatKey2`).
 *
 * A <axis, series> pair can only own to one `AxisStatKey`.
 */
// PORT-TODO: upstream `AxisStatKey = string & {_: 'AxisStatKey'}` is a nominal-branded string;
//   the brand is dropped in Swift (aliased to String).
public typealias AxisStatKey = String

// PORT-TODO: upstream `ClientLookupKey = string & {_: 'ClientLookupKey'}` (nominal, internal); brand dropped.
typealias ClientLookupKey = String

public struct AxisStatMetrics {

    // NOTICE:
    //  May be time-consuming in large data due to some metrics requiring travel and sort of
    //  series data, especially when axis break is used, so it is performed only if required.
    public var liPosMinGap: Bool?

    public init(liPosMinGap: Bool? = nil) {
        self.liPosMinGap = liPosMinGap
    }
}

public struct AxisStatisticsResult {   // Pick<AxisStatPerKeyPerAxis, 'liPosMinGap'>
    public var liPosMinGap: Double?
    public init(liPosMinGap: Double? = nil) {
        self.liPosMinGap = liPosMinGap
    }
}

public typealias AxisStatEachSeriesCb = (SeriesModel) -> Void

// let validateInputAxis: ((axis: Axis) => void) | NullUndefined; (assigned only in __DEV__)
private let validateInputAxis: ((Axis) -> Void)? = __DEV__ ? { axis in
    // assert(axis && axis.model && axis.model.uid && axis.model.ecModel);
    util.assert(!axis.model.uid.isEmpty)   // ecModel is non-optional in the placeholder; uid truthiness -> non-empty
} : nil

private func getAxisStatPerKeyPerAxis(
    _ axis: Axis,
    _ axisStatKey: AxisStatKey
) -> AxisStatPerKeyPerAxis? {
    let axisModel = axis.model!
    let keyed = ecModelCacheFullUpdateInner(getCachePerECFullUpdate(axisModel.ecModel!)).keyed
    let perKey = keyed?.get(axisStatKey)
    return perKey?.get(axisModel.uid)
}

// Return: Never return null/undefined.
public func getAxisStat(
    _ axis: Axis,
    _ axisStatKey: AxisStatKey
) -> AxisStatisticsResult {
    if __DEV__ {
        util.assert(!axisStatKey.isEmpty)   // upstream: assert(axisStatKey != null); AxisStatKey is non-optional String here, so guard emptiness
        validateInputAxis?(axis)
    }
    return wrapStatResult(getAxisStatPerKeyPerAxis(axis, axisStatKey))
}

// Return: Never be null/undefined; never contain null/undefined.
public func getAxisStatBySeries(
    _ axis: Axis,
    _ seriesList: [SeriesModel?]
) -> [AxisStatisticsResult] {
    if __DEV__ {
        validateInputAxis?(axis)
    }
    var result: [AxisStatisticsResult] = []
    eachKeyEachAxis(axis.model.ecModel!, { perKeyPerAxis, _, _ in
        for idx in 0..<seriesList.count {
            if let s = seriesList[idx], getSparse(perKeyPerAxis.serByIdx, Int(s.seriesIndex)) != nil {
                result.append(wrapStatResult(perKeyPerAxis))
            }
        }
    })
    return result
}

private func eachKeyEachAxis(
    _ ecModel: GlobalModel,
    _ cb: (
        _ perKeyPerAxis: AxisStatPerKeyPerAxis,
        _ axisStatKey: AxisStatKey,
        _ axisModelUid: String
    ) -> Void
) {
    let keyed = ecModelCacheFullUpdateInner(getCachePerECFullUpdate(ecModel)).keyed
    keyed?.each({ perKey, axisStatKey in
        perKey.each({ perKeyPerAxis, axisModelUid in
            cb(perKeyPerAxis, axisStatKey, axisModelUid)
        })
    })
}

private func wrapStatResult(_ record: AxisStatPerKeyPerAxis?) -> AxisStatisticsResult {
    return AxisStatisticsResult(
        liPosMinGap: record != nil ? record!.liPosMinGap : nil
    )
}

public func eachSeriesOnAxis(
    _ axis: Axis,
    _ cb: @escaping AxisStatEachSeriesCb
) {
    if __DEV__ {
        validateInputAxis?(axis)
    }
    let ecModel = axis.model.ecModel!
    let seriesOnAxisMap = ecModelCacheFullUpdateInner(getCachePerECFullUpdate(ecModel)).axSer
    if let seriesOnAxisMap = seriesOnAxisMap {
        eachSeriesDealForAxisStat(ecModel, seriesOnAxisMap.get(axis.model.uid), cb)
    }
}

/**
 * NOTE:
 *  - series declaration order is respected (some ec option precedence matters, e.g., bar series).
 *  - series filtered out are excluded.
 */
public func eachSeriesOnAxisOnKey(
    _ axis: Axis,
    _ axisStatKey: AxisStatKey,
    _ cb: @escaping AxisStatEachSeriesCb
) {
    if __DEV__ {
        util.assert(!axisStatKey.isEmpty)   // upstream: assert(axisStatKey != null); AxisStatKey is non-optional String here, so guard emptiness
        validateInputAxis?(axis)
    }
    let perKeyPerAxis = getAxisStatPerKeyPerAxis(axis, axisStatKey)
    if let perKeyPerAxis = perKeyPerAxis {
        eachSeriesDealForAxisStat(axis.model.ecModel!, perKeyPerAxis.sers, cb)
    }
}

public func eachSeriesDealForAxisStat(
    _ ecModel: GlobalModel,
    _ seriesList: [SeriesModel]?,
    _ cb: AxisStatEachSeriesCb
) {
    guard let seriesList = seriesList else {
        return
    }
    for i in 0..<seriesList.count {
        let seriesModel = seriesList[i]
        // Legend-filtered series need to be ignored since series are registered before `legendFilter`.
        if !ecModel.isSeriesFiltered(seriesModel) {
            cb(seriesModel)
        }
    }
}

/**
 * NOTE:
 *  - series filtered out are excluded.
 */
public func countSeriesOnAxisOnKey(
    _ axis: Axis,
    _ axisStatKey: AxisStatKey
) -> Double {
    if __DEV__ {
        util.assert(!axisStatKey.isEmpty)   // upstream: assert(axisStatKey != null); AxisStatKey is non-optional String here, so guard emptiness
        validateInputAxis?(axis)
    }
    let perKeyPerAxis = getAxisStatPerKeyPerAxis(axis, axisStatKey)
    if perKeyPerAxis == nil || perKeyPerAxis!.sers.isEmpty {
        return 0
    }
    var count: Double = 0
    eachSeriesDealForAxisStat(axis.model.ecModel!, perKeyPerAxis!.sers, { _ in
        count += 1
    })
    return count
}

/**
 * NOTICE: Available after `CoordinateSystem['create']` (not included).
 *
 * Query all axes that have at least one associated series (via `associateSeriesWithAxis`)
 * by the given key.
 */
public func eachAxisOnKey(
    _ ecModel: GlobalModel,
    _ axisStatKey: AxisStatKey,
    _ cb: (Axis) -> Void
) {
    if __DEV__ {
        util.assert(!axisStatKey.isEmpty)   // upstream: assert(axisStatKey != null); AxisStatKey is non-optional String here, so guard emptiness
    }
    let keyed = ecModelCacheFullUpdateInner(getCachePerECFullUpdate(ecModel)).keyed
    let perKey = keyed?.get(axisStatKey)
    perKey?.each({ perKeyPerAxis, _ in
        if __DEV__ {
            util.assert(perKeyPerAxis.sers.count > 0) // This is to avoid irrelevant axes to enter `cb`.
        }
        cb(perKeyPerAxis.axis)
    })
}

/**
 * NOTICE: Available after `CoordinateSystem['create']` (not included).
 *
 * Query all `AxisStatKey`s that have at least one associated series (via `associateSeriesWithAxis`)
 * by the given axis.
 */
public func eachKeyOnAxis(
    _ axis: Axis,
    _ cb: (AxisStatKey) -> Void
) {
    if __DEV__ {
        validateInputAxis?(axis)
    }
    let model = axis.model!
    let keysByAxisModelUid = ecModelCacheFullUpdateInner(getCachePerECFullUpdate(model.ecModel!)).keys
    if let keysByAxisModelUid = keysByAxisModelUid {
        util.each(keysByAxisModelUid.get(model.uid), { axisStatKey, _ in
            if __DEV__ {
                let stat = getAxisStatPerKeyPerAxis(axis, axisStatKey)
                util.assert(stat != nil && stat!.sers.count > 0) // This is to avoid irrelevant `AxisStatKey` to enter `cb`.
            }
            cb(axisStatKey)
        })
    }
}

/**
 * NOTICE: this processor may be omitted - it is registered only if required.
 */
private func performAxisStatisticsOnOverallReset(_ ecModel: GlobalModel) {
    let ecPrepareCache = ecModelCachePrepareInner(getCachePerECPrepare(ecModel))
    let ecPrepareCacheKeyed: AxisStatECPrepareCacheKeyed = ecPrepareCache.keyed ?? {
        let m: AxisStatECPrepareCacheKeyed = createHashMap(); ecPrepareCache.keyed = m; return m
    }()

    eachKeyEachAxis(ecModel, { perKeyPerAxis, axisStatKey, axisModelUid in
        let ecPrepareCachePerKey = ecPrepareCacheKeyed.get(axisStatKey)
            ?? ecPrepareCacheKeyed.set(axisStatKey, createHashMap())
        let ecPreparePerKeyPerAxis = ecPrepareCachePerKey.get(axisModelUid)
            ?? ecPrepareCachePerKey.set(axisModelUid, AxisStatECPrepareCachePerKeyPerAxis())

        if perKeyPerAxis.metrics?.liPosMinGap == true {
            // We should assert the impl exists -- fail-fast if missing `registerMetricImpl`.
            _metricImpl["liPosMinGap"]!(ecModel, perKeyPerAxis, ecPreparePerKeyPerAxis)
        }
    })
}

// To reduce code size from unnecessary metrics.
// PORT-TODO: upstream `metricType: keyof AxisStatMetrics` narrowed to String.
public func registerMetricImpl(_ metricType: String, _ impl: @escaping AxisStateMetricImpl) {
    _metricImpl[metricType] = impl
}
private var _metricImpl: [String: AxisStateMetricImpl] = [:]
// (ecModel, perKeyPerAxis, ecPreparePerKeyPerAxis) => void
public typealias AxisStateMetricImpl = (GlobalModel, AxisStatPerKeyPerAxis, AxisStatECPrepareCachePerKeyPerAxis) -> Void

/**
 * NOTICE:
 *  - It must be called in `CoordinateSystem['create']`, before series filtering.
 *  - It must be called in `seriesIndex` ascending order (series declaration order).
 *    i.e., iterated by `ecModel.eachSeries`.
 *  - Every <axis, series> pair can only call this method once.
 *
 * @see scaleRawExtentInfoCreate in `scaleRawExtentInfo.ts`
 */
// PORT-TODO: upstream `coordSysType: CoordinateSystem['type']` modeled as String.
public func associateSeriesWithAxis(
    _ axis: Axis?,
    _ seriesModel: SeriesModel,
    _ coordSysType: String
) {
    guard let axis = axis else {
        return
    }

    // PORT-TODO: `Model.ecModel` is `GlobalModel?`; upstream treats it as non-null here.
    let ecModel = seriesModel.ecModel!
    let ecFullUpdateCache = ecModelCacheFullUpdateInner(getCachePerECFullUpdate(ecModel))
    let axisModelUid = axis.model.uid

    if __DEV__ {
        validateInputAxis?(axis)
        // - An axis can be associated with multiple `axisStatKey`s. For example, if `axisStatKey`s are
        //   "candlestick" and "bar", they can be associated with the same "xAxis".
        // - Within an individual axis, it is a typically incorrect usage if a <axis, series> pair is
        //   associated with multiple `perKeyPerAxis`, which may cause repeated calculation and
        //   performance degradation, had hard to be found without the checking below. For example, If
        //   `axisStatKey` are "grid-bar" (see `barGrid.ts`) and "polar-bar" (see `barPolar.ts`), and
        //   a <xAxis-series> pair is wrongly associated with both "polar-bar" and "grid-bar", the
        //   relevant statistics will be computed twice.
        let axSerPairCheck: HashMap<Double> = ecFullUpdateCache.axSerPairCheck ?? {
            let m: HashMap<Double> = createHashMap(); ecFullUpdateCache.axSerPairCheck = m; return m
        }()
        let pairKey = "\(axisModelUid)\(AXIS_STAT_KEY_DELIMITER)\(seriesModel.uid)"
        util.assert(axSerPairCheck.get(pairKey) == nil)
        axSerPairCheck.set(pairKey, 1)
    }

    let seriesOnAxisMap: HashMap<[SeriesModel]> = ecFullUpdateCache.axSer ?? {
        let m: HashMap<[SeriesModel]> = createHashMap(); ecFullUpdateCache.axSer = m; return m
    }()
    // PORT-TODO: JS arrays are reference types; Swift `[SeriesModel]` is a value type stored in the
    //   HashMap, so the appended array must be written back (see `seriesOnAxisMap.set` below).
    var seriesListPerAxis = seriesOnAxisMap.get(axisModelUid) ?? seriesOnAxisMap.set(axisModelUid, [])
    if __DEV__ {
        let lastSeries = seriesListPerAxis.last   // seriesListPerAxis[seriesListPerAxis.length - 1]
        if let lastSeries = lastSeries {
            // Series order should respect to the input order, since it matters in some cases
            // (e.g., see `barGrid.ts` and `barPolar.ts` - ec option declaration order matters).
            util.assert(lastSeries.seriesIndex < seriesModel.seriesIndex)
        }
    }
    seriesListPerAxis.append(seriesModel)
    seriesOnAxisMap.set(axisModelUid, seriesListPerAxis)

    let seriesType = seriesModel.subType
    let isBaseAxis = (seriesModel.getBaseAxis() as AnyObject?) === (axis as AnyObject)

    let client = clientsForLookup.get(makeClientLookupKey(seriesType, isBaseAxis, coordSysType))
        ?? clientsForLookup.get(makeClientLookupKey(seriesType, isBaseAxis, nil))
    guard let client = client else {
        return
    }

    let keyed: AxisStatKeyed = ecFullUpdateCache.keyed ?? {
        let m: AxisStatKeyed = createHashMap(); ecFullUpdateCache.keyed = m; return m
    }()
    let keys: AxisStatKeys = ecFullUpdateCache.keys ?? {
        let m: AxisStatKeys = createHashMap(); ecFullUpdateCache.keys = m; return m
    }()

    let axisStatKey = client.key
    let perKey = keyed.get(axisStatKey) ?? keyed.set(axisStatKey, createHashMap())
    var perKeyPerAxis = perKey.get(axisModelUid)
    if perKeyPerAxis == nil {
        let created = AxisStatPerKeyPerAxis(axis: axis, sers: [], serByIdx: [])
        perKeyPerAxis = perKey.set(axisModelUid, created)
        // They should only be executed for each <key, axis> pair once:
        created.metrics = client.getMetrics(axis)
        // PORT-TODO: value-array write-back (see note above).
        var keysArr = keys.get(axisModelUid) ?? keys.set(axisModelUid, [])
        keysArr.append(axisStatKey)
        keys.set(axisModelUid, keysArr)
    }

    // series order should respect to the input order.
    perKeyPerAxis!.sers.append(seriesModel)
    setSparse(&perKeyPerAxis!.serByIdx, Int(seriesModel.seriesIndex), seriesModel)
}

/**
 * NOTE: Currently, the scenario is simple enough to look up clients by hash map.
 * Otherwise, a caller-provided `filter` may be an alternative if more complex requirements arise.
 */
// PORT-TODO: upstream `coordSysType: CoordinateSystem['type'] | NullUndefined` modeled as String?.
private func makeClientLookupKey(
    _ seriesType: ComponentSubType,
    _ isBaseAxis: Bool?,
    _ coordSysType: String?
) -> ClientLookupKey {
    // retrieve2(isBaseAxis, true) then JS-coerced to 'true'/'false' via string concatenation.
    let base = util.retrieve2(isBaseAxis, true)!
    return (
        seriesType
        + AXIS_STAT_KEY_DELIMITER + (base ? "true" : "false")
        + AXIS_STAT_KEY_DELIMITER + (coordSysType ?? "")
    )
}

/**
 * NOTICE: Can only be called in "install" stage.
 *
 * See `axisSnippets.ts` for some commonly used clients.
 */
public func requireAxisStatistics(
    _ registers: EChartsExtensionInstallRegisters,
    _ client: AxisStatKeyedClient
) {
    let clientKey = makeClientLookupKey(client.seriesType, client.baseAxis, client.coordSysType)

    if __DEV__ {
        util.assert(!client.seriesType.isEmpty
            && !client.key.isEmpty
            && clientsForCheckingStatKey.get(client.key) == nil
            && clientsForLookup.get(clientKey) == nil
        ) // More checking is performed in `axSerPairCheck`.
        clientsForCheckingStatKey.set(client.key, 1)
    }

    clientsForLookup.set(clientKey, client)

    callOnlyOnce(registers, {
        registers.registerProcessor(registers.PRIORITY.PROCESSOR.AXIS_STATISTICS, AxisStatProcessorRegistration(
            // NOTE: Theoretically, `appendData` requires `dirtyOnOverallProgress: true` here to re-calculate them.
            // But this OVERALL_STAGE_TASK is applied to all series (no `getTargetSeries` specified),
            // `dirtyOnOverallProgress: true` can cause irrelevant series (e.g., series on geo)
            // to be re-rendered when `appendData` is called, which cause `appendData` meaningless,
            // thereby not setting `dirtyOnOverallProgress: true`.
            overallReset: performAxisStatisticsOnOverallReset
        ))
    })
}

// let clientsForCheckingStatKey: HashMap<1, AxisStatKey>; (assigned only in __DEV__)
// PORT-TODO: upstream leaves this undefined when !__DEV__; here it is always created (unused unless __DEV__).
private let clientsForCheckingStatKey: HashMap<Double> = createHashMap()
private let clientsForLookup: HashMap<AxisStatKeyedClient> = createHashMap()

// ----------------------------------------------------------------------------
// PORT-TODO: helpers modeling JS sparse-array (`serByIdx`) write/read (not upstream).
private func setSparse(_ arr: inout [SeriesModel?], _ index: Int, _ value: SeriesModel) {
    while arr.count <= index {
        arr.append(nil)
    }
    arr[index] = value
}
private func getSparse(_ arr: [SeriesModel?], _ index: Int) -> SeriesModel? {
    return index >= 0 && index < arr.count ? arr[index] : nil
}
