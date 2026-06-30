// Ported from echarts/src/scale/Interval.ts — keep in sync with upstream
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
//   import {round, mathRound, mathMin, getPrecision} from '../util/number';
//       -> sibling number.swift caseless enum `number` (`number.round`, `number.mathRound`,
//          `number.mathMin`, `number.getPrecision`).
//   import {addCommas} from '../util/format';            -> sibling format.swift (`format.addCommas`).
//   import Scale, { ScaleGetTicksOpt } from './Scale';   -> sibling Scale.swift (`Scale`, `ScaleGetTicksOpt`).
//   import { getIntervalPrecision, IntervalScaleGetLabelOpt } from './helper';
//       -> sibling helper.swift (`helper.getIntervalPrecision`, `IntervalScaleGetLabelOpt`).
//   import {ScaleTick, ScaleDataValue, NullUndefined, AxisBreakOption} from '../util/types';
//       -> sibling types.swift (`ScaleTick`, `ScaleDataValue`, `AxisBreakOption`);
//          NullUndefined collapses to Optional (CONVENTIONS §6).
//   import { AxisBreakParsingResult, getBreaksUnsafe, getScaleBreakHelper, hasBreaks,
//            simplyParseBreakOption } from './break';
//       -> sibling break.swift. DEVIATION: the sibling exposes these as top-level *free functions*
//          (`getScaleBreakHelper()`, `simplyParseBreakOption(_:_:)`, `getBreaksUnsafe(_:)`,
//          `hasBreaks(_:)`) rather than a caseless enum namespace (CONVENTIONS §2). Called bare here
//          to match the sibling's actual public API. `simplyParseBreakOption`'s inline `opt` shape is
//          its own `SimplyParseBreakOptionOpt` (constructed from `IntervalScaleSetting`'s fields).
//   import { assert, clone } from 'zrender/src/core/util';   -> ZRenderKit `util` (`util.assert`, `util.clone`).
//   import { getMinorTicks } from './minorTicks';            -> sibling minorTicks.swift (`minorTicks.getMinorTicks`).
//   import { getScaleExtentForTickUnsafe, initBreakOrLinearMapper, ScaleMapperGeneric }
//       from './scaleMapper';
//       -> sibling scaleMapper.swift. DEVIATION: exposed as top-level *free functions*
//          (`getScaleExtentForTickUnsafe(_:)`, `initBreakOrLinearMapper(_:_:_:)`), called bare here.
//          `ScaleMapperGeneric` is the mapper mixin, attached to `Scale` via an extension in the
//          sibling scaleMapper.swift.
//   import { warn } from '../util/log';                      -> sibling log.swift (`log.warn`).

// upstream: export type IntervalScaleConfig = { interval; intervalPrecision?; intervalCount?; niceExtent? }
public struct IntervalScaleConfig {
    public var interval: Double
    public var intervalPrecision: Double?
    public var intervalCount: Double?
    public var niceExtent: [Double]?
    public init(
        interval: Double,
        intervalPrecision: Double? = nil,
        intervalCount: Double? = nil,
        niceExtent: [Double]? = nil
    ) {
        self.interval = interval
        self.intervalPrecision = intervalPrecision
        self.intervalCount = intervalCount
        self.niceExtent = niceExtent
    }
}

// upstream: type IntervalScaleConfigParsed (module-private). Promoted to `public` because it is the
//  return type of the public `getConfig()` (Swift access-level constraint).
public struct IntervalScaleConfigParsed {
    /**
     * Step of ticks.
     */
    public var interval: Double
    public var intervalPrecision: Double
    /**
     * `_intervalCount` effectively specifies the number of "nice segments". This is for special cases,
     * such as `alignTicks: true` and min max are fixed. In this case, `_interval` may be specified with
     * a "not-nice" value and needs to be rounded with `_intervalPrecision` for better appearance. Then
     * merely accumulating `_interval` may generate incorrect number of ticks due to cumulative errors.
     * So `_intervalCount` is required to specify the expected nice ticks number.
     * Should ensure `_intervalCount >= -1`,
     *  where `-1` means no nice tick (e.g., `_extent: [5.2, 5.8], _interval: 1`),
     *  and `0` means only one nice tick (e.g., `_extent: [5, 5.8], _interval: 1`).
     * @see setInterval
     */
    public var intervalCount: Double?   // number | NullUndefined
    /**
     * Should ensure:
     *  `_extent[0] <= _niceExtent[0] && _niceExtent[1] <= _extent[1]`
     * But NOTICE:
     *  `_niceExtent[0] - _niceExtent[1] <= _interval`, rather than always `< 0`,
     *  because `_niceExtent` is typically calculated by
     *  `[ Math.ceil(_extent[0] / _interval) * _interval, Math.floor(_extent[1] / _interval) * _interval ]`.
     *  e.g., `_extent: [5.2, 5.8]` with interval `1` will get `_niceExtent: [6, 5]`.
     *  e.g., `_extent: [5, 5.8]` with interval `1` will get `_niceExtent: [5, 5]`.
     *  e.g., `_extent: [5.7, 5.7]` with interval `1` will get `_niceExtent: [6, 5]`.
     * @see setInterval
     */
    public var niceExtent: [Double]?    // number[] | NullUndefined
    public init(
        interval: Double,
        intervalPrecision: Double,
        intervalCount: Double?,
        niceExtent: [Double]?
    ) {
        self.interval = interval
        self.intervalPrecision = intervalPrecision
        self.intervalCount = intervalCount
        self.niceExtent = niceExtent
    }
}

// upstream: type IntervalScaleSetting (module-private). Promoted to `public` because it is the
//  parameter type of the public initializer.
public struct IntervalScaleSetting {
    // Either `breakOption` or `parsedBreaks` can be specified.
    public var breakOption: [AxisBreakOption]?
    public var breakParsed: AxisBreakParsingResult?
    public init(
        breakOption: [AxisBreakOption]? = nil,
        breakParsed: AxisBreakParsingResult? = nil
    ) {
        self.breakOption = breakOption
        self.breakParsed = breakParsed
    }
}

/**
 * @final NEVER inherit me!
 */
// upstream: interface IntervalScale extends ScaleMapperGeneric<IntervalScale> {}
//           class IntervalScale extends Scale<IntervalScale> { ... }
// The `ScaleMapperGeneric` mixin is satisfied on the `Scale` base (CONVENTIONS §2; see Scale.swift);
// `@final` -> Swift `final class`. `ClassManageable` conformance supplies the `static type` that
// `Scale.registerClass` reads (the upstream `static type = 'interval'`).
public final class IntervalScale: Scale, ClassManageable {

    // upstream: static type = 'interval';
    public static let type = "interval"
    // upstream: type = 'interval' as const;  — instance field, assigned in `init` (see below).

    private var _cfg: IntervalScaleConfigParsed

    public init(_ setting: IntervalScaleSetting? = nil) {
        // upstream sets `this._cfg` last in the constructor. Moved before `super.init()` to satisfy
        // Swift two-phase initialization (all stored properties must be set before `super.init()`).
        // Nothing reads `_cfg` between here and the original assignment, so behavior is unchanged.
        self._cfg = IntervalScaleConfigParsed(
            interval: 0,
            intervalPrecision: 2,
            intervalCount: nil,    // undefined
            niceExtent: nil        // undefined
        )

        super.init()

        // upstream class field: `type = 'interval' as const`.
        // Assigned through the `Scale` base: the static `IntervalScale.type` (ClassManageable)
        //  shadows the inherited instance property for unqualified `self.type` lookup, so the
        //  upcast disambiguates to the instance `var type`.
        (self as Scale).type = "interval"

        self.parse = IntervalScale.parse

        let setting = setting ?? IntervalScaleSetting()   // setting = setting || {}

        // upstream: simplyParseBreakOption(this, setting). The sibling's `opt` is the dedicated
        //  `SimplyParseBreakOptionOpt` (nominal Swift type), built here from `setting`'s fields —
        //  upstream passes `setting` directly via TS structural typing.
        let breakParsed = simplyParseBreakOption(
            self,
            SimplyParseBreakOptionOpt(breakOption: setting.breakOption, breakParsed: setting.breakParsed)
        )

        let res = initBreakOrLinearMapper(self, breakParsed, nil)
        // @ts-ignore (upstream) — `brk` is readonly; assigned here during construction.
        self.brk = res.brk
    }

    public static func parse(_ val: ScaleDataValue) -> ParsedValueNumeric {
        // `Scale#parse` (and its overrids) are typically applied at the axis values input
        // in echarts option. e.g., `axis.min/max`, `dataZoom.min/max`, etc.
        // but `series.data` is not included, which uses `dataValueHelper.ts`#`parseDataValue`.
        // `Scale#parse` originally introduced in fb8c813215098b9d2458966229bb95c510883d5e
        // at 2016 for dataZoom start/end settings (See `parseAxisModelMinMax`).
        //
        // Historically `scale/Interval.ts` returns the input value directly. But numeric
        // values (such as a number-like string '123') effectively passed through here and
        // were involved in calculations, which was error-prone and inconsistent with the
        // declared TS return type. Previously such issues are fixed separately in different
        // places case by case (such as #2475).
        //
        // Now, we perform actual parse to ensure its `number` type here. The parsing rule
        // follows the series data parsing rule (`dataValueHelper.ts`#`parseDataValue`)
        // and maintains compatibility as much as possible (thus a more strict parsing
        // `number.ts`#`numericToNumber` is not used here.)
        //
        // FIXME: `ScaleDataValue` also need to be modified to include numeric string type,
        //  since it effectively does.
        //
        // upstream: return (val == null || val === '') ? NaN : Number(val)
        // `val` is non-optional `Any` (matches `Scale.parse`'s closure type `(ScaleDataValue) -> ...`);
        //  the upstream `val == null` guard is not reachable in Swift's type system, and
        //  `number.numberCoerce` already returns NaN for unsupported/`nil` inputs. The `val === ''`
        //  guard is preserved because `Number('')` is `0` in JS but upstream wants `NaN`.
        return (val as? String) == ""
            ? Double.nan
            // If string (like '-'), using '+' parse to NaN
            // If object, also parse to NaN
            : number.numberCoerce(val)
    }

    public func getConfig() -> IntervalScaleConfigParsed {
        return util.clone(self._cfg)
    }

    public func setConfig(_ cfg: IntervalScaleConfig) {
        let extent = getScaleExtentForTickUnsafe(self)

        if __DEV__ {
            // upstream: assert(cfg.interval != null)
            //  Dropped: `interval` is a non-optional `Double` in `IntervalScaleConfig`, so it can
            //  never be `null` in Swift's type system.
            if cfg.intervalCount != nil {
                util.assert(
                    cfg.intervalCount! >= -1
                    && cfg.intervalPrecision != nil
                    // Do not support intervalCount on axis break currently.
                    && !hasBreaks(self)
                )
            }
            if let niceExtent = cfg.niceExtent {
                util.assert(niceExtent[0].isFinite && niceExtent[1].isFinite)
                util.assert(extent[0] <= niceExtent[0] && niceExtent[1] <= extent[1])
                util.assert(number.round(niceExtent[0] - niceExtent[1], number.getPrecision(cfg.interval)) <= cfg.interval)
            }
        }

        // Reset all.
        // upstream: this._cfg = cfg = clone(cfg) as IntervalScaleConfigParsed
        // Deviation: `IntervalScaleConfig` (optional `intervalPrecision`) and
        //  `IntervalScaleConfigParsed` (required `intervalPrecision`) are distinct nominal Swift
        //  structs, so the structural cast becomes an explicit field copy. `intervalPrecision` is
        //  seeded with a placeholder when absent, then overwritten by the `== nil` branch below.
        let cfg = util.clone(cfg)
        var parsed = IntervalScaleConfigParsed(
            interval: cfg.interval,
            intervalPrecision: cfg.intervalPrecision ?? 0,
            intervalCount: cfg.intervalCount,
            niceExtent: cfg.niceExtent
        )
        if parsed.niceExtent == nil {
            // Dropped the auto calculated niceExtent and use user-set extent.
            // We assume users want to set both interval and extent to get a better result.
            parsed.niceExtent = extent   // extent.slice() as [number, number]
        }
        if cfg.intervalPrecision == nil {
            parsed.intervalPrecision = helper.getIntervalPrecision(cfg.interval)
        }
        self._cfg = parsed
    }

    /**
     * In ascending order.
     */
    public override func getTicks(_ opt: ScaleGetTicksOpt? = nil) -> [ScaleTick] {
        let opt = opt ?? ScaleGetTicksOpt()
        let cfg = self._cfg
        let interval = cfg.interval
        let extent = getScaleExtentForTickUnsafe(self)
        let niceExtent = cfg.niceExtent
        let intervalPrecision = cfg.intervalPrecision
        let scaleBreakHelper = getScaleBreakHelper()
        let brk = self.brk
        let brkAvailable = scaleBreakHelper != nil && brk != nil

        var ticks: [ScaleTick] = []
        // If interval is 0, return [];
        if interval == 0 || interval.isNaN {   // upstream: if (!interval)
            return ticks
        }

        if opt.breakTicks == "only_break" && brkAvailable {
            scaleBreakHelper!.addBreaksToTicks(&ticks, brk!.breaks, extent, nil)
            return ticks
        }

        if __DEV__ {
            util.assert(niceExtent != nil)
        }

        // [CAVEAT]: If changing this logic, must sync it to `axisAlignTicks.ts`.

        // A fail-safe is required since `interval` can be user specified, or for the case
        // that using dataZoom toolbox and zoom repeatedly.
        let safeLimit = 3000.0

        if extent[0] < niceExtent![0] {
            ticks.append(ScaleTick(value:
                opt.expandToNicedExtent == true
                    ? number.round(niceExtent![0] - interval, intervalPrecision)
                    : extent[0]
            ))
        }

        let estimateNiceMultiple: (Double, Double) -> Double = { tickVal, targetTick in
            return number.mathRound((targetTick - tickVal) / interval)
        }

        let intervalCount = cfg.intervalCount
        var tick = niceExtent![0]
        var niceTickIdx = 0
        while true {
            // Consider case `_extent: [5.2, 5.8], _niceExtent: [6, 5], interval: 1`,
            //  `_intervalCount` makes sense iff `-1`.
            // Consider case `_extent: [5, 5.8], _niceExtent: [5, 5], interval: 1`,
            //  `_intervalCount` makes sense iff `0`.
            if intervalCount == nil {
                if tick > niceExtent![1] || !tick.isFinite || !niceExtent![1].isFinite {
                    break
                }
            }
            else {
                if Double(niceTickIdx) > intervalCount! { // nice ticks number should be `intervalCount + 1`
                    break
                }
                // Consider cumulative error, especially caused by rounding, the last nice
                // `tick` may be less than or greater than `niceExtent[1]` slightly.
                tick = number.mathMin(tick, niceExtent![1])
                if Double(niceTickIdx) == intervalCount! {
                    tick = niceExtent![1]
                }
            }

            ticks.append(ScaleTick(value: tick))

            // Avoid rounding error
            tick = number.round(tick + interval, intervalPrecision)

            if let brk = brk {
                let moreMultiple = brk.calcNiceTickMultiple(tick, estimateNiceMultiple)
                if moreMultiple >= 0 {
                    tick = number.round(tick + moreMultiple * interval, intervalPrecision)
                }
            }

            if ticks.count > 0 && tick == ticks[ticks.count - 1].value {
                // Consider out of safe float point, e.g.,
                // -3711126.9907707 + 2e-10 === -3711126.9907707
                break
            }
            if Double(ticks.count) > safeLimit {
                if __DEV__ {
                    log.warn("Exceed safe limit in IntervalScale[\"getTicks\"].")
                }
                return []
            }

            niceTickIdx += 1
        }

        // Consider this case: the last item of ticks is smaller
        // than niceExtent[1] and niceExtent[1] === extent[1].
        let lastNiceTick = ticks.count > 0 ? ticks[ticks.count - 1].value : niceExtent![1]
        if extent[1] > lastNiceTick {
            ticks.append(ScaleTick(value:
                opt.expandToNicedExtent == true
                    ? number.round(lastNiceTick + interval, intervalPrecision)
                    : extent[1]
            ))
        }

        if brkAvailable {
            scaleBreakHelper!.pruneTicksByBreak(
                opt.pruneByBreak,
                &ticks,
                brk!.breaks,
                { item in item.value },
                cfg.interval,
                extent
            )
        }
        if brkAvailable && opt.breakTicks != "none" {
            scaleBreakHelper!.addBreaksToTicks(&ticks, brk!.breaks, extent, nil)
        }

        return ticks
    }

    public override func getMinorTicks(_ splitNumber: Double) -> [[Double]] {
        return minorTicks.getMinorTicks(
            self,
            splitNumber,
            getBreaksUnsafe(self),
            self._cfg.interval
        )
    }

    // upstream: getLabel(tick: ScaleTick, opt?: IntervalScaleGetLabelOpt): string
    // The abstract base `Scale.getLabel(tick)` takes no `opt`; Swift overrides cannot add a
    // parameter, so the method is split: the `override` forwarder (no `opt`) delegates to the
    // real 2-arg implementation. `tick` is `ScaleTick?` to preserve the upstream `tick == null`
    // guard (TS permits passing null despite the declared non-null type).
    public override func getLabel(_ tick: ScaleTick) -> String {
        return getLabel(tick, nil)
    }

    public func getLabel(
        _ tick: ScaleTick?,
        _ opt: IntervalScaleGetLabelOpt?
    ) -> String {
        if tick == nil {
            return ""
        }
        let tick = tick!

        var precision: Any? = opt?.precision   // 'auto' | number

        if precision == nil {
            // upstream: getPrecision(tick.value) || 0  (`|| 0` is inert — getPrecision never returns NaN)
            precision = number.getPrecision(tick.value)
        }
        else if (precision as? String) == "auto" {
            // Should be more precise then tick.
            precision = self._cfg.intervalPrecision
        }

        // (1) If `precision` is set, 12.005 should be display as '12.00500'.
        // (2) Use `round` (toFixed) to avoid scientific notation like '3.5e-7'.
        // upstream: round(tick.value, precision as number, true) — returnStr: true -> `roundStr`.
        let dataNum = number.roundStr(tick.value, precision as! Double)

        return format.addCommas(dataNum)
    }

}

// upstream: Scale.registerClass(IntervalScale);
// PORT-TODO: upstream runs this side-effecting registration at module import time. Swift libraries
//  have no import-time hook, and a lazy `let` global only initializes on first access (so it would
//  never run). Exposed instead as an idempotent static bootstrap that the EChartsKit registration
//  entry point must invoke once (mirroring how other "register at load" side effects are wired).
extension IntervalScale {
    @discardableResult
    public static func registerScaleClass() -> Bool {
        Scale.registerClass(IntervalScale.self)
        return true
    }
}

// upstream: export default IntervalScale;  -> `public final class IntervalScale` above.
