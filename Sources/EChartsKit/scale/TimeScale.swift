// Ported from echarts/src/scale/Time.ts — keep in sync with upstream
// NOTE (PORT_STATUS §8): on-disk basename renamed `Time.swift` -> `TimeScale.swift` to avoid the
// case-insensitive (macOS APFS) object-file collision with `util/time.swift` (`time.swift.o`),
// which silently dropped this file's symbols from the EChartsKit static archive. Type names and
// upstream mapping are unchanged; re-sync stays mechanical.
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

/*
* A third-party license is embedded for some of the code in this file:
* The "scaleLevels" was originally copied from "d3.js" with some
* modifications made for this project.
* (See more details in the comment on the definition of "scaleLevels" below.)
* The use of the source code of this file is also subject to the terms
* and consitions of the license of "d3.js" (BSD-3Clause, see
* </licenses/LICENSE-d3>).
*/


// [About UTC and local time zone]:
// In most cases, `number.parseDate` will treat input data string as local time
// (except time zone is specified in time string). And `format.formateTime` returns
// local time by default. option.useUTC is false by default. This design has
// considered these common cases:
// (1) Time that is persistent in server is in UTC, but it is needed to be displayed
// in local time by default.
// (2) By default, the input data string (e.g., '2011-01-02') should be displayed
// as its original time, without any time difference.

import Foundation
import ZRenderKit

// upstream imports:
//   import * as numberUtil from '../util/number';            -> sibling number.swift (`number.*`).
//   import {
//       ONE_SECOND, ONE_MINUTE, ONE_HOUR, ONE_DAY, ONE_YEAR, format, leveledFormat,
//       PrimaryTimeUnit, TimeUnit, timeUnits, fullLeveledFormatter, getPrimaryTimeUnit,
//       isPrimaryTimeUnit, getDefaultFormatPrecisionOfInterval, fullYearGetterName,
//       monthSetterName, fullYearSetterName, dateSetterName, hoursGetterName, hoursSetterName,
//       minutesSetterName, secondsSetterName, millisecondsSetterName, monthGetterName,
//       dateGetterName, minutesGetterName, secondsGetterName, millisecondsGetterName,
//       JSDateGetterNames, JSDateSetterNames, getUnitFromValue, primaryTimeUnits, roundTime
//   } from '../util/time';
//       -> sibling time.swift caseless enum `time` (`time.ONE_SECOND` …); `PrimaryTimeUnit`/
//          `TimeUnit`/`JSDateGetterNames`/`JSDateSetterNames` are file-scope in time.swift.
//   import { ensureValidSplitNumber } from './helper';       -> sibling helper.swift (`helper.ensureValidSplitNumber`).
//   import Scale, { ScaleGetTicksOpt } from './Scale';       -> sibling Scale.swift (`Scale`, `ScaleGetTicksOpt`).
//   import {TimeScaleTick, ScaleTick, AxisBreakOption, NullUndefined} from '../util/types';
//       -> sibling types.swift (`ScaleTick`, `TimeScaleTickTime`, `AxisBreakOption`); NullUndefined
//          collapses to Optional (CONVENTIONS §6). See the `TimeScaleTick` -> `ScaleTick` note below.
//   import {TimeAxisLabelFormatterParsed} from '../coord/axisCommonTypes';
//       -> forward-ref placeholder in time.swift (`TimeAxisLabelFormatterParsed`).
//   import { warn } from '../util/log';                      -> sibling log.swift (`log.warn`).
//   import { LocaleOption } from '../core/locale';           -> PORT-TODO: core/locale (Tier6) not ported.
//   import Model from '../model/Model';                      -> forward-ref placeholder `Model` in types.swift.
//   import { each, filter, indexOf, isNumber, map } from 'zrender/src/core/util';   -> ZRenderKit `util`.
//   import { BreakScaleMapper, getBreaksUnsafe, getScaleBreakHelper, simplyParseBreakOption } from './break';
//       -> sibling break.swift (caseless enum `` `break` ``; `break` is a Swift keyword so the namespace
//          is back-tick escaped, matching minorTicks.swift / Interval.swift).
//   import type { ScaleCalcNiceMethod } from '../coord/axisNiceTicks';
//       -> forward-ref placeholder at the bottom of this file (PORT-TODO: belongs to coord/axisNiceTicks).
//   import { getMinorTicks } from './minorTicks';            -> sibling minorTicks.swift (`minorTicks.getMinorTicks`).
//   import {
//       getScaleLinearSpanEffective, getScaleExtentForTickUnsafe, initBreakOrLinearMapper, ScaleMapperGeneric
//   } from './scaleMapper';
//       -> sibling swift (caseless enum `scaleMapper`; `ScaleMapperGeneric` is the mapper mixin,
//          satisfied on the `Scale` base — CONVENTIONS §2, see Interval.swift).
//   import { removeDuplicates, removeDuplicatesGetKeyFromValueProp } from '../util/model';
//       -> sibling model.swift (`model.removeDuplicates`, `model.removeDuplicatesGetKeyFromValueProp`).
//
// NOTE on the tick element type: upstream `getTicks()`/`createIntervalTicks()` return
//   `TimeScaleTick[]` (which only narrows `ScaleTick['time']` to be required). Swift override
//   invariance forces `TimeScale.getTicks` to keep the base `Scale.getTicks(): [ScaleTick]`
//   return type, and the break-helper API also operates on `[ScaleTick]`, so this file models
//   the ticks as `ScaleTick` (with the optional `time` set) throughout. (CONVENTIONS §8.)

// FIXME 公用？
fileprivate func bisect(
    _ a: [(TimeUnit, Double)],
    _ x: Double,
    _ lo: Double,
    _ hi: Double
) -> Double {
    var lo = lo
    var hi = hi
    while lo < hi {
        // upstream: const mid = lo + hi >>> 1;  (`>>>` unsigned shift; lo/hi are non-negative)
        let mid = Double((Int(lo) + Int(hi)) >> 1)
        if a[Int(mid)].1 < x {
            lo = mid + 1
        }
        else {
            hi = mid
        }
    }
    return lo
}

// upstream: type TimeScaleSetting = { locale; useUTC; breakOption };
//   `locale: Model<LocaleOption>` -> `Model` (forward-ref placeholder in types.swift; the
//   `<LocaleOption>` generic argument is dropped — PORT-TODO: core/locale not ported).
public struct TimeScaleSetting {
    public var locale: Model
    public var useUTC: Bool
    public var breakOption: [AxisBreakOption]?   // AxisBreakOption[] | NullUndefined
    public init(
        locale: Model,
        useUTC: Bool,
        breakOption: [AxisBreakOption]? = nil
    ) {
        self.locale = locale
        self.useUTC = useUTC
        self.breakOption = breakOption
    }
}

// upstream: the inline object param of `setTimeInterval`:
//   { interval: number; approxInterval: number; minLevelUnit: TimeUnit }
public struct TimeScaleSetTimeIntervalOpt {
    public var interval: Double
    public var approxInterval: Double
    public var minLevelUnit: TimeUnit
    public init(interval: Double, approxInterval: Double, minLevelUnit: TimeUnit) {
        self.interval = interval
        self.approxInterval = approxInterval
        self.minLevelUnit = minLevelUnit
    }
}

/**
 * @final NEVER inherit me!
 */
// upstream: interface TimeScale extends ScaleMapperGeneric<TimeScale> {}
//           class TimeScale extends Scale<TimeScale> { ... }
// The `ScaleMapperGeneric` mixin is satisfied on the `Scale` base (CONVENTIONS §2; see Interval.swift);
// `@final` -> Swift `final class`. `ClassManageable` conformance supplies the `static type` that
// `Scale.registerClass` reads (the upstream `static type = 'time'`).
public final class TimeScale: Scale, ClassManageable {

    // upstream: static type = 'time';
    public static let type = "time"
    // upstream: readonly type = 'time' as const;  — instance field, assigned in `init` (see below).

    private var _locale: Model
    private var _useUTC: Bool
    // upstream: `_approxInterval`/`_minLevelUnit` are not set in the constructor (set by
    //   `setTimeInterval`). Modeled as IUO so "unset" traps on misuse (mirrors reading `undefined`).
    private var _approxInterval: Double!
    private var _interval: Double = 0

    private var _minLevelUnit: TimeUnit!

    public init(_ setting: TimeScaleSetting) {
        // upstream sets `_locale`/`_useUTC`/`_interval` after `super()`. Swift two-phase init requires
        // the non-optional stored properties to be set before `super.init()`; nothing reads them in
        // between, so behavior is unchanged (mirrors Interval.swift).
        self._locale = setting.locale
        self._useUTC = setting.useUTC
        self._interval = 0

        super.init()

        // upstream class field: `type = 'time' as const`.
        // Assigned through the `Scale` base: the static `TimeScale.type` (ClassManageable) shadows the
        //  inherited instance property for unqualified `self.type` lookup, so the upcast disambiguates
        //  to the instance `var type` (mirrors Interval.swift).
        (self as Scale).type = "time"

        self.parse = TimeScale.parse

        // upstream: simplyParseBreakOption(this, setting). The sibling's `opt` is the dedicated
        //  `SimplyParseBreakOptionOpt` (nominal Swift type), built here from `setting`'s fields —
        //  upstream passes `setting` directly via TS structural typing.
        let breakParsed = `break`.simplyParseBreakOption(
            self,
            SimplyParseBreakOptionOpt(breakOption: setting.breakOption)
        )

        let res = initBreakOrLinearMapper(self, breakParsed, nil)
        // @ts-ignore (upstream) — `brk` is readonly; assigned here during construction.
        self.brk = res.brk
    }

    /**
     * Get label is mainly for other components like dataZoom, tooltip.
     */
    public override func getLabel(_ tick: ScaleTick) -> String {
        return time.format(
            tick.value,
            time.fullLeveledFormatter[
                time.getDefaultFormatPrecisionOfInterval(time.getPrimaryTimeUnit(self._minLevelUnit))
            ] ?? time.fullLeveledFormatter[.second]!,
            self._useUTC,
            self._locale
        )
    }

    public func getFormattedLabel(
        _ tick: ScaleTick,
        _ idx: Double,
        _ labelFormatter: TimeAxisLabelFormatterParsed
    ) -> String {
        return time.leveledFormat(tick, idx, labelFormatter, self._locale, self._useUTC)
    }

    public override func getTicks(_ opt: ScaleGetTicksOpt? = nil) -> [ScaleTick] {
        // PORT-DEVIATION: honor the per-instance `getTicksOverride` (timeline axis) — see Scale.swift.
        if let override = self.getTicksOverride { return override(opt) }
        let opt = opt ?? ScaleGetTicksOpt()

        let interval = self._interval
        let extent = getScaleExtentForTickUnsafe(self)
        let scaleBreakHelper = `break`.getScaleBreakHelper()
        let brk = self.brk
        let brkAvailable = scaleBreakHelper != nil && brk != nil

        var ticks: [ScaleTick] = []
        // If interval is 0, return [];
        if interval == 0 || interval.isNaN {   // if (!interval)
            return ticks
        }

        let useUTC = self._useUTC

        if brkAvailable && opt.breakTicks == "only_break" {
            `break`.getScaleBreakHelper()!.addBreaksToTicks(&ticks, brk!.breaks, extent, nil)
            return ticks
        }

        ticks = createIntervalTicks(
            self._minLevelUnit,
            self._approxInterval,
            useUTC,
            extent,
            getScaleLinearSpanEffective(self),
            brk
        )

        var upperUnitIndex = Double(time.primaryTimeUnits.count) - 1
        var maxLevel = 0.0
        util.each(ticks) { tick, _ in
            if let tickTime = tick.time {
                upperUnitIndex = Swift.min(upperUnitIndex, util.indexOf(time.primaryTimeUnits, tickTime.upperTimeUnit))
                maxLevel = Swift.max(maxLevel, tickTime.level)
            }
        }

        if brkAvailable {
            `break`.getScaleBreakHelper()!.pruneTicksByBreak(
                opt.pruneByBreak,
                &ticks,
                brk!.breaks,
                { item in item.value },
                self._approxInterval,
                extent
            )
        }
        if brkAvailable && opt.breakTicks != "none" {
            `break`.getScaleBreakHelper()!.addBreaksToTicks(&ticks, brk!.breaks, extent, { trimmedBrk in
                // @see `parseTimeAxisLabelFormatterDictionary`.
                let lowerBrkUnitIndex = Swift.max(
                    util.indexOf(time.primaryTimeUnits, time.getUnitFromValue(trimmedBrk.vmin, useUTC)),
                    util.indexOf(time.primaryTimeUnits, time.getUnitFromValue(trimmedBrk.vmax, useUTC))
                )
                var upperBrkUnitIndex = 0.0
                for unitIdx in 0..<time.primaryTimeUnits.count {
                    if !isPrimaryUnitValueAndGreaterSame(
                        time.primaryTimeUnits[unitIdx], trimmedBrk.vmin, trimmedBrk.vmax, useUTC
                    ) {
                        upperBrkUnitIndex = Double(unitIdx)
                        break
                    }
                }
                let upperIdx = Swift.min(upperBrkUnitIndex, upperUnitIndex)
                let lowerIdx = Swift.max(upperIdx, lowerBrkUnitIndex)
                return TimeScaleTickTime(
                    level: maxLevel,
                    upperTimeUnit: time.primaryTimeUnits[Int(upperIdx)],
                    lowerTimeUnit: time.primaryTimeUnits[Int(lowerIdx)]
                )
            })
        }

        return ticks
    }

    public override func getMinorTicks(_ splitNumber: Double) -> [[Double]] {
        return minorTicks.getMinorTicks(
            self,
            splitNumber,
            `break`.getBreaksUnsafe(self),
            self._interval
        )
    }

    public func setTimeInterval(_ opt: TimeScaleSetTimeIntervalOpt) {
        self._interval = opt.interval
        self._approxInterval = opt.approxInterval
        self._minLevelUnit = opt.minLevelUnit
    }

    public static func parse(_ val: ScaleDataValue) -> ParsedValueNumeric {
        // `val` might be a float (e.g., calculated from percent), so call `round`.
        // upstream: return isNumber(val) ? Math.round(val) : +numberUtil.parseDate(val);
        //   `Math.round` rounds half **up** -> `floor(x + 0.5)` (CONVENTIONS §5).
        //   `+parseDate(val)` -> the `Date`'s ms-since-epoch timestamp.
        return util.isNumber(val)
            ? floor((val as! Double) + 0.5)
            : number.parseDate(val).timeIntervalSince1970 * 1000
    }

}


/**
 * This implementation was originally copied from "d3.js"
 * <https://github.com/d3/d3/blob/b516d77fb8566b576088e73410437494717ada26/src/time/scale.js>
 * with some modifications made for this program.
 * See the license statement at the head of this file.
 */
fileprivate let scaleIntervals: [(TimeUnit, Double)] = [
    // Format                                interval
    (.second, time.ONE_SECOND),             // 1s
    (.minute, time.ONE_MINUTE),             // 1m
    (.hour, time.ONE_HOUR),                 // 1h
    (.quarterDay, time.ONE_HOUR * 6),       // 6h
    (.halfDay, time.ONE_HOUR * 12),         // 12h
    (.day, time.ONE_DAY * 1.2),             // 1d
    (.halfWeek, time.ONE_DAY * 3.5),        // 3.5d
    (.week, time.ONE_DAY * 7),              // 7d
    (.month, time.ONE_DAY * 31),            // 1M
    (.quarter, time.ONE_DAY * 95),          // 3M
    (.halfYear, time.ONE_YEAR / 2),         // 6M
    (.year, time.ONE_YEAR)                  // 1Y
]

fileprivate func isPrimaryUnitValueAndGreaterSame(
    _ unit: PrimaryTimeUnit,
    _ valueA: Double,
    _ valueB: Double,
    _ isUTC: Bool
) -> Bool {
    return time.roundTime(Date(timeIntervalSince1970: valueA / 1000), unit, isUTC).timeIntervalSince1970 * 1000
        == time.roundTime(Date(timeIntervalSince1970: valueB / 1000), unit, isUTC).timeIntervalSince1970 * 1000
}

// function isUnitValueSame(
//     unit: PrimaryTimeUnit,
//     valueA: number,
//     valueB: number,
//     isUTC: boolean
// ): boolean {
//     const dateA = numberUtil.parseDate(valueA) as any;
//     const dateB = numberUtil.parseDate(valueB) as any;

//     const isSame = (unit: PrimaryTimeUnit) => {
//         return getUnitValue(dateA, unit, isUTC)
//             === getUnitValue(dateB, unit, isUTC);
//     };
//     const isSameYear = () => isSame('year');
//     // const isSameHalfYear = () => isSameYear() && isSame('half-year');
//     // const isSameQuater = () => isSameYear() && isSame('quarter');
//     const isSameMonth = () => isSameYear() && isSame('month');
//     const isSameDay = () => isSameMonth() && isSame('day');
//     // const isSameHalfDay = () => isSameDay() && isSame('half-day');
//     const isSameHour = () => isSameDay() && isSame('hour');
//     const isSameMinute = () => isSameHour() && isSame('minute');
//     const isSameSecond = () => isSameMinute() && isSame('second');
//     const isSameMilliSecond = () => isSameSecond() && isSame('millisecond');

//     switch (unit) {
//         case 'year':
//             return isSameYear();
//         case 'month':
//             return isSameMonth();
//         case 'day':
//             return isSameDay();
//         case 'hour':
//             return isSameHour();
//         case 'minute':
//             return isSameMinute();
//         case 'second':
//             return isSameSecond();
//         case 'millisecond':
//             return isSameMilliSecond();
//     }
// }

// const primaryUnitGetters = {
//     year: fullYearGetterName(),
//     month: monthGetterName(),
//     day: dateGetterName(),
//     hour: hoursGetterName(),
//     minute: minutesGetterName(),
//     second: secondsGetterName(),
//     millisecond: millisecondsGetterName()
// };

// const primaryUnitUTCGetters = {
//     year: fullYearGetterName(true),
//     month: monthGetterName(true),
//     day: dateGetterName(true),
//     hour: hoursGetterName(true),
//     minute: minutesGetterName(true),
//     second: secondsGetterName(true),
//     millisecond: millisecondsGetterName(true)
// };

// function moveTick(date: Date, unitName: TimeUnit, step: number, isUTC: boolean) {
//     step = step || 1;
//     switch (getPrimaryTimeUnit(unitName)) {
//         case 'year':
//             date[fullYearSetterName(isUTC)](date[fullYearGetterName(isUTC)]() + step);
//             break;
//         case 'month':
//             date[monthSetterName(isUTC)](date[monthGetterName(isUTC)]() + step);
//             break;
//         case 'day':
//             date[dateSetterName(isUTC)](date[dateGetterName(isUTC)]() + step);
//             break;
//         case 'hour':
//             date[hoursSetterName(isUTC)](date[hoursGetterName(isUTC)]() + step);
//             break;
//         case 'minute':
//             date[minutesSetterName(isUTC)](date[minutesGetterName(isUTC)]() + step);
//             break;
//         case 'second':
//             date[secondsSetterName(isUTC)](date[secondsGetterName(isUTC)]() + step);
//             break;
//         case 'millisecond':
//             date[millisecondsSetterName(isUTC)](date[millisecondsGetterName(isUTC)]() + step);
//             break;
//     }
//     return date.getTime();
// }

// const DATE_INTERVALS = [[8, 7.5], [4, 3.5], [2, 1.5]];
// const MONTH_INTERVALS = [[6, 5.5], [3, 2.5], [2, 1.5]];
// const MINUTES_SECONDS_INTERVALS = [[30, 30], [20, 20], [15, 15], [10, 10], [5, 5], [2, 2]];

fileprivate func getDateInterval(_ approxInterval: Double, _ daysInMonth: Double) -> Double {
    var approxInterval = approxInterval
    approxInterval /= time.ONE_DAY
    return approxInterval > 16 ? 16
                // Math.floor(daysInMonth / 2) + 1  // In this case we only want one tick between two months.
            : approxInterval > 7.5 ? 7  // TODO week 7 or day 8?
            : approxInterval > 3.5 ? 4
            : approxInterval > 1.5 ? 2 : 1
}

fileprivate func getMonthInterval(_ approxInterval: Double) -> Double {
    let APPROX_ONE_MONTH = 30 * time.ONE_DAY
    var approxInterval = approxInterval
    approxInterval /= APPROX_ONE_MONTH
    return approxInterval > 6 ? 6
            : approxInterval > 3 ? 3
            : approxInterval > 2 ? 2 : 1
}

fileprivate func getHourInterval(_ approxInterval: Double) -> Double {
    var approxInterval = approxInterval
    approxInterval /= time.ONE_HOUR
    return approxInterval > 12 ? 12
            : approxInterval > 6 ? 6
            : approxInterval > 3.5 ? 4
            : approxInterval > 2 ? 2 : 1
}

fileprivate func getMinutesAndSecondsInterval(_ approxInterval: Double, _ isMinutes: Bool? = nil) -> Double {
    var approxInterval = approxInterval
    approxInterval /= (isMinutes ?? false) ? time.ONE_MINUTE : time.ONE_SECOND
    return approxInterval > 30 ? 30
            : approxInterval > 20 ? 20
            : approxInterval > 15 ? 15
            : approxInterval > 10 ? 10
            : approxInterval > 5 ? 5
            : approxInterval > 2 ? 2 : 1
}

fileprivate func getMillisecondsInterval(_ approxInterval: Double) -> Double {
    // If less than 1, the getTicks loop will inevitably deed loop and read safeLimit.
    return number.mathMax(number.nice(approxInterval, .round), 1)
}

// e.g., if the input unit is 'day', start calculate ticks from the first day of
// that month to make ticks "nice".
fileprivate func getFirstTimestampOfUnit(_ timestamp: Double, _ unitName: TimeUnit, _ isUTC: Bool) -> Double {
    // upstream: indexOf(primaryTimeUnits, unitName) — `unitName` is a `TimeUnit` matched against the
    //   `PrimaryTimeUnit[]` by string identity (returns -1 for non-primary units). Compared via rawValue.
    let upperUnitIdx = Swift.max(0, util.indexOf(time.primaryTimeUnits.map { $0.rawValue }, unitName.rawValue) - 1)
    return time.roundTime(Date(timeIntervalSince1970: timestamp / 1000), time.primaryTimeUnits[Int(upperUnitIdx)], isUTC).timeIntervalSince1970 * 1000
}

fileprivate func createEstimateNiceMultiple(
    _ setMethodName: JSDateSetterNames,
    _ dateMethodInterval: Double
) -> (Double, Double) -> Double {
    var tmpDate = Date(timeIntervalSince1970: 0)   // new Date(0)
    tmpDate = time.jsDateSet(tmpDate, setMethodName, 1)
    let tmpTime = tmpDate.timeIntervalSince1970 * 1000
    tmpDate = time.jsDateSet(tmpDate, setMethodName, 1 + dateMethodInterval)
    let approxTimeInterval = tmpDate.timeIntervalSince1970 * 1000 - tmpTime

    return { tickVal, targetValue in
        // Only in month that accurate result can not get by division of
        // timestamp interval, but no need accurate here.
        return Swift.max(
            0,
            floor((targetValue - tickVal) / approxTimeInterval + 0.5)   // Math.round
        )
    }
}

fileprivate func createIntervalTicks(
    _ bottomUnitName: TimeUnit,
    _ approxInterval: Double,
    _ isUTC: Bool,
    _ extent: [Double],
    _ innermostSpan: Double,
    _ brk: BreakScaleMapper?
) -> [ScaleTick] {
    // A fail-safe is required since `interval` can be user specified, or for the case
    // that using dataZoom toolbox and zoom repeatedly.
    let safeLimit = 3000.0
    let unitNames = time.timeUnits
    // const bottomPrimaryUnitName = getPrimaryTimeUnit(bottomUnitName);

    // upstream: interface InnerTimeTick { value: TimeScaleTick['value']; notAdd?: boolean }
    struct InnerTimeTick {
        var value: Double
        var notAdd: Bool?
        init(value: Double, notAdd: Bool? = nil) {
            self.value = value
            self.notAdd = notAdd
        }
    }

    var iter = 0.0

    func addTicksInSpan(
        _ interval: Double,
        _ minTimestamp: Double,
        _ maxTimestamp: Double,
        _ getMethodName: JSDateGetterNames,
        _ setMethodName: JSDateSetterNames,
        _ isDate: Bool,
        _ out: inout [InnerTimeTick]
    ) {
        let estimateNiceMultiple = createEstimateNiceMultiple(setMethodName, interval)

        var dateTime = minTimestamp
        var date = Date(timeIntervalSince1970: dateTime / 1000)   // new Date(dateTime)

        // if (isDate) {
        //     d -= 1; // Starts with 0;   PENDING
        // }
        _ = isDate

        while dateTime < maxTimestamp && dateTime <= extent[1] {
            out.append(InnerTimeTick(value: dateTime))

            // upstream: if (iter++ > safeLimit)  (post-increment: test pre-value, then increment)
            let exceeded = iter > safeLimit
            iter += 1
            if exceeded {
                if __DEV__ {
                    log.warn("Exceed safe limit in TimeScale[\"getTicks\"].")
                }
                break
            }

            date = time.jsDateSet(date, setMethodName, time.jsDateGet(date, getMethodName) + interval)
            dateTime = date.timeIntervalSince1970 * 1000

            if let brk = brk {
                let moreMultiple = brk.calcNiceTickMultiple(dateTime, estimateNiceMultiple)
                if moreMultiple > 0 {
                    date = time.jsDateSet(date, setMethodName, time.jsDateGet(date, getMethodName) + moreMultiple * interval)
                    dateTime = date.timeIntervalSince1970 * 1000
                }
            }
        }

        // This extra tick is for calculating ticks of next level. Will not been added to the final result
        out.append(InnerTimeTick(
            value: dateTime,
            // extent[1] should be added; deduplication will be performed later.
            notAdd: dateTime > extent[1]
        ))
    }

    func addLevelTicks(
        _ unitName: TimeUnit,
        _ lastLevelTicksIn: [InnerTimeTick],
        _ levelTicks: inout [InnerTimeTick]
    ) {
        var newAddedTicks: [InnerTimeTick] = []   // upstream: ScaleTick[] (effectively InnerTimeTick)
        let isFirstLevel = lastLevelTicksIn.isEmpty   // !lastLevelTicks.length
        var lastLevelTicks = lastLevelTicksIn

        if isPrimaryUnitValueAndGreaterSame(time.getPrimaryTimeUnit(unitName), extent[0], extent[1], isUTC) {
            return
        }

        if isFirstLevel {
            lastLevelTicks = [
                InnerTimeTick(value: getFirstTimestampOfUnit(extent[0], unitName, isUTC)),
                InnerTimeTick(value: extent[1])
            ]
        }

        if lastLevelTicks.count > 0 {
            for i in 0..<(lastLevelTicks.count - 1) {
                let startTick = lastLevelTicks[i].value
                let endTick = lastLevelTicks[i + 1].value
                if startTick == endTick {
                    continue
                }

                var interval: Double
                var getterName: JSDateGetterNames
                var setterName: JSDateSetterNames
                var isDate = false

                switch unitName {
                    case .year:
                        interval = Swift.max(1, floor(approxInterval / time.ONE_DAY / 365 + 0.5))   // Math.round
                        getterName = time.fullYearGetterName(isUTC)
                        setterName = time.fullYearSetterName(isUTC)
                    case .halfYear, .quarter, .month:
                        interval = getMonthInterval(approxInterval)
                        getterName = time.monthGetterName(isUTC)
                        setterName = time.monthSetterName(isUTC)
                    case .week, .halfWeek, .day:   // PENDING If week is added. Ignore day.
                        interval = getDateInterval(approxInterval, 31)   // Use 32 days and let interval been 16
                        getterName = time.dateGetterName(isUTC)
                        setterName = time.dateSetterName(isUTC)
                        isDate = true
                    case .halfDay, .quarterDay, .hour:
                        interval = getHourInterval(approxInterval)
                        getterName = time.hoursGetterName(isUTC)
                        setterName = time.hoursSetterName(isUTC)
                    case .minute:
                        interval = getMinutesAndSecondsInterval(approxInterval, true)
                        getterName = time.minutesGetterName(isUTC)
                        setterName = time.minutesSetterName(isUTC)
                    case .second:
                        interval = getMinutesAndSecondsInterval(approxInterval, false)
                        getterName = time.secondsGetterName(isUTC)
                        setterName = time.secondsSetterName(isUTC)
                    case .millisecond:
                        interval = getMillisecondsInterval(approxInterval)
                        getterName = time.millisecondsGetterName(isUTC)
                        setterName = time.millisecondsSetterName(isUTC)
                }

                // Notice: This expansion by `getFirstTimestampOfUnit` may cause too many ticks and
                // iteration. e.g., when three levels of ticks is displayed, which can be caused by
                // data zoom and axis breaks. Thus trim them here.
                if endTick >= extent[0] && startTick <= extent[1] {
                    addTicksInSpan(
                        interval, startTick, endTick, getterName, setterName, isDate, &newAddedTicks
                    )
                }

                if unitName == .year && levelTicks.count > 1 && i == 0 {
                    // Add nearest years to the left extent.
                    levelTicks.insert(InnerTimeTick(value: levelTicks[0].value - interval), at: 0)
                }
            }
        }

        for i in 0..<newAddedTicks.count {
            levelTicks.append(newAddedTicks[i])
        }
    }

    var levelsTicks: [[InnerTimeTick]] = []
    var currentLevelTicks: [InnerTimeTick] = []

    var tickCount = 0.0
    var lastLevelTickCount = 0.0
    for i in 0..<unitNames.count {
        let primaryTimeUnit = time.getPrimaryTimeUnit(unitNames[i])
        if !time.isPrimaryTimeUnit(unitNames[i]) {   // TODO
            continue
        }
        addLevelTicks(unitNames[i], levelsTicks.last ?? [], &currentLevelTicks)

        let nextPrimaryTimeUnit: PrimaryTimeUnit? = (i + 1 < unitNames.count) ? time.getPrimaryTimeUnit(unitNames[i + 1]) : nil
        if primaryTimeUnit != nextPrimaryTimeUnit {
            if !currentLevelTicks.isEmpty {
                lastLevelTickCount = tickCount
                // Remove the duplicate so the tick count can be precisely.
                currentLevelTicks.sort { $0.value < $1.value }
                var levelTicksRemoveDuplicated: [InnerTimeTick] = []
                for i in 0..<currentLevelTicks.count {
                    let tickValue = currentLevelTicks[i].value
                    if i == 0 || currentLevelTicks[i - 1].value != tickValue {
                        levelTicksRemoveDuplicated.append(currentLevelTicks[i])
                        if tickValue >= extent[0] && tickValue <= extent[1] {
                            tickCount += 1
                        }
                    }
                }

                let targetTickNum = innermostSpan / approxInterval
                // Added too much in this level and not too less in last level
                if tickCount > targetTickNum * 1.5 && lastLevelTickCount > targetTickNum / 1.5 {
                    break
                }

                // Only treat primary time unit as one level.
                levelsTicks.append(levelTicksRemoveDuplicated)

                if tickCount > targetTickNum || bottomUnitName == unitNames[i] {
                    break
                }

            }
            // Reset if next unitName is primary
            currentLevelTicks = []
        }

    }

    let levelsTicksInExtent = util.filter(util.map(levelsTicks) { levelTicks, _ in
        return util.filter(levelTicks) { tick, _ in
            tick.value >= extent[0] && tick.value <= extent[1] && !(tick.notAdd ?? false)
        }
    }) { levelTicks, _ in levelTicks.count > 0 }

    let maxLevel = levelsTicksInExtent.count - 1
    var ticks: [ScaleTick] = []

    for i in 0..<levelsTicksInExtent.count {
        let levelTicks = levelsTicksInExtent[i]
        for k in 0..<levelTicks.count {
            let unit = time.getUnitFromValue(levelTicks[k].value, isUTC)
            var tick = ScaleTick(value: levelTicks[k].value)
            tick.time = TimeScaleTickTime(
                level: Double(maxLevel - i),
                upperTimeUnit: unit,
                lowerTimeUnit: unit
            )
            ticks.append(tick)
        }
    }

    // Remove duplicates, which may cause jitter of `splitArea` and other bad cases.
    // upstream: removeDuplicates(ticks, removeDuplicatesGetKeyFromValueProp, null);
    // PORT-TODO: `model.removeDuplicatesGetKeyFromValueProp` extracts `value` from a `[String:Any]`
    //   bag; our ticks are `ScaleTick` structs, so the key closure mirrors its semantics (`item.value + ''`).
    //   `model.removeDuplicates` takes `inout [TItem?]`, so bridge through an optional array.
    var ticksForDedup: [ScaleTick?] = ticks
    model.removeDuplicates(&ticksForDedup, { item in
        item != nil ? String(item!.value) : "undefined"
    }, nil)
    ticks = ticksForDedup.compactMap { $0 }

    ticks.sort { $0.value < $1.value }

    let currMinTick = ticks.first
    let currMaxTick = ticks.last
    let extent0Unit = time.getUnitFromValue(extent[0], isUTC)
    let extent1Unit = time.getUnitFromValue(extent[1], isUTC)
    if currMinTick == nil || currMinTick!.value > extent[0] {
        var tick = ScaleTick(value: extent[0])
        tick.time = TimeScaleTickTime(level: 0, upperTimeUnit: extent0Unit, lowerTimeUnit: extent0Unit)
        tick.notNice = true
        ticks.insert(tick, at: 0)
    }
    if currMaxTick == nil || currMaxTick!.value < extent[1] {
        var tick = ScaleTick(value: extent[1])
        tick.time = TimeScaleTickTime(level: 0, upperTimeUnit: extent1Unit, lowerTimeUnit: extent1Unit)
        tick.notNice = true
        ticks.append(tick)
    }

    return ticks
}

// upstream: export const calcNiceForTimeScale: ScaleCalcNiceMethod = function (scale: TimeScale, opt) { ... };
//   `const = function` -> a free function (matches the free-function convention used across this tier);
//   the `ScaleCalcNiceMethod` typing is preserved via the forward-ref placeholder below. The `scale`
//   parameter is concretely `TimeScale` (TS bivariance) — kept as `TimeScale` here.
public func calcNiceForTimeScale(_ scale: TimeScale, _ opt: ScaleCalcNiceMethodOpt) {
    var extent = scale.getExtent()
    // If extent start and end are same, expand them
    if extent[0] == extent[1] {
        // Expand extent
        extent[0] -= time.ONE_DAY
        extent[1] += time.ONE_DAY
    }
    // If there are no data and extent are [Infinity, -Infinity]
    if extent[1] == -Double.infinity && extent[0] == Double.infinity {
        let d = Date()   // new Date()
        // upstream: extent[1] = +new Date(d.getFullYear(), d.getMonth(), d.getDate());
        //   -> local-time midnight of today.
        var comps = DateComponents()
        comps.year = Int(time.jsDateGet(d, "getFullYear"))
        comps.month = Int(time.jsDateGet(d, "getMonth")) + 1   // JS month is 0-based
        comps.day = Int(time.jsDateGet(d, "getDate"))
        let localMidnight = time.calendar(false).date(from: comps) ?? d
        extent[1] = localMidnight.timeIntervalSince1970 * 1000
        extent[0] = extent[1] - time.ONE_DAY
    }
    scale.setExtent(extent[0], extent[1])

    let splitNumber = helper.ensureValidSplitNumber(opt.splitNumber, 10)
    var approxInterval = getScaleLinearSpanEffective(scale) / splitNumber

    let minInterval = opt.minInterval
    let maxInterval = opt.maxInterval
    if let minInterval = minInterval, approxInterval < minInterval {
        approxInterval = minInterval
    }
    if let maxInterval = maxInterval, approxInterval > maxInterval {
        approxInterval = maxInterval
    }

    let scaleIntervalsLen = Double(scaleIntervals.count)
    let idx = Swift.min(
        bisect(scaleIntervals, approxInterval, 0, scaleIntervalsLen),
        scaleIntervalsLen - 1
    )

    // Interval that can be used to calculate ticks
    let interval = scaleIntervals[Int(idx)].1
    // Min level used when picking ticks from top down.
    // We check one more level to avoid the ticks are to sparse in some case.
    let minLevelUnit = scaleIntervals[Int(Swift.max(idx - 1, 0))].0

    scale.setTimeInterval(TimeScaleSetTimeIntervalOpt(
        interval: interval,
        approxInterval: approxInterval,
        minLevelUnit: minLevelUnit
    ))
}

// upstream: Scale.registerClass(TimeScale);
// PORT-TODO: upstream runs this side-effecting registration at module import time. Swift libraries have
//  no import-time hook, so it is exposed as an idempotent static bootstrap the EChartsKit registration
//  entry point must invoke once (mirrors Interval.swift's `registerScaleClass`).
extension TimeScale {
    @discardableResult
    public static func registerScaleClass() -> Bool {
        Scale.registerClass(TimeScale.self)
        return true
    }
}

// upstream: export default TimeScale;  -> `public final class TimeScale` above.

// upstream: import type { ScaleCalcNiceMethod, ScaleCalcNiceMethodOpt } from '../coord/axisNiceTicks';
//   Now that coord/axisNiceTicks.swift has landed, `ScaleCalcNiceMethod` / `ScaleCalcNiceMethodOpt`
//   are defined there (their real owner); the forward-declaration placeholder previously kept here
//   has been removed per its own instructions.
