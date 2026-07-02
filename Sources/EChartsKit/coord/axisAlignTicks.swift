// Ported from echarts/src/coord/axisAlignTicks.ts — keep in sync with upstream
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
//   import {
//       getAcceptableTickPrecision, isNullableNumberFinite,
//       mathAbs, mathCeil, mathFloor, mathMax, mathRound, nice, NICE_MODE_MIN, quantity, round
//   } from '../util/number';
//       -> sibling util/number.swift caseless enum `number` (`number.getAcceptableTickPrecision`,
//          `number.isNullableNumberFinite`, `number.mathAbs`, `number.mathCeil`, `number.mathFloor`,
//          `number.mathMax`, `number.mathRound`, `number.nice`, `number.NICE_MODE_MIN`,
//          `number.quantity`, `number.round`).
//   import IntervalScale from '../scale/Interval';   -> sibling scale/Interval.swift (`IntervalScale`)
//   import LogScale from '../scale/Log';             -> sibling scale/LogScale.swift (`LogScale`)
//   import type Scale from '../scale/Scale';         -> sibling scale/Scale.swift (`Scale`)
//   import { updateIntervalOrLogScaleForNiceOrAligned } from './axisHelper';
//       -> sibling coord/axisHelper.swift caseless enum `axisHelper` (same tier, this phase).
//   import { warn } from '../util/log';              -> sibling util/log.swift (`log.warn`).
//   import {
//       increaseInterval, isLogScale, getIntervalPrecision, intervalScaleEnsureValidExtent,
//   } from '../scale/helper';
//       -> sibling scale/helper.swift caseless enum `helper` (`helper.increaseInterval`,
//          `helper.isLogScale`, `helper.getIntervalPrecision`, `helper.intervalScaleEnsureValidExtent`).
//   import { assert } from 'zrender/src/core/util';  -> ZRenderKit `util.assert`.
//   import { adoptScaleRawExtentInfoAndPrepare } from './scaleRawExtentInfo';
//       -> sibling coord/scaleRawExtentInfo.swift top-level free function (real impl, this phase).
//   import { hasBreaks } from '../scale/break';      -> sibling scale/break.swift top-level `hasBreaks`.
//   import type Axis from './Axis';                  -> shared `Axis` placeholder in coord/axisStatistics.swift.
//
// NOTE: upstream is a named-export free-function module (`import { scaleCalcAlign } from './axisAlignTicks'`),
//   so it is ported as a top-level free function (CONVENTIONS §2), matching the sibling coord modules
//   (e.g. axisStatistics.swift). Call sites stay identical: `scaleCalcAlign(...)`.


/**
 * NOTE: See the summary of the process of extent determination in the comment of `scaleMapper.setExtent`.
 *
 * @see SCALE_EXTENT_CONSTRUCTION for the full processing flow.
 */
// upstream: alignToScale: IntervalScale | LogScale. Ported as the common base `Scale` (both are
//   `Scale` subclasses); the union is narrowed by `as!` casts below, exactly where upstream reads
//   subtype-only members (`.intervalStub`). (CONVENTIONS §2)
public func scaleCalcAlign(
    _ targetAxis: Axis,
    _ alignToScale: Scale
) {

    // upstream: targetAxis.scale as (IntervalScale | LogScale) & Scale
    let targetScale = targetAxis.scale
    let targetAxisModel = targetAxis.model!
    if __DEV__ {
        // upstream: assert(targetScale && targetAxisModel && ...). The `targetScale`/`targetAxisModel`
        // truthy guards drop: both are non-optional references in Swift (CONVENTIONS §6).
        util.assert(
            (targetScale is IntervalScale || targetScale is LogScale)
            && (alignToScale is IntervalScale || alignToScale is LogScale)
        )
    }
    let targetExtentInfo = adoptScaleRawExtentInfoAndPrepare(
        targetScale, targetAxisModel, targetAxisModel.ecModel, targetAxis, nil
    )

    // FIXME:
    //  (1) Axis inverse is not considered yet.
    //  (2) `SCALE_EXTENT_KIND_MAPPING` is not considered yet.

    let isTargetLogScale = helper.isLogScale(targetScale)
    let alignToScaleLinear: IntervalScale = helper.isLogScale(alignToScale)
        ? (alignToScale as! LogScale).intervalStub
        : (alignToScale as! IntervalScale)
    let targetIntervalStub: IntervalScale = isTargetLogScale
        ? (targetScale as! LogScale).intervalStub
        : (targetScale as! IntervalScale)

    // upstream: (targetScale as LogScale).base — only read on the `isTargetLogScale` path below.
    let targetLogScaleBase = (targetScale as? LogScale)?.base ?? Double.nan
    let alignToTicks = alignToScaleLinear.getTicks()
    // upstream: alignToScaleLinear.getTicks({expandToNicedExtent: true})
    var expandOpt = ScaleGetTicksOpt()   // ScaleGetTicksOpt has no memberwise init; set field then pass.
    expandOpt.expandToNicedExtent = true
    let alignToExpNiceTicks = alignToScaleLinear.getTicks(expandOpt)
    let alignToSegCount = alignToTicks.count - 1

    if __DEV__ {
        // This is guards for future changes of `Interval#getTicks`.
        util.assert(!hasBreaks(alignToScale) && !hasBreaks(targetScale))
        util.assert(alignToSegCount > 0) // Ticks length >= 2 even on a blank scale.
        util.assert(alignToExpNiceTicks.count == alignToTicks.count)
        util.assert(alignToTicks[0].value <= alignToTicks[alignToSegCount].value)
        util.assert(
            alignToExpNiceTicks[0].value <= alignToTicks[0].value
            && alignToTicks[alignToSegCount].value <= alignToExpNiceTicks[alignToSegCount].value
        )
        if alignToSegCount >= 2 {
            util.assert(alignToExpNiceTicks[1].value == alignToTicks[1].value)
            util.assert(alignToExpNiceTicks[alignToSegCount - 1].value == alignToTicks[alignToSegCount - 1].value)
        }
    }

    // The Current strategy: Find a proper interval and an extent for the target scale to derive ticks
    // matching exactly to ticks of `alignTo` scale.

    // Adjust min, max based on the extent of alignTo. When min or max is set in alignTo scale
    var t0: Double = 0 // diff ratio on min not-nice segment. 0 <= t0 < 1
    var t1: Double = 0 // diff ratio on max not-nice segment. 0 <= t1 < 1
    var alignToNiceSegCount: Double = 0 // >= 1
    // Consider ticks of `alignTo`, only these cases below may occur:
    if alignToSegCount == 1 {
        // `alignToTicks` is like:
        //  |--|
        // In this case, we make the corresponding 2 target ticks "nice".
        t0 = 0
        t1 = 0   // upstream: t0 = t1 = 0
        alignToNiceSegCount = 1
    }
    else if alignToSegCount == 2 {
        // `alignToTicks` is like:
        //  |-|-----| or
        //  |-----|-| or
        //  |-----|-----|
        // Notices that nice ticks do not necessarily exist in this case.
        // In this case, we choose the larger segment as the "nice segment" and
        // the corresponding target ticks are made "nice".
        let interval0 = number.mathAbs(alignToTicks[0].value - alignToTicks[1].value)
        let interval1 = number.mathAbs(alignToTicks[1].value - alignToTicks[2].value)
        t0 = 0
        t1 = 0   // upstream: t0 = t1 = 0
        if interval0 == interval1 {
            alignToNiceSegCount = 2
        }
        else {
            alignToNiceSegCount = 1
            if interval0 < interval1 {
                t0 = interval0 / interval1
            }
            else {
                t1 = interval1 / interval0
            }
        }
    }
    else { // alignToSegCount >= 3
        // `alignToTicks` is like:
        //  |-|-----|-----|-| or
        //  |-----|-----|-| or
        //  |-|-----|-----| or ...
        // At least one nice segment is present, and not-nice segments are only present on
        // the start and/or the end.
        // In this case, ticks corresponding to nice segments are made "nice".
        let alignToInterval = alignToScaleLinear.getConfig().interval
        t0 = (
            1 - (alignToTicks[0].value - alignToExpNiceTicks[0].value) / alignToInterval
        ).truncatingRemainder(dividingBy: 1)
        t1 = (
            1 - (alignToExpNiceTicks[alignToSegCount].value - alignToTicks[alignToSegCount].value) / alignToInterval
        ).truncatingRemainder(dividingBy: 1)
        // `t0 ? 1 : 0` / `t1 ? 1 : 0` — JS truthiness on a finite ratio in [0, 1); replicated as `!= 0`
        // (NaN is not reachable here since `alignToInterval > 0`).
        alignToNiceSegCount = Double(alignToSegCount) - (t0 != 0 ? 1 : 0) - (t1 != 0 ? 1 : 0)
    }

    if __DEV__ {
        util.assert(alignToNiceSegCount >= 1)
    }

    // NOTE:
    //  Consider a case:
    //    dataZoom controls all Y axes;
    //    dataZoom end is 90% (maxFixed: true, dataZoomFixMinMax[0]: true);
    //    but dataZoom start is 0% (minFixed: false, dataZoomFixMinMax[1]: false);
    //  In this case,
    //    - `Interval#calcNiceTicks` only uses `targetExtentInfo.max` as the upper bound, but expand the
    //      lower bound to a "nice" tick and can get an acceptable result.
    //    - `scaleCalcAlign` has to use both `targetExtentInfo.min/max` as the bounds without any expansion,
    //      otherwise the lower bound may become negative unexpectedly, especially for all positive series data.
    let dataZoomFixMinMax = targetExtentInfo.zoomFixMM
    let hasDataZoomFixMinMax = dataZoomFixMinMax[0] || dataZoomFixMinMax[1]
    let targetMinMaxFixed = [
        targetExtentInfo.fixMM[0] || hasDataZoomFixMinMax,
        targetExtentInfo.fixMM[1] || hasDataZoomFixMinMax
    ]
    // MEMO: When only `xxxAxis.min` or `xxxAxis.max` is fixed,
    //  - Even a "nice" interval can be calculated, ticks accumulated based on `min`/`max` can be "nice" only if
    //    `min` or `max` is a "nice" number.
    //  - Generating a "nice" interval may cause the extent have both positive and negative ticks, which may be
    //    not preferable for all positive (very common) or all negative series data. But it can be simply resolved
    //    by specifying `xxxAxis.min: 0`/`xxxAxis.max: 0`, so we do not specially handle this case here.
    //  Therefore, we prioritize generating "nice" interval over preventing from crossing zero.
    //  e.g., if series data are all positive and the max data is `11739`,
    //      If setting `yAxis.max: 'dataMax'`, ticks may be like:
    //          `11739, 8739, 5739, 2739, -1739` (not "nice" enough)
    //      If setting `yAxis.max: 'dataMax', yAxis.min: 0`, ticks may be like:
    //          `11739, 8805, 5870, 2935, 0` (not "nice" enough but may be acceptable)
    //      If setting `yAxis.max: 12000, yAxis.min: 0`, ticks may be like:
    //          `12000, 9000, 6000, 3000, 0` ("nice")

    let targetOldOutermostExtent = targetScale.getExtent()
    let targetOldIntervalExtent = targetIntervalStub.getExtent()
    let targetExtent = helper.intervalScaleEnsureValidExtent(targetOldIntervalExtent, targetMinMaxFixed)

    // upstream declares these uninitialized (`let min: number;` …). Seeded to `NaN` so that any
    // read-before-assign mirrors JS `undefined` arithmetic (→ NaN); required in Swift because the
    // nested functions below capture them (definite-initialization + capture rules, CONVENTIONS §7).
    var min: Double = .nan
    var max: Double = .nan
    var interval: Double = .nan
    var intervalPrecision: Double = .nan
    var maxNice: Double = .nan
    var minNice: Double = .nan

    func loopIncreaseInterval(_ cb: () -> Bool) {
        // Typically this loop runs less than 5 times. But we still
        // use a fail-safe for future changes.
        let LOOP_MAX = 50
        var loopGuard = 0
        while loopGuard < LOOP_MAX {
            if cb() {
                break
            }
            interval = isTargetLogScale
                // TODO: `mathMax(base, 2)` is a guardcode to avoid infinite loop,
                // but probably it should be guranteed by `LogScale` itself.
                ? interval * number.mathMax(targetLogScaleBase, 2)
                : helper.increaseInterval(interval)
            intervalPrecision = helper.getIntervalPrecision(interval)
            loopGuard += 1
        }
        if __DEV__ {
            if loopGuard >= LOOP_MAX {
                log.warn("incorrect impl in `scaleCalcAlign`.")
            }
        }
    }

    func updateMinFromMinNice() {
        min = number.round(minNice - interval * t0, intervalPrecision)
    }
    func updateMaxFromMaxNice() {
        max = number.round(maxNice + interval * t1, intervalPrecision)
    }
    func updateMinNiceFromMinT0Interval() {
        minNice = (t0 != 0) ? number.round(min + interval * t0, intervalPrecision) : min
    }
    func updateMaxNiceFromMaxT1Interval() {
        maxNice = (t1 != 0) ? number.round(max - interval * t1, intervalPrecision) : max
    }

    // NOTE: The new calculated `min`/`max` must NOT shrink the original extent; otherwise some series
    // data may be outside of the extent. They can expand the original extent slightly to align with
    // ticks of `alignTo`. In this case, more blank space is added but visually fine.

    if targetMinMaxFixed[0] && targetMinMaxFixed[1] {
        // Both `min` and `max` are specified (via dataZoom or ec option; consider both Cartesian, radar and
        // other possible axes). In this case, "nice" ticks can hardly be calculated, but reasonable ticks should
        // still be calculated whenever possible, especially `intervalPrecision` should be tuned for better
        // appearance and lower cumulative error.

        min = targetExtent[0]
        max = targetExtent[1]
        interval = (max - min) / (alignToNiceSegCount + t0 + t1)
        // Typically axis pixel extent is ready here. See `create` in `Grid.ts`.
        let axisPxExtent = targetAxis.getExtent()
        // NOTICE: this pxSpan may be not accurate yet due to "outerBounds" logic, but acceptable so far.
        let pxSpan = number.mathAbs(axisPxExtent[1] - axisPxExtent[0])
        // We imperically choose `pxDiffAcceptable` as `0.5 / alignToNiceSegCount` for reduce cumulative
        // error, otherwise a discernible misalign (> 1px) may occur.
        // PENDING: We do not find a acceptable precision for LogScale here.
        //  Theoretically it can be addressed but introduce more complexity. Is it necessary?
        intervalPrecision = number.getAcceptableTickPrecision([max, min], pxSpan, 0.5 / alignToNiceSegCount)
        updateMinNiceFromMinT0Interval()
        updateMaxNiceFromMaxT1Interval()
        if number.isNullableNumberFinite(intervalPrecision) {
            interval = number.round(interval, intervalPrecision)
        }
    }
    else {
        // Make a minimal enough `interval`, increase it later.
        // It is a similar logic as `IntervalScale#calcNiceTicks` and `LogScale#calcNiceTicks`.
        // Axis break is not supported, which is guranteed by the caller of this function.
        let targetSpan = targetExtent[1] - targetExtent[0]
        interval = isTargetLogScale
            ? number.mathMax(number.quantity(targetSpan), 1)
            : number.nice(targetSpan / alignToNiceSegCount, number.NiceMode.min)   // upstream: nice(..., NICE_MODE_MIN)
        intervalPrecision = helper.getIntervalPrecision(interval)

        if targetMinMaxFixed[0] {
            min = targetExtent[0]
            loopIncreaseInterval {
                updateMinNiceFromMinT0Interval()
                maxNice = number.round(minNice + interval * alignToNiceSegCount, intervalPrecision)
                updateMaxFromMaxNice()
                if max >= targetExtent[1] {
                    return true
                }
                return false
            }
        }
        else if targetMinMaxFixed[1] {
            max = targetExtent[1]
            loopIncreaseInterval {
                updateMaxNiceFromMaxT1Interval()
                minNice = number.round(maxNice - interval * alignToNiceSegCount, intervalPrecision)
                updateMinFromMinNice()
                if min <= targetExtent[0] {
                    return true
                }
                return false
            }
        }
        else {
            loopIncreaseInterval {
                minNice = number.round(number.mathCeil(targetExtent[0] / interval) * interval, intervalPrecision)
                maxNice = number.round(number.mathFloor(targetExtent[1] / interval) * interval, intervalPrecision)
                // NOTE:
                //  - `maxNice - minNice >= -interval` here.
                //  - While `interval` increases, `currIntervalCount` decreases, minimum `-1`.
                let currIntervalCount = number.mathRound((maxNice - minNice) / interval)
                if currIntervalCount <= alignToNiceSegCount {
                    let moreCount = alignToNiceSegCount - currIntervalCount
                    // Consider cases that negative tick do not make sense (or vice versa), users can simply
                    // specify `xxxAxis.min/max: 0` to avoid negative. But we still automatically handle it
                    // for some common cases whenever possible:
                    //  - When ec option is `xxxAxis.scale: false` (the default), it is usually unexpected if
                    //    negative (or positive) ticks are introduced.
                    //  - In LogScale, series data are usually either all > 1 or all < 1, rather than both,
                    //    that is, logarithm result is typically either all positive or all negative.
                    var moreCountPair: [Double]
                    let mayEnhanceZero = targetExtentInfo.incl0 || isTargetLogScale
                    // `bounds < 0` or `bounds > 0` may require more complex handling, so we only auto handle
                    // `bounds === 0`.
                    if mayEnhanceZero && targetExtent[0] == 0 {
                        // 0 has been included in extent and all positive.
                        moreCountPair = [0, moreCount]
                    }
                    else if mayEnhanceZero && targetExtent[1] == 0 {
                        // 0 has been included in extent and all negative.
                        moreCountPair = [moreCount, 0]
                    }
                    else {
                        // Try to center ticks in axis space whenever possible, which is especially preferable
                        // in `LogScale`.
                        let lessHalfCount = number.mathFloor(moreCount / 2)
                        moreCountPair = moreCount.truncatingRemainder(dividingBy: 2) == 0 ? [lessHalfCount, lessHalfCount]
                            : (min + max) < (targetExtent[0] + targetExtent[1]) ? [lessHalfCount, lessHalfCount + 1]
                            : [lessHalfCount + 1, lessHalfCount]
                    }
                    minNice = number.round(minNice - interval * moreCountPair[0], intervalPrecision)
                    maxNice = number.round(maxNice + interval * moreCountPair[1], intervalPrecision)
                    updateMinFromMinNice()
                    updateMaxFromMaxNice()
                    if min <= targetExtent[0] && max >= targetExtent[1] {
                        return true
                    }
                }
                return false
            }
        }
    }

    axisHelper.updateIntervalOrLogScaleForNiceOrAligned(
        targetScale,
        targetMinMaxFixed,
        targetOldIntervalExtent,
        [min, max],
        targetOldOutermostExtent,
        IntervalScaleConfig(
            // NOTE: Even in LogScale, `interval` should not be in log space.
            interval: interval,
            intervalPrecision: intervalPrecision,
            // Force ticks count, otherwise cumulative error may cause more unexpected ticks to be generated.
            // Though the overlapping tick labels may be auto-ignored, but probably unexpected, e.g., the min
            // tick label is ignored but the secondary min tick label is shown, which is unexpected when
            // `axis.min` is user-specified or dataZoom-specified.
            intervalCount: alignToNiceSegCount,
            niceExtent: [minNice, maxNice]
        )
    )

    if __DEV__ {
        targetScale.freeze()
    }
}
