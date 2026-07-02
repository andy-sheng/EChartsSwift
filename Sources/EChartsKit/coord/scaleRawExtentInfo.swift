// Ported from echarts/src/coord/scaleRawExtentInfo.ts — keep in sync with upstream
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
//   import { assert, isArray, eqNaN, isFunction, each, HashMap, createHashMap } from 'zrender/src/core/util';
//       -> `util.*` (ZRenderKit Core/util.swift, re-exported); HashMap/createHashMap from util/modelUtil.swift shim.
//   import Scale from '../scale/Scale';                     -> scale/Scale.swift (same module)
//   import { AxisBaseModel } from './AxisBaseModel';        -> AxisBaseModel (model/referHelper.swift placeholder; real type = Phase 6b)
//   import { parsePercent } from 'zrender/src/contain/text';-> `text.parsePercent` (ZRenderKit Contain/ContainText.swift)
//   import { NumericAxisBaseOptionCommon, NumericAxisBoundaryGapOptionItemValue } from './axisCommonTypes';
//       -> option interfaces not ported; dynamic option bag read via `model.get` (Any?).
//   import { DimensionIndex, DimensionName, NullUndefined, ScaleDataValue } from '../util/types';
//       -> util/types.swift; NullUndefined collapses to Optional (CONVENTIONS §6).
//   import { isIntervalScale, isLogScale, isOrdinalScale, isTimeScale } from '../scale/helper';
//       -> `helper.*` (scale/helper.swift)
//   import { makeInner, initExtentForUnion, unionExtentFromNumber, isValidNumberForExtent, extentHasValue,
//            unionExtentFromExtent, unionExtentStartFromNumber, unionExtentEndFromNumber, ensureExtentAscSimply }
//       from '../util/model';
//       -> `model.*` (util/modelUtil.swift caseless enum). NOTE: the `model` enum name clashes with the
//          `model` parameter of several functions here; util-namespace calls are qualified as
//          `EChartsKit.model.*` to disambiguate.
//   import { discourageOnAxisZero, getDataDimensionsOnAxis, isAxisOnBand } from './axisHelper';
//       -> coord/axisHelper.swift NOT yet ported (Phase 6b) — call sites marked PORT-TODO.
//   import { getCoordForCoordSysUsageKindBox } from '../core/CoordinateSystem';
//       -> core/CoordinateSystem.swift NOT yet ported (Phase 6b) — box-coord-sys branch marked PORT-TODO.
//   import type GlobalModel from '../model/Global';         -> model/Global.swift (same module)
//   import { error } from '../util/log';                    -> `log.error` (util/log.swift)
//   import type Axis from './Axis';                         -> the `Axis` placeholder in coord/axisStatistics.swift
//   import { isNullableNumberFinite, mathMax, mathMin } from '../util/number';   -> `number.*` (util/number.swift)
//   import { SCALE_EXTENT_KIND_MAPPING } from '../scale/scaleMapper';            -> scale/scaleMapper.swift (top-level `let`)
//   import { AxisStatKey, eachKeyOnAxis, eachSeriesOnAxis } from './axisStatistics';  -> coord/axisStatistics.swift


// NOTE: `getCategories` now lives on the real `AxisBaseModel` (coord/AxisBaseModel.swift) as an
//   `open` base member (overridden by the generated `AxisModel`); the former forward-reference shim
//   here was removed once that landed.


/**
 * NOTICE: Can be only used in `ensureScaleStore(axisLike)`.
 *
 * In most cases the instances of `Axis` and `Scale` are one-to-one mapping and share the same lifecycle.
 * But in some external usage (such as echarts-gl), axis instance does not necessarily exist, and only
 * scale instance and axisModel are used. Therefore we store the internal info on scale instance directly.
 */
// upstream: makeInner<{ extent: number[]; dimIdxInCoord: number; }, Scale>()
//   `T` must be a class for `makeInner` (object-identity WeakMap keyed) → `ScaleInnerStore`.
final class ScaleInnerStore {
    var extent: [Double]?
    var dimIdxInCoord: Double?
    init() {}
}
private let scaleInner: (Scale) -> ScaleInnerStore = EChartsKit.model.makeInner { ScaleInnerStore() }

// upstream: export type AxisExtentInfoBuildFrom = 1 | 2 | 3 (literal union) -> `Double`.
public typealias AxisExtentInfoBuildFrom = Double
public let AXIS_EXTENT_INFO_BUILD_FROM_COORD_SYS_UPDATE: AxisExtentInfoBuildFrom = 1
public let AXIS_EXTENT_INFO_BUILD_FROM_DATA_ZOOM: AxisExtentInfoBuildFrom = 2
private let AXIS_EXTENT_INFO_BUILD_FROM_EMPTY: AxisExtentInfoBuildFrom = 3

/**
 * It is originally created as `ScaleRawExtentResultFinal['fixMinMax']` and may be
 * modified in the subsequent process.
 * It suggests axes to use `scaleRawExtentResult.min/max` directly as their bounds,
 * instead of expanding the extent by some "nice strategy". But axes may refuse to
 * comply with it in some special cases, for example, when their scale extents are
 * invalid, or when they need to be expanded to visually contain series bars.
 *
 * In `ScaleRawExtentResultFinal['fixMinMax']`, it is `true` iff:
 *  - ec option `xxxAxis.min/max` are specified, or
 *  - `scaleRawExtentResult.zoomFixMinMax[]` are `true`.
 *  - `min` `max` are expanded by `AxisContainShapeHandler`.
 *
 * In the subsequent process, it may be modified to `true` for customization.
 */
public typealias ScaleExtentFixMinMax = [Bool]

/**
 * Return the min max before `dataZoom` applied.
 * This is `noZoomEffMM`, corresponding to `SCALE_EXTENT_KIND_EFFECTIVE`.
 */
public typealias ScaleRawExtentResultForZoom = [Double]

// upstream: type ScaleRawExtentResultFinal = Pick<ScaleRawExtentInternal,
//   'fixMM' | 'zoomFixMM' | 'isBlank' | 'incl0' | 'tggAxInv' | 'ctnShp'> & { effMM: number[] };
// Data bag (no identity) → struct (CONVENTIONS §4).
public struct ScaleRawExtentResultFinal {
    public var fixMM: ScaleExtentFixMinMax
    public var zoomFixMM: ScaleExtentFixMinMax
    public var isBlank: Bool
    public var incl0: Bool
    public var tggAxInv: Bool
    public var ctnShp: Bool
    // This is the effective min max. "effective" indicates `SCALE_EXTENT_KIND_EFFECTIVE`.
    // It is determined by series data extent and ec options such as `xxxAxis.min/max`,
    // `xxxAxis.boundaryGap`, etc. And this is the input of "nice" strategy.
    // Ensure `effMM` has only finite numbers or `NaN`, but never has `null`/`undefined`.
    // `NaN` means min/max axis is blank.
    public var effMM: [Double]
    public init(
        fixMM: ScaleExtentFixMinMax,
        zoomFixMM: ScaleExtentFixMinMax,
        isBlank: Bool,
        incl0: Bool,
        tggAxInv: Bool,
        ctnShp: Bool,
        effMM: [Double]
    ) {
        self.fixMM = fixMM
        self.zoomFixMM = zoomFixMM
        self.isBlank = isBlank
        self.incl0 = incl0
        self.tggAxInv = tggAxInv
        self.ctnShp = ctnShp
        self.effMM = effMM
    }
}

// upstream: type ScaleRawExtentResultOthers = Pick<ScaleRawExtentInternal, 'startValue'>;
public struct ScaleRawExtentResultOthers {
    public var startValue: Double?
    public init(startValue: Double?) { self.startValue = startValue }
}


/**
 * CAVEAT: MUST NOT be modified outside!
 */
// upstream: interface ScaleRawExtentInternal — a mutable bag whose arrays are aliased/mutated in place
//   (fixMM/zoomFixMM toggled in makeFinal, noZoomEffMM sanitized). Shared-identity mutation → final class
//   (CONVENTIONS §4).
final class ScaleRawExtentInternal {

    var scale: Scale

    // The effective min max before `dataZoom` being applied.
    // "effective" means `SCALE_EXTENT_KIND_EFFECTIVE`.
    var noZoomEffMM: [Double]

    // data min max, an union from series data on this axis and `model.dataMin/dataMax`.
    // May be at the initial state `[Infinity, -Infinity]`.
    var dataMM: [Double]

    // See `ScaleRawExtentInfo['setZoomMM']`
    // upstream: (number | NullUndefined)[]
    var zoomMM: [Double?]

    // See comments of `ScaleExtentFixMinMax`
    var fixMM: ScaleExtentFixMinMax

    // It indicates that the min max have been fixed by `dataZoom` when its start/end is not 0%/100%.
    var zoomFixMM: ScaleExtentFixMinMax

    // Parsed from `AxisBaseOptionCommon['startValue'`]`.
    // If it is not explicitly specified in ec option, and no series has a true return
    // of `__requireStartValue()`, it will be a null/undefined.
    var startValue: Double?

    // Mark that the axis should be blank.
    var isBlank: Bool

    // Need to include zero
    var incl0: Bool

    // Need to toggle axis inverse.
    var tggAxInv: Bool

    // Whether "containShape" is required on this axis.
    // NOTICE: This is just a requirement; "containShape" is performed only if possible.
    var ctnShp: Bool

    init(
        scale: Scale,
        dataMM: [Double],
        noZoomEffMM: [Double],
        zoomMM: [Double?],
        fixMM: ScaleExtentFixMinMax,
        zoomFixMM: ScaleExtentFixMinMax,
        startValue: Double?,
        isBlank: Bool,
        incl0: Bool,
        tggAxInv: Bool,
        ctnShp: Bool
    ) {
        self.scale = scale
        self.dataMM = dataMM
        self.noZoomEffMM = noZoomEffMM
        self.zoomMM = zoomMM
        self.fixMM = fixMM
        self.zoomFixMM = zoomFixMM
        self.startValue = startValue
        self.isBlank = isBlank
        self.incl0 = incl0
        self.tggAxInv = tggAxInv
        self.ctnShp = ctnShp
    }
}

// upstream: type AxisContainShapeHandler = (axis: Axis, ecModel: GlobalModel) => number[] | NullUndefined
//   @return: supplement in linear space.
//    Must ensure: `supplement[0] <= 0 && supplement[1] >= 0`
public typealias AxisContainShapeHandler = (_ axis: Axis, _ ecModel: GlobalModel) -> [Double]?


public final class ScaleRawExtentInfo {

    private var _i: ScaleRawExtentInternal!

    // Injected outside
    // upstream: readonly from: AxisExtentInfoBuildFrom — injected via `injectScaleRawExtentInfo`.
    public internal(set) var from: AxisExtentInfoBuildFrom!


    public init(
        _ scale: Scale,
        _ model: AxisBaseModel,
        // Typically: data extent from all series on this axis.
        _ dataExtent: [Double],
        _ requireStartValue: Bool,
        _ requireContainShape: Bool
    ) {
        let isOrdinal = helper.isOrdinalScale(scale)

        let axisDataLen: Double? = isOrdinal
            // FIXME: there is a flaw here: if there is no "block" data processor like `dataZoom`,
            // and progressive rendering is using, here the category result might just only contain
            // the processed chunk rather than the entire result.
            ? Double(model.getCategories()?.count ?? 0)
            : nil

        // [CATEGORY_AXIS_MODEL_DATA_IS_EMPTY_ARRAY]:
        // This is only for backward compatibility - `xxxAxis: {data: []}` can declare this axis as
        // a "category" axis and use `series.data` to determine its extent but the axis is blank - only
        // axis line is displayed. This is a conincidence, but it is used in some cases.
        var categoryAxisModelDataIsEmptyArray: Bool = false
        if isOrdinal {
            let axisModelDataArray = model.getCategories(true)
            categoryAxisModelDataIsEmptyArray = axisModelDataArray != nil && axisModelDataArray!.isEmpty
        }

        // NOTE: also considered the input dataExtent may be still in the initialized state `[Infinity, -Infinity]`.
        var dataMM = dataExtent   // dataExtent.slice()
        // custom dataMin/dataMax.
        // Also considered `modelDataMinMax[0] > modelDataMinMax[1]` may occur.
        if helper.isIntervalScale(scale) || helper.isLogScale(scale) || helper.isTimeScale(scale) {
            EChartsKit.model.unionExtentStartFromNumber(
                &dataMM,
                parseAxisModelMinMax(scale, model.get("dataMin", true))
            )
            EChartsKit.model.unionExtentEndFromNumber(
                &dataMM,
                parseAxisModelMinMax(scale, model.get("dataMax", true))
            )
        }
        if !EChartsKit.model.extentHasValue(dataMM) {
            // dataMM may be still `[Infinity, -Infinity]`, we use `NaN` on the subsequent calculations
            // to force the `noZoomEffMM` to be `[NaN, NaN]` if needed.
            dataMM[0] = Double.nan
            dataMM[1] = Double.nan
        }

        var noZoomEffMM: [Double?] = [nil, nil]
        var fixMM: [Bool] = [false, false]

        // Notice: When min/max is not set (that is, when there are null/undefined,
        // which is the most common case), these cases should be ensured:
        // (1) For 'ordinal', show all axis.data.
        // (2) For others:
        //      + `boundaryGap` is applied (if min/max set, boundaryGap is
        //      disabled).
        //      + If `needIncludeZero`, min/max should be zero, otherwise, min/max should
        //      be the result that originalExtent enlarged by boundaryGap.
        // (3) If no data, it should be ensured that `scale.setBlank` is set.

        let modelMinRaw = model.get("min", true)
        if (modelMinRaw as? String) == "dataMin" {
            noZoomEffMM[0] = dataMM[0]
            fixMM[0] = true
        }
        else {
            noZoomEffMM[0] = parseAxisModelMinMax(
                scale,
                util.isFunction(modelMinRaw)
                    // This callback always provides users the full data extent (before data is filtered).
                    ? invokeAxisMinMaxCallback(modelMinRaw, dataMM)
                    : modelMinRaw
            )
            // If `xxxAxis.min: null/undefined`, min should not be fixed.
            fixMM[0] = noZoomEffMM[0] != nil
        }

        let modelMaxRaw = model.get("max", true)
        if (modelMaxRaw as? String) == "dataMax" {
            noZoomEffMM[1] = dataMM[1]
            fixMM[1] = true
        }
        else {
            noZoomEffMM[1] = parseAxisModelMinMax(
                scale,
                util.isFunction(modelMaxRaw)
                    // This callback always provides users the full data extent (before data is filtered).
                    ? invokeAxisMinMaxCallback(modelMaxRaw, dataMM)
                    : modelMaxRaw
            )
            // If `xxxAxis.max: null/undefined`, max should not be fixed.
            fixMM[1] = noZoomEffMM[1] != nil
        }

        let boundaryGap = parseBoundaryGapOption(scale, model)

        let span: Double? = !isOrdinal
            // PENDING: Historicall behavior but may not reasonable enough.
            ? { let diff = dataMM[1] - dataMM[0]; return (diff == 0 || diff.isNaN) ? number.mathAbs(dataMM[0]) : diff }()
            : nil
        // JS truthy on `axisDataLen`: non-nil and non-zero.
        let axisDataLenTruthy = (axisDataLen != nil && axisDataLen! != 0)
        // NOTE: If a numeric axis min/max is specified as 'dataMin'/'dataMax',
        // `boundaryGap` will not be used.
        if noZoomEffMM[0] == nil {
            noZoomEffMM[0] = isOrdinal
                ? (categoryAxisModelDataIsEmptyArray ? dataMM[0] : (axisDataLenTruthy ? 0 : Double.nan))
                : dataMM[0] - boundaryGap[0] * span!
        }
        if noZoomEffMM[1] == nil {
            noZoomEffMM[1] = isOrdinal
                ? (categoryAxisModelDataIsEmptyArray ? dataMM[1] : (axisDataLenTruthy ? axisDataLen! - 1 : Double.nan))
                : dataMM[1] + boundaryGap[1] * span!
        }

        // Normalize to `NaN` if invalid; e.g., this may occur when `dataMM` has Infinity.
        if !EChartsKit.model.isValidNumberForExtent(noZoomEffMM[0]) { noZoomEffMM[0] = Double.nan }
        if !EChartsKit.model.isValidNumberForExtent(noZoomEffMM[1]) { noZoomEffMM[1] = Double.nan }

        let isBlank = categoryAxisModelDataIsEmptyArray
            || util.eqNaN(noZoomEffMM[0]!) || util.eqNaN(noZoomEffMM[1]!)
            || (isOrdinal && !axisDataLenTruthy)

        // NOTE: `needIncludeZero` is not applicable to LogScale, TimeScale, OrdinalScale.
        let needIncludeZeroApplicable = helper.isIntervalScale(scale)
        let needIncludeZero = needIncludeZeroApplicable && model.needIncludeZero()
        if needIncludeZero {
            if noZoomEffMM[0]! > 0 && noZoomEffMM[1]! > 0 && !fixMM[0] {
                noZoomEffMM[0] = 0
                // fixMM[0] = true;
            }
            if noZoomEffMM[0]! < 0 && noZoomEffMM[1]! < 0 && !fixMM[1] {
                noZoomEffMM[1] = 0
                // fixMM[1] = true;
            }
        }

        var needToggleAxisInverse: Bool = false
        if noZoomEffMM[0]! > noZoomEffMM[1]! {
            // Historically, if users set `xxxAxis.min > xxxAxis.max`, or `xxxAxis.max < dataExtent[0]`,
            // or `xxxAxis.min > dataExtent[1]` the behavior is sometimes like `xxxAxis.inverse = true`,
            // sometimes abnormal. We remain backward compatible with the former one, though this feature
            // may not be reasonable.
            // And handle it after "needIncludeZero" is also for backward compatibility.
            noZoomEffMM.reverse()
            needToggleAxisInverse = true
        }

        var startValue = parseAxisModelMinMax(scale, model.get("startValue", true))
        let startValueSpecified = startValue != nil
        if !number.isNullableNumberFinite(startValue) && requireStartValue {
            startValue = scale.getDefaultStartValue != nil ? scale.getDefaultStartValue!() : 0
        }
        if number.isNullableNumberFinite(startValue)
            // Keep backward compatibility and enable `xxxAxis.scale: true` enabled on bar series:
            // if `xxxAxis.scale: true` and `startValue` is not specified, do not union the default `startValue`,
            && (startValueSpecified || !needIncludeZeroApplicable || needIncludeZero)
        {
            if startValue! < noZoomEffMM[0]! && !fixMM[0] {
                noZoomEffMM[0] = startValue
                fixMM[0] = true
            }
            else if startValue! > noZoomEffMM[1]! && !fixMM[1] {
                noZoomEffMM[1] = startValue
                fixMM[1] = true
            }
        }

        let noZoomEffMMFinal: [Double] = [noZoomEffMM[0]!, noZoomEffMM[1]!]
        let internalBag = ScaleRawExtentInternal(
            scale: scale,
            dataMM: dataMM,
            noZoomEffMM: noZoomEffMMFinal,
            zoomMM: [],
            fixMM: fixMM,
            zoomFixMM: [false, false],
            startValue: startValue,
            isBlank: isBlank,
            incl0: needIncludeZero,
            tggAxInv: needToggleAxisInverse,
            ctnShp: requireContainShape
        )
        self._i = internalBag

        sanitizeExtent(internalBag, &internalBag.noZoomEffMM)
    }

    public func makeNoZoom() -> ScaleRawExtentResultForZoom {
        return self._i.noZoomEffMM   // .slice()
    }

    public func makeFinal() -> ScaleRawExtentResultFinal {
        let internalBag = self._i!
        let zoomMM = internalBag.zoomMM
        let noZoomEffMM = internalBag.noZoomEffMM

        var effMM = noZoomEffMM   // noZoomEffMM.slice()

        // NOTE: Switching `fixMM` probably leads to abrupt extent changes when draging a `dataZoom`
        //  handle, since `fixMM` impact the "nice extent" and "nice ticks" calculation.
        //  Consider a case:
        //    dataZoom `start` is 2% but its `end` is 100%, (or vice versa), we currently only set `fixMM[0]`
        //    as `true` but remain `fixMM[1]` as `false` for this case to avoid unnecessary abrupt change.
        //    Incidentally, the effect is not unacceptable if we set both `fixMM[0]/[1]` as `true`.
        if zoomMM.count > 0, let z0 = zoomMM[0] {
            effMM[0] = z0
            internalBag.fixMM[0] = true
            internalBag.zoomFixMM[0] = true
        }
        if zoomMM.count > 1, let z1 = zoomMM[1] {
            effMM[1] = z1
            internalBag.fixMM[1] = true
            internalBag.zoomFixMM[1] = true
        }
        sanitizeExtent(internalBag, &effMM)

        // upstream `result` aliases `internal.fixMM`/`zoomFixMM` (JS refs), so the mutations above are
        // reflected in the returned result; Swift value arrays copy the post-mutation state here.
        return ScaleRawExtentResultFinal(
            fixMM: internalBag.fixMM,
            zoomFixMM: internalBag.zoomFixMM,
            isBlank: internalBag.isBlank,
            incl0: internalBag.incl0,
            tggAxInv: internalBag.tggAxInv,
            ctnShp: internalBag.ctnShp,
            effMM: effMM
        )
    }

    public func makeRenderInfo() -> ScaleRawExtentResultOthers {
        return ScaleRawExtentResultOthers(
            startValue: self._i.startValue
        )
    }

    /**
     * NOTICE:
     *  - Do not set them if the percent are 0% or 100%. (See `AxisProxy['reset']`.)
     *  - The caller must ensure `start <= end` and the range is equal or less then `noZoomEffMM`.
     *    (See `AxisProxy['calculateDataWindow']`.)
     *  - The outcome `_zoomMM` may have both `NullUndefined` and a finite value, like `[undefined, 123]`.
     */
    // upstream: setZoomMM(idxMinMax: 0 | 1, val: number | NullUndefined)
    public func setZoomMM(_ idxMinMax: Int, _ val: Double?) {
        // upstream `this._i.zoomMM[idxMinMax] = val` on a possibly-empty array (JS auto-grows).
        while self._i.zoomMM.count <= idxMinMax {
            self._i.zoomMM.append(nil)
        }
        self._i.zoomMM[idxMinMax] = val
    }

}

/**
 * Should be called when a new extent is created or modified.
 */
private func sanitizeExtent(
    _ internalBag: ScaleRawExtentInternal,
    _ mm: inout [Double]
) {
    let scale = internalBag.scale
    let dataMM = internalBag.dataMM
    if let sanitize = scale.sanitize {
        // upstream: mm[0] = scale.sanitize(mm[0], dataMM); mm[1] = scale.sanitize(mm[1], dataMM);
        // PORT-TODO: sanitize returns `Double?` (optional slot); upstream returns a number — keep the
        //   existing value if a nil is returned.
        if let s0 = sanitize(mm[0], dataMM) { mm[0] = s0 }
        if let s1 = sanitize(mm[1], dataMM) { mm[1] = s1 }
        // ensureExtentAscSimply(mm) — model.ensureExtentAscSimply takes `inout [Double?]`; bridge.
        var tmp: [Double?] = [mm[0], mm[1]]
        EChartsKit.model.ensureExtentAscSimply(&tmp)
        mm[0] = tmp[0]!
        mm[1] = tmp[1]!
    }
}

// upstream: parseAxisModelMinMax(scale, minMax: ScaleDataValue): number
//   The body returns `null` when `minMax == null`, so the Swift return is `Double?`.
private func parseAxisModelMinMax(_ scale: Scale, _ minMax: ScaleDataValue?) -> Double? {
    if minMax == nil || minMax is NSNull {
        return nil // null/undefined means not specified and other default values can be applied.
    }
    if let d = minMax as? Double, util.eqNaN(d) {
        return Double.nan // NaN means a deliberate invalid number.
    }
    return scale.parse(minMax!)
}

// PORT-TODO: min/max callback `({min, max}) => value`. The option bag stores it as `Any`; we attempt a
//   best-effort cast to a `([String: Double]) -> ScaleDataValue` closure and invoke it with the full
//   (pre-filter) data extent. If the cast fails, treat as unspecified (nil).
private func invokeAxisMinMaxCallback(_ raw: Any?, _ dataMM: [Double]) -> ScaleDataValue? {
    if let fn = raw as? (([String: Double]) -> ScaleDataValue) {
        return fn(["min": dataMM[0], "max": dataMM[1]])
    }
    return nil
}

private func parseBoundaryGapOption(
    _ scale: Scale,
    _ model: AxisBaseModel
) -> [Double] {
    var boundaryGapOptionArr: [Any?]
    if helper.isOrdinalScale(scale) {
        boundaryGapOptionArr = [0, 0]
    }
    else {
        var boundaryGap = model.get("boundaryGap")
        if boundaryGap is Bool {
            if __DEV__ {
                if (boundaryGap as? Bool) == true {
                    log.error("Boolean type for boundaryGap is only "
                        + "allowed for ordinal axis. Please use string in "
                        + "percentage instead, e.g., \"20%\". Currently, "
                        + "boundaryGap is set to 0.")
                }
            }
            boundaryGap = nil
        }
        boundaryGapOptionArr = util.isArray(boundaryGap)
            ? (boundaryGap as! [Any?])
            : [boundaryGap, boundaryGap]
    }
    return [
        parseBoundaryGapOptionItem(boundaryGapOptionArr[0]),
        parseBoundaryGapOptionItem(boundaryGapOptionArr[1]),
    ]
}

// upstream: parseBoundaryGapOptionItem(opt: NumericAxisBoundaryGapOptionItemValue | boolean): number
private func parseBoundaryGapOptionItem(
    _ opt: Any?
) -> Double {
    let value: NumberOrString
    if opt is Bool {
        value = 0
    }
    else if let d = opt as? Double {
        value = .number(d)
    }
    else if let i = opt as? Int {
        value = .number(Double(i))
    }
    else if let s = opt as? String {
        value = .string(s)
    }
    else {
        value = 0
    }
    // parsePercent(...) || 0
    let p = text.parsePercent(value, 1)
    return (p.isNaN || p == 0) ? 0 : p
}

/**
 * NOTE: `associateSeriesWithAxis` is not necessarily called, e.g., when
 * an axis is not used by any series.
 */
// upstream: ensureScaleStore(axisLike: {scale: Scale}) — takes the scale directly here.
private func ensureScaleStore(_ scale: Scale) -> ScaleInnerStore {
    let store = scaleInner(scale)
    if store.extent == nil {
        store.extent = EChartsKit.model.initExtentForUnion()
    }
    return store
}

/**
 * This supports union extent on case like: pie (or other similar series)
 * lays out on cartesian2d.
 * @see scaleRawExtentInfoCreate
 */
// upstream: axisLike: { scale: Scale; dim: DimensionName } — passed as (scale, dim) here.
public func scaleRawExtentInfoEnableBoxCoordSysUsage(
    _ scale: Scale,
    _ dim: DimensionName,
    _ coordSysDimIdxMap: HashMap<DimensionIndex>?
) {
    ensureScaleStore(scale).dimIdxInCoord = coordSysDimIdxMap?.get(dim)
}

/**
 * @usage
 *  class SomeCoordSys {
 *      static create() {
 *          ecModel.eachSeries(function (seriesModel) {
 *              associateSeriesWithAxis(axis1, seriesModel, ...);
 *              associateSeriesWithAxis(axis2, seriesModel, ...);
 *              // ...
 *          });
 *      }
 *      update() {
 *          scaleRawExtentInfoCreate(axis1);
 *          scaleRawExtentInfoCreate(axis2);
 *      }
 *  }
 *  class AxisProxy {
 *      reset() {
 *          scaleRawExtentInfoCreate(axis1);
 *      }
 *  }
 *
 * NOTICE:
 *  - `associateSeriesWithAxis`(in `axisStatistics.ts`) should be called in:
 *    - Coord sys create method.
 *  - `scaleRawExtentInfoCreate` should be typically called in:
 *    - `dataZoom` processor. It requires processing like:
 *      1. Filter series data by dataZoom1;
 *      2. Union the filtered data and init the extent of the orthogonal axes, which is the 100% of dataZoom2;
 *      3. Filter series data by dataZoom2;
 *      4. ...
 *    - Coord sys update method, for other axes that not covered by `dataZoom`.
 *      NOTE: If a `dataZoom` covers this series, this data and its extent has been dataZoom-filtered.
 *      Therefore this handling should not before `dataZoom`.
 *  - The callback of `min`/`max` in ec option should NOT be called multiple times,
 *    therefore, we initialize `ScaleRawExtentInfo` uniformly in `scaleRawExtentInfoCreate`.
 *
 * @see SCALE_EXTENT_CONSTRUCTION for the full processing flow.
 */
public func scaleRawExtentInfoCreate(
    _ axis: Axis,
    _ from: AxisExtentInfoBuildFrom
) {
    let scale = axis.scale
    let model: AxisBaseModel = axis.model   // upstream: axis.model (IUO; asserted below)
    let axisDim = axis.dim
    if __DEV__ {
        util.assert(!axisDim.isEmpty)   // assert(scale && model && axisDim)
    }

    if scale.rawExtentInfo != nil {
        if __DEV__ {
            // Check for incorrect impl - the duplicated calling of this method is only allowed in
            // these cases:
            //  - First in `AxisProxy['reset']` (for dataZoom)
            //  - Then in `CoordinateSystem['update']`.
            //  - Then after `chart.appendData()` due to `dirtyOnOverallProgress: true`
            util.assert(scale.rawExtentInfo!.from != from || from == AXIS_EXTENT_INFO_BUILD_FROM_DATA_ZOOM)
        }
        return
    }

    scaleRawExtentInfoCreateDeal(scale, axis, axisDim, model, from)
}

private func scaleRawExtentInfoCreateDeal(
    _ scale: Scale,
    _ axis: Axis,
    _ axisDim: DimensionName,
    _ model: AxisBaseModel,
    _ from: AxisExtentInfoBuildFrom
) {
    let scaleStore = ensureScaleStore(axis.scale)
    var extent = scaleStore.extent!
    // PORT-TODO(Phase 6b): restore to `var` when the `__requireStartValue` branch below is wired
    //   (it reassigns this to true). Currently that branch is stubbed, so it stays false.
    let requireStartValue = false

    eachSeriesOnAxis(axis) { seriesModel in
        // PORT-TODO: `seriesModel.boxCoordinateSystem` + `getCoordForCoordSysUsageKindBox`
        //   (core/CoordinateSystem.ts) not ported (Phase 6b). The box-coord-sys union branch
        //   (pie-on-cartesian2d and similar) is omitted; only the `coordinateSystem` data-extent
        //   branch below is ported.
        //
        // if (seriesModel.boxCoordinateSystem) {
        //     const {coord} = getCoordForCoordSysUsageKindBox(seriesModel);
        //     const dimIdx = scaleStore.dimIdxInCoord;
        //     if (!(dimIdx >= 0)) { error(...); }
        //     else if (isArray(coord)) {
        //         const coordItem = coord[dimIdx];
        //         if (coordItem != null && !isArray(coordItem)) {
        //             unionExtentFromNumber(extent, scale.parse(coordItem));
        //         }
        //     }
        // }
        // else if (seriesModel.coordinateSystem) {
        if seriesModel.coordinateSystem != nil {
            // NOTE: This data may have been filtered by dataZoom on orthogonal axes.
            let data = seriesModel.getData()
            // if (data) {
            let filter = scale.getFilter != nil ? scale.getFilter!() : nil
            util.each(axisHelper.getDataDimensionsOnAxis(data, axisDim)) { dim, _ in
                EChartsKit.model.unionExtentFromExtent(&extent, data.getApproximateExtent(dim, filter))
            }
            // }
            // PORT-TODO: `seriesModel.__requireStartValue(axis)` not on the ported SeriesModel (Phase 6b).
            //   if (seriesModel.__requireStartValue && seriesModel.__requireStartValue(axis)) {
            //       requireStartValue = true;
            //   }
        }
    }

    let requireContainShape = determineRequireContainShape(scale, axis, model)

    let rawExtentInfo = ScaleRawExtentInfo(scale, model, extent, requireStartValue, requireContainShape)
    injectScaleRawExtentInfo(scale, rawExtentInfo, from)

    scaleStore.extent = nil // Clean up
}

/**
 * `rawExtentInfo` may not be created in some cases, such as no series declared or extra useless
 * axes declared in ec option. In this case we still create a default one for that empty axis.
 */
// upstream: axisLike: { scale: Scale; model: AxisBaseModel } — passed as (scale, model) here.
private func scaleRawExtentInfoBuildDefault(
    _ scale: Scale,
    _ model: AxisBaseModel,
    _ dataExtent: [Double]
) {
    if __DEV__ {
        util.assert(scale.rawExtentInfo == nil)
    }
    injectScaleRawExtentInfo(
        scale,
        ScaleRawExtentInfo(scale, model, dataExtent, false, false),
        AXIS_EXTENT_INFO_BUILD_FROM_EMPTY
    )
}

private func injectScaleRawExtentInfo(
    _ scale: Scale,
    _ scaleRawExtentInfo: ScaleRawExtentInfo,
    _ from: AxisExtentInfoBuildFrom
) {
    scale.rawExtentInfo = scaleRawExtentInfo
    scaleRawExtentInfo.from = from
}

/**
 * See `axisSnippets.ts` for some commonly used handlers.
 *
 * FIXME:
 *  `boundaryGap: true` (i.e., `onBand: true` in code) has long been supported on category axis.
 *  And it is implemented in different code and not merged to this implementation yet.
 */
public func registerAxisContainShapeHandler(
    // `axisStatKey` is used to quickly omit irrelevant handlers,
    // since handlers need to be iterated per axis.
    _ axisStatKey: AxisStatKey,
    _ handler: @escaping AxisContainShapeHandler
) {
    if __DEV__ {
        util.assert(axisContainShapeHandlerMap.get(axisStatKey) == nil)
    }
    axisContainShapeHandlerMap.set(axisStatKey, handler)
}

// upstream: const axisContainShapeHandlerMap: HashMap<AxisContainShapeHandler, AxisStatKey> = createHashMap();
private let axisContainShapeHandlerMap: HashMap<AxisContainShapeHandler> = createHashMap()


/**
 * Prepare axis scale extent before "nice".
 * Item of returned array can only be number (including Infinity and NaN).
 */
public func adoptScaleRawExtentInfoAndPrepare(
    _ scale: Scale,
    _ model: AxisBaseModel,
    _ ecModel: GlobalModel?,
    _ axis: Axis?,
    _ externalDataExtent: [Double]?
) -> ScaleRawExtentResultFinal {

    if __DEV__ {
        util.assert(externalDataExtent == nil || scale.rawExtentInfo == nil)
    }

    if scale.rawExtentInfo == nil {
        scaleRawExtentInfoBuildDefault(
            scale, model,
            externalDataExtent ?? EChartsKit.model.initExtentForUnion()
        )
    }
    let rawExtentResult = scale.rawExtentInfo!.makeFinal()

    // NOTE: This `scale.setExtent()` is required by:
    //  - `axisNiceTicks.ts` and `axisAlignTicks.ts`, where the internal `scaleMapper` may be required.
    let effectiveMinMax = rawExtentResult.effMM
    scale.setExtent(effectiveMinMax[0], effectiveMinMax[1])

    scale.setBlank(rawExtentResult.isBlank)

    // JS truthy check on `ecModel.get('legacyMinMaxDontInverseAxis')`.
    let legacyOpt = ecModel != nil ? ecModel!.get("legacyMinMaxDontInverseAxis") : nil
    let legacyTruthy = (legacyOpt as? Bool) ?? (legacyOpt != nil && !(legacyOpt is NSNull))
    if let axis = axis,
        rawExtentResult.tggAxInv,
        ecModel != nil && !legacyTruthy
    {
        axis.inverse = !axis.inverse
    }

    return rawExtentResult
}

private func determineRequireContainShape(
    _ scale: Scale,
    _ axis: Axis,
    _ model: AxisBaseModel
) -> Bool {
    let onBand = axisHelper.isAxisOnBand(scale, model)
    var modelContainShape = model.get("containShape", true)
    if (modelContainShape == nil || modelContainShape is NSNull) && !onBand {
        modelContainShape = true
    }
    // if (!modelContainShape) — JS falsy guard.
    let containShapeTruthy = (modelContainShape as? Bool) ?? (modelContainShape != nil && !(modelContainShape is NSNull))
    if !containShapeTruthy {
        return false
    }
    var requireContainShape = false
    eachKeyOnAxis(axis) { axisStatKey in
        requireContainShape = (axisContainShapeHandlerMap.get(axisStatKey) != nil) || requireContainShape
    }
    return requireContainShape
}

/**
 * This implements ec option `someAxis.containShape`. That is, expand scale extent slightly to
 * ensure shapes of specific series are fully contained in the axis extent without overflow.
 *
 * NOTICE:
 *  Scale extent (data extent) and axis pixel extent (pixel extent) and are required as inputs.
 *    - See BAND_WIDTH_USED_SCALE_LINEAR_SPAN.
 *    - Axis pixel extent has been set outside, though it may be modified later (e.g., via `outerBounds`).
 *
 * @tutorial [AXIS_CONTAIN_SHAPE_PROCESSING_ORDER]
 *  This is a trade-off between the following 2 approaches:
 *    - Steps: (the current implementation)
 *        1. Process `dataZoom` based on a full window `noZoomEffMM`.
 *        2. Perform "nice" or "align" scale, where `intervalScaleEnsureValidExtent`-ish may be performed to
 *           expand extent to avoid `extent[0] === extent[1]`.
 *        3. Calculate linear supplement of containShape based on the final result.
 *      Cons:
 *        - Abrupt changes occur when zooming away from 0% or 100%.
 *        - Edge shapes are clipped in "dataZoom shadow".
 *    - Steps: (discarded)
 *        1. Calculate linear supplement of containShape based on `noZoomEffMM` and
 *           `intervalScaleEnsureValidExtent`-ish.
 *        2. Process `dataZoom` based on a full window `noZoomEffMM + linearSupplement`.
 *        3. Perform "nice"/"align" scale.
 *      Cons:
 *        - Input `startValue: 0` (in ec option or action) does not corresponds to `0%`, which is unacceptable.
 *        - Not easy to perform `intervalScaleEnsureValidExtent`-ish before "nice"/"align" processing.
 *
 * @see SCALE_EXTENT_CONSTRUCTION for the full processing flow.
 */
public func adoptScaleExtentKindMapping(
    _ axis: Axis,
    _ scale: Scale,
    _ rawExtentResult: ScaleRawExtentResultFinal,
    _ ecModel: GlobalModel
) {

    if !rawExtentResult.ctnShp {
        return
    }

    var linearSupplement: [Double]?
    eachKeyOnAxis(axis) { axisStatKey in
        let handler = axisContainShapeHandlerMap.get(axisStatKey)
        if let handler = handler {
            // This feature can be implemented by either expanding axis extent or scale extent. The choice depends
            // on whether series shape sizes are defined in pixels or data space. For example, scatter series glyph
            // sizes is mainly defined in pixel, while bar series `bandWidth` is mainly determined by given percents
            // of data scale. Since currently scatter does not require this feature, we implement it only on the
            // data scale.
            let singleLinearSupplement = handler(axis, ecModel)
            if let singleLinearSupplement = singleLinearSupplement {
                if linearSupplement == nil { linearSupplement = [0, 0] }
                EChartsKit.model.unionExtentStartFromNumber(&linearSupplement!, singleLinearSupplement[0])
                EChartsKit.model.unionExtentEndFromNumber(&linearSupplement!, singleLinearSupplement[1])

                // Consider the consistency of `onZero` behavior (not varying by series data; otherwise error-prone
                // to users), if any `containShape` really performed on this axis, discourage `onZero`.
                axisHelper.discourageOnAxisZero(axis)
            }
        }
    }

    guard let linearSupplement = linearSupplement else {
        return
    }

    let scaleExtent = scale.getExtent()

    if helper.isOrdinalScale(scale) {
        if !axis.onBand {
            // - Zooming on `OrdinalScale` auto "snaps" to integer ticks, which causes edge shapes to
            //   always overlap and be clipped at the boundaries. Therefore we always supplement it with
            //   half bandWith to avoid that overlapping.
            // - `linearSupplement` is typically [-0.5, 0.5] in this case. `linearSupplement` exists only
            //   if any series call `registerAxisContainShapeHandler`.
            // - PENDING: For historical reason, `onBand: true` has another implementation to handle
            //   this case. Merge them to this?
            scale.setExtent2(
                SCALE_EXTENT_KIND_MAPPING,
                number.mathMin(scaleExtent[0], scaleExtent[0] + linearSupplement[0]),
                number.mathMax(scaleExtent[1], scaleExtent[1] + linearSupplement[1])
            )
        }
    }
    else {
        // For other cases, `SCALE_EXTENT_KIND_MAPPING` is only used on the full window of `dataZoom`,
        // where the visual result is more intuitive when zooming: when dataZoom is applied and its ends
        // (i.e., `zoomMM`) do not reach 0% or 100%, the axis ends should exactly respect to the dataZoom
        // ends, and shapes are clipped if overflowing.
        var scaleExtentExpanded = scaleExtent   // scaleExtent.slice()

        if !rawExtentResult.zoomFixMM[0] {
            scaleExtentExpanded[0] = number.mathMin(
                scaleExtentExpanded[0],
                scale.transformOut(scale.transformIn(scaleExtentExpanded[0], nil) + linearSupplement[0], nil)
            )
        }
        if !rawExtentResult.zoomFixMM[1] {
            scaleExtentExpanded[1] = number.mathMax(
                scaleExtentExpanded[1],
                scale.transformOut(scale.transformIn(scaleExtentExpanded[1], nil) + linearSupplement[1], nil)
            )
        }

        if scaleExtentExpanded[0] < scaleExtent[0] || scaleExtentExpanded[1] > scaleExtent[1] {
            scale.setExtent2(SCALE_EXTENT_KIND_MAPPING, scaleExtentExpanded[0], scaleExtentExpanded[1])
        }
    }
    // NOTE: since currently `SCALE_EXTENT_KIND_MAPPING` is never required to be displayed, we
    // do not need to find a proper precision for that. But if it is required in the future, We
    // can use `getAcceptableTickPrecision` to find a proper precision.
}
