// Ported from echarts/src/coord/axisNiceTicks.ts — keep in sync with upstream
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
//   import { assert, noop } from 'zrender/src/core/util';        -> ZRenderKit `util` (`util.assert`, `util.noop`).
//   import { ensureValidSplitNumber, getIntervalPrecision, intervalScaleEnsureValidExtent,
//            isIntervalScale, isLogScale, isTimeScale } from '../scale/helper';
//       -> sibling helper.swift caseless enum `helper` (`helper.ensureValidSplitNumber`, etc.).
//   import IntervalScale, { IntervalScaleConfig } from '../scale/Interval';
//       -> sibling Interval.swift (`IntervalScale`, `IntervalScaleConfig`).
//   import { mathCeil, mathFloor, mathMax, nice, quantity, round } from '../util/number';
//       -> sibling number.swift caseless enum `number` (`number.mathCeil`, `number.nice`, etc.).
//   import type { AxisBaseModel } from './AxisBaseModel';         -> sibling AxisBaseModel.swift (`AxisBaseModel`).
//   import type { AxisScaleType, NumericAxisBaseOptionCommon } from './axisCommonTypes';
//       -> sibling axisCommonTypes.swift (`AxisScaleType` = String alias). PORT-NOTE: `NumericAxisBaseOptionCommon`
//          (the generic option bag) is dropped per CONVENTIONS §2 — the option tree is the dynamic
//          `Any` bag on Model, read via `model.get(...)`.
//   import { updateIntervalOrLogScaleForNiceOrAligned } from './axisHelper';
//       -> sibling axisHelper.swift (same tier, other agent this phase). PORT-NOTE: referenced as a
//          caseless enum namespace `axisHelper` per CONVENTIONS §2 (pure free-function module); if the
//          sibling exposes it as a bare free function instead, drop the `axisHelper.` qualifier.
//   import { calcNiceForTimeScale } from '../scale/Time';         -> sibling TimeScale.swift, exposed as a
//          bare free function `calcNiceForTimeScale(_:_:)`.
//   import type LogScale from '../scale/Log';                     -> sibling LogScale.swift (`LogScale`).
//   import Scale from '../scale/Scale';                           -> sibling Scale.swift (`Scale`).
//   import { adoptScaleExtentKindMapping, adoptScaleRawExtentInfoAndPrepare, ScaleExtentFixMinMax,
//            ScaleRawExtentResultFinal } from './scaleRawExtentInfo';
//       -> sibling scaleRawExtentInfo.swift (same tier, other agent this phase). PORT-NOTE: the `adopt*`
//          functions are referenced as bare free functions (scaleRawExtentInfo is not a pure
//          free-function module — it carries the ScaleRawExtentInfo class — so it mirrors the
//          scaleMapper/break free-function deviation). `ScaleExtentFixMinMax` / `ScaleRawExtentResultFinal`
//          are the types that module owns.
//   import { getScaleLinearSpanEffective } from '../scale/scaleMapper';
//       -> sibling scaleMapper.swift, exposed as a bare free function `getScaleLinearSpanEffective(_:)`.
//   import { NullUndefined } from '../util/types';                -> collapses to Optional (CONVENTIONS §6).
//   import type GlobalModel from '../model/Global';               -> sibling Global.swift (`GlobalModel`).
//   import type Axis from './Axis';                               -> coord/Axis.swift (ported; `scaleCalcNice`'s
//          `axisLike` uses the narrow ScaleCalcNiceAxisLike struct below rather than the full Axis).


// ------ START: LinearIntervalScaleStub Nice ------

// upstream: scale param is `(IntervalScale | LogScale) & Scale`. Swift has no intersection/union types,
//   so it is typed `Scale` (matching `ScaleCalcNiceMethod`) and downcast to the concrete kind below.
func calcNiceForIntervalOrLogScale(
    _ scale: Scale,
    _ opt: ScaleCalcNiceMethodOpt
) {
    // [CAVEAT]: If updating this impl, need to sync it to `axisAlignTicks.ts`.

    let isTargetLogScale = helper.isLogScale(scale)
    let intervalStub: IntervalScale = isTargetLogScale ? (scale as! LogScale).intervalStub : (scale as! IntervalScale)

    let fixMinMax = opt.fixMinMax ?? []
    let oldOutermostExtent: [Double]? = isTargetLogScale ? scale.getExtent() : nil
    let oldIntervalExtent = intervalStub.getExtent()

    var newIntervalExtent = helper.intervalScaleEnsureValidExtent(oldIntervalExtent, fixMinMax, opt.rawExtentResult)

    intervalStub.setExtent(newIntervalExtent[0], newIntervalExtent[1])
    newIntervalExtent = intervalStub.getExtent()

    var config = isTargetLogScale
        ? logScaleCalcNiceTicks(intervalStub, opt)
        : intervalScaleCalcNiceTicks(intervalStub, opt)
    let autoIntervalPrecision = config.intervalPrecision
    let autoInterval = config.interval

    // When auto calculated interval is not preferable, users are allowed to explicity specify
    // `interval`, `min`, `max` to customize the axis. A typical case is, in angle axis with angle
    // 0 - 360, where the internally calculated interval is not 60-based.
    // NOTICE:
    //  - In `xxxAxis.type: 'log'`, ec option `xxxAxis.interval` requires a logarithm-applied
    //    value rather than a value in the raw scale.
    //  - Follow the historical behavior:
    //    - even `interval` is specified, the scale extent is still expanded based on the auto-calculated
    //      interval.
    //    - No validation to the specified `interval`.
    let userInterval = opt.userInterval
    if userInterval != nil {
        config.interval = userInterval!
        config.intervalPrecision = helper.getIntervalPrecision(userInterval!)
    }

    if !fixMinMax[0] {
        newIntervalExtent[0] = number.round(
            number.mathFloor(newIntervalExtent[0] / autoInterval) * autoInterval, autoIntervalPrecision!
        )
    }
    if !fixMinMax[1] {
        newIntervalExtent[1] = number.round(
            number.mathCeil(newIntervalExtent[1] / autoInterval) * autoInterval, autoIntervalPrecision!
        )
    }
    if userInterval != nil { // Historical behavior.
        config.niceExtent = newIntervalExtent   // newIntervalExtent.slice() (Swift arrays are value types)
    }

    // PORT-NOTE: `axisHelper.updateIntervalOrLogScaleForNiceOrAligned` — enum-namespace assumption; see import note.
    axisHelper.updateIntervalOrLogScaleForNiceOrAligned(
        scale,
        fixMinMax,
        oldIntervalExtent,
        newIntervalExtent,
        oldOutermostExtent,
        config
    )
}

// ------ END: LinearIntervalScaleStub Nice ------


// ------ START: IntervalScale Nice ------

// upstream opt: Pick<ScaleCalcNiceMethodOpt, 'splitNumber' | 'minInterval' | 'maxInterval' | 'userInterval'>.
//   Swift has no `Pick`; the full `ScaleCalcNiceMethodOpt` is passed (only those fields are read).
func intervalScaleCalcNiceTicks(
    _ scale: IntervalScale,
    _ opt: ScaleCalcNiceMethodOpt
) -> IntervalScaleConfig {
    let splitNumber = helper.ensureValidSplitNumber(opt.splitNumber, 5)
    // Use the span in the innermost linear space to calculate nice ticks.
    let span = getScaleLinearSpanEffective(scale)

    if __DEV__ {
        util.assert(span.isFinite && span > 0) // It should have been ensured by `intervalScaleEnsureValidExtent`.
    }

    let minInterval = opt.minInterval
    let maxInterval = opt.maxInterval

    var interval = number.nice(span / splitNumber, .round)
    if let minInterval = minInterval, interval < minInterval {
        interval = minInterval
    }
    if let maxInterval = maxInterval, interval > maxInterval {
        interval = maxInterval
    }

    let intervalPrecision = helper.getIntervalPrecision(interval)
    let extent = scale.getExtent()
    // By design, the `niceExtent` is inside the original extent
    let niceExtent = [
        number.round(number.mathCeil(extent[0] / interval) * interval, intervalPrecision),
        number.round(number.mathFloor(extent[1] / interval) * interval, intervalPrecision)
    ]

    return IntervalScaleConfig(interval: interval, intervalPrecision: intervalPrecision, niceExtent: niceExtent)
}

// ------ END: IntervalScale Nice ------


// ------ START: LogScale Nice ------

// upstream opt: Pick<ScaleCalcNiceMethodOpt, 'splitNumber' | 'minInterval' | 'maxInterval' | 'userInterval'>.
func logScaleCalcNiceTicks(
    _ intervalStub: IntervalScale,
    _ opt: ScaleCalcNiceMethodOpt
) -> IntervalScaleConfig {
    // [CAVEAT]: If updating this impl, need to sync it to `axisAlignTicks.ts`.

    let splitNumber = helper.ensureValidSplitNumber(opt.splitNumber, 10)
    // Find nice ticks in the "logarithmic space". Notice that "logarithmic space" is a middle space
    // rather than the innermost linear space when axis breaks exist.
    let intervalExtent = intervalStub.getExtent()
    // But use the span in the innermost linear space to calculate nice ticks.
    let span = getScaleLinearSpanEffective(intervalStub)

    if __DEV__ {
        util.assert(span.isFinite && span > 0) // It should be ensured by `intervalScaleEnsureValidExtent`.
    }

    // Interval should be integer
    var interval = number.mathMax(number.quantity(span), 1)
    let err = splitNumber / span * interval
    // Filter ticks to get closer to the desired count.
    if err <= 0.5 {
        // TODO: support other bases other than 10?
        interval *= 10
    }

    let intervalPrecision = helper.getIntervalPrecision(interval)
    // For LogScale, we use a `niceExtent` in the "logarithmic space" rather than
    // the original "pow space", because it is used in `intervalStub.getTicks()` thereafter.
    let niceExtent: [Double] = [
        number.round(number.mathCeil(intervalExtent[0] / interval) * interval, intervalPrecision),
        number.round(number.mathFloor(intervalExtent[1] / interval) * interval, intervalPrecision)
    ]

    return IntervalScaleConfig(interval: interval, intervalPrecision: intervalPrecision, niceExtent: niceExtent)
}

// ------ END: LogScale Nice ------


// ------ START: scaleCalcNice Entry ------

// upstream: export type ScaleCalcNiceMethod = (scale: Scale, opt: ScaleCalcNiceMethodOpt) => void;
public typealias ScaleCalcNiceMethod = (Scale, ScaleCalcNiceMethodOpt) -> Void

// upstream: type ScaleCalcNiceMethodOpt = { splitNumber?; minInterval?; maxInterval?; userInterval?;
//                                           userIntervalUseLegacy?; fixMinMax?; rawExtentResult?; };
public struct ScaleCalcNiceMethodOpt {
    public var splitNumber: Double?
    public var minInterval: Double?
    public var maxInterval: Double?
    public var userInterval: Double?
    public var userIntervalUseLegacy: Bool?
    public var fixMinMax: ScaleExtentFixMinMax?
    public var rawExtentResult: ScaleRawExtentResultFinal?
    public init(
        splitNumber: Double? = nil,
        minInterval: Double? = nil,
        maxInterval: Double? = nil,
        userInterval: Double? = nil,
        userIntervalUseLegacy: Bool? = nil,
        fixMinMax: ScaleExtentFixMinMax? = nil,
        rawExtentResult: ScaleRawExtentResultFinal? = nil
    ) {
        self.splitNumber = splitNumber
        self.minInterval = minInterval
        self.maxInterval = maxInterval
        self.userInterval = userInterval
        self.userIntervalUseLegacy = userIntervalUseLegacy
        self.fixMinMax = fixMinMax
        self.rawExtentResult = rawExtentResult
    }
}

// upstream: the inline object type `{ scale: Scale, model: AxisBaseModel }` of `scaleCalcNice`'s
//   `axisLike` param. Modeled as a small struct so call sites keep `axisLike.scale` / `axisLike.model`.
//   PORT-NOTE: upstream passes an `Axis` here (Axis has `scale`/`model`); modeled as this narrow struct
//   to keep call sites `axisLike.scale` / `axisLike.model`.
public struct ScaleCalcNiceAxisLike {
    public var scale: Scale
    public var model: AxisBaseModel
    public init(scale: Scale, model: AxisBaseModel) {
        self.scale = scale
        self.model = model
    }
}

/**
 * NOTE: See the summary of the process of extent determination in the comment of `scaleMapper.setExtent`.
 *
 * Calculate a "nice" extent and "nice" ticks configs based on the current scale extent and ec options.
 * scale extent will be modified, and config may be set to the scale.
 *
 * @see SCALE_EXTENT_CONSTRUCTION for the full processing flow.
 */
public func scaleCalcNice(
    _ axisLike: ScaleCalcNiceAxisLike
) {
    let scale = axisLike.scale
    // upstream: const model = axisLike.model as AxisBaseModel<NumericAxisBaseOptionCommon>;
    let model = axisLike.model

    let axis = model.axis
    let ecModel = model.ecModel
    if __DEV__ {
        // upstream: assert(axis && ecModel). PORT-NOTE: `model.axis` is a non-optional `Any` in this
        //   port (see AxisBaseModel.swift), so only `ecModel` truthiness is asserted here.
        util.assert(ecModel != nil)
    }

    // `model.axis` is `Any` on AxisBaseModel; narrow to the real `Axis` for `scaleCalcNice2`.
    scaleCalcNice2(scale, model, axis as? Axis, ecModel, nil)
}

/**
 * @see SCALE_EXTENT_CONSTRUCTION for the full processing flow.
 */
public func scaleCalcNice2(
    _ scale: Scale,
    _ model: AxisBaseModel,
    // Some call from external source, such as echarts-gl, may have no `axis` and `ecModel`,
    // but has `externalDataExtent`.
    // upstream: axis: Axis | NullUndefined.
    _ axis: Axis?,
    _ ecModel: GlobalModel?,
    _ externalDataExtent: [Double]?
) {

    // PORT-NOTE: `adoptScaleRawExtentInfoAndPrepare` — bare free function in sibling scaleRawExtentInfo.swift.
    let rawExtentResult = adoptScaleRawExtentInfoAndPrepare(scale, model, ecModel, axis, externalDataExtent)

    let isIntervalOrTime = helper.isIntervalScale(scale) || helper.isTimeScale(scale)
    scaleCalcNiceDirectly(scale, ScaleCalcNiceMethodOpt(
        splitNumber: model.get("splitNumber") as? Double, // Backward compat - not get('xxx', true).
        minInterval: isIntervalOrTime ? model.get("minInterval") as? Double : nil,
        maxInterval: isIntervalOrTime ? model.get("maxInterval") as? Double : nil,
        userInterval: model.get("interval") as? Double, // Backward compat - not get('xxx', true).
        fixMinMax: rawExtentResult.fixMM,
        rawExtentResult: rawExtentResult
    ))

    if let axis = axis, let ecModel = ecModel {
        adoptScaleExtentKindMapping(axis, scale, rawExtentResult, ecModel)
    }

    if __DEV__ {
        scale.freeze()
    }
}

public func scaleCalcNiceDirectly(
    _ scale: Scale,
    _ opt: ScaleCalcNiceMethodOpt
) {
    // upstream indexes a total `Record<AxisScaleType, ...>`; the Swift dictionary lookup is forced.
    scaleCalcNiceMethods[scale.type]!(scale, opt)
}

let scaleCalcNiceMethods: [AxisScaleType: ScaleCalcNiceMethod] = [
    "interval": calcNiceForIntervalOrLogScale,
    "log": calcNiceForIntervalOrLogScale,
    // `calcNiceForTimeScale` takes a concrete `TimeScale` (TS bivariance) — wrapped with a downcast.
    "time": { scale, opt in calcNiceForTimeScale(scale as! TimeScale, opt) },
    // upstream: ordinal: noop. `noop` takes no args here; wrapped to fit `ScaleCalcNiceMethod`.
    "ordinal": { _, _ in util.noop() },
]

// ------ END: scaleCalcNice Entry ------
