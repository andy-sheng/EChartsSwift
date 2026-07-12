// Ported from echarts/src/util/number.ts — keep in sync with upstream
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
* The method "quantile" was copied from "d3.js".
* (See more details in the comment of the method below.)
* The use of the source code of this file is also subject to the terms
* and consitions of the license of "d3.js" (BSD-3Clause, see
* </licenses/LICENSE-d3>).
*/

import Foundation
import ZRenderKit

// upstream: `import * as zrUtil from 'zrender/src/core/util'` -> ZRenderKit.util
// upstream: `import { NullUndefined } from './types'` -> Optional (see CONVENTIONS §6);
//           ported sibling `types.swift` is expected to expose `NullUndefined` but in
//           Swift `number | NullUndefined` collapses to `Double?`.

// upstream module `number.ts` (free functions) -> caseless enum namespace `number`.
public enum number {

    static let RADIAN_EPSILON = 1e-4

    // A `RangeError` may be thrown if `n` is out of this range when calling `toFixed(n)`.
    // Although Chrome and ES2017+ have enlarged this number to 100, but we sill follow
    // the ES3~ES6 spec (0 <= n <= 20) for backward and cross-platform compatibility.
    static let TO_FIXED_SUPPORTED_PRECISION_MAX: Double = 20

    // For rounding error like `2.9999999999999996`, with respect to IEEE754 64bit float.
    // NOTICE: It only works when the expected result is a rational number with low
    // precision. See method `round` for details.
    public static let DEFAULT_PRECISION_FOR_ROUNDING_ERROR: Double = 14

    static func _trim(_ str: String) -> String {
        // upstream: str.replace(/^\s+|\s+$/g, '')
        return str.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func mathMin(_ a: Double, _ b: Double) -> Double { Swift.min(a, b) }
    public static func mathMax(_ a: Double, _ b: Double) -> Double { Swift.max(a, b) }
    public static func mathAbs(_ a: Double) -> Double { Swift.abs(a) }
    // JS `Math.round` rounds half up (toward +Infinity); replicate via floor(x + 0.5).
    public static func mathRound(_ a: Double) -> Double { floor(a + 0.5) }
    public static func mathFloor(_ a: Double) -> Double { floor(a) }
    public static func mathCeil(_ a: Double) -> Double { ceil(a) }
    public static func mathPow(_ a: Double, _ b: Double) -> Double { pow(a, b) }
    public static func mathLog(_ a: Double) -> Double { Foundation.log(a) }
    public static let mathLN10: Double = M_LN10
    public static let mathPI: Double = Double.pi
    public static func mathRandom() -> Double { Double.random(in: 0..<1) }

    /**
     * Linear mapping a value from domain to range
     * @param  val
     * @param  domain Domain extent domain[0] can be bigger than domain[1]
     * @param  range  Range extent range[0] can be bigger than range[1]
     * @param  clamp Default to be false
     */
    public static func linearMap(
        _ val: Double,
        _ domain: [Double],
        _ range: [Double],
        _ clamp: Bool? = nil
    ) -> Double {
        let d0 = domain[0]
        let d1 = domain[1]
        let r0 = range[0]
        let r1 = range[1]

        let subDomain = d1 - d0
        let subRange = r1 - r0

        if subDomain == 0 {
            return subRange == 0
                ? r0
                : (r0 + r1) / 2
        }

        // Avoid accuracy problem in edge, such as
        // 146.39 - 62.83 === 83.55999999999999.
        // See echarts/test/ut/spec/util/number.js#linearMap#accuracyError
        // It is a little verbose for efficiency considering this method
        // is a hotspot.
        if clamp == true {
            if subDomain > 0 {
                if val <= d0 {
                    return r0
                }
                else if val >= d1 {
                    return r1
                }
            }
            else {
                if val >= d0 {
                    return r0
                }
                else if val <= d1 {
                    return r1
                }
            }
        }
        else {
            if val == d0 {
                return r0
            }
            if val == d1 {
                return r1
            }
        }

        return (val - d0) / subDomain * subRange + r0
    }

    /**
     * Preserve the name `parsePercent` for backward compatibility,
     * and it's effectively published as `echarts.number.parsePercent`.
     */
    public static func parsePercent(_ option: Any?, _ percentBase: Double, _ percentOffset: Double? = nil) -> Double {
        return parsePositionOption(option, percentBase, percentOffset)
    }

    /**
     * @see {parsePositionSizeOption} and also accept a string preset.
     * @see {PositionSizeOption}
     */
    public static func parsePositionOption(
        _ option: Any?,
        _ percentBase: Double,
        _ percentOffset: Double? = nil
    ) -> Double {
        var option = option
        switch option as? String {
        case "center", "middle":
            option = "50%"
        case "left", "top":
            option = "0%"
        case "right", "bottom":
            option = "100%"
        default:
            break
        }
        return parsePositionSizeOption(option, percentBase, percentOffset)
    }

    /**
     * Accept number, or numeric string (`'123'`), or percentage ('100%'), as x/y/width/height pixel number.
     * If null/undefined or invalid, return NaN.
     * (But allow JS type coercion (`+option`) due to backward compatibility)
     * @see {PositionSizeOption}
     */
    public static func parsePositionSizeOption(
        _ option: Any?,
        _ percentBase: Double,
        // Typical usage of `percentOffset`: percent value is based on an specific rect rather than canvas viewport:
        //  `parsePercent(percentOrAbsoluteLeft, rect.width, rect.x)`
        _ percentOffset: Double? = nil
    ) -> Double {
        if util.isString(option) {
            let str = option as! String
            if isOptionStringPercent(str) {
                return parseFloatLeading(str) / 100 * percentBase + or(percentOffset, 0)
            }
            return parseFloatLeading(str)
        }
        // Allow flexible input due to backward compatibility.
        return option == nil ? Double.nan : numberCoerce(option)
    }

    /**
     * Perserve the same rule with `parsePositionSizeOption`.
     */
    public static func isPositionSizeOptionPercent(_ option: Any?) -> Bool {
        return util.isString(option) && isOptionStringPercent(option as! String)
    }

    static func isOptionStringPercent(_ option: String) -> Bool {
        // upstream: !!_trim(option).match(/%$/)
        return _trim(option).hasSuffix("%")
    }

    /**
     * [Feature_1] Round at specified precision.
     *  FIXME: this is not a general-purpose rounding implementation yet due to `TO_FIXED_SUPPORTED_PRECISION_MAX`.
     *  e.g., `round(1.25 * 1e-150, 151)` has no overflow in IEEE754 64bit float, but can not be handled by
     *  this method.
     *
     * [Feature_2] Support return string to avoid scientific notation like '3.5e-7'.
     *
     * [Feature_3] Fix rounding error of float numbers !!!ONLY SUITABLE FOR SPECIAL CASES!!!.
     *  [CAVEAT]:
     *      Rounding is NEVER a general-purpose solution for rounding errors.
     *      Consider a case: `expect=123.99994999`, `actual=123.99995000` (suppose rounding error occurs).
     *          Calling `round(expect, 4)` gets `123.9999`.
     *          Calling `round(actual, 4)` gets `124.0000`.
     *          A unacceptable result arises, even if the original difference is only `0.00000001` (tiny
     *          and not strongly correlated with the digit pattern).
     *      So the rounding approach works only if:
     *          The digit next to the `precision` won't cross the rounding boundary. Typically, it works if
     *          the digit next to the `precision` is expected to be `0`, and the rounding error is small
     *          enough and impossible to affect that digit (`roundingError < Math.pow(10, -precision) / 2`).
     *      The quantity of a rounding error can be roughly estimated by formula:
     *          `minPrecisionRoundingErrorMayOccur ~= max(0, floor(14 - quantityExponent(val)))`
     *          MEMO: This is derived from:
     *              Let ` EXP52B10 = log10(pow(2, 52)) = 15.65355977452702 `
     *                  (`52` is IEEE754 float64 mantissa bits count)
     *              We require: ` abs(val) * pow(10, precision) < pow(10, EXP52B10) `
     *              Hence: ` precision < EXP52B10 - log10(abs(val)) `
     *              Hence: ` precision = floor( EXP52B10 - log10(abs(val)) ) `
     *              Since: ` quantityExponent(val) = floor(log10(abs(val))) `
     *              Hence: ` precision ~= floor(EXP52B10 - 1 - quantityExponent(val))
     */
    // PORT-NOTE: upstream `round(x, precision, returnStr)` overloads vary the return type by the
    //  runtime boolean `returnStr`, which Swift cannot express. They are split into `round` (->Double,
    //  returnStr omitted/false) and `roundStr` (->String, returnStr: true). Call sites
    //  `round(x, p, true)` become `roundStr(x, p)`.
    public static func round(_ x: Double, _ precision: Double) -> Double {
        // __DEV__: zrUtil.assert(precision != null) — precision is non-optional in Swift, so dropped.
        if precision.isNaN {
            // precision utils (such as getAcceptableTickPrecision) may return NaN.
            return x
        }
        // Avoid range error
        let precision = mathMin(mathMax(0, precision), TO_FIXED_SUPPORTED_PRECISION_MAX)
        // PENDING: 1.005.toFixed(2) is '1.00' rather than '1.01'
        let str = String(format: "%.\(Int(precision))f", x)
        return numberCoerce(str)
    }

    public static func round(_ x: String, _ precision: Double) -> Double {
        return round(numberCoerce(x), precision)
    }

    public static func roundStr(_ x: Double, _ precision: Double) -> String {
        if precision.isNaN {
            return jsNumberString(x)
        }
        let precision = mathMin(mathMax(0, precision), TO_FIXED_SUPPORTED_PRECISION_MAX)
        return String(format: "%.\(Int(precision))f", x)
    }

    public static func roundStr(_ x: String, _ precision: Double) -> String {
        return roundStr(numberCoerce(x), precision)
    }

    public static func roundLegacy(_ x: Double, _ precision: Double? = nil) -> Double {
        let precision = precision ?? 10
        return round(x, precision)
    }

    public static func roundLegacy(_ x: String, _ precision: Double? = nil) -> Double {
        return roundLegacy(numberCoerce(x), precision)
    }

    public static func roundLegacyStr(_ x: Double, _ precision: Double? = nil) -> String {
        let precision = precision ?? 10
        return roundStr(x, precision)
    }

    public static func roundLegacyStr(_ x: String, _ precision: Double? = nil) -> String {
        return roundLegacyStr(numberCoerce(x), precision)
    }

    /**
     * Inplacd asc sort arr.
     * The input arr will be modified.
     */
    // CONVENTIONS §3: value-returning (Swift `Array` is a value type; upstream mutates in place
    //  AND returns). Call sites `asc(arr)` become `arr = number.asc(arr)`.
    public static func asc(_ arr: [Double]) -> [Double] {
        var arr = arr
        arr.sort { a, b in
            a - b < 0
        }
        return arr
    }

    /**
     * Get precision.
     * e.g. `getPrecisionSafe(100.123)` return `3`.
     * e.g. `getPrecisionSafe(100)` return `0`.
     */
    public static func getPrecision(_ val: Any?) -> Double {
        let val = numberCoerce(val)
        if val.isNaN {
            return 0
        }

        // It is much faster than methods converting number to string as follows
        //      let tmp = val.toString();
        //      return tmp.length - 1 - tmp.indexOf('.');
        // especially when precision is low
        // Notice:
        // (1) If the loop count is over about 20, it is slower than `getPrecisionSafe`.
        //     (see https://jsbench.me/2vkpcekkvw/1)
        // (2) If the val is less than for example 1e-15, the result may be incorrect.
        //     (see test/ut/spec/util/number.test.ts `getPrecision_equal_random`)
        if val > 1e-14 {
            var e = 1.0
            var i = 0
            while i < 15 {
                if mathRound(val * e) / e == val {
                    return Double(i)
                }
                i += 1
                e *= 10
            }
        }

        return getPrecisionSafe(val)
    }

    /**
     * Get precision with slow but safe method
     * e.g. `getPrecisionSafe(100.123)` return `3`.
     * e.g. `getPrecisionSafe(100)` return `0`.
     */
    public static func getPrecisionSafe(_ val: Any?) -> Double {
        // toLowerCase for: '3.4E-12'
        // POTENTIAL-BUG: JS `Number.prototype.toString` uses a different scientific-notation threshold
        //  and exponent format than `jsNumberString`; tiny/huge magnitudes may diverge here.
        let str = jsNumberString(numberCoerce(val)).lowercased()

        // Consider scientific notation: '3.4e-12' '3.4e+12'
        let eIndex = indexOf(str, "e")
        let exp = eIndex > 0 ? numberCoerce(slice(str, eIndex + 1, nil)) : 0
        let significandPartLen = eIndex > 0 ? Double(eIndex) : Double(str.count)
        let dotIndex = indexOf(str, ".")
        let decimalPartLen = dotIndex < 0 ? 0 : significandPartLen - 1 - Double(dotIndex)
        return mathMax(0, decimalPartLen - exp)
    }

    /**
     * @deprecated Use `getAcceptableTickPrecision` instead. See bad case in `test/ut/spec/util/number.test.ts`
     * NOTE: originally introduced in commit `ff93e3e7f9ff24902e10d4469fd3187393b05feb`
     *
     * Minimal discernible data precision according to a single pixel.
     */
    public static func getPixelPrecision(_ dataExtent: (Double, Double), _ pixelExtent: (Double, Double)) -> Double {
        let dataQuantity = mathFloor(mathLog(dataExtent.1 - dataExtent.0) / mathLN10)
        let sizeQuantity = mathRound(mathLog(mathAbs(pixelExtent.1 - pixelExtent.0)) / mathLN10)
        // toFixed() digits argument must be between 0 and 20.
        let precision = mathMin(mathMax(-dataQuantity + sizeQuantity, 0), TO_FIXED_SUPPORTED_PRECISION_MAX)
        return !precision.isFinite ? TO_FIXED_SUPPORTED_PRECISION_MAX : precision
    }

    /**
     * This method chooses a reasonable "data" precision that can be used in `round` method.
     * A reasonable precision is suitable for display; it may cause cumulative error but acceptable.
     *
     * "data" is linearly mapped to pixel according to the ratio determined by `dataSpan` and `pxSpan`.
     * The diff from the original "data" to the rounded "data" (with the result precision) should be
     * equal or less than `pxDiffAcceptable`, which is typically `1` pixel.
     * And the result precision should be as small as possible for a concise display.
     *
     * [NOTICE]: using arbitrary parameters is NOT preferable - a discernible misalign (e.g., over 1px)
     *  may occur, especially when `splitLine` is displayed.
     *
     * PENDING: Only the linear case is addressed for now; other mapping methods (like logarithm) will
     *  not be covered until necessary.
     */
    public static func getAcceptableTickPrecision(
        _ dataExtent: [Double],
        // Typically, `Math.abs(pixelExtent[1] - pixelExtent[0])`.
        _ pxSpan: Double,
        // By default, `1`.
        _ pxDiffAcceptable: Double?
        // Return a precision >= 0
        // This precision can be used in method `round`.
        // Return `NaN` for edge case or illegal inputs. Callers need to handle that.
    ) -> Double {
        let dataSpan = mathAbs(dataExtent[1] - dataExtent[0])
        if !dataSpan.isFinite || dataSpan == 0 {
            return Double.nan
        }
        // Formula for choosing an acceptable precision:
        //  Let `pxDiff = abs(dataSpan - round(dataSpan, precision))`.
        //  We require `pxDiff <= dataSpan * pxDiffAcceptable / pxSpan`.
        //  Consider the nature of "round", the max `pxDiff` is: `pow(10, -precision) / 2`,
        //  Hence: `pow(10, -precision) / 2 <= dataSpan * pxDiffAcceptable / pxSpan`
        //  Hence: `precision >= -log10(2 * dataSpan * pxDiffAcceptable / pxSpan)`
        let dataExp2 = mathLog(2 * mathAbs(or(pxDiffAcceptable, 1)) * mathAbs(dataSpan)) / mathLN10
        let pxExp = mathLog(mathAbs(pxSpan)) / mathLN10
        // PENDING: Rounding error generally does not matter; do not fix it before `Math.ceil`
        // until bad case occur.
        var precision = mathMax(0, mathCeil(-dataExp2 + pxExp))
        if !precision.isFinite {
            // If dataSpan is near `0`, the result should not be too big or even `Infinity`.
            precision = Double.nan
        }
        return precision
    }

    /**
     * Get a data of given precision, assuring the sum of percentages
     * in valueList is 1.
     * The largest remainder method is used.
     * https://en.wikipedia.org/wiki/Largest_remainder_method
     *
     * @param valueList a list of all data
     * @param idx index of the data to be processed in valueList
     * @param precision integer number showing digits of precision
     * @return percent ranging from 0 to 100
     */
    public static func getPercentWithPrecision(_ valueList: [Double], _ idx: Int, _ precision: Double) -> Double {
        // upstream: if (!valueList[idx]) — JS falsy (0, NaN, undefined).
        if idx >= valueList.count || valueList[idx] == 0 || valueList[idx].isNaN {
            return 0
        }

        let seats = getPercentSeats(valueList, precision)

        return or(idx < seats.count ? seats[idx] : Double.nan, 0)
    }

    /**
     * Get a data of given precision, assuring the sum of percentages
     * in valueList is 1.
     * The largest remainder method is used.
     * https://en.wikipedia.org/wiki/Largest_remainder_method
     *
     * @param valueList a list of all data
     * @param precision integer number showing digits of precision
     * @return {Array<number>}
     */
    public static func getPercentSeats(_ valueList: [Double], _ precision: Double) -> [Double] {
        let sum = util.reduce(valueList, { (acc: Double, val: Double, _: Int) in
            return acc + (val.isNaN ? 0 : val)
        }, 0)
        if sum == 0 {
            return []
        }

        let digits = mathPow(10, precision)
        let votesPerQuota = util.map(valueList, { (val: Double, _: Int) in
            return (val.isNaN ? 0 : val) / sum * digits * 100
        })
        let targetSeats = digits * 100

        var seats = util.map(votesPerQuota, { (votes: Double, _: Int) in
            // Assign automatic seats.
            return mathFloor(votes)
        })
        var currentSum = util.reduce(seats, { (acc: Double, val: Double, _: Int) in
            return acc + val
        }, 0)

        var remainder = util.map(votesPerQuota, { (votes: Double, idx: Int) in
            return votes - seats[idx]
        })

        // Has remainding votes.
        while currentSum < targetSeats {
            // Find next largest remainder.
            var max = -Double.infinity
            var maxId: Int! = nil
            var i = 0
            let len = remainder.count
            while i < len {
                if remainder[i] > max {
                    max = remainder[i]
                    maxId = i
                }
                i += 1
            }

            // Add a vote to max remainder.
            seats[maxId] += 1
            remainder[maxId] = 0
            currentSum += 1
        }
        return util.map(seats, { (seat: Double, _: Int) in
            return seat / digits
        })
    }

    /**
     * Solve the floating point adding problem like 0.1 + 0.2 === 0.30000000000000004
     * See <http://0.30000000000000004.com/>
     */
    public static func addSafe(_ val0: Double, _ val1: Double) -> Double {
        let maxPrecision = mathMax(getPrecision(val0), getPrecision(val1))
        // const multiplier = Math.pow(10, maxPrecision);
        // return (mathRound(val0 * multiplier) + mathRound(val1 * multiplier)) / multiplier;
        let sum = val0 + val1
        // // PENDING: support more?
        return maxPrecision > TO_FIXED_SUPPORTED_PRECISION_MAX
            ? sum : round(sum, maxPrecision)
    }

    // Number.MAX_SAFE_INTEGER, ie do not support.
    public static let MAX_SAFE_INTEGER: Double = mathPow(2, 53) - 1

    /**
     * To 0 - 2 * PI, considering negative radian.
     */
    public static func remRadian(_ radian: Double) -> Double {
        let pi2 = mathPI * 2
        return (radian.truncatingRemainder(dividingBy: pi2) + pi2).truncatingRemainder(dividingBy: pi2)
    }

    /**
     * @param {type} radian
     * @return {boolean}
     */
    public static func isRadianAroundZero(_ val: Double) -> Bool {
        return val > -RADIAN_EPSILON && val < RADIAN_EPSILON
    }

    // eslint-disable-next-line
    static let TIME_REG_PATTERN =
        "^(?:(\\d{4})(?:[-/](\\d{1,2})(?:[-/](\\d{1,2})(?:[T ](\\d{1,2})(?::(\\d{1,2})(?::(\\d{1,2})(?:[.,](\\d+))?)?)?(Z|[+-]\\d\\d:?\\d\\d)?)?)?)?)?$"
    static let TIME_REG = try! NSRegularExpression(pattern: TIME_REG_PATTERN)

    // upstream: `new Date(NaN)` — an Invalid Date. Swift `Date` wraps a `Double`, so NaN is storable.
    static var invalidDate: Date { Date(timeIntervalSince1970: Double.nan) }

    /**
     * @param value valid type: number | string | Date, otherwise return `new Date(NaN)`
     *   These values can be accepted:
     *   + An instance of Date, represent a time in its own time zone.
     *   + Or string in a subset of ISO 8601, only including:
     *     + only year, month, date: '2012-03', '2012-03-01', '2012-03-01 05', '2012-03-01 05:06',
     *     + separated with T or space: '2012-03-01T12:22:33.123', '2012-03-01 12:22:33.123',
     *     + time zone: '2012-03-01T12:22:33Z', '2012-03-01T12:22:33+8000', '2012-03-01T12:22:33-05:00',
     *     all of which will be treated as local time if time zone is not specified
     *     (see <https://momentjs.com/>).
     *   + Or other string format, including (all of which will be treated as local time):
     *     '2012', '2012-3-1', '2012/3/1', '2012/03/01',
     *     '2009/6/12 2:00', '2009/6/12 2:05:08', '2009/6/12 2:05:08.123'
     *   + a timestamp, which represent a time in UTC.
     * @return date Never be null/undefined. If invalid, return `new Date(NaN)`.
     */
    public static func parseDate(_ value: Any?) -> Date {
        if let date = value as? Date {
            return date
        }
        else if util.isString(value) {
            let value = value as! String
            // Different browsers parse date in different way, so we parse it manually.
            // Some other issues:
            // new Date('1970-01-01') is UTC,
            // new Date('1970/01/01') and new Date('1970-1-01') is local.
            // See issue #3623
            let ns = value as NSString
            guard let m = TIME_REG.firstMatch(
                in: value, range: NSRange(location: 0, length: ns.length)
            ) else {
                // return Invalid Date.
                return invalidDate
            }

            func match(_ i: Int) -> String? {
                let r = m.range(at: i)
                return r.location == NSNotFound ? nil : ns.substring(with: r)
            }

            // Use local time when no timezone offset is specified.
            if match(8) == nil {
                // match[n] can only be string or undefined.
                // But take care of '12' + 1 => '121'.
                return makeDate(
                    timeZone: TimeZone.current,
                    plusOp(match(1)),
                    (match(2) != nil ? jsNumber(match(2)!) : 1) - 1,
                    or(plusOp(match(3)), 1),
                    or(plusOp(match(4)), 0),
                    (match(5) != nil ? jsNumber(match(5)!) : 0),
                    or(plusOp(match(6)), 0),
                    match(7) != nil ? plusOp(substring(match(7)!, 0, 3)) : 0
                )
            }
            // Timezoneoffset of Javascript Date has considered DST (Daylight Saving Time,
            // https://tc39.github.io/ecma262/#sec-daylight-saving-time-adjustment).
            // For example, system timezone is set as "Time Zone: America/Toronto",
            // then these code will get different result:
            // `new Date(1478411999999).getTimezoneOffset();  // get 240`
            // `new Date(1478412000000).getTimezoneOffset();  // get 300`
            // So we should not use `new Date`, but use `Date.UTC`.
            else {
                let m8 = match(8)!
                var hour = or(plusOp(match(4)), 0)
                if m8.uppercased() != "Z" {
                    hour -= plusOp(slice(m8, 0, 3))
                }
                return makeDate(
                    timeZone: TimeZone(identifier: "UTC")!,
                    plusOp(match(1)),
                    (match(2) != nil ? jsNumber(match(2)!) : 1) - 1,
                    or(plusOp(match(3)), 1),
                    hour,
                    (match(5) != nil ? jsNumber(match(5)!) : 0),
                    or(plusOp(match(6)), 0),
                    match(7) != nil ? plusOp(substring(match(7)!, 0, 3)) : 0
                )
            }
        }
        else if value == nil {
            return invalidDate
        }

        let n = numberCoerce(value)
        if n.isNaN {
            return invalidDate
        }
        return Date(timeIntervalSince1970: mathRound(n) / 1000)
    }

    // Helper to mirror `new Date(year, monthZeroBased, day, hour, min, sec, ms)` and
    // `new Date(Date.UTC(...))`. `month` is zero-based as in JS; `DateComponents.month` is 1-based.
    static func makeDate(
        timeZone: TimeZone,
        _ year: Double,
        _ monthZeroBased: Double,
        _ day: Double,
        _ hour: Double,
        _ minute: Double,
        _ second: Double,
        _ millisecond: Double
    ) -> Date {
        var cal = Foundation.Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        var comps = DateComponents()
        comps.year = Int(year)
        comps.month = Int(monthZeroBased) + 1
        comps.day = Int(day)
        comps.hour = Int(hour)
        comps.minute = Int(minute)
        comps.second = Int(second)
        comps.nanosecond = Int(millisecond * 1_000_000)
        return cal.date(from: comps) ?? invalidDate
    }

    /**
     * Quantity of a number. e.g. 0.1, 1, 10, 100
     *
     * @param val
     * @return
     */
    public static func quantity(_ val: Double) -> Double {
        return mathPow(10, quantityExponent(val))
    }

    /**
     * Exponent of the quantity of a number
     * e.g., 9876 equals to 9.876*10^3, so quantityExponent(9876) is 3
     * e.g., 0.09876 equals to 9.876*10^-2, so quantityExponent(0.09876) is -2
     *
     * @param val non-negative value
     * @return
     */
    public static func quantityExponent(_ val: Double) -> Double {
        if val == 0 {
            // PENDING: like IEEE754 use exponent `0` in this case.
            // but methematically, exponent of zero is `-Infinity`.
            return 0
        }

        var exp = mathFloor(mathLog(val) / mathLN10)
        /**
         * exp is expected to be the rounded-down result of the base-10 log of val.
         * But due to the precision loss with Math.log(val), we need to restore it
         * using 10^exp to make sure we can get val back from exp. #11249
         */
        if val / mathPow(10, exp) >= 10 {
            exp += 1
        }
        return exp
    }

    public static let NICE_MODE_ROUND: Double = 1
    public static let NICE_MODE_MIN: Double = 2

    /**
     * find a “nice” number approximately equal to x. Round the number if 'round',
     * take ceiling if 'round'. The primary observation is that the “nicest”
     * numbers in decimal are 1, 2, and 5, and all power-of-ten multiples of these numbers.
     *
     * See "Nice Numbers for Graph Labels" of Graphic Gems.
     *
     * @param  val Non-negative value.
     * @return Niced number
     */
    // upstream `mode`: boolean | NICE_MODE_ROUND | NICE_MODE_MIN. Ported as a small enum-ish
    //  parameter modeled by `NiceMode`; any non-`NICE_MODE_MIN`-truthy value means round.
    public enum NiceMode {
        case none           // undefined / false (falsy) -> NICE_MODE_MIN path is NOT taken, `else if (mode)` false
        case round          // truthy / NICE_MODE_ROUND
        case min            // NICE_MODE_MIN
    }

    public static func nice(
        _ val: Double,
        // All non-`NICE_MODE_MIN`-truthy values means `NICE_MODE_ROUND`, for backward compatibility.
        _ mode: NiceMode = .none
    ) -> Double {
        // Consider the scientific notation of `val`:
        //  - `exponent` is its exponent.
        //  - `f` is its coefficient. `1 <= f < 10`.
        //  e.g., if `val` is `0.0054321`, `exponent` is `-3`, `f` is `5.4321`,
        //      The result is `0.005` on NICE_MODE_ROUND.
        //  e.g., if `val` is `987.12345`, `exponent` is `2`, `f` is `9.8712345`,
        //      The result is `1000` on NICE_MODE_ROUND.
        //  e.g., if `val` is `0`,
        //      The result is `1`.
        let exponent = quantityExponent(val)
        // No rounding error in Math.pow(10, integer).
        let exp10 = mathPow(10, exponent)
        let f = val / exp10

        var nf: Double
        if mode == .min {
            nf = 1
        }
        else if mode == .round {
            if f < 1.5 {
                nf = 1
            }
            else if f < 2.5 {
                nf = 2
            }
            else if f < 4 {
                nf = 3
            }
            else if f < 7 {
                nf = 5
            }
            else {
                nf = 10
            }
        }
        else {
            if f < 1 {
                nf = 1
            }
            else if f < 2 {
                nf = 2
            }
            else if f < 3 {
                nf = 3
            }
            else if f < 5 {
                nf = 5
            }
            else {
                nf = 10
            }
        }
        let val = nf * exp10

        // Fix IEEE 754 float rounding error
        return round(val, -exponent)
    }

    /**
     * This code was copied from "d3.js"
     * <https://github.com/d3/d3/blob/9cc9a875e636a1dcf36cc1e07bdf77e1ad6e2c74/src/arrays/quantile.js>.
     * See the license statement at the head of this file.
     * @param ascArr
     */
    public static func quantile(_ ascArr: [Double], _ p: Double) -> Double {
        let H = (Double(ascArr.count) - 1) * p + 1
        let h = mathFloor(H)
        let v = ascArr[Int(h) - 1]
        let e = H - h
        return e != 0 ? v + e * (ascArr[Int(h)] - v) : v
    }

    public struct IntervalItem {
        public var interval: [Double]            // [number, number]
        public var close: [Double]               // [0 | 1, 0 | 1]
        public init(interval: [Double], close: [Double]) {
            self.interval = interval
            self.close = close
        }
    }
    /**
     * Order intervals asc, and split them when overlap.
     * expect(numberUtil.reformIntervals([
     *     {interval: [18, 62], close: [1, 1]},
     *     {interval: [-Infinity, -70], close: [0, 0]},
     *     {interval: [-70, -26], close: [1, 1]},
     *     {interval: [-26, 18], close: [1, 1]},
     *     {interval: [62, 150], close: [1, 1]},
     *     {interval: [106, 150], close: [1, 1]},
     *     {interval: [150, Infinity], close: [0, 0]}
     * ])).toEqual([
     *     {interval: [-Infinity, -70], close: [0, 0]},
     *     {interval: [-70, -26], close: [1, 1]},
     *     {interval: [-26, 18], close: [0, 1]},
     *     {interval: [18, 62], close: [0, 1]},
     *     {interval: [62, 150], close: [0, 1]},
     *     {interval: [150, Infinity], close: [0, 0]}
     * ]);
     * @param list, where `close` mean open or close
     *        of the interval, and Infinity can be used.
     * @return The origin list, which has been reformed.
     */
    // CONVENTIONS §3: value-returning. Upstream mutates `list` in place and returns it; in Swift
    //  `[IntervalItem]` (struct elements) is a value type, so call sites reassign the result.
    public static func reformIntervals(_ list: [IntervalItem]) -> [IntervalItem] {
        func littleThan(_ a: IntervalItem, _ b: IntervalItem, _ lg: Int) -> Bool {
            return a.interval[lg] < b.interval[lg]
                || (
                    a.interval[lg] == b.interval[lg]
                    && (
                        (a.close[lg] - b.close[lg] == (lg == 0 ? 1 : -1))
                        || (lg == 0 && littleThan(a, b, 1))
                    )
                )
        }

        var list = list
        list.sort { a, b in
            littleThan(a, b, 0) ? true : false
        }

        var curr = -Double.infinity
        var currClose: Double = 1
        var i = 0
        while i < list.count {
            for lg in 0..<2 {
                if list[i].interval[lg] <= curr {
                    list[i].interval[lg] = curr
                    list[i].close[lg] = (lg == 0 ? 1 - currClose : 1)
                }
                curr = list[i].interval[lg]
                currClose = list[i].close[lg]
            }

            if list[i].interval[0] == list[i].interval[1] && list[i].close[0] * list[i].close[1] != 1 {
                list.remove(at: i)
            }
            else {
                i += 1
            }
        }

        return list
    }

    /**
     * [Numeric is defined as]:
     *     `parseFloat(val) == val`
     * For example:
     * numeric:
     *     typeof number except NaN, '-123', '123', '2e3', '-2e3', '011', 'Infinity', Infinity,
     *     and they rounded by white-spaces or line-terminal like ' -123 \n ' (see es spec)
     * not-numeric:
     *     null, undefined, [], {}, true, false, 'NaN', NaN, '123ab',
     *     empty string, string with only white-spaces or line-terminal (see es spec),
     *     0x12, '0x12', '-0x12', 012, '012', '-012',
     *     non-string, ...
     *
     * @test See full test cases in `test/ut/spec/util/number.js`.
     * @return Must be a typeof number. If not numeric, return NaN.
     */
    public static func numericToNumber(_ val: Any?) -> Double {
        let valFloat = parseFloatLeading(jsString(val))
        // upstream: `valFloat == val` is a loose (==) comparison between a number and `unknown`.
        // PORT-NOTE: only number/string/bool/null loose-equality is modeled; exotic coercions
        //  (objects via ToPrimitive) are not reproduced. Semantically equivalent for internal usage,
        //  which never passes objects to `numericToNumber`.
        let looseEq: Bool
        if val == nil {
            // `number == null` is always false in JS.
            looseEq = false
        }
        else {
            looseEq = (valFloat == numberCoerce(val))
        }
        return (
            looseEq // eslint-disable-line eqeqeq
            && (valFloat != 0 || !util.isString(val) || indexOf(val as! String, "x") <= 0) // For case ' 0x0 '.
        ) ? valFloat : Double.nan
    }

    /**
     * Definition of "numeric": see `numericToNumber`.
     */
    public static func isNumeric(_ val: Any?) -> Bool {
        return !numericToNumber(val).isNaN
    }

    /**
     * Use random base to prevent users hard code depending on
     * this auto generated marker id.
     * @return An positive integer.
     */
    public static func getRandomIdBase() -> Double {
        return mathRound(mathRandom() * 9)
    }

    /**
     * Get the greatest common divisor.
     *
     * @param {number} a one number
     * @param {number} b the other number
     */
    public static func getGreatestCommonDividor(_ a: Double, _ b: Double) -> Double {
        if b == 0 {
            return a
        }
        return getGreatestCommonDividor(b, a.truncatingRemainder(dividingBy: b))
    }

    /**
     * Get the least common multiple.
     *
     * @param {number} a one number
     * @param {number} b the other number
     */
    public static func getLeastCommonMultiple(_ a: Double?, _ b: Double?) -> Double? {
        if a == nil {
            return b
        }
        if b == nil {
            return a
        }
        return a! * b! / getGreatestCommonDividor(a!, b!)
    }

    /**
     * NOTICE: Assume the input `val` is number or null/undefined, no type check, no support of BitInt.
     * Therefore, it is NOT suitable for processing user input, but sufficient for
     * internal usage in most cases.
     * For platform-agnosticism, `Number.isFinite` is not used.
     */
    public static func isNullableNumberFinite(_ val: Double?) -> Bool {
        return val != nil && val!.isFinite
    }

    // ---------------------------------------------------------------------------------------------
    // Private helpers replicating JS numeric coercion / string ops used above.
    // Not part of upstream `number.ts`; introduced to faithfully reproduce JS `+x`, `Number(x)`,
    // `parseFloat(x)`, `'' + x`, `String.prototype.indexOf/slice/substring`.
    // ---------------------------------------------------------------------------------------------

    // JS `a || b` for numbers: returns `a` when truthy (non-zero and not NaN), else `b`.
    static func or(_ a: Double?, _ b: Double) -> Double {
        if let a = a, a != 0, !a.isNaN {
            return a
        }
        return b
    }

    // JS `String(val)` (used as `parseFloat(val as string)` argument).
    static func jsString(_ val: Any?) -> String {
        switch val {
        case nil: return "null"
        case let s as String: return s
        case let b as Bool: return b ? "true" : "false"
        case let d as Double: return jsNumberString(d)
        case let i as Int: return String(i)
        default: return String(describing: val!)
        }
    }

    // JS `'' + x` / `Number.prototype.toString` for a Double.
    // POTENTIAL-BUG: JS uses a specific scientific-notation threshold/format; only the common
    //  finite/integer/decimal cases are reproduced here.
    static func jsNumberString(_ x: Double) -> String {
        if x.isNaN { return "NaN" }
        if x.isInfinite { return x > 0 ? "Infinity" : "-Infinity" }
        if x == x.rounded() && Swift.abs(x) < 1e21 {
            return String(Int64(x))
        }
        return String(x)
    }

    // JS `Number(val)` (i.e. the `+x` operator) on number / string / bool / null.
    static func numberCoerce(_ val: Any?) -> Double {
        switch val {
        case nil: return Double.nan  // PENDING: `+null` is 0 but `+undefined` is NaN; callers guard null.
        case let d as Double: return d
        case let b as Bool: return b ? 1 : 0
        case let i as Int: return Double(i)
        case let s as String: return jsNumber(s)
        default: return Double.nan
        }
    }

    // JS `+s` where `s` is a `string | undefined` match group (undefined -> NaN).
    static func plusOp(_ s: String?) -> Double {
        guard let s = s else { return Double.nan }
        return jsNumber(s)
    }

    // JS `Number(string)`: trims whitespace, "" -> 0, full-string parse, else NaN.
    static func jsNumber(_ s: String) -> Double {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return 0 }
        if t == "Infinity" || t == "+Infinity" { return Double.infinity }
        if t == "-Infinity" { return -Double.infinity }
        if let d = Double(t) { return d }
        // 0x / 0o / 0b radix literals (Number() supports these; parseFloat does not).
        let lower = t.lowercased()
        if lower.hasPrefix("0x"), let i = Int(t.dropFirst(2), radix: 16) { return Double(i) }
        if lower.hasPrefix("0o"), let i = Int(t.dropFirst(2), radix: 8) { return Double(i) }
        if lower.hasPrefix("0b"), let i = Int(t.dropFirst(2), radix: 2) { return Double(i) }
        return Double.nan
    }

    // JS `parseFloat(s)`: skips leading whitespace, parses leading float, else NaN.
    static func parseFloatLeading(_ s: String) -> Double {
        let trimmed = String(s.drop(while: { $0 == " " || $0 == "\t" || $0 == "\n" || $0 == "\r" }))
        if trimmed.hasPrefix("Infinity") || trimmed.hasPrefix("+Infinity") { return Double.infinity }
        if trimmed.hasPrefix("-Infinity") { return -Double.infinity }
        let scanner = Scanner(string: trimmed)
        scanner.charactersToBeSkipped = nil
        if let d = scanner.scanDouble() { return d }
        return Double.nan
    }

    // JS `String.prototype.indexOf(ch)` -> index or -1.
    static func indexOf(_ s: String, _ ch: Character) -> Int {
        let arr = Array(s)
        for i in 0..<arr.count where arr[i] == ch {
            return i
        }
        return -1
    }

    // JS `String.prototype.slice(from)` / `slice(from, to)`.
    static func slice(_ s: String, _ from: Int, _ to: Int?) -> String {
        let arr = Array(s)
        let end = to ?? arr.count
        let lo = Swift.max(0, Swift.min(from, arr.count))
        let hi = Swift.max(lo, Swift.min(end, arr.count))
        return String(arr[lo..<hi])
    }

    // JS `String.prototype.substring(from, to)`.
    static func substring(_ s: String, _ from: Int, _ to: Int) -> String {
        let arr = Array(s)
        let f = Swift.max(0, Swift.min(from, arr.count))
        let t = Swift.max(0, Swift.min(to, arr.count))
        let lo = Swift.min(f, t)
        let hi = Swift.max(f, t)
        return String(arr[lo..<hi])
    }
}
