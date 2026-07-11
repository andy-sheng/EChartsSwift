// Ported from echarts/src/core/CoordinateSystem.ts — keep in sync with upstream
//
// PORT-NOTE: The Swift file is named `CoordinateSystemManager.swift` (after this module's default
//   export) rather than `CoordinateSystem.swift`, because SwiftPM cannot compile two source files
//   with the same basename in one target, and `coord/CoordinateSystem.swift` already exists in
//   EChartsKit (mirroring `echarts/src/coord/CoordinateSystem.ts`). The upstream provenance for
//   re-sync is the header path above (`echarts/src/core/CoordinateSystem.ts`), not the Swift file name.

import Foundation
import ZRenderKit

// import * as zrUtil from 'zrender/src/core/util';                     -> `util` (ZRenderKit)
// import type GlobalModel from '../model/Global';                      -> GlobalModel (this module)
// import type ExtensionAPI from './ExtensionAPI';                      -> ExtensionAPI (core/ExtensionAPI.swift)
// import type { CoordinateSystem, CoordinateSystemCreator, CoordinateSystemMaster }
//     from '../coord/CoordinateSystem';                                -> coord/CoordinateSystem.swift
// import { SINGLE_REFERRING } from '../util/model';                    -> model.SINGLE_REFERRING (util/modelUtil.swift)
// import ComponentModel from '../model/Component';                     -> ComponentModel (this module)
// import SeriesModel from '../model/Series';                           -> SeriesModel (this module)
// import { error } from '../util/log';                                 -> log.error (util/log.swift)
// import { CoordinateSystemDataCoord, NullUndefined } from '../util/types';  -> util/types.swift
//   NullUndefined collapses to Optional (CONVENTIONS §6).

// PORT-NOTE: upstream `type CoordinateSystemCreatorMap = {[type: string]: CoordinateSystemCreator}`
//   is a plain object literal iterated by `zrUtil.each` in insertion order. Modeled as the
//   insertion-ordered `HashMap` shim (util/modelUtil.swift) so `.each`/`.get`/`.set` mirror the
//   upstream object semantics; replace with `util.HashMap` once ZRenderKit ports it.
typealias CoordinateSystemCreatorMap = HashMap<CoordinateSystemCreator>

/**
 * FIXME:
 * `nonSeriesBoxCoordSysCreators` and `_nonSeriesBoxMasterList` are hardcoded implementations.
 * Regarding "coord sys layout based on another coord sys", currently we only experimentally support one level
 * dependency, such as, "grid(cartesian)s can be laid out based on matrix/calendar coord sys."
 * But a comprehensive implementation may need to support:
 *  - Recursive dependencies. e.g., a matrix coord sys lays out based on another matrix coord sys.
 *    That requires in the implementation `create` and `update` of coord sys are called by a dependency graph.
 *    (@see enableTopologicalTravel in `util/component.ts`)
 */
// upstream `const` object literals, mutated in place by `register`. `HashMap` is a reference type,
//   so a `let` binding + `.set(...)` mutation matches the upstream `const` + `map[type] = ...`.
private let nonSeriesBoxCoordSysCreators: CoordinateSystemCreatorMap = createHashMap()
private let normalCoordSysCreators: CoordinateSystemCreatorMap = createHashMap()

// upstream: `export default class CoordinateSystemManager` (CONVENTIONS §2: TS class → final class).
public final class CoordinateSystemManager {

    private var _normalMasterList: [CoordinateSystemMaster] = []
    private var _nonSeriesBoxMasterList: [CoordinateSystemMaster] = []

    public init() {}

    /**
     * Typically,
     *  - in `create`, a coord sys lays out based on a given rect;
     *  - in `update`, update the pixel and data extent of there axes (if any) based on processed `series.data`.
     * After that, a coord sys can serve (typically by `dataToPoint`/`dataToLayout`/`pointToData`).
     * If the coordinate system do not lay out based on `series.data`, `update` is not needed.
     */
    public func create(_ ecModel: GlobalModel, _ api: ExtensionAPI) {

        func dealCreate(_ creatorMap: CoordinateSystemCreatorMap, _ canBeNonSeriesBox: Bool) -> [CoordinateSystemMaster] {
            var coordinateSystems: [CoordinateSystemMaster] = []
            creatorMap.each { creator, _ in
                let list = creator.create(ecModel, api)
                coordinateSystems = coordinateSystems + list // list || []

                if __DEV__ {
                    if canBeNonSeriesBox {
                        // Disallow `update` is a brutal way to ensure `_nonSeriesBoxMasterList`s are ready to
                        // serve after `create`. But if `update` has to be involved in `_nonSeriesBoxMasterList`
                        // for some future case, more complicated mechanisms need to be introduced.
                        // PORT-NOTE: `zrUtil.each(list, master => zrUtil.assert(!master.update))` checks the
                        //   optional `update` method is *absent*. In the Swift port `update` is a protocol
                        //   requirement with a no-op default, so its presence cannot be detected at runtime;
                        //   the assertion is omitted.
                    }
                }
            }
            return coordinateSystems
        }

        _nonSeriesBoxMasterList = dealCreate(nonSeriesBoxCoordSysCreators, true)
        _normalMasterList = dealCreate(normalCoordSysCreators, false)
    }

    /**
     * @see CoordinateSystem['create']
     */
    public func update(_ ecModel: GlobalModel, _ api: ExtensionAPI) {
        util.each(_normalMasterList) { coordSys, _ in
            coordSys.update(ecModel, api) // coordSys.update && coordSys.update(...)
        }
    }

    public func getCoordinateSystems() -> [CoordinateSystemMaster] {
        return _normalMasterList + _nonSeriesBoxMasterList
    }

    // upstream: `static register = function (type, creator): void {...}` (static function-valued field).
    public static func register(_ type: String, _ creator: CoordinateSystemCreator) {
        if type == "matrix" || type == "calendar" { // FIXME: hardcode, @see nonSeriesBoxCoordSysCreators
            nonSeriesBoxCoordSysCreators.set(type, creator)
            return
        }
        normalCoordSysCreators.set(type, creator)
    }

    // upstream: `static get = function (type): CoordinateSystemCreator {...}` (static function-valued field).
    public static func get(_ type: String) -> CoordinateSystemCreator? {
        return normalCoordSysCreators.get(type) ?? nonSeriesBoxCoordSysCreators.get(type)
    }

}

func canBeNonSeriesBoxCoordSys(_ coordSysType: String) -> Bool {
    return nonSeriesBoxCoordSysCreators.get(coordSysType) != nil // !!nonSeriesBoxCoordSysCreators[coordSysType]
}

// By default fetch coord from `model.get('coord')`.
public let BOX_COORD_SYS_COORD_FROM_PROP_COORD: Double = 1 // upstream: `1 as const`
// Some model/series, such as pie, is allowed to also get coord from `model.get('center')`,
// if cannot get from `model.get('coord')`. But historically pie use `center` option, but
// geo use `layoutCenter` option to specify layout center; they are not able to be unified.
// Therefor it is not recommended.
public let BOX_COORD_SYS_COORD_FROM_PROP_COORD2: Double = 2 // upstream: `2 as const`
// upstream: `type BoxCoordinateSystemCoordFrom = 1 | 2`
public typealias BoxCoordinateSystemCoordFrom = Double

// type BoxCoordinateSystemGetCoord2 = (model: ComponentModel) => CoordinateSystemDataCoord;
public typealias BoxCoordinateSystemGetCoord2 = (_ model: ComponentModel) -> CoordinateSystemDataCoord

// PORT-NOTE: TS object-param `opt: {...}` modeled as a param struct (CONVENTIONS style, see modelUtil.swift).
public struct RegisterLayOutOnCoordSysUsageOpt {
    // `SomeSeries.type` or `SomeComponent.type`
    public var fullType: ComponentFullType // ComponentModel['type']
    // @see BoxCoordinateSystemCoordFrom . Be `false` by default.
    public var getCoord2: BoxCoordinateSystemGetCoord2?
    public init(fullType: ComponentFullType, getCoord2: BoxCoordinateSystemGetCoord2? = nil) {
        self.fullType = fullType
        self.getCoord2 = getCoord2
    }
}

// PORT-NOTE: upstream stores `{getCoord2: BoxCoordinateSystemGetCoord2 | NullUndefined}` and mutates
//   its `.getCoord2` through the value returned by `map.set(...)`. Modeled as a `final class` so the
//   mutation is observed through the stored reference (a struct would mutate a copy).
final class CoordSysUseStore {
    var getCoord2: BoxCoordinateSystemGetCoord2?
    init(getCoord2: BoxCoordinateSystemGetCoord2?) {
        self.getCoord2 = getCoord2
    }
}

/**
 * @see_also `createBoxLayoutReference`
 * @see_also `injectCoordSysByOption`
 */
public func registerLayOutOnCoordSysUsage(_ opt: RegisterLayOutOnCoordSysUsageOpt) {
    if __DEV__ {
        util.assert(coordSysUseMap.get(opt.fullType) == nil) // !coordSysUseMap.get(opt.fullType)
    }
    coordSysUseMap.set(opt.fullType, CoordSysUseStore(getCoord2: nil)).getCoord2 = opt.getCoord2
}
// upstream: zrUtil.createHashMap<{getCoord2: BoxCoordinateSystemGetCoord2 | NullUndefined}, ComponentModel['type']>()
private let coordSysUseMap: HashMap<CoordSysUseStore> = createHashMap()

/**
 * @return Be an object, but never be NullUndefined.
 */
public func getCoordForCoordSysUsageKindBox(
    _ model: ComponentModel
) -> (
    coord: CoordinateSystemDataCoord?, // CoordinateSystemDataCoord | NullUndefined
    from: BoxCoordinateSystemCoordFrom
) {
    var coord: CoordinateSystemDataCoord? = model.getShallow("coord", true)
    var from: BoxCoordinateSystemCoordFrom = BOX_COORD_SYS_COORD_FROM_PROP_COORD
    if coord == nil {
        let store = coordSysUseMap.get(model.type)
        if let store = store, let getCoord2 = store.getCoord2 { // store && store.getCoord2
            from = BOX_COORD_SYS_COORD_FROM_PROP_COORD2
            coord = getCoord2(model)
        }
    }
    return (coord, from)
}

/**
 * - `COORD_SYS_USAGE_KIND_DATA`: each data item is laid out based on a coord sys.
 * - `COORD_SYS_USAGE_KIND_BOX`: the overall bounding rect or anchor point is calculated based on a coord sys.
 *   e.g.,
 *      grid rect (cartesian rect) is calculate based on matrix/calendar coord sys;
 *      pie center is calculated based on calendar/cartesian;
 *
 * The default value (if not declared in option `coordinateSystemUsage`):
 *  For series, use `COORD_SYS_USAGE_KIND_DATA`, since this is the most common case and backward compatible.
 *  For non-series components, use `COORD_SYS_USAGE_KIND_BOX`, since `COORD_SYS_USAGE_KIND_DATA` is not applicable.
 */
public let COORD_SYS_USAGE_KIND_NONE: Double = 0 // upstream: `0 as const`
public let COORD_SYS_USAGE_KIND_DATA: Double = 1 // upstream: `1 as const`
public let COORD_SYS_USAGE_KIND_BOX: Double = 2 // upstream: `2 as const`
// upstream: `type CoordinateSystemUsageKind = 0 | 1 | 2`
public typealias CoordinateSystemUsageKind = Double

public func decideCoordSysUsageKind(
    // Component or series
    _ model: ComponentModel,
    _ printError: Bool? = nil
) -> (
    kind: CoordinateSystemUsageKind,
    coordSysType: String? // string | NullUndefined
) {
    // For backward compat, still not use `true` in model.get.
    let coordSysType = model.getShallow("coordinateSystem") as? String
    var coordSysUsageOption = model.getShallow("coordinateSystemUsage", true)
    let isDeclaredExplicitly = coordSysUsageOption != nil
    var kind: CoordinateSystemUsageKind = COORD_SYS_USAGE_KIND_NONE

    if let coordSysType = coordSysType, !coordSysType.isEmpty { // if (coordSysType)
        let isSeries = model.mainType == "series"
        if coordSysUsageOption == nil {
            coordSysUsageOption = isSeries ? "data" : "box"
        }

        if (coordSysUsageOption as? String) == "data" {
            kind = COORD_SYS_USAGE_KIND_DATA
            if !isSeries {
                if __DEV__ {
                    if isDeclaredExplicitly && (printError ?? false) {
                        log.error("coordinateSystemUsage \"data\" is not supported in non-series components.")
                    }
                }
                kind = COORD_SYS_USAGE_KIND_NONE
            }
        }
        else if (coordSysUsageOption as? String) == "box" {
            kind = COORD_SYS_USAGE_KIND_BOX
            if !isSeries && !canBeNonSeriesBoxCoordSys(coordSysType) {
                if __DEV__ {
                    if isDeclaredExplicitly && (printError ?? false) {
                        log.error("coordinateSystem \"\(coordSysType)\" cannot be used"
                            + " as coordinateSystemUsage \"box\" for \"\(model.type)\" yet."
                        )
                    }
                }
                kind = COORD_SYS_USAGE_KIND_NONE
            }
        }
    }

    return (kind, coordSysType)
}

/**
 * These cases are considered:
 *  (A) Most series can use only "COORD_SYS_USAGE_KIND_DATA", but "COORD_SYS_USAGE_KIND_BOX" is not applicable:
 *    - e.g., series.heatmap, series.line, series.bar, series.scatter, ...
 *  (B) Some series and most components can use only "COORD_SYS_USAGE_KIND_BOX", but "COORD_SYS_USAGE_KIND_DATA"
 *    is not applicable:
 *    - e.g., series.pie, series.funnel, ...
 *    - e.g., grid, polar, geo, title, ...
 *  (C) Several series can use both "COORD_SYS_USAGE_KIND_BOX" and "COORD_SYS_USAGE_KIND_DATA", even at the same time:
 *    - e.g., series.graph, series.map
 *      - If graph or map series use "COORD_SYS_USAGE_KIND_BOX", it creates a internal coord sys as
 *        "COORD_SYS_USAGE_KIND_DATA" to lay out its data.
 *      - Graph series can use matrix coord sys as either the "COORD_SYS_USAGE_KIND_DATA" (each item layout
 *        on one cell) or "COORD_SYS_USAGE_KIND_BOX" (the entire series are layout within one cell).
 *    - To achieve this effect,
 *      `series.coordinateSystemUsage: 'box'` needs to be specified explicitly.
 *
 * Check these echarts option settings:
 *  - If `series: {type: 'bar'}`:
 *      COORD_SYS_USAGE_KIND_DATA: "cartesian2d",
 *      COORD_SYS_USAGE_KIND_BOX: "none".
 *      (since `coordinateSystem: 'cartesian2d'` is the default option in bar.)
 *  - If `grid: {coordinateSystem: 'matrix'}`
 *      COORD_SYS_USAGE_KIND_DATA: "none",
 *      COORD_SYS_USAGE_KIND_BOX: "matrix".
 *  - If `series: {type: 'pie', coordinateSystem: 'matrix'}`:
 *      COORD_SYS_USAGE_KIND_DATA: "none",
 *      COORD_SYS_USAGE_KIND_BOX: "matrix".
 *      (since `coordinateSystemUsage: 'box'` is the default option in pie.)
 *  - If `series: {type: 'graph', coordinateSystem: 'matrix'}`:
 *      COORD_SYS_USAGE_KIND_DATA: "matrix",
 *      COORD_SYS_USAGE_KIND_BOX: "none"
 *  - If `series: {type: 'graph', coordinateSystem: 'matrix', coordinateSystemUsage: 'box'}`:
 *      COORD_SYS_USAGE_KIND_DATA: "an internal view",
 *      COORD_SYS_USAGE_KIND_BOX: "the internal view is laid out on a matrix"
 *  - If `series: {type: 'map'}`:
 *      COORD_SYS_USAGE_KIND_DATA: "a internal geo",
 *      COORD_SYS_USAGE_KIND_BOX: "none"
 *  - If `series: {type: 'map', coordinateSystem: 'geo', geoIndex: 0}`:
 *      COORD_SYS_USAGE_KIND_DATA: "a geo",
 *      COORD_SYS_USAGE_KIND_BOX: "none"
 *  - If `series: {type: 'map', coordinateSystem: 'matrix'}`:
 *      not_applicable
 *  - If `series: {type: 'map', coordinateSystem: 'matrix', coordinateSystemUsage: 'box'}`:
 *      COORD_SYS_USAGE_KIND_DATA: "an internal geo",
 *      COORD_SYS_USAGE_KIND_BOX: "the internal geo is laid out on a matrix"
 *
 * @usage
 * For case (A) & (B),
 *  call `injectCoordSysByOption({coordSysType: 'aaa', ...})` once for each series/components.
 * For case (C),
 *  call `injectCoordSysByOption({coordSysType: 'aaa', ...})` once for each series/components,
 *  and then call `injectCoordSysByOption({coordSysType: 'bbb', ..., isDefaultDataCoordSys: true})`
 *  once for each series/components.
 */
// PORT-NOTE: TS object-param `opt: {...}` modeled as a param struct (CONVENTIONS style, see modelUtil.swift).
public struct InjectCoordSysByOptionOpt {
    // series or component
    public var targetModel: ComponentModel
    public var coordSysType: String
    public var coordSysProvider: CoordSysInjectionProvider
    public var isDefaultDataCoordSys: Bool?
    public var allowNotFound: Bool?
    public init(
        targetModel: ComponentModel,
        coordSysType: String,
        coordSysProvider: @escaping CoordSysInjectionProvider,
        isDefaultDataCoordSys: Bool? = nil,
        allowNotFound: Bool? = nil
    ) {
        self.targetModel = targetModel
        self.coordSysType = coordSysType
        self.coordSysProvider = coordSysProvider
        self.isDefaultDataCoordSys = isDefaultDataCoordSys
        self.allowNotFound = allowNotFound
    }
}

public func injectCoordSysByOption(_ opt: InjectCoordSysByOptionOpt) -> CoordinateSystemUsageKind {
    let targetModel = opt.targetModel
    let coordSysType = opt.coordSysType
    let coordSysProvider = opt.coordSysProvider
    let isDefaultDataCoordSys = opt.isDefaultDataCoordSys
    let allowNotFound = opt.allowNotFound
    if __DEV__ {
        util.assert(!coordSysType.isEmpty) // !!coordSysType
    }

    // let {kind, coordSysType: declaredType} = decideCoordSysUsageKind(targetModel, true);
    let decided = decideCoordSysUsageKind(targetModel, true)
    var kind = decided.kind
    var declaredType = decided.coordSysType

    if (isDefaultDataCoordSys ?? false)
        && kind != COORD_SYS_USAGE_KIND_DATA {
        // If both `COORD_SYS_USAGE_KIND_DATA` and `COORD_SYS_USAGE_KIND_BOX` declared in one model.
        // There is the only case in series-graph, and no other cases yet.
        kind = COORD_SYS_USAGE_KIND_DATA
        declaredType = coordSysType
    }

    if kind == COORD_SYS_USAGE_KIND_NONE || declaredType != coordSysType {
        return COORD_SYS_USAGE_KIND_NONE
    }

    let coordSys = coordSysProvider(coordSysType, targetModel)
    if coordSys == nil { // if (!coordSys)
        if __DEV__ {
            if !(allowNotFound ?? false) {
                log.error("\(coordSysType) cannot be found for"
                    + " \(targetModel.type) (index: \(targetModel.componentIndex))."
                )
            }
        }
        return COORD_SYS_USAGE_KIND_NONE
    }

    if kind == COORD_SYS_USAGE_KIND_DATA {
        if __DEV__ {
            util.assert(targetModel.mainType == "series")
        }
        // Store the UNWRAPPED existential (`coordSys!`) — it is guaranteed non-nil past the guard above.
        // `coordSys as Any?` boxes an `Optional<CoordinateSystemMaster>` (a nested optional-in-`Any?`),
        // which downstream `coordinateSystem as? Cartesian2D` casts resolve unreliably; storing the
        // unwrapped value yields a clean `Any? = .some(existential)` that casts consistently.
        (targetModel as! SeriesModel).coordinateSystem = coordSys!
    }
    else { // kind === COORD_SYS_USAGE_KIND_BOX
        targetModel.boxCoordinateSystem = coordSys!
    }

    return kind
}

// type CoordSysInjectionProvider = (
//     coordSysType: string, injectTargetModel: ComponentModel
// ) => CoordinateSystem | NullUndefined;
public typealias CoordSysInjectionProvider = (
    _ coordSysType: String, _ injectTargetModel: ComponentModel
) -> CoordinateSystem?

public let simpleCoordSysInjectionProvider: CoordSysInjectionProvider = { coordSysType, injectTargetModel in
    // const coordSysModel = injectTargetModel.getReferringComponents(
    //     coordSysType, SINGLE_REFERRING
    // ).models[0] as (ComponentModel & {coordinateSystem: CoordinateSystem});
    // PORT-TODO: TS intersection cast `ComponentModel & {coordinateSystem: CoordinateSystem}` modeled
    //   as `as? CoordinateSystemHostModel` (the protocol that declares `coordinateSystem`). Its property
    //   type is `CoordinateSystemMaster?`, whereas upstream loosely types this as `CoordinateSystem`;
    //   bridged back with `as? CoordinateSystem` (runtime existential cast).
    let coordSysModel = injectTargetModel.getReferringComponents(
        coordSysType, model.SINGLE_REFERRING
    ).models.first as? CoordinateSystemHostModel
    return coordSysModel?.coordinateSystem as? CoordinateSystem // coordSysModel && coordSysModel.coordinateSystem
}

// export default CoordinateSystemManager;  -> `public final class CoordinateSystemManager` above.
