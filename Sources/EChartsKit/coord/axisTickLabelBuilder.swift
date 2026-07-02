// Ported from echarts/src/coord/axisTickLabelBuilder.ts — keep in sync with upstream

import Foundation
import ZRenderKit

// upstream imports:
//   import * as zrUtil from 'zrender/src/core/util';          -> `util.*` (ZRenderKit) at use sites.
//   import * as textContain from 'zrender/src/contain/text';  -> `text.*` (ZRenderKit Contain/ContainText.swift).
//   import {makeInner, removeDuplicates, removeDuplicatesGetKeyFromItemItself} from '../util/model';
//       -> `model.makeInner` / `model.removeDuplicates` / `model.removeDuplicatesGetKeyFromItemItself`.
//   import {makeLabelFormatter, getOptionCategoryInterval} from './axisHelper';
//       -> `axisHelper.*` (sibling coord/axisHelper.swift, this phase — referenced by conventional API).
//   import type Axis from './Axis';                           -> `Axis` (sibling coord/Axis.ts, this phase).
//   import Model from '../model/Model';                       -> `Model` (model/Model.swift; TS generic dropped).
//   import {AxisBaseOption, AxisTickLabelCustomValuesOption, CategoryAxisBaseOption,
//           CategoryTickLabelSplitBuildingOption, CategoryTickLabelSplitIntervalCb} from './axisCommonTypes';
//       -> `axisCommonTypes.swift` (sibling; only `AxisScaleType` landed so far — the option/cb types are
//          filled in by the coord-option phase). Referenced by conventional API here.
//   import OrdinalScale from '../scale/Ordinal';              -> `OrdinalScale` (scale/Ordinal.swift).
//   import {AxisBaseModel} from './AxisBaseModel';            -> `AxisBaseModel` (coord/AxisBaseModel.swift).
//   import type Axis2D from './cartesian/Axis2D';             -> `Axis2D` (sibling coord/cartesian/Axis2D.ts, this phase).
//   import {NullUndefined, ScaleTick} from '../util/types';   -> NullUndefined collapses to Optional (§6); `ScaleTick` (types.swift).
//   import Scale, {ScaleGetTicksOpt} from '../scale/Scale';   -> `Scale` / `ScaleGetTicksOpt` (scale/Scale.swift).
//   import {asc} from '../util/number';                       -> `number.asc` (value-returning, §3).
//   import {ordinalScaleCreateTicks} from '../scale/helper';  -> `helper.ordinalScaleCreateTicks`.
//
// PORT-TODO: `Axis`, `Axis2D`, `AxisBaseModel`, the `axisHelper.*` free functions and the
//   `axisCommonTypes` option/callback types are sibling files being ported in this same coord phase.
//   This file targets their *conventional* public API (per the task brief); it compiles once those
//   siblings land. `makeLabelFormatter(axis)` is assumed to return `(ScaleTick, Double?) -> String`
//   (the optional 2nd arg mirrors upstream `idx?`).

// PORT-TODO: these two types belong to `coord/axisCommonTypes.ts`, whose Swift stub currently only
//   exports `AxisScaleType`. Declared here as placeholders for this phase; remove them once
//   axisCommonTypes.swift lands the real declarations (owned by the coord-option phase).
public typealias AxisTickLabelCustomValuesOption = [Any] // upstream: (number | string | Date)[]
public typealias CategoryTickLabelSplitIntervalCb = (
    _ linearTickValue: Double, // tick value before sorted. "sort" means `OrdinalScale['setSortInfo']`.
    _ rawLabel: String
) -> Bool

public struct AxisLabelInfoDetermined {
    public var formattedLabel: String
    public var rawLabel: String
    public var tick: ScaleTick // Never be null/undefined.
    public init(formattedLabel: String, rawLabel: String, tick: ScaleTick) {
        self.formattedLabel = formattedLabel
        self.rawLabel = rawLabel
        self.tick = tick
    }
}

// upstream: type AxisCache<TKey, TVal> = { list: {key: TKey; value: TVal;}[] };
// PORT-TODO: `TKey` is dropped → the key is `Any?` (the category `interval` option); see
//   `axisCacheKeyEquals`. Modeled as a `final class` because it is stored on the `makeInner`
//   record and mutated in place via `push`.
final class AxisCache<TVal> {
    var list: [(key: Any?, value: TVal)] = []
    init() {}
}

// upstream: type AxisCategoryTickLabelCacheKey<TTickLabel> = CategoryAxisBaseOption[TTickLabel]['interval'];
//   -> the category `interval` option ('auto' | number | callback | NullUndefined); modeled as `Any?`.

struct AxisCategoryLabelsCreated {
    var labels: [AxisLabelInfoDetermined]
    // PORT-TODO: upstream declares `number`, but it is left `undefined` when `interval` is a callback.
    var labelCategoryInterval: Double?
}
public struct AxisCategoryTicksCreated {
    public var ticks: [ScaleTick]
    public var tickCategoryInterval: Double?
    public init(ticks: [ScaleTick], tickCategoryInterval: Double? = nil) {
        self.ticks = ticks
        self.tickCategoryInterval = tickCategoryInterval
    }
}

public typealias AxisTicksCreated = AxisCategoryTicksCreated

final class AxisModelInnerStore {
    // PORT-TODO: upstream types these `number`, but they are `undefined` until first written
    //   (`makeInner` default `{}`), and the code checks `!= null` — so modeled as `Double?`.
    var lastAutoInterval: Double?
    var lastTickCount: Double?
    var axisExtent0: Double?
    var axisExtent1: Double?
    init() {}
}
private let modelInner: (AxisBaseModel) -> AxisModelInnerStore = model.makeInner { AxisModelInnerStore() }

// upstream: type AxisInnerStoreCacheProp = 'axisTick' | 'axisLabel';
final class AxisInnerStore {
    var axisTick: AxisCache<AxisCategoryTicksCreated>?
    var axisLabel: AxisCache<AxisCategoryLabelsCreated>?
    var autoInterval: Double?
    init() {}
}
private let axisInner: (Axis) -> AxisInnerStore = model.makeInner { AxisInnerStore() }

// upstream: export const AxisTickLabelComputingKind = { estimate: 1, determine: 2 } as const;
//           export type AxisTickLabelComputingKind = (typeof AxisTickLabelComputingKind)[keyof ...]; // = 1 | 2
// PORT-TODO: the value-object doubles as a type upstream (via `typeof`). In Swift the value side is a
//   caseless-enum namespace of `Double` constants; the "type" side collapses to `Double`
//   (fields/params typed `kind: Double`).
public enum AxisTickLabelComputingKind {
    public static let estimate: Double = 1
    public static let determine: Double = 2
}

public struct AxisLabelsComputingContextOut {
    // - If `noPxChangeTryDetermine` is not empty, it indicates that the result is not reusable
    //  when axis pixel extent or axis origin point changed.
    //  Generally the result is reusable if the result values are calculated with no dependency
    //  on pixel info, such as `axis.dataToCoord` or `axis.extent`.
    // - If ensuring no px changed, calling `noPxChangeTryDetermine` to attempt to convert the
    //  "estimate" result to "determine" result.
    //  If return any falsy, cannot make that conversion and need recompute.
    public var noPxChangeTryDetermine: [() -> Bool] = []
    public init() {}
}

// upstream: interface AxisLabelsComputingContext — mutated through the reference (push to
//   `out.noPxChangeTryDetermine`), so a `final class` (identity + shared mutation).
public final class AxisLabelsComputingContext {
    // PENDING: ugly impl, refactor for better code structure?
    public var out: AxisLabelsComputingContextOut
    // Must never be NullUndefined
    public var kind: Double // AxisTickLabelComputingKind
    public init(out: AxisLabelsComputingContextOut, kind: Double) {
        self.out = out
        self.kind = kind
    }
}

public func createAxisLabelsComputingContext(_ kind: Double) -> AxisLabelsComputingContext {
    return AxisLabelsComputingContext(
        out: AxisLabelsComputingContextOut(),
        kind: kind
    )
}

// upstream inline return type of `createAxisLabels`/`makeCategoryLabels`/`makeRealNumberLabels`:
//   `{ labels: AxisLabelInfoDetermined[] }`.
public struct AxisLabelsResult {
    public var labels: [AxisLabelInfoDetermined]
    public init(labels: [AxisLabelInfoDetermined]) { self.labels = labels }
}

/**
 * CAUTION: Do not modify the result.
 */
public func createAxisLabels(_ axis: Axis, _ ctx: AxisLabelsComputingContext) -> AxisLabelsResult {
    let custom = axis.getLabelModel().get("customValues")
    if jsTruthy(custom) {
        let scale = axis.scale
        return AxisLabelsResult(
            labels: util.map(parseTickLabelCustomValues(custom as! AxisTickLabelCustomValuesOption, scale)) { tick, index in
                return AxisLabelInfoDetermined(
                    formattedLabel: axisHelper.makeLabelFormatter(axis)(tick, Double(index)),
                    rawLabel: scale.getLabel(tick),
                    tick: tick
                )
            }
        )
    }
    // Only ordinal scale support tick interval
    return axis.type == "category"
        ? makeCategoryLabels(axis, ctx)
        : makeRealNumberLabels(axis)
}

/**
 * CAUTION: Do not modify the result.
 *
 * @param tickModel For example, can be axisTick, splitLine, splitArea.
 */
public func createAxisTicks(
    _ axis: Axis,
    _ tickModel: Model,
    // PORT-TODO: upstream `Pick<ScaleGetTicksOpt, 'breakTicks' | 'pruneByBreak'>` — the full struct is
    //   accepted here and forwarded to `scale.getTicks`.
    _ opt: ScaleGetTicksOpt? = nil
) -> AxisTicksCreated {
    let scale = axis.scale
    let custom = axis.getTickModel().get("customValues")
    if jsTruthy(custom) {
        return AxisCategoryTicksCreated(
            ticks: parseTickLabelCustomValues(custom as! AxisTickLabelCustomValuesOption, scale)
        )
    }
    // Only ordinal scale support tick interval
    return axis.type == "category"
        ? makeCategoryTicks(axis, tickModel)
        : AxisCategoryTicksCreated(ticks: scale.getTicks(opt))
}

private func parseTickLabelCustomValues(
    _ customValues: AxisTickLabelCustomValuesOption,
    _ scale: Scale
) -> [ScaleTick] {
    let extent = scale.getExtent()
    // PORT-TODO: upstream `number[]`; modeled as `[Double?]` so it can be passed `inout` to
    //   `model.removeDuplicates(_: inout [TItem?], ...)`.
    var tickNumbers: [Double?] = []
    util.each(customValues) { val, _ in
        let val = scale.parse(val)
        if val >= extent[0] && val <= extent[1] {
            tickNumbers.append(val)
        }
    }
    model.removeDuplicates(&tickNumbers, { model.removeDuplicatesGetKeyFromItemItself($0) }, nil)
    // asc(tickNumbers) — value-returning per CONVENTIONS §3.
    let ascNumbers = number.asc(tickNumbers.compactMap { $0 })
    return util.map(ascNumbers) { tickVal, _ in
        return ScaleTick(value: tickVal)
    }
}

private func makeCategoryLabels(_ axis: Axis, _ ctx: AxisLabelsComputingContext) -> AxisLabelsResult {
    let labelModel = axis.getLabelModel()
    let result = makeCategoryLabelsActually(axis, labelModel, ctx)

    return (!jsTruthy(labelModel.get("show")) || axis.scale.isBlank())
        ? AxisLabelsResult(labels: [])
        : AxisLabelsResult(labels: result.labels)
}

private func makeCategoryLabelsActually(
    _ axis: Axis,
    _ labelModel: Model,
    _ ctx: AxisLabelsComputingContext
) -> AxisCategoryLabelsCreated {
    let labelsCache = ensureCategoryLabelCache(axis)
    let optionLabelInterval = axisHelper.getOptionCategoryInterval(labelModel)
    let isEstimate = ctx.kind == AxisTickLabelComputingKind.estimate

    // In AxisTickLabelComputingKind.estimate, the result likely varies during a single
    // pass of ec main process,due to the change of axisExtent, and will not be shared with
    // splitLine. Therefore no cache is used.
    if !isEstimate {
        // PENDING: check necessary?
        if let result = axisCacheGet(labelsCache, optionLabelInterval) {
            return result
        }
    }

    var labels: [AxisLabelInfoDetermined]
    var numericLabelInterval: Double?

    // PORT-TODO: `zrUtil.isFunction` cannot introspect a Swift closure stored in `Any`
    //   (util.isFunction returns false); the interval callback is detected via `as?` cast instead.
    if (optionLabelInterval as? CategoryTickLabelSplitIntervalCb) != nil {
        labels = makeTicksLabelsByCategoryIntervalNumOrCb(axis, optionLabelInterval, false) as! [AxisLabelInfoDetermined]
    }
    else {
        // optionLabelInterval === 'auto' ? makeAutoCategoryInterval(axis, ctx) : optionLabelInterval
        let ni: Double = (optionLabelInterval as? String) == "auto"
            ? makeAutoCategoryInterval(axis, ctx)
            : ((optionLabelInterval as? Double) ?? 0) // PORT-TODO: `optionLabelInterval` is a number here.
        numericLabelInterval = ni
        labels = makeTicksLabelsByCategoryIntervalNumOrCb(axis, ni, false) as! [AxisLabelInfoDetermined]
    }

    let result = AxisCategoryLabelsCreated(labels: labels, labelCategoryInterval: numericLabelInterval)
    if !isEstimate {
        axisCacheSet(labelsCache, optionLabelInterval, result)
    }
    else {
        ctx.out.noPxChangeTryDetermine.append {
            axisCacheSet(labelsCache, optionLabelInterval, result)
            return true
        }
    }
    return result
}

private func makeCategoryTicks(
    _ axis: Axis,
    _ tickModel: Model
) -> AxisCategoryTicksCreated {
    let ticksCache = ensureCategoryTickCache(axis)
    let optionTickInterval = axisHelper.getOptionCategoryInterval(tickModel)
    if let result = axisCacheGet(ticksCache, optionTickInterval) {
        return result
    }

    var ticks: [ScaleTick]
    var tickCategoryInterval: Double?

    // Optimize for the case that large category data and no label displayed,
    // we should not return all ticks.
    if !jsTruthy(tickModel.get("show")) || axis.scale.isBlank() {
        ticks = []
    }

    // PORT-TODO: `zrUtil.isFunction` → `as?` cast (see `makeCategoryLabelsActually`).
    if (optionTickInterval as? CategoryTickLabelSplitIntervalCb) != nil {
        ticks = makeTicksLabelsByCategoryIntervalNumOrCb(axis, optionTickInterval, true) as! [ScaleTick]
    }
    // Always use label interval by default despite label show. Consider this
    // scenario, Use multiple grid with the xAxis sync, and only one xAxis shows
    // labels. `splitLine` and `axisTick` should be consistent in this case.
    else if (optionTickInterval as? String) == "auto" {
        let labelsResult = makeCategoryLabelsActually(
            axis, axis.getLabelModel(), createAxisLabelsComputingContext(AxisTickLabelComputingKind.determine)
        )
        tickCategoryInterval = labelsResult.labelCategoryInterval
        ticks = util.map(labelsResult.labels) { labelItem, _ in
            return labelItem.tick
        }
    }
    else {
        let interval: Double = (optionTickInterval as? Double) ?? 0 // PORT-TODO: `optionTickInterval` is a number here.
        tickCategoryInterval = interval
        ticks = makeTicksLabelsByCategoryIntervalNumOrCb(axis, interval, true) as! [ScaleTick]
    }

    // Cache to avoid calling interval function repeatedly.
    return axisCacheSet(ticksCache, optionTickInterval, AxisCategoryTicksCreated(
        ticks: ticks, tickCategoryInterval: tickCategoryInterval
    ))
}

private func makeRealNumberLabels(_ axis: Axis) -> AxisLabelsResult {
    let ticks = axis.scale.getTicks()
    let labelFormatter = axisHelper.makeLabelFormatter(axis)
    return AxisLabelsResult(
        labels: util.map(ticks) { tick, idx in
            return AxisLabelInfoDetermined(
                formattedLabel: labelFormatter(tick, Double(idx)),
                rawLabel: axis.scale.getLabel(tick),
                tick: tick
            )
        }
    )
}

// Large category data calculation is performance sensitive, and ticks and label probably will
// be fetched multiple times (e.g. shared by splitLine and axisTick). So we cache the result.
// axis is created each time during a ec process, so we do not need to clear cache.
private let ensureCategoryTickCache: (Axis) -> AxisCache<AxisCategoryTicksCreated>
    = initAxisCacheMethod({ $0.axisTick }, { $0.axisTick = $1 })
private let ensureCategoryLabelCache: (Axis) -> AxisCache<AxisCategoryLabelsCreated>
    = initAxisCacheMethod({ $0.axisLabel }, { $0.axisLabel = $1 })

/**
 * PENDING: refactor to JS Map? Because key can be a function or more complicated object, and
 * cache size always is small, and currently no JS Map object key polyfill, we use a simple
 * array cache instead of plain object hash.
 */
// PORT-TODO: upstream indexes the store by the string `prop` (`AxisInnerStore[TCacheProp]`). Swift has
//   no heterogeneous keyed member access, so the store slot is passed as a getter/setter closure pair.
private func initAxisCacheMethod<TVal>(
    _ get: @escaping (AxisInnerStore) -> AxisCache<TVal>?,
    _ set: @escaping (AxisInnerStore, AxisCache<TVal>) -> Void
) -> (Axis) -> AxisCache<TVal> {
    return { axis in
        // return axisInner(axis)[prop] || (axisInner(axis)[prop] = {list: []});
        let store = axisInner(axis)
        if let existing = get(store) {
            return existing
        }
        let created = AxisCache<TVal>()
        set(store, created)
        return created
    }
}

private func axisCacheGet<TVal>(_ cache: AxisCache<TVal>, _ key: Any?) -> TVal? {
    for i in 0..<cache.list.count {
        if axisCacheKeyEquals(cache.list[i].key, key) {
            return cache.list[i].value
        }
    }
    return nil
}

@discardableResult
private func axisCacheSet<TVal>(_ cache: AxisCache<TVal>, _ key: Any?, _ value: TVal) -> TVal {
    cache.list.append((key: key, value: value))
    return value
}

// PORT-TODO: upstream compares cache keys with `===`. The key is the category `interval` option
//   ('auto' | number | callback). Swift cannot `===`-compare an arbitrary `Any`; we value-compare the
//   String/Double/Bool cases (covers 'auto' and numeric intervals). A callback key never matches
//   (closures are not identity-comparable here), so a function interval recomputes each call — this
//   preserves correctness (recompute yields the same result) at a small perf cost.
private func axisCacheKeyEquals(_ a: Any?, _ b: Any?) -> Bool {
    if a == nil && b == nil { return true }
    if let a = a as? String, let b = b as? String { return a == b }
    if let a = a as? Double, let b = b as? Double { return a == b }
    if let a = a as? Bool, let b = b as? Bool { return a == b }
    return false
}

private func makeAutoCategoryInterval(_ axis: Axis, _ ctx: AxisLabelsComputingContext) -> Double {
    if ctx.kind == AxisTickLabelComputingKind.estimate {
        // Currently axisTick is not involved in estimate kind, and the result likely varies during a
        // single pass of ec main process, due to the change of axisExtent. Therefore no cache is used.
        let result = axis.calculateCategoryInterval(ctx)
        ctx.out.noPxChangeTryDetermine.append {
            axisInner(axis).autoInterval = result
            return true
        }
        return result
    }
    // Both tick and label uses this result, cacah it to avoid recompute.
    let result = axisInner(axis).autoInterval
    if result != nil {
        return result!
    }
    // axisInner(axis).autoInterval = axis.calculateCategoryInterval(ctx)
    let computed = axis.calculateCategoryInterval(ctx)
    axisInner(axis).autoInterval = computed
    return computed
}

/**
 * Calculate interval for category axis ticks and labels.
 * Use a strategy to try to avoid overlapping.
 * To get precise result, at least one of `getRotate` and `isHorizontal`
 * should be implemented in axis.
 */
public func calculateCategoryInterval(_ axis: Axis, _ ctx: AxisLabelsComputingContext) -> Double {
    let kind = ctx.kind

    let params = fetchAutoCategoryIntervalCalculationParams(axis)
    let labelFormatter = axisHelper.makeLabelFormatter(axis)
    let rotation = (params.axisRotate - params.labelRotate) / 180 * Double.pi

    let ordinalScale = axis.scale as! OrdinalScale
    let ordinalExtent = ordinalScale.getExtent()
    // Providing this method is for optimization:
    // avoid generating a long array by `getTicks`
    // in large category data case.
    let tickCount = ordinalScale.count()

    if ordinalExtent[1] - ordinalExtent[0] < 1 {
        return 0
    }

    var step: Double = 1
    // Simple optimization. Arbitrary value.
    let maxCount: Double = 40
    if tickCount > maxCount {
        step = Swift.max(1, floor(tickCount / maxCount))
    }
    var tickValue = ordinalExtent[0]
    let unitSpan = axis.dataToCoord(tickValue + 1) - axis.dataToCoord(tickValue)
    let unitW = Swift.abs(unitSpan * cos(rotation))
    let unitH = Swift.abs(unitSpan * sin(rotation))

    var maxW: Double = 0
    var maxH: Double = 0

    // Caution: Performance sensitive for large category data.
    // Consider dataZoom, we should make appropriate step to avoid O(n) loop.
    while tickValue <= ordinalExtent[1] {
        var width: Double = 0
        var height: Double = 0

        // Not precise, do not consider align and vertical align
        // and each distance from axis line yet.
        let rect = text.getBoundingRect(
            labelFormatter(ScaleTick(value: tickValue), nil), params.font, .center, .top
        )
        // Magic number
        width = rect.width * 1.3
        height = rect.height * 1.3

        // Min size, void long loop.
        maxW = Swift.max(maxW, width, 7)
        maxH = Swift.max(maxH, height, 7)

        tickValue += step
    }

    var dw = maxW / unitW
    var dh = maxH / unitH
    // 0/0 is NaN, 1/0 is Infinity.
    if dw.isNaN { dw = Double.infinity }
    if dh.isNaN { dh = Double.infinity }
    let interval = Swift.max(0, floor(Swift.min(dw, dh)))

    if kind == AxisTickLabelComputingKind.estimate {
        // In estimate kind, the inteval likely varies, thus do not erase the cache.
        // zrUtil.bind(calculateCategoryIntervalTryDetermine, null, axis, interval, tickCount) → closure.
        ctx.out.noPxChangeTryDetermine.append {
            return calculateCategoryIntervalTryDetermine(axis, interval, tickCount)
        }
        return interval
    }

    let lastInterval = calculateCategoryIntervalDealCache(axis, interval, tickCount)
    return lastInterval != nil ? lastInterval! : interval
}

private func calculateCategoryIntervalTryDetermine(
    _ axis: Axis, _ interval: Double, _ tickCount: Double
) -> Bool {
    return calculateCategoryIntervalDealCache(axis, interval, tickCount) == nil
}

// Return the lastInterval if need to use it, otherwise return NullUndefined and save cache.
private func calculateCategoryIntervalDealCache(
    _ axis: Axis, _ interval: Double, _ tickCount: Double
) -> Double? {
    let cache = modelInner(axis.model)
    let axisExtent = axis.getExtent()
    let lastAutoInterval = cache.lastAutoInterval
    let lastTickCount = cache.lastTickCount
    // Use cache to keep interval stable while moving zoom window,
    // otherwise the calculated interval might jitter when the zoom
    // window size is close to the interval-changing size.
    // For example, if all of the axis labels are `a, b, c, d, e, f, g`.
    // The jitter will cause that sometimes the displayed labels are
    // `a, d, g` (interval: 2) sometimes `a, c, e`(interval: 1).
    if lastAutoInterval != nil
        && lastTickCount != nil
        && Swift.abs(lastAutoInterval! - interval) <= 1
        && Swift.abs(lastTickCount! - tickCount) <= 1
        // Always choose the bigger one, otherwise the critical
        // point is not the same when zooming in or zooming out.
        && lastAutoInterval! > interval
        // If the axis change is caused by chart resize, the cache should not
        // be used. Otherwise some hidden labels might not be shown again.
        && cache.axisExtent0 == axisExtent[0]
        && cache.axisExtent1 == axisExtent[1]
    {
        return lastAutoInterval
    }
    // Only update cache if cache not used, otherwise the
    // changing of interval is too insensitive.
    else {
        cache.lastTickCount = tickCount
        cache.lastAutoInterval = interval
        cache.axisExtent0 = axisExtent[0]
        cache.axisExtent1 = axisExtent[1]
        return nil
    }
}

private struct AutoCategoryIntervalCalculationParams {
    var axisRotate: Double
    var labelRotate: Double
    var font: String
}

private func fetchAutoCategoryIntervalCalculationParams(_ axis: Axis) -> AutoCategoryIntervalCalculationParams {
    let labelModel = axis.getLabelModel()
    // axis.getRotate ? axis.getRotate() : ((axis as Axis2D).isHorizontal && !(axis as Axis2D).isHorizontal()) ? 90 : 0
    let axisRotate: Double
    if let getRotate = axis.getRotate {
        axisRotate = getRotate()
    }
    // PORT-TODO: `Axis2D` (coord/cartesian/Axis2D.ts) is a sibling not yet landed this phase.
    //   `(axis as Axis2D).isHorizontal &&` (a truthy method-existence check) collapses to the
    //   `as? Axis2D` cast; `!(axis as Axis2D).isHorizontal()` is the negated call.
    else if let axis2D = axis as? Axis2D, !axis2D.isHorizontal() {
        axisRotate = 90
    }
    else {
        axisRotate = 0
    }
    return AutoCategoryIntervalCalculationParams(
        axisRotate: axisRotate,
        labelRotate: (labelModel.get("rotate") as? Double) ?? 0, // labelModel.get('rotate') || 0
        font: labelModel.getFont()
    )
}

// upstream: two overloads (onlyTick: false → AxisLabelInfoDetermined[]; onlyTick: true → ScaleTick[])
//   plus the implementation returning `(AxisLabelInfoDetermined | ScaleTick)[]`.
// PORT-TODO: Swift cannot overload on a `Bool` argument value, so this is one implementation returning
//   `[Any]`; call sites downcast to `[AxisLabelInfoDetermined]` / `[ScaleTick]`.
private func makeTicksLabelsByCategoryIntervalNumOrCb(
    _ axis: Axis,
    _ categoryInterval: Any,
    _ onlyTick: Bool = false
) -> [Any] {
    let labelFormatter = axisHelper.makeLabelFormatter(axis)
    let ordinalScale = axis.scale as! OrdinalScale
    var result: [Any] = [] // (AxisLabelInfoDetermined | ScaleTick)[]
    let categoryIntervalCb = categoryInterval as? CategoryTickLabelSplitIntervalCb
    let categoryIntervalIsCb = categoryIntervalCb != nil

    helper.ordinalScaleCreateTicks(
        ordinalScale,
        categoryIntervalIsCb ? 0 : ((categoryInterval as? Double) ?? 0),

        { tick, isExtentBoundary in
            var tickObj = tick
            let tickLabel = ordinalScale.getLabel(tickObj)
            if let categoryIntervalCb = categoryIntervalCb {
                // When interval is function, a falsy return means ignore the tick.
                // It is time consuming for large category data.
                let isOnInterval = categoryIntervalCb(tickObj.value, tickLabel)
                tickObj.offInterval = !isOnInterval
                // axis extent min max labels should be always included and the display strategy
                // is adopted uniformly later in `AxisBuilder`.
                if !isOnInterval && !isExtentBoundary {
                    return
                }
            }
            if onlyTick {
                result.append(tickObj)
            }
            else {
                result.append(AxisLabelInfoDetermined(
                    formattedLabel: labelFormatter(tickObj, nil),
                    rawLabel: tickLabel,
                    tick: tickObj
                ))
            }
        }
    )

    return result
}

// JS truthiness shim for the dynamic option bag (nil/false/0/NaN/"" are falsy). Not an upstream
// symbol — replaces inline `if (x)` / `!x` truthiness on `Any?` option values (e.g. `get('show')`,
// `get('customValues')`).
private func jsTruthy(_ v: Any?) -> Bool {
    guard let v = v else { return false }
    if v is NSNull { return false }
    if let b = v as? Bool { return b }
    if let n = v as? Double { return n != 0 && !n.isNaN }
    if let i = v as? Int { return i != 0 }
    if let s = v as? String { return !s.isEmpty }
    return true
}
