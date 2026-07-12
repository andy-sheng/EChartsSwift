// Ported from echarts/src/coord/axisHelper.ts — keep in sync with upstream
/*
* Licensed to the Apache Software Foundation (ASF) under one
* or more contributor license agreements.  See the NOTICE file
* distributed with this work for additional information
* regarding copyright ownership.  The ASF licenses this file
* to you under the Apache License, Version 2.0 (the
* "License"); you may not use this file except in compliance
* with the License.  You may obtain a copy of the License at
*
*   http://www.apache.org/licenses/LICENSE-2.0
*
* Unless required by applicable law or agreed to in writing,
* software distributed under the License is distributed on an
* "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
* KIND, either express or implied.  See the License for the
* specific language governing permissions and limitations
* under the License.
*/

import Foundation
import ZRenderKit

// upstream imports:
//   import * as zrUtil from 'zrender/src/core/util';           -> ZRenderKit `util` (`util.each`/`util.keys`/`util.isString`/`util.isFunction`)
//   import OrdinalScale from '../scale/Ordinal';               -> scale/Ordinal.swift (`OrdinalScale`)
//   import IntervalScale, { IntervalScaleConfig } from '../scale/Interval';  -> scale/Interval.swift (`IntervalScale`, `IntervalScaleConfig`)
//   import Scale from '../scale/Scale';                        -> scale/Scale.swift (`Scale`)
//   import TimeScale from '../scale/Time';                     -> scale/TimeScale.swift (`TimeScale`)
//   import Model from '../model/Model';                        -> model/Model.swift (`Model`)
//   import { AxisBaseModel } from './AxisBaseModel';           -> coord/AxisBaseModel.swift (`AxisBaseModel`)
//   import LogScale from '../scale/Log';                       -> scale/LogScale.swift (`LogScale`)
//   import type Axis from './Axis';                            -> coord/axisStatistics.swift shared `Axis` placeholder (Phase 6b)
//   import { AxisBaseOption, CategoryAxisBaseOption, LogAxisBaseOption, TimeAxisLabelFormatterOption,
//            AxisBaseOptionCommon, AxisLabelCategoryFormatter, AxisLabelValueFormatter,
//            AxisLabelFormatterExtraParams, OptionAxisType, AXIS_TYPES,
//            CategoryTickLabelSplitBuildingOption } from './axisCommonTypes';
//       -> coord/axisCommonTypes.swift is a minimal stub (only `AxisScaleType`); the option interfaces
//          are not yet ported (Phase 6b). The option-shape generics that only param-type the `model`
//          (AxisBaseOption / CategoryAxisBaseOption / LogAxisBaseOption / AxisBaseOptionCommon /
//          CategoryTickLabelSplitBuildingOption) collapse because `Model`/`AxisBaseModel` are
//          non-generic in the port. `OptionAxisType`, `AXIS_TYPES`, `AxisLabelCategoryFormatter`,
//          `AxisLabelValueFormatter` are forward-declared placeholders below. `TimeAxisLabelFormatterOption`
//          is reused from util/time.swift; `AxisLabelFormatterExtraParams` from scale/break.swift.
//   import SeriesData from '../data/SeriesData';               -> data/SeriesData.swift (`SeriesData`)
//   import { getStackedDimension } from '../data/helper/dataStackHelper';  -> top-level `getStackedDimension`
//   import { Dictionary, DimensionName, NullUndefined, ScaleTick } from '../util/types';
//       -> `Dictionary<T>` = [String: T] (ZRenderKit); `DimensionName`/`ScaleTick` from util/types.swift;
//          `NullUndefined` collapses to Optional (CONVENTIONS §6).
//   import { ScaleExtentFixMinMax } from './scaleRawExtentInfo';  -> declared in scale/helper.swift (belongs to coord/scaleRawExtentInfo)
//   import { parseTimeAxisLabelFormatter } from '../util/time';  -> util/time.swift (`time.parseTimeAxisLabelFormatter`)
//   import { getScaleBreakHelper } from '../scale/break';       -> scale/break.swift top-level `getScaleBreakHelper()`
//   import { error } from '../util/log';                        -> util/log.swift (`log.error`)
//   import { extentDiffers, isLogScale, isOrdinalScale } from '../scale/helper';
//       -> scale/helper.swift caseless enum `helper` (`helper.extentDiffers`/`helper.isLogScale`/`helper.isOrdinalScale`)
//   import { AxisModelExtendedInCreator } from './axisModelCreator';  -> forward-declared placeholder below (Phase 6b)
//   import { initExtentForUnion, isValidBoundsForExtent, makeInner } from '../util/model';
//       -> util/modelUtil.swift caseless enum `model` (`model.initExtentForUnion`/`model.isValidBoundsForExtent`/`model.makeInner`)
//   import { getScaleExtentForMappingUnsafe, SCALE_EXTENT_KIND_EFFECTIVE, SCALE_MAPPER_DEPTH_OUT_OF_BREAK }
//       from '../scale/scaleMapper';  -> scale/scaleMapper.swift top-level free funcs / constants
//   import ComponentModel from '../model/Component';           -> model/Component.swift (`ComponentModel`)

// ============================================================================
// PORT-NOTE: FORWARD-REFERENCE PLACEHOLDERS
// Upstream `axisHelper.ts` imports these from sibling files that are NOT yet ported in
// this phase (coord/axisCommonTypes option interfaces, coord/axisModelCreator). They are
// declared here as minimal placeholders so this hub file compiles. The agent that ports
// the corresponding source file MUST remove the placeholder here and replace it with the
// real, fully-ported type/API.
// ============================================================================

// './axisCommonTypes' — OptionAxisType = AxisBaseOption['type'] (= 'value' | 'category' | 'time' | 'log').
//   No string unions in Swift → `String` alias (mirrors the `AxisScaleType` stub already in
//   axisCommonTypes.swift). PORT-NOTE: belongs to coord/axisCommonTypes.
public typealias OptionAxisType = String

// './axisCommonTypes' — const AXIS_TYPES = {value: 1, category: 1, time: 1, log: 1} as const.
//   `Record<..., 1>` -> `[String: Int]`; the values are an unused marker constant `1`.
//   PORT-NOTE: belongs to coord/axisCommonTypes.
public let AXIS_TYPES: [String: Int] = ["value": 1, "category": 1, "time": 1, "log": 1]

// './axisCommonTypes' — AxisLabelCategoryFormatter = (rawValue, labelIndex, extra?) => string.
//   PORT-NOTE: belongs to coord/axisCommonTypes (`rawValue` is the category raw value, so `Any`).
public typealias AxisLabelCategoryFormatter = (Any, Double, Any?) -> String
// './axisCommonTypes' — AxisLabelValueFormatter = (value: number, index, extra?) => string.
//   PORT-NOTE: belongs to coord/axisCommonTypes.
public typealias AxisLabelValueFormatter = (Double, Double, AxisLabelFormatterExtraParams?) -> String

// './axisModelCreator' — AxisModelExtendedInCreator: the axis-model methods mixed in by
//   `axisModelCreator`. Now REAL: the forward-reference placeholder has been removed; the canonical
//   protocol is declared in coord/axisModelCreator.swift (its true upstream home, exported from
//   axisModelCreator.ts). `createScaleByModel` reads `getOrdinalMeta()` off it below.

// upstream inline `makeInner<{ noOnMyZero: boolean }, Axis>()` record type. Not a standalone upstream
//   symbol; `makeInner` requires a class store (CONVENTIONS §8 — makeInner keys by object identity).
//   PORT-NOTE: upstream `noOnMyZero` starts `undefined` (falsy); modeled as `false`.
final class AxisHelperInner {
    var noOnMyZero: Bool = false
    init() {}
}

// ============================================================================

// upstream module `axisHelper.ts` (free functions) -> caseless enum namespace `axisHelper`
//   (CONVENTIONS §2). Call sites: upstream `createScaleByModel(...)` -> `axisHelper.createScaleByModel(...)`.
//   The exported constants/types (`ScaleValuePositionKind`, `SCALE_VALUE_POSITION_KIND_*`) stay
//   top-level to match `import { SCALE_VALUE_POSITION_KIND_INSIDE } from './axisHelper'`.
public enum axisHelper {

    // const axisInner = makeInner<{ noOnMyZero: boolean }, Axis>();
    private static let axisInner: (Axis) -> AxisHelperInner = model.makeInner { AxisHelperInner() }

    public static func determineAxisType(
        _ model: Model
    ) -> OptionAxisType {
        var type = model.get("type") as? OptionAxisType
        if // In ec option, `xxxAxis.type` may be undefined.
            type == nil
            // PENDING: Theoretically, a customized `Scale` is probably impossible, since
            // the interface of `Scale` does not guarantee stability. But we still literally
            // support it for backward compat, though type incorrect.
            // zrUtil.hasOwn(AXIS_TYPES, type) -> dict[key] != nil (CONVENTIONS §8).
            || (AXIS_TYPES[type!] == nil && Scale.getClass(type!) == nil) {
            type = "value"
        }
        return type!
    }

    public static func createScaleByModel(
        // Expect `Pick<AxisBaseOptionCommon, 'type'>`, but be lenient for user's invalid input;
        // plus `Partial<Pick<AxisModelExtendedInCreator, 'getOrdinalMeta' | 'getCategories'>>`.
        _ model: Model,
        _ type: OptionAxisType,
        _ coordSysSupportAxisBreaks: Bool
    ) -> Scale {

        let breakHelper = getScaleBreakHelper()
        var breakOption: [AxisBreakOption]?
        if breakHelper != nil {
            breakOption = retrieveAxisBreaksOption(model, type, coordSysSupportAxisBreaks)
        }

        switch type {
        case "category":
            // upstream: ordinalMeta: model.getOrdinalMeta ? model.getOrdinalMeta() : model.getCategories()
            // PORT-NOTE: upstream duck-types on whether the *method* `getOrdinalMeta` is defined. The
            //   `AxisModelExtendedInCreator` protocol requires BOTH `getOrdinalMeta`/`getCategories`, and
            //   every ported conformer (axisModelCreator's generated model) implements `getOrdinalMeta`, so
            //   the `getOrdinalMeta()` arm is always the correct one; the `getCategories()`-only fallback
            //   describes a shape no ported model exhibits. Non-conformers yield `nil` (the empty case).
            let ordinalMeta: Any? = (model as? AxisModelExtendedInCreator)?.getOrdinalMeta()
            return OrdinalScale(OrdinalScaleSetting(
                ordinalMeta: ordinalMeta,
                // `model.initExtentForUnion()` — the `model` param (a `Model` instance) shadows the
                //   `model` util namespace enum, so the namespace call is module-qualified here.
                extent: EChartsKit.model.initExtentForUnion()
            ))
        case "time":
            return TimeScale(TimeScaleSetting(
                locale: model.ecModel!.getLocaleModel(),
                // upstream passes `model.ecModel.get('useUTC')` (typed boolean); coerced from the dynamic bag.
                useUTC: (model.ecModel!.get("useUTC") as? Bool) ?? false,  // PORT-NOTE: option-bag coercion
                breakOption: breakOption
            ))
        case "log":
            // See also #3749
            return LogScale(LogScaleSetting(
                // PORT-NOTE: `logBase` defaults to the Int literal `10` in axisDefault; a bare
                //   `as? Double` returns nil on an Int-boxed option and would silently drop it (the
                //   Int-vs-Double option-read trap), so coerce Int/NSNumber → Double.
                logBase: axisHelperNumOpt(model.get("logBase")),
                breakOption: breakOption
            ))
        case "value":
            return IntervalScale(IntervalScaleSetting(
                breakOption: breakOption
            ))
        default:
            // case others.
            // upstream: return new (Scale.getClass(type) || IntervalScale)({});
            // PORT-NOTE (platform): `Scale.getClass(type)` returns a `Constructor` (= `ClassManageable.Type`)
            //   metatype; unlike JS, Swift cannot `new Ctor({})` on an arbitrary registered metatype (there is
            //   no uniform init-from-untyped-settings requirement), so this falls back to `IntervalScale`. Only
            //   the 4 built-in scale types (category/time/log/value) are reachable; no non-builtin scale type is
            //   registered in the core port, so the fallback is never hit in practice.
            return IntervalScale()
        }
    }

    /**
     * Check if the axis cross a specific value.
     */
    public static func getScaleValuePositionKind(
        _ scale: Scale, _ value: Double, _ considerMappingExtent: Bool
    ) -> ScaleValuePositionKind {
        let dataExtent = considerMappingExtent
            ? getScaleExtentForMappingUnsafe(scale, nil)
            : scale.getExtentUnsafe(SCALE_EXTENT_KIND_EFFECTIVE, nil)
        let min = dataExtent?[0]
        let max = dataExtent?[1]
        return !model.isValidBoundsForExtent(min, max) ? SCALE_VALUE_POSITION_KIND_OUTSIDE
            : (min == value || max == value) ? SCALE_VALUE_POSITION_KIND_EDGE
            : (min! < value && max! > value) ? SCALE_VALUE_POSITION_KIND_INSIDE
            : SCALE_VALUE_POSITION_KIND_OUTSIDE
    }

    public static func discourageOnAxisZero(_ axis: Axis) {
        axisInner(axis).noOnMyZero = true
    }

    /**
     * `true`: Prevent orthoganal axes from positioning at the zero point of this axis.
     */
    public static func isOnAxisZeroDiscouraged(_ axis: Axis) -> Bool {
        return axisInner(axis).noOnMyZero
    }

    /**
     * @param axis
     * @return Label formatter function.
     *         param: {number} tickValue,
     *         param: {number} idx, the index in all ticks.
     *                         If category axis, this param is not required.
     *         return: {string} label string.
     */
    public static func makeLabelFormatter(_ axis: Axis) -> (ScaleTick, Double?) -> String {
        let labelFormatter = axis.getLabelModel().get("formatter")

        if axis.type == "time" {
            let parsed = time.parseTimeAxisLabelFormatter(labelFormatter as TimeAxisLabelFormatterOption)
            return { tick, idx in
                // PORT-NOTE: upstream `idx: number`; the returned type widens to `idx?` — time axis
                //   always receives an index, so `nil` falls back to `0`.
                return (axis.scale as! TimeScale).getFormattedLabel(tick, idx ?? 0, parsed)
            }
        }
        else if util.isString(labelFormatter) {
            let labelFormatter = labelFormatter as! String
            return { tick, _ in
                // For category axis, get raw value; for numeric axis,
                // get formatted label like '1,333,444'.
                let label = axis.scale.getLabel(tick)
                // upstream: labelFormatter.replace('{value}', label != null ? label : '')
                //   `label` is a non-optional `String` in the port (base `getLabel` never returns nil).
                // PORT-NOTE: JS `String.prototype.replace(string, ...)` replaces the FIRST match only;
                //   `replacingOccurrences` replaces all (rare for a single `{value}` placeholder).
                let text = labelFormatter.replacingOccurrences(of: "{value}", with: label)
                return text
            }
        }
        else if util.isFunction(labelFormatter) {
            if axis.type == "category" {
                return { tick, _ in
                    // The original intention of `idx` is "the index of the tick in all ticks".
                    // But the previous implementation of category axis do not consider the
                    // `axisLabel.interval`, which cause that, for example, the `interval` is
                    // `1`, then the ticks "name5", "name7", "name9" are displayed, where the
                    // corresponding `idx` are `0`, `2`, `4`, but not `0`, `1`, `2`. So we keep
                    // the definition here for back compatibility.
                    return (labelFormatter as! AxisLabelCategoryFormatter)(
                        getAxisRawValue(axis, tick),
                        tick.value - axis.scale.getExtent()[0],
                        nil // Using `null` just for backward compat.
                    )
                }
            }
            let scaleBreakHelper = getScaleBreakHelper()
            return { tick, idx in
                // Using `null` just for backward compat. It's been found that in the `test/axis-customTicks.html`,
                // there is a formatter `function (value, index, revers = true) { ... }`. Although the third param
                // `revers` is incorrect and always `null`, changing it might introduce a breaking change.
                var extra: AxisLabelFormatterExtraParams? = nil
                if let scaleBreakHelper = scaleBreakHelper {
                    extra = scaleBreakHelper.makeAxisLabelFormatterParamBreak(extra, tick.break)
                }
                return (labelFormatter as! AxisLabelValueFormatter)(
                    // PORT-NOTE: `getAxisRawValue<false>` returns `number`; cast from `Any`.
                    getAxisRawValue(axis, tick) as! Double,
                    idx ?? Double.nan,  // PORT-NOTE: returned type widens `idx` to optional
                    extra
                )
            }
        }
        else {
            return { tick, _ in
                return axis.scale.getLabel(tick)
            }
        }
    }

    // upstream: getAxisRawValue<TIsCategory extends boolean>(axis, tick): TIsCategory extends true ? string : number
    // PORT-NOTE: the `<TIsCategory>` type predicate return (`string` vs `number`) is not expressible;
    //   returns `Any` (String for ordinal scales, Double otherwise), cast at call sites.
    public static func getAxisRawValue(_ axis: Axis, _ tick: ScaleTick) -> Any {
        // In category axis with data zoom, tick is not the original
        // index of axis.data. So tick should not be exposed to user
        // in category axis.
        let scale = axis.scale
        return helper.isOrdinalScale(scale) ? scale.getLabel(tick) : tick.value
    }

    /**
     * @param model axisLabelModel or axisTickModel
     */
    // upstream: getOptionCategoryInterval(model: Model<CategoryTickLabelSplitBuildingOption>)
    //   The option-shape generic collapses (Model is non-generic in the port).
    //   upstream return: CategoryAxisBaseOption['axisLabel']['interval'] (= 'auto' | number | Function).
    public static func getOptionCategoryInterval(_ model: Model) -> Any {
        let interval = model.get("interval")
        return interval == nil ? "auto" : interval!
    }

    /**
     * Set `categoryInterval` as 0 implicitly indicates that
     * show all labels regardless of overlap.
     * @param {Object} axis axisModel.axis
     */
    public static func shouldShowAllLabels(_ axis: Axis) -> Bool {
        return axis.type == "category"
            // upstream: getOptionCategoryInterval(axis.getLabelModel()) === 0
            && (getOptionCategoryInterval(axis.getLabelModel()) as? Double) == 0
    }

    public static func getDataDimensionsOnAxis(_ data: SeriesData, _ axisDim: String) -> [DimensionName] {
        // Remove duplicated dat dimensions caused by `getStackedDimension`.
        var dataDimMap: [String: Bool] = [:]  // {} as Dictionary<boolean>
        // Currently `mapDimensionsAll` will contain stack result dimension ('__\0ecstackresult').
        // PENDING: is it reasonable? Do we need to remove the original dim from "coord dim" since
        // there has been stacked result dim?
        util.each(data.mapDimensionsAll(axisDim)) { dataDim, _ in
            // For example, the extent of the original dimension
            // is [0.1, 0.5], the extent of the `stackResultDimension`
            // is [7, 9], the final extent should NOT include [0.1, 0.5],
            // because there is no graphic corresponding to [0.1, 0.5].
            // See the case in `test/area-stack.html` `main1`, where area line
            // stack needs `yAxis` not start from 0.
            dataDimMap[getStackedDimension(data, dataDim)] = true
        }
        return util.keys(dataDimMap)
    }

    // upstream: isNameLocationCenter(nameLocation: AxisBaseOptionCommon['nameLocation'])
    //   The option union collapses to `String?` (nameLocation may be undefined).
    public static func isNameLocationCenter(_ nameLocation: String?) -> Bool {
        return nameLocation == "middle" || nameLocation == "center"
    }

    public static func shouldAxisShow(_ axisModel: AxisBaseModel) -> Bool {
        // PORT-NOTE: `getShallow` returns the dynamic option bag (`Any?`); coerced to Bool.
        return (axisModel.getShallow("show") as? Bool) ?? false
    }

    public static func retrieveAxisBreaksOption(
        _ model: Model,
        _ axisType: OptionAxisType,
        _ coordSysSupportAxisBreaks: Bool
    ) -> [AxisBreakOption]? {
        let option = model.get("breaks", true)
        if option != nil {
            if getScaleBreakHelper() == nil {
                if __DEV__ {
                    log.error(
                        "Must `import {AxisBreak} from \"echarts/features\"; use(AxisBreak);` first if using breaks option."
                    )
                }
                return nil
            }
            if !coordSysSupportAxisBreaks || !isAxisTypeSupportAxisBreak(axisType) {
                if __DEV__ { // Users have provided `breaks` in ec option but not supported.
                    let axisInfo = (model is ComponentModel)
                        ? " \((model as! ComponentModel).type)[\((model as! ComponentModel).componentIndex)]"
                        : ""
                    log.error("Axis\(axisInfo) does not support break.")
                }
                return nil
            }
            // upstream returns `axisModel.get('breaks')` directly as `AxisBreakOption[]`. In the port
            //   the dynamic option bag stores each break as a raw dictionary (the axis-option struct
            //   parser is not ported), so convert the raw `[{start,end,gap?,isExpanded?}]` entries into
            //   `AxisBreakOption` structs here. Non-dict / malformed entries are skipped.
            if let rawList = option as? [Any] {
                var result: [AxisBreakOption] = []
                for raw in rawList {
                    guard let dict = raw as? [String: Any] else { continue }
                    guard let start = dict["start"], let end = dict["end"] else { continue }
                    result.append(AxisBreakOption(
                        start: start,
                        end: end,
                        gap: dict["gap"],
                        isExpanded: dict["isExpanded"] as? Bool
                    ))
                }
                return result
            }
            // Already-parsed structs (e.g. built programmatically) pass through.
            return option as? [AxisBreakOption]
        }
        return nil
    }

    private static func isAxisTypeSupportAxisBreak(_ axisType: OptionAxisType) -> Bool {
        return axisType != "category"
    }

    public static func updateIntervalOrLogScaleForNiceOrAligned(
        // upstream: scale: IntervalScale | LogScale
        // PORT-NOTE: the `IntervalScale | LogScale` union is taken as the base `Scale`; the branches
        //   downcast (`helper.isLogScale` is upstream's `isLogScale` type predicate).
        _ scale: Scale,
        _ fixMinMax: ScaleExtentFixMinMax,
        _ oldIntervalExtent: [Double],
        _ newIntervalExtent: [Double],
        _ oldOutermostExtent: [Double]?,
        _ cfg: IntervalScaleConfig
    ) {
        let isTargetLogScale = helper.isLogScale(scale)
        let intervalStub: IntervalScale = isTargetLogScale ? (scale as! LogScale).intervalStub : (scale as! IntervalScale)
        intervalStub.setExtent(newIntervalExtent[0], newIntervalExtent[1])

        if isTargetLogScale {
            // Sync intervalStub extent to the outermost extent (i.e., `powStub` for `LogScale`).
            let powStub = (scale as! LogScale).powStub!
            let opt = ScaleMapperTransformOutOpt(depth: SCALE_MAPPER_DEPTH_OUT_OF_BREAK)  // {depth: ...} as const
            var minPow = scale.transformOut(newIntervalExtent[0], opt)
            var maxPow = scale.transformOut(newIntervalExtent[1], opt)
            // Log transform is probably not inversible by rounding error, which causes min/max tick may be
            // displayed as `5.999999999999999` unexpectedly when min/max are required to be fixed (specified
            // by users or by dataZoom). Therefore we set `powStub` with respect to `oldOutermostExtent` if
            // interval extent is not changed. But `intervalStub` should not be inversely changed by this
            // handling, otherwise its monotonicity between `niceExtent` and `extent` may be broken and cause
            // unexpected ticks generation.
            let extentChanged = helper.extentDiffers(oldIntervalExtent, newIntervalExtent)
            // NOTE: extent may still be changed even when min/max are required to be fixed,
            // e.g., by `intervalScaleEnsureValidExtent`.
            if fixMinMax[0] && !extentChanged[0] {
                minPow = oldOutermostExtent![0]
            }
            if fixMinMax[1] && !extentChanged[1] {
                maxPow = oldOutermostExtent![1]
            }
            powStub.setExtent(minPow, maxPow)
        }

        intervalStub.setConfig(cfg)
    }

    public static func getTickValueOutermost(_ scale: Scale, _ tick: ScaleTick) -> Double {
        return helper.isOrdinalScale(scale)
            ? (scale as! OrdinalScale).getRawOrdinalNumber(tick.value)
            : tick.value
    }

    public static func isAxisOnBand(_ scale: Scale, _ axisModel: AxisBaseModel) -> Bool {
        // upstream: isOrdinalScale(scale) && !!(axisModel as AxisBaseModel<CategoryAxisBaseOption>).get('boundaryGap')
        // PORT-NOTE: `boundaryGap` on a category axis is a boolean; coerced with `!!` truthiness.
        return helper.isOrdinalScale(scale) && ((axisModel.get("boundaryGap") as? Bool) ?? false)
    }
}

// Coerce a dynamic option value to Double, tolerating the Int boxing that `[String: Any]`
// defaultOption literals use (e.g. `"logBase": 10`). A bare `as? Double` returns nil on an Int,
// silently dropping the value — the recurring Int-vs-Double option-read trap.
private func axisHelperNumOpt(_ v: Any?) -> Double? {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let n = v as? NSNumber, !(n === kCFBooleanTrue || n === kCFBooleanFalse) { return n.doubleValue }
    return nil
}

// upstream: export type ScaleValuePositionKind = ... ; export const SCALE_VALUE_POSITION_KIND_* = ...;
//   Kept top-level (they are exported alongside the free functions).
// PORT-NOTE: the `1 | 2 | 3` literal union collapses to `Double` (a plain numeric tag).
public typealias ScaleValuePositionKind = Double
public let SCALE_VALUE_POSITION_KIND_INSIDE: ScaleValuePositionKind = 1
public let SCALE_VALUE_POSITION_KIND_EDGE: ScaleValuePositionKind = 2
public let SCALE_VALUE_POSITION_KIND_OUTSIDE: ScaleValuePositionKind = 3
