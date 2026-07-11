// Ported from echarts/src/util/time.ts — keep in sync with upstream
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
//   import * as zrUtil from 'zrender/src/core/util';                    -> ZRenderKit.util
//   import {...} from './../coord/axisCommonTypes';                     -> PORT-NOTE: coord/axisCommonTypes.swift
//       is ported, but the TimeAxisLabelFormatter* types it exports are still declared here (kept in
//       time.swift rather than moved into axisCommonTypes.swift).
//   import * as numberUtil from './number';                            -> EChartsKit.number (same module)
//   import {NullUndefined, ScaleTick} from './types';                  -> ScaleTick in types.swift;
//                                                                          NullUndefined collapses to `nil`.
//   import { getDefaultLocaleModel, getLocaleModel, SYSTEM_LANG, LocaleOption } from '../core/locale';
//                                                                       -> PORT-TODO: core/locale (Tier6) not ported.
//   import Model from '../model/Model';                                -> model/Model.swift (ported).
//   import { getScaleBreakHelper } from '../scale/break';              -> PORT-TODO: scale/break not ported.

// ============================================================================
// PORT-NOTE: FORWARD-REFERENCE TYPES for coord/axisCommonTypes.ts
// These TimeAxisLabelFormatter* aliases/types are exported by `coord/axisCommonTypes`
// upstream. coord/axisCommonTypes.swift is now ported, but these Time* types are still
// declared here (kept in time.swift); they could later be moved/reconciled into that file.
// ============================================================================

// upstream: AxisLabelTimeFormatter = (value, index, extra: TimeAxisLabelFormatterExtraParams) => string
public typealias AxisLabelTimeFormatter =
    (Double, Double, TimeAxisLabelFormatterExtraParams) -> String          // PORT-NOTE: axisCommonTypes type (kept here)
// upstream: TimeAxisLabelFormatterExtraParams = { time, level } & AxisLabelFormatterExtraParams
public struct TimeAxisLabelFormatterExtraParams {                           // PORT-NOTE: axisCommonTypes type (kept here)
    public var time: TimeScaleTickTime? // upstream: TimeScaleTick['time']
    /**
     * @deprecated Refactored to `time.level`, kept for backward compat.
     */
    public var level: Double
    // PORT-TODO: also intersects AxisLabelFormatterExtraParams (the break part); omitted
    //   until scale/break lands.
    public init(time: TimeScaleTickTime?, level: Double) {
        self.time = time
        self.level = level
    }
}
// upstream: TimeAxisLabelLeveledFormatterOption = string[] | string
public typealias TimeAxisLabelLeveledFormatterOption = Any                  // PORT-NOTE: [String] | String
// upstream: TimeAxisLabelFormatterUpperDictionaryOption = {[key in PrimaryTimeUnit]?: ...}
// upstream: TimeAxisLabelFormatterDictionaryOption = {[key in PrimaryTimeUnit]?: ...}
//   Modeled as the project dynamic option bag ([String: Any]) keyed by PrimaryTimeUnit.rawValue.
public typealias TimeAxisLabelFormatterDictionaryOption = [String: Any]     // PORT-NOTE: axisCommonTypes type (kept here)
// upstream: TimeAxisLabelFormatterOption = string | AxisLabelTimeFormatter | dictOption
public typealias TimeAxisLabelFormatterOption = Any                         // PORT-NOTE: union
// upstream: TimeAxisLabelFormatterParsed = string | AxisLabelTimeFormatter | dict
public typealias TimeAxisLabelFormatterParsed = Any                         // PORT-NOTE: union
// upstream: TimeAxisLabelFormatterUpperDictionary = {[key in PrimaryTimeUnit]: string[]}
public typealias TimeAxisLabelFormatterUpperDictionary = [PrimaryTimeUnit: [String]] // PORT-NOTE: axisCommonTypes type (kept here)
// upstream: TimeAxisLabelFormatterDictionary = {[key in PrimaryTimeUnit]: TimeAxisLabelFormatterUpperDictionary}
public typealias TimeAxisLabelFormatterDictionary = [PrimaryTimeUnit: TimeAxisLabelFormatterUpperDictionary] // PORT-NOTE: axisCommonTypes type (kept here)

// upstream: type JSDateGetterNames = 'getUTCFullYear' | 'getFullYear' | ...
// upstream: type JSDateSetterNames = 'setUTCFullYear' | 'setFullYear' | ...
//   The string-literal unions collapse to `String` (the getter/setter name functions below
//   return one of these literals; dynamic dispatch on `Date` is emulated by `jsDateGet`/`jsDateSet`).
public typealias JSDateGetterNames = String                                 // PORT-NOTE: string-literal union
public typealias JSDateSetterNames = String                                 // PORT-NOTE: string-literal union

// upstream `time.ts` (free functions) -> caseless enum namespace `time`.
// (upstream alias at call sites: `import * as timeUtil from '../util/time'`.)
public enum time {

    public static let ONE_SECOND: Double = 1000
    public static let ONE_MINUTE: Double = ONE_SECOND * 60
    public static let ONE_HOUR: Double = ONE_MINUTE * 60
    public static let ONE_DAY: Double = ONE_HOUR * 24
    public static let ONE_YEAR: Double = ONE_DAY * 365


    static let primaryTimeUnitFormatterMatchers: [PrimaryTimeUnit: NSRegularExpression] = [
        .year: try! NSRegularExpression(pattern: "(\\{yyyy\\}|\\{yy\\})"),
        .month: try! NSRegularExpression(pattern: "(\\{MMMM\\}|\\{MMM\\}|\\{MM\\}|\\{M\\})"),
        .day: try! NSRegularExpression(pattern: "(\\{dd\\}|\\{d\\})"),
        .hour: try! NSRegularExpression(pattern: "(\\{HH\\}|\\{H\\}|\\{hh\\}|\\{h\\})"),
        .minute: try! NSRegularExpression(pattern: "(\\{mm\\}|\\{m\\})"),
        .second: try! NSRegularExpression(pattern: "(\\{ss\\}|\\{s\\})"),
        .millisecond: try! NSRegularExpression(pattern: "(\\{SSS\\}|\\{S\\})"),
    ]

    static let defaultFormatterSeed: [PrimaryTimeUnit: String] = [
        .year: "{yyyy}",
        .month: "{MMM}",
        .day: "{d}",
        .hour: "{HH}:{mm}",
        .minute: "{HH}:{mm}",
        .second: "{HH}:{mm}:{ss}",
        .millisecond: "{HH}:{mm}:{ss} {SSS}",
    ]

    static let defaultFullFormatter = "{yyyy}-{MM}-{dd} {HH}:{mm}:{ss} {SSS}"
    static let fullDayFormatter = "{yyyy}-{MM}-{dd}"

    public static let fullLeveledFormatter: [PrimaryTimeUnit: String] = [
        .year: "{yyyy}",
        .month: "{yyyy}-{MM}",
        .day: fullDayFormatter,
        .hour: fullDayFormatter + " " + defaultFormatterSeed[.hour]!,
        .minute: fullDayFormatter + " " + defaultFormatterSeed[.minute]!,
        .second: fullDayFormatter + " " + defaultFormatterSeed[.second]!,
        .millisecond: defaultFullFormatter
    ]

    // upstream: export type PrimaryTimeUnit = (typeof primaryTimeUnits)[number];
    //   -> the `PrimaryTimeUnit` enum (declared at file scope below, since Swift enums cannot
    //      reference a top-level `enum`-nested type from sibling modules; see end of file).

    // Order must be ensured from big to small.
    public static let primaryTimeUnits: [PrimaryTimeUnit] = [
        .year, .month, .day, .hour, .minute, .second, .millisecond
    ]
    public static let timeUnits: [TimeUnit] = [
        .year, .halfYear, .quarter, .month, .week, .halfWeek, .day,
        .halfDay, .quarterDay, .hour, .minute, .second, .millisecond
    ]


    public static func parseTimeAxisLabelFormatter(
        _ formatter: TimeAxisLabelFormatterOption
    ) -> TimeAxisLabelFormatterParsed {
        // Keep the logic the same with function `leveledFormat`.
        // PORT-TODO: util.isFunction currently returns false (ZRenderKit limitation), so a
        //   closure formatter is not detected here and falls into the dictionary branch.
        return (!util.isString(formatter) && !util.isFunction(formatter))
            ? parseTimeAxisLabelFormatterDictionary(formatter as? TimeAxisLabelFormatterDictionaryOption)
            : formatter
    }

    /**
     * The final generated dictionary is like:
     *  generated_dict = {
     *      year: {
     *          year: ['{yyyy}', ...<higher_levels_if_any>]
     *      },
     *      month: {
     *          year: ['{yyyy} {MMM}', ...<higher_levels_if_any>],
     *          month: ['{MMM}', ...<higher_levels_if_any>]
     *      },
     *      day: {
     *          year: ['{yyyy} {MMM} {d}', ...<higher_levels_if_any>],
     *          month: ['{MMM} {d}', ...<higher_levels_if_any>],
     *          day: ['{d}', ...<higher_levels_if_any>]
     *      },
     *      ...
     *  }
     *
     * In echarts option, users can specify the entire dictionary or typically just:
     *  {formatter: {
     *      year: '{yyyy}', // Or an array of leveled templates: `['{yyyy}', '{bold1|{yyyy}}', ...]`,
     *                      // corresponding to `[level0, level1, level2, ...]`.
     *      month: '{MMM}',
     *      day: '{d}',
     *      hour: '{HH}:{mm}',
     *      second: '{HH}:{mm}',
     *      ...
     *  }}
     *  If any time unit is not specified in echarts option, the default template is used,
     *  such as `['{yyyy}', {primary|{yyyy}']`.
     *
     * The `tick.level` is only used to read string from each array, meaning the style type.
     *
     * Let `lowerUnit = getUnitFromValue(tick.value)`.
     * The non-break axis ticks only use `generated_dict[lowerUnit][lowerUnit][level]`.
     * The break axis ticks may use `generated_dict[lowerUnit][upperUnit][level]`, because:
     *  Consider the case: the non-break ticks are `16th, 23th, Feb, 7th, ...`, where `Feb` is in the break
     *  range and pruned by breaks, and the break ends might be in lower time unit than day. e.g., break start
     *  is `Jan 25th 18:00`(in unit `hour`) and break end is `Feb 6th 18:30` (in unit `minute`). Thus the break
     *  label prefers `Jan 25th 18:00` and `Feb 6th 18:30` rather than only `18:00` and `18:30`, otherwise it
     *  causes misleading.
     *  In this case, the tick of the break start and end will both be:
     *      `{level: 1, lowerTimeUnit: 'minute', upperTimeUnit: 'month'}`
     *  And get the final template by `generated_dict[lowerTimeUnit][upperTimeUnit][level]`.
     *  Note that the time unit can not be calculated directly by a single tick value, since the two breaks have
     *  to be at the same time unit to avoid awkward appearance. i.e., `Jan 25th 18:00` is in the time unit "hour"
     *  but we need it to be "minute", following `Feb 6th 18:30`.
     */
    static func parseTimeAxisLabelFormatterDictionary(
        _ dictOptionIn: TimeAxisLabelFormatterDictionaryOption?
    ) -> TimeAxisLabelFormatterDictionary {
        let dictOption = dictOptionIn ?? [:]
        var dict = TimeAxisLabelFormatterDictionary()

        // Currently if any template is specified by user, it may contain rich text tag,
        // such as `'{my_bold|{YYYY}}'`, thus we do add highlight style to it.
        // (Note that nested tag (`'{some|{some2|xxx}}'`) in rich text is not supported yet.)
        var canAddHighlight = true
        util.each(primaryTimeUnits) { lowestUnit, _ in
            canAddHighlight = canAddHighlight && (dictOption[lowestUnit.rawValue] == nil)
        }

        util.each(primaryTimeUnits) { lowestUnit, lowestUnitIdx in
            let upperDictOption = dictOption[lowestUnit.rawValue]
            dict[lowestUnit] = TimeAxisLabelFormatterUpperDictionary()

            var lowerTpl: String? = nil
            var upperUnitIdx = lowestUnitIdx
            while upperUnitIdx >= 0 {
                let upperUnit = primaryTimeUnits[upperUnitIdx]
                let upperDictItemOption: Any? =
                    (util.isObject(upperDictOption) && !util.isArray(upperDictOption))
                        ? (upperDictOption as? [String: Any])?[upperUnit.rawValue]
                        : upperDictOption

                var tplArr: [String]
                if util.isArray(upperDictItemOption) {
                    tplArr = (upperDictItemOption as! [String]) // slice()
                    lowerTpl = tplArr.first ?? "" // tplArr[0] || ''
                }
                else if util.isString(upperDictItemOption) {
                    lowerTpl = (upperDictItemOption as! String)
                    tplArr = [lowerTpl!]
                }
                else {
                    if lowerTpl == nil {
                        lowerTpl = defaultFormatterSeed[lowestUnit]
                    }
                    // Generate the dict by the rule as follows:
                    // If the user specify (or by default):
                    //  {formatter: {
                    //      year: '{yyyy}',
                    //      month: '{MMM}',
                    //      day: '{d}',
                    //      ...
                    //  }}
                    // Concat them to make the final dictionary:
                    //  {formatter: {
                    //      year: {year: ['{yyyy}']},
                    //      month: {year: ['{yyyy} {MMM}'], month: ['{MMM}']},
                    //      day: {year: ['{yyyy} {MMM} {d}'], month: ['{MMM} {d}'], day: ['{d}']}
                    //      ...
                    //  }}
                    // And then add `{primary|...}` to each array if from default template.
                    // This strategy is convinient for user configurating and works for most cases.
                    // If bad cases encountered, users can specify the entire dictionary themselves
                    // instead of going through this logic.
                    else if !test(primaryTimeUnitFormatterMatchers[upperUnit]!, lowerTpl!) {
                        lowerTpl = "\(dict[upperUnit]![upperUnit]![0]) \(lowerTpl!)"
                    }
                    tplArr = [lowerTpl!]
                    if canAddHighlight {
                        tplArr.append("{primary|\(lowerTpl!)}") // tplArr[1] = ...
                    }
                }
                dict[lowestUnit]![upperUnit] = tplArr
                upperUnitIdx -= 1
            }
        }
        return dict
    }

    public static func pad(_ str: String, _ len: Double) -> String {
        // upstream: str += ''; return '0000'.substr(0, len - str.length) + str;
        let count = Int(len) - str.count
        // '0000'.substr(0, n) -> "" if n <= 0, capped at the 4-char source string.
        let zeros = count > 0 ? String("0000".prefix(count)) : ""
        return zeros + str
    }

    // upstream `pad(str: string | number, len)` accepts numbers (`str += ''` stringifies them).
    public static func pad(_ str: Double, _ len: Double) -> String {
        return pad(numStr(str), len)
    }

    public static func getPrimaryTimeUnit(_ timeUnit: TimeUnit) -> PrimaryTimeUnit {
        switch timeUnit {
        case .halfYear:
            fallthrough
        case .quarter:
            return .month
        case .week:
            fallthrough
        case .halfWeek:
            return .day
        case .halfDay:
            fallthrough
        case .quarterDay:
            return .hour
        default:
            // year, minutes, second, milliseconds
            return PrimaryTimeUnit(rawValue: timeUnit.rawValue)!
        }
    }

    public static func isPrimaryTimeUnit(_ timeUnit: TimeUnit) -> Bool {
        return timeUnit.rawValue == getPrimaryTimeUnit(timeUnit).rawValue
    }

    public static func getDefaultFormatPrecisionOfInterval(_ timeUnit: PrimaryTimeUnit) -> PrimaryTimeUnit {
        switch timeUnit {
        case .year:
            fallthrough
        case .month:
            return .day
        case .millisecond:
            return .millisecond
        default:
            // Also for day, hour, minute, second
            return .second
        }
    }

    public static func format(
        // Note: The result based on `isUTC` are totally different, which can not be just simply
        // substituted by the result without `isUTC`. So we make the param `isUTC` mandatory.
        _ time: Any?, _ template: String?, _ isUTC: Bool, _ lang: Any? = nil
    ) -> String {
        let date = number.parseDate(time)
        let y = jsDateGet(date, fullYearGetterName(isUTC))
        let M = jsDateGet(date, monthGetterName(isUTC)) + 1
        let q = floor((M - 1) / 3) + 1
        let d = jsDateGet(date, dateGetterName(isUTC))
        let e = jsDateGet(date, "get" + (isUTC ? "UTC" : "") + "Day")
        let H = jsDateGet(date, hoursGetterName(isUTC))
        let h = (H - 1).truncatingRemainder(dividingBy: 12) + 1
        let m = jsDateGet(date, minutesGetterName(isUTC))
        let s = jsDateGet(date, secondsGetterName(isUTC))
        let S = jsDateGet(date, millisecondsGetterName(isUTC))
        let a = H >= 12 ? "pm" : "am"
        let A = a.uppercased()

        // PORT-TODO: locale Model (core/locale, model/Model) not ported yet. Upstream resolves
        //   month/monthAbbr/dayOfWeek/dayOfWeekAbbr from a locale model
        //   (`lang instanceof Model ? lang : getLocaleModel(lang || SYSTEM_LANG) || getDefaultLocaleModel()`).
        //   Until locale lands, fall back to the built-in English locale (i18n/langEN).
        _ = lang
        let month = _fallbackMonth
        let monthAbbr = _fallbackMonthAbbr
        let dayOfWeek = _fallbackDayOfWeek
        let dayOfWeekAbbr = _fallbackDayOfWeekAbbr

        return replaceAll(template ?? "", "{a}", a + "")
            |> { replaceAll($0, "{A}", A + "") }
            |> { replaceAll($0, "{yyyy}", numStr(y)) }
            |> { replaceAll($0, "{yy}", pad(y.truncatingRemainder(dividingBy: 100), 2)) }
            |> { replaceAll($0, "{Q}", numStr(q)) }
            |> { replaceAll($0, "{MMMM}", month[Int(M) - 1]) }
            |> { replaceAll($0, "{MMM}", monthAbbr[Int(M) - 1]) }
            |> { replaceAll($0, "{MM}", pad(M, 2)) }
            |> { replaceAll($0, "{M}", numStr(M)) }
            |> { replaceAll($0, "{dd}", pad(d, 2)) }
            |> { replaceAll($0, "{d}", numStr(d)) }
            |> { replaceAll($0, "{eeee}", dayOfWeek[Int(e)]) }
            |> { replaceAll($0, "{ee}", dayOfWeekAbbr[Int(e)]) }
            |> { replaceAll($0, "{e}", numStr(e)) }
            |> { replaceAll($0, "{HH}", pad(H, 2)) }
            |> { replaceAll($0, "{H}", numStr(H)) }
            |> { replaceAll($0, "{hh}", pad(h, 2)) }
            |> { replaceAll($0, "{h}", numStr(h)) }
            |> { replaceAll($0, "{mm}", pad(m, 2)) }
            |> { replaceAll($0, "{m}", numStr(m)) }
            |> { replaceAll($0, "{ss}", pad(s, 2)) }
            |> { replaceAll($0, "{s}", numStr(s)) }
            |> { replaceAll($0, "{SSS}", pad(S, 3)) }
            |> { replaceAll($0, "{S}", numStr(S)) }
    }

    public static func leveledFormat(
        _ tick: ScaleTick,
        _ idx: Double,
        _ formatter: TimeAxisLabelFormatterParsed,
        _ lang: Any?,
        _ isUTC: Bool
    ) -> String {
        var template: String? = nil
        if util.isString(formatter) {
            // Single formatter for all units at all levels
            template = (formatter as! String)
        }
        else if util.isFunction(formatter) {
            // PORT-TODO: util.isFunction currently returns false (ZRenderKit limitation), so this
            //   branch is effectively dead; closure formatters cannot be detected dynamically.
            let extra = TimeAxisLabelFormatterExtraParams(
                time: tick.time,
                level: tick.time != nil ? tick.time!.level : 0
            )
            // PORT-TODO: getScaleBreakHelper() (scale/break) not ported; the break-param
            //   enrichment is skipped (the helper would be nil here).
            // const scaleBreakHelper = getScaleBreakHelper();
            // if (scaleBreakHelper) {
            //     scaleBreakHelper.makeAxisLabelFormatterParamBreak(extra, tick.break);
            // }
            if let fn = formatter as? AxisLabelTimeFormatter {
                template = fn(tick.value, idx, extra)
            }
        }
        else {
            let tickTime = tick.time
            if let tickTime = tickTime {
                let leveledTplArr = (formatter as! TimeAxisLabelFormatterDictionary)[tickTime.lowerTimeUnit]![tickTime.upperTimeUnit]!
                template = leveledTplArr[Int(Swift.min(tickTime.level, Double(leveledTplArr.count - 1)))] // || ''
            }
            else {
                // tick may be from customTicks or timeline therefore no tick.time.
                let unit = getUnitFromValue(tick.value, isUTC)
                template = (formatter as! TimeAxisLabelFormatterDictionary)[unit]![unit]![0]
            }
        }

        // The default time templates wrap the primary unit in rich-text markup (`{primary|...}`) so it can
        //   be styled bold. The port's axis text does not render rich text, so it would show the raw
        //   `{primary|8}` markup. Strip the wrapper down to its plain content (non-nested, matching the
        //   upstream note that nested rich tags are unsupported).
        return stripTimeRichText(format(Date(timeIntervalSince1970: tick.value / 1000), template, isUTC, lang))
    }

    // `{tag|content}` → `content` (and `{content}` → `content`). Non-nested only.
    private static func stripTimeRichText(_ s: String) -> String {
        guard s.contains("{") else { return s }
        var result = ""
        var i = s.startIndex
        while i < s.endIndex {
            if s[i] == "{", let close = s[i...].firstIndex(of: "}") {
                let inner = s[s.index(after: i)..<close]
                if let bar = inner.firstIndex(of: "|") {
                    result += inner[inner.index(after: bar)...]
                }
                else {
                    result += inner
                }
                i = s.index(after: close)
                continue
            }
            result.append(s[i])
            i = s.index(after: i)
        }
        return result
    }

    public static func getUnitFromValue(
        _ value: Any?,
        _ isUTC: Bool
    ) -> PrimaryTimeUnit {
        let date = number.parseDate(value)
        let M = jsDateGet(date, monthGetterName(isUTC)) + 1
        let d = jsDateGet(date, dateGetterName(isUTC))
        let h = jsDateGet(date, hoursGetterName(isUTC))
        let m = jsDateGet(date, minutesGetterName(isUTC))
        let s = jsDateGet(date, secondsGetterName(isUTC))
        let S = jsDateGet(date, millisecondsGetterName(isUTC))

        let isSecond = S == 0
        let isMinute = isSecond && s == 0
        let isHour = isMinute && m == 0
        let isDay = isHour && h == 0
        let isMonth = isDay && d == 1
        let isYear = isMonth && M == 1

        if isYear {
            return .year
        }
        else if isMonth {
            return .month
        }
        else if isDay {
            return .day
        }
        else if isHour {
            return .hour
        }
        else if isMinute {
            return .minute
        }
        else if isSecond {
            return .second
        }
        else {
            return .millisecond
        }
    }

    // export function getUnitValue(
    //     value: number | Date,
    //     unit: TimeUnit,
    //     isUTC: boolean
    // ) : number {
    //     const date = zrUtil.isNumber(value)
    //         ? numberUtil.parseDate(value)
    //         : value;
    //     unit = unit || getUnitFromValue(value, isUTC);
    //
    //     switch (unit) {
    //         case 'year':
    //             return date[fullYearGetterName(isUTC)]();
    //         case 'half-year':
    //             return date[monthGetterName(isUTC)]() >= 6 ? 1 : 0;
    //         case 'quarter':
    //             return Math.floor((date[monthGetterName(isUTC)]() + 1) / 4);
    //         case 'month':
    //             return date[monthGetterName(isUTC)]();
    //         case 'day':
    //             return date[dateGetterName(isUTC)]();
    //         case 'half-day':
    //             return date[hoursGetterName(isUTC)]() / 24;
    //         case 'hour':
    //             return date[hoursGetterName(isUTC)]();
    //         case 'minute':
    //             return date[minutesGetterName(isUTC)]();
    //         case 'second':
    //             return date[secondsGetterName(isUTC)]();
    //         case 'millisecond':
    //             return date[millisecondsGetterName(isUTC)]();
    //     }
    // }

    /**
     * e.g.,
     * If timeUnit is 'year', return the Jan 1st 00:00:00 000 of that year.
     * If timeUnit is 'day', return the 00:00:00 000 of that day.
     *
     * @return The input date.
     */
    // CONVENTIONS §3: Swift `Date` is a value type; upstream mutates the `Date` in place AND
    //   returns it. The setter dispatch (`jsDateSet`) returns a new `Date`, so this reassigns a
    //   local `date` and returns it. The upstream `switch` deliberately omits `break` (cascading
    //   fallthrough) — replicated with Swift `fallthrough`.
    public static func roundTime(_ date: Date, _ timeUnit: PrimaryTimeUnit, _ isUTC: Bool) -> Date {
        var date = date
        switch timeUnit {
        case .year:
            date = jsDateSet(date, monthSetterName(isUTC), 0)
            fallthrough
        case .month:
            date = jsDateSet(date, dateSetterName(isUTC), 1)
            fallthrough
        case .day:
            date = jsDateSet(date, hoursSetterName(isUTC), 0)
            fallthrough
        case .hour:
            date = jsDateSet(date, minutesSetterName(isUTC), 0)
            fallthrough
        case .minute:
            date = jsDateSet(date, secondsSetterName(isUTC), 0)
            fallthrough
        case .second:
            date = jsDateSet(date, millisecondsSetterName(isUTC), 0)
        default:
            break
        }
        return date
    }

    public static func fullYearGetterName(_ isUTC: Bool) -> JSDateGetterNames {
        return isUTC ? "getUTCFullYear" : "getFullYear"
    }

    public static func monthGetterName(_ isUTC: Bool) -> JSDateGetterNames {
        return isUTC ? "getUTCMonth" : "getMonth"
    }

    public static func dateGetterName(_ isUTC: Bool) -> JSDateGetterNames {
        return isUTC ? "getUTCDate" : "getDate"
    }

    public static func hoursGetterName(_ isUTC: Bool) -> JSDateGetterNames {
        return isUTC ? "getUTCHours" : "getHours"
    }

    public static func minutesGetterName(_ isUTC: Bool) -> JSDateGetterNames {
        return isUTC ? "getUTCMinutes" : "getMinutes"
    }

    public static func secondsGetterName(_ isUTC: Bool) -> JSDateGetterNames {
        return isUTC ? "getUTCSeconds" : "getSeconds"
    }

    public static func millisecondsGetterName(_ isUTC: Bool) -> JSDateGetterNames {
        return isUTC ? "getUTCMilliseconds" : "getMilliseconds"
    }

    public static func fullYearSetterName(_ isUTC: Bool) -> JSDateSetterNames {
        return isUTC ? "setUTCFullYear" : "setFullYear"
    }

    public static func monthSetterName(_ isUTC: Bool) -> JSDateSetterNames {
        return isUTC ? "setUTCMonth" : "setMonth"
    }

    public static func dateSetterName(_ isUTC: Bool) -> JSDateSetterNames {
        return isUTC ? "setUTCDate" : "setDate"
    }

    public static func hoursSetterName(_ isUTC: Bool) -> JSDateSetterNames {
        return isUTC ? "setUTCHours" : "setHours"
    }

    public static func minutesSetterName(_ isUTC: Bool) -> JSDateSetterNames {
        return isUTC ? "setUTCMinutes" : "setMinutes"
    }

    public static func secondsSetterName(_ isUTC: Bool) -> JSDateSetterNames {
        return isUTC ? "setUTCSeconds" : "setSeconds"
    }

    public static func millisecondsSetterName(_ isUTC: Bool) -> JSDateSetterNames {
        return isUTC ? "setUTCMilliseconds" : "setMilliseconds"
    }

    // ---------------------------------------------------------------------------------------------
    // Private helpers — NOT part of upstream `time.ts`. Introduced to faithfully reproduce JS
    // behavior that has no direct Swift analogue:
    //   * `date[<getterName>]()` / `date[<setterName>](v)` — JS `Date` exposes string-named
    //     getters/setters dispatched dynamically; Swift `Date` does not, so we emulate via
    //     `Calendar` in the requested time zone (UTC vs local), matching JS field semantics
    //     (0-based month, Sunday=0 weekday, ms component).
    //   * `'' + x` / `String.prototype.replace(/.../g, ...)` numeric/string ops used by `format`.
    // ---------------------------------------------------------------------------------------------

    static func calendar(_ isUTC: Bool) -> Foundation.Calendar {
        var cal = Foundation.Calendar(identifier: .gregorian)
        cal.timeZone = isUTC ? TimeZone(identifier: "UTC")! : TimeZone.current
        return cal
    }

    // Emulates `date[getterName]()` returning the JS field value as a Double.
    static func jsDateGet(_ date: Date, _ getterName: String) -> Double {
        let isUTC = getterName.hasPrefix("getUTC")
        let cal = calendar(isUTC)
        let c = cal.dateComponents(
            [.year, .month, .day, .hour, .minute, .second, .nanosecond, .weekday], from: date
        )
        switch getterName {
        case "getUTCFullYear", "getFullYear": return Double(c.year ?? 0)
        case "getUTCMonth", "getMonth": return Double((c.month ?? 1) - 1) // JS month is 0-based
        case "getUTCDate", "getDate": return Double(c.day ?? 1)
        case "getUTCDay", "getDay": return Double((c.weekday ?? 1) - 1)   // JS Sunday=0; Calendar Sunday=1
        case "getUTCHours", "getHours": return Double(c.hour ?? 0)
        case "getUTCMinutes", "getMinutes": return Double(c.minute ?? 0)
        case "getUTCSeconds", "getSeconds": return Double(c.second ?? 0)
        case "getUTCMilliseconds", "getMilliseconds": return Double((c.nanosecond ?? 0) / 1_000_000)
        default: return Double.nan
        }
    }

    // Emulates `date[setterName](value)` returning the resulting `Date`.
    static func jsDateSet(_ date: Date, _ setterName: String, _ value: Double) -> Date {
        let isUTC = setterName.hasPrefix("setUTC")
        let cal = calendar(isUTC)
        var c = cal.dateComponents(
            [.year, .month, .day, .hour, .minute, .second, .nanosecond], from: date
        )
        switch setterName {
        case "setUTCFullYear", "setFullYear": c.year = Int(value)
        case "setUTCMonth", "setMonth": c.month = Int(value) + 1 // JS month is 0-based
        case "setUTCDate", "setDate": c.day = Int(value)
        case "setUTCHours", "setHours": c.hour = Int(value)
        case "setUTCMinutes", "setMinutes": c.minute = Int(value)
        case "setUTCSeconds", "setSeconds": c.second = Int(value)
        case "setUTCMilliseconds", "setMilliseconds": c.nanosecond = Int(value) * 1_000_000
        default: break
        }
        return cal.date(from: c) ?? date
    }

    // JS `'' + x` for the integer-valued date fields used by `format`/`pad`.
    static func numStr(_ x: Double) -> String {
        if x == x.rounded() && x.isFinite {
            return String(Int(x))
        }
        return String(x)
    }

    // JS `String.prototype.replace(/{token}/g, replacement)` — replace all literal occurrences.
    static func replaceAll(_ s: String, _ token: String, _ replacement: String) -> String {
        return s.replacingOccurrences(of: token, with: replacement)
    }

    // `NSRegularExpression.test(str)` (JS `regex.test(str)`).
    static func test(_ re: NSRegularExpression, _ s: String) -> Bool {
        return re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
    }

    // PORT-TODO: locale fallback (i18n/langEN `time`), see `format`.
    static let _fallbackMonth = [
        "January", "February", "March", "April", "May", "June",
        "July", "August", "September", "October", "November", "December"
    ]
    static let _fallbackMonthAbbr = [
        "Jan", "Feb", "Mar", "Apr", "May", "Jun",
        "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"
    ]
    static let _fallbackDayOfWeek = [
        "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"
    ]
    static let _fallbackDayOfWeekAbbr = [
        "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"
    ]
}

// Pipe operator — NOT part of upstream. Used only to keep `format`'s long `.replace(...)` chain
// readable and line-aligned with upstream (Swift's `String.replacingOccurrences` is not chainable
// like JS `String.prototype.replace`).
infix operator |>: AdditionPrecedence
@inline(__always)
func |> (_ value: String, _ transform: (String) -> String) -> String {
    return transform(value)
}

// upstream: export type PrimaryTimeUnit = (typeof primaryTimeUnits)[number];
//   The 7 primary time unit string literals, big to small.
//   (Defined at file scope, not nested in `enum time`, because sibling files reference it bare,
//    e.g. types.swift `TimeScaleTickTime.upperTimeUnit: PrimaryTimeUnit`.)
public enum PrimaryTimeUnit: String {
    case year
    case month
    case day
    case hour
    case minute
    case second
    case millisecond
}

// upstream: export type TimeUnit = (typeof timeUnits)[number];
//   The full ordered list of time units (big to small), including non-primary ones.
public enum TimeUnit: String {
    case year
    case halfYear = "half-year"
    case quarter
    case month
    case week
    case halfWeek = "half-week"
    case day
    case halfDay = "half-day"
    case quarterDay = "quarter-day"
    case hour
    case minute
    case second
    case millisecond
}
