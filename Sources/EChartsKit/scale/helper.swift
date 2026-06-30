// Ported from echarts/src/scale/helper.ts — keep in sync with upstream
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

// upstream imports:
//   import { getPrecision, round, nice, quantityExponent, mathPow, mathMax, mathRound,
//            mathLog, mathAbs, mathFloor, mathCeil } from '../util/number';
//       -> sibling number.swift caseless enum `number` (qualified `number.*` at use sites).
//   import type IntervalScale from './Interval';   -> placeholder below (PORT-TODO)
//   import type LogScale from './Log';             -> placeholder below (PORT-TODO)
//   import type Scale from './Scale';              -> placeholder below (PORT-TODO)
//   import type TimeScale from './Time';           -> placeholder below (PORT-TODO)
//   import { NullUndefined, ScaleTick } from '../util/types';
//       -> NullUndefined collapses to Optional (CONVENTIONS §6); ScaleTick from sibling types.swift.
//   import type OrdinalScale from './Ordinal';     -> placeholder below (PORT-TODO)
//   import { ScaleExtentFixMinMax, ScaleRawExtentResultFinal } from '../coord/scaleRawExtentInfo';
//       -> placeholders below (PORT-TODO)
//   import { isValidNumberForExtent } from '../util/model';   -> sibling model.swift (`model.*`)
//   import { getScaleExtentForTickUnsafe } from './scaleMapper';   -> placeholder below (PORT-TODO)

// `Scale` (abstract base), `IntervalScale`, `LogScale`, `TimeScale` are imported by upstream only
// for the TS type-predicate return types of `is*Scale` (e.g. `scale is IntervalScale`). Swift cannot
// express type predicates, so those functions return `Bool` (see below) and reference only the real
// `Scale` class from sibling `scale/Scale.swift`; the subtype imports are therefore dropped.

// ============================================================================
// PORT-TODO: FORWARD-REFERENCE PLACEHOLDERS
// Upstream `scale/helper.ts` imports these from sibling files that are being
// ported by other agents this phase but are not yet present. They are declared
// here as minimal placeholders so this file compiles. The agent that ports the
// corresponding source file MUST remove the placeholder here and replace it
// with the real, fully-ported type/API.
// ============================================================================

// './Ordinal' — OrdinalScale: real `final class OrdinalScale` now ported in scale/Ordinal.swift
//   (placeholder removed per the contract above). It exposes `count()` and is a `Scale`, so it
//   satisfies both `ordinalScaleCreateTicks` and the `getScaleExtentForTickUnsafe` placeholder.

// '../coord/scaleRawExtentInfo' — ScaleExtentFixMinMax = boolean[]
public typealias ScaleExtentFixMinMax = [Bool]                              // PORT-TODO: belongs to coord/scaleRawExtentInfo
// '../coord/scaleRawExtentInfo' — ScaleRawExtentResultFinal (only `ctnShp` is read here).
public protocol ScaleRawExtentResultFinal {                                 // PORT-TODO: belongs to coord/scaleRawExtentInfo
    var ctnShp: Bool { get }
}

// './scaleMapper' — getScaleExtentForTickUnsafe(mapper): number[].
// The upstream call site is a bare `getScaleExtentForTickUnsafe(ordinalScale)`. When scaleMapper.swift
// is ported (caseless enum `scaleMapper`), this becomes `scaleMapper.getScaleExtentForTickUnsafe(...)`.
public func getScaleExtentForTickUnsafe(_ mapper: OrdinalScale) -> [Double] {  // PORT-TODO: belongs to scale/scaleMapper
    fatalError("PORT-TODO: scaleMapper.getScaleExtentForTickUnsafe not yet ported")
}


// upstream: type intervalScaleNiceTicksResult = { interval, intervalPrecision, niceTickExtent }.
// upstream is module-private (`type`), but it is the return type of the exported
// `intervalScaleNiceTicks`, so it must be `public` in Swift (access-level constraint).
public struct intervalScaleNiceTicksResult {
    public var interval: Double = 0
    public var intervalPrecision: Double = 0
    public var niceTickExtent: [Double] = [0, 0]   // [number, number]
    public init() {}
}

public struct IntervalScaleGetLabelOpt {
    // If 'auto', use nice precision.
    public var precision: Any?   // upstream: 'auto' | number
    // `true`: returns 1.50 but not 1.5 if precision is 2.
    public var pad: Bool?
    public init() {}
}

// upstream module `scale/helper.ts` (free functions) -> caseless enum namespace `helper`
// (CONVENTIONS §2). Call sites: upstream `isIntervalScale(scale)` -> `helper.isIntervalScale(scale)`.
public enum helper {

    /**
     * See also method `nice` in `src/util/number.ts`.
     */
    // export function isValueNice(val: number) {
    //     const exp10 = Math.pow(10, quantityExponent(Math.abs(val)));
    //     const f = Math.abs(round(val / exp10, 0));
    //     return f === 0
    //         || f === 1
    //         || f === 2
    //         || f === 3
    //         || f === 5;
    // }

    // upstream return type `scale is (LogScale | IntervalScale)` (TS type predicate) -> `Bool`.
    public static func isIntervalOrLogScale(_ scale: Scale) -> Bool {
        return isIntervalScale(scale) || isLogScale(scale)
    }

    // upstream return type `scale is (IntervalScale | TimeScale)` -> `Bool`.
    public static func isIntervalOrTimeScale(_ scale: Scale) -> Bool {
        return isIntervalScale(scale) || isTimeScale(scale)
    }

    // upstream return type `scale is IntervalScale` -> `Bool`.
    public static func isIntervalScale(_ scale: Scale) -> Bool {
        return scale.type == "interval"
    }

    // upstream return type `scale is TimeScale` -> `Bool`.
    public static func isTimeScale(_ scale: Scale) -> Bool {
        return scale.type == "time"
    }

    // upstream return type `scale is LogScale` -> `Bool`.
    public static func isLogScale(_ scale: Scale) -> Bool {
        return scale.type == "log"
    }

    // upstream return type `scale is OrdinalScale` -> `Bool`.
    public static func isOrdinalScale(_ scale: Scale) -> Bool {
        return scale.type == "ordinal"
    }

    /**
     * @param extent Both extent[0] and extent[1] should be valid number.
     *               Should be extent[0] < extent[1].
     * @param splitNumber splitNumber should be >= 1.
     */
    public static func intervalScaleNiceTicks(
        _ extent: [Double],
        _ spanWithBreaks: Double,
        _ splitNumber: Double,
        _ minInterval: Double? = nil,
        _ maxInterval: Double? = nil
    ) -> intervalScaleNiceTicksResult {

        var result = intervalScaleNiceTicksResult()   // {} as intervalScaleNiceTicksResult

        var interval = number.nice(spanWithBreaks / splitNumber, .round)
        result.interval = interval
        if let minInterval = minInterval, interval < minInterval {
            interval = minInterval
            result.interval = interval
        }
        if let maxInterval = maxInterval, interval > maxInterval {
            interval = maxInterval
            result.interval = interval
        }
        let precision = getIntervalPrecision(interval)
        result.intervalPrecision = precision
        // Niced extent inside original extent
        result.niceTickExtent = [
            number.round(number.mathCeil(extent[0] / interval) * interval, precision),
            number.round(number.mathFloor(extent[1] / interval) * interval, precision)
        ]

        return result
    }

    /**
     * The input `niceInterval` should be generated
     * from `nice` method in `src/util/number.ts`, or
     * from `increaseInterval` itself.
     */
    public static func increaseInterval(_ niceInterval: Double) -> Double {
        let exponent = number.quantityExponent(niceInterval)
        // No rounding error in Math.pow(10, integer).
        let exp10 = number.mathPow(10, exponent)
        // Fix IEEE 754 float rounding error
        var f = number.mathRound(niceInterval / exp10)
        if f == 0 {   // if (!f)  — JS falsy (0 / NaN)
            f = 1
        }
        else if f == 2 {
            f = 3
        }
        else if f == 3 {
            f = 5
        }
        else { // f is 1 or 5
            f *= 2
        }
        // Fix IEEE 754 float rounding error
        return number.round(f * exp10, -exponent)
    }

    public static func getIntervalPrecision(_ niceInterval: Double) -> Double {
        // Tow more digital for tick.
        // NOTE: `2` was introduced in commit `af2a2a9f6303081d7c3b52f0a38add07b4c6e0c7`;
        // it works on "nice" interval, but seems not necessarily mathematically required.
        return number.getPrecision(niceInterval) + 2
    }

    /**
     * NOTE:
     *  - If `val` is `NaN`, return `NaN`.
     *  - If `val` is `0`, return `-Infinity`.
     *  - If `val` is negative, return `NaN`.
     *
     * @see {DataStore#getDataExtent} It handles non-positive values for logarithm scale.
     */
    public static func logScaleLogTick(
        _ val: Double,
        _ base: Double
    ) -> Double {
        // NOTE:
        //  - rounding error may happen above, typically expecting `log10(1000)` but actually
        //    getting `2.9999999999999996`, but generally it does not matter since they are not
        //    used to display.
        //  - Consider backward compatibility and other log bases, do not use `Math.log10`.
        return number.mathLog(val) / number.mathLog(base)
    }

    /**
     * Cumulative rounding errors cause the logarithm operation to become non-invertible by simply exponentiation.
     *  - `Math.pow(10, integer)` itself has no rounding error. But,
     *  - If `linearTickVal` is generated internally by `calcNiceTicks`, it may be still "not nice" (not an integer)
     *    when it is `extent[i]`.
     *  - If `linearTickVal` is generated outside (e.g., by `scaleCalcAlign`) and set by `setExtent`,
     *    `logScaleLogTick` may already have introduced rounding errors even for "nice" values.
     * But invertible is required when the original `extent[i]` need to be respected, or "nice" ticks need to be
     * displayed instead of something like `5.999999999999999`, which is addressed in this function.
     * See also `#4158`.
     *
     * [CAUTION]:
     *  Monotonicity may be broken on extent ends - callers must make sure it does not matter.
     */
    public static func logScalePowTick(
        // `tickVal` should be in the linear space.
        _ linearTickVal: Double,
        _ base: Double,
        _ opt: ValueTransformLookupOpt?
    ) -> Double {
        let lookup = opt?.lookup   // opt && opt.lookup
        if let lookup = lookup {
            for i in 0..<lookup.from.count {
                if linearTickVal == lookup.from[i] {
                    return lookup.to[i]
                }
            }
        }
        return number.mathPow(base, linearTickVal)
    }

    /**
     * For `IntervalScale`, convert `rawExtent` to:
     *  - Be no non-finite number.
     *  - Be `extent[0] < extent[1]`- no equal; otherwise, additional handling is required
     *    in "nice" and "align" ticks.
     */
    public static func intervalScaleEnsureValidExtent(
        _ rawExtent: [Double],
        _ fixMinMax: ScaleExtentFixMinMax,
        _ rawExtentResult: ScaleRawExtentResultFinal? = nil
    ) -> [Double] {
        var extent = rawExtent   // rawExtent.slice()

        // PENDING:
        //  This implementation is not rigorous, but has long been in use.

        // If extent start and end are same, expand them
        if extent[0] == extent[1] {
            // If `containShape`, the extent must be evenly distributed to both sides;
            // otherwise, shape (e.g., bars) may be overflow and clipped.
            let containShapeRequired = rawExtentResult != nil && rawExtentResult!.ctnShp

            if extent[0] != 0 {
                // Expand extent
                // Note that extents can be both negative. See #13154
                let expandSize = number.mathAbs(extent[0])
                // In the fowllowing case
                //      Axis has been fixed max 100
                //      Plus data are all 100 and axis extent are [100, 100].
                // Extend to the both side will cause expanded max is larger than fixed max.
                // So only expand to the smaller side.
                if !fixMinMax[1] {
                    extent[1] += expandSize / 2
                    extent[0] -= expandSize / 2
                }
                else {
                    extent[0] -= expandSize / 2
                }
            }
            else {
                if containShapeRequired {
                    extent[0] = -1
                    extent[1] = 1
                }
                else {
                    extent[1] = 1
                }
            }
        }
        // For example, if there are no series data, extent may be `[Infinity, -Infinity]` here.
        if !model.isValidNumberForExtent(extent[0]) || !model.isValidNumberForExtent(extent[1]) {
            extent[0] = 0
            extent[1] = 1
        }
        if extent[1] < extent[0] {
            extent.reverse()
        }

        return extent
    }

    public static func extentDiffers(_ extent1: [Double], _ extent2: [Double]) -> [Bool] {
        return [extent1[0] != extent2[0], extent1[1] != extent2[1]]
    }

    public static func ensureValidSplitNumber(
        _ rawSplitNumber: Double?, _ defaultSplitNumber: Double
    ) -> Double {
        // rawSplitNumber = rawSplitNumber || defaultSplitNumber;
        let rawSplitNumber = number.or(rawSplitNumber, defaultSplitNumber)
        return number.mathRound(number.mathMax(rawSplitNumber, 1))
    }

    /**
     * NOTE: The result can have only one item, e.g., when `extent[0] === extent[1]`
     * and `categoryInterval === 0`.
     */
    public static func ordinalScaleCreateTicks(
        _ ordinalScale: OrdinalScale,
        // `categoryInterval` is the number part of `CategoryTickLabelSplitIntervalOption`.
        _ categoryInterval: Double,
        _ addItem: (
            _ tick: ScaleTick,
            _ isExtentBoundary: Bool
        ) -> Void
    ) {
        let extent = getScaleExtentForTickUnsafe(ordinalScale)
        var startTick = extent[0]
        let tickCount = ordinalScale.count()
        let step = Swift.max(number.or(categoryInterval, 0) + 1, 1)   // Math.max((categoryInterval || 0) + 1, 1)

        // Calculate start tick based on zero if possible to keep label consistent
        // while zooming and moving while interval > 0. Otherwise the selection
        // of displayable ticks and symbols probably keep changing.
        if startTick != 0 && step > 1 && tickCount / step > 2 {
            startTick = number.mathRound(number.mathCeil(startTick / step) * step)
        }

        // min max labels may be excluded if `startTick > 0`, but they should be always
        // included and the label display strategy is adopted uniformly later in `AxisBuilder`.
        if startTick != extent[0] {
            addItemInternally(extent[0], true, true)
        }

        var tickValue = startTick
        while tickValue <= extent[1] {
            addItemInternally(tickValue, false, tickValue == extent[0] || tickValue == extent[1])
            tickValue += step
        }

        if tickValue - step != extent[1] {
            addItemInternally(extent[1], true, true)
        }

        func addItemInternally(_ tickValue: Double, _ offInterval: Bool, _ isExtentBoundary: Bool) {
            var tick = ScaleTick(value: tickValue)
            tick.offInterval = offInterval
            addItem(
                tick,
                isExtentBoundary
            )
        }
    }
}

/**
 * Lookup table to avoid rounding error - if the value before transformed is in `lookup.from[i]`,
 * return `lookup.to[i]` directly without transform.
 * Rounding errors typically arise in logarithm transform, which can cause the tick to be displayed
 * like `5.999999999999999` when it is expected to be `6`.
 */
// upstream: export type ValueTransformLookupOpt = { lookup?: { from; to } | NullUndefined };
// (Placed here, after `helper`, but kept top-level since it is an exported type consumed by
//  `scaleMapper.ts`; the declaration order within the upstream file is preserved by the comment
//  block above `logScaleLogTick`, where the original `type` declaration sits.)
public struct ValueTransformLookupOpt {
    public struct Lookup {
        public var from: [Double]
        public var to: [Double]
        public init(from: [Double], to: [Double]) {
            self.from = from
            self.to = to
        }
    }
    public var lookup: Lookup?   // { from; to } | NullUndefined
    public init(lookup: Lookup? = nil) {
        self.lookup = lookup
    }
}
