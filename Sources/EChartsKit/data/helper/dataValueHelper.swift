// Ported from echarts/src/data/helper/dataValueHelper.ts — keep in sync with upstream
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

// upstream: import { ParsedValue, DimensionType, NullUndefined } from '../../util/types';
//   -> EChartsKit util/types.swift exposes `ParsedValue` (= Any), `DimensionType`
//      (= DataStoreDimensionType). `NullUndefined` collapses to Optional (CONVENTIONS §6).
// upstream: import { parseDate, numericToNumber } from '../../util/number';
//   -> EChartsKit `number` namespace (number.parseDate / number.numericToNumber).
// upstream: import { createHashMap, trim, hasOwn, isString, isNumber } from 'zrender/src/core/util';
//   -> createHashMap -> a Swift `Dictionary` (CONVENTIONS §2 / zrender util PORT-TODO).
//      trim -> `String.trimmingCharacters(in: .whitespacesAndNewlines)`.
//      hasOwn(obj, k) -> `dict[k] != nil` (CONVENTIONS §8).
//      isString / isNumber -> ZRenderKit `util.isString` / `util.isNumber`.
// upstream: import { throwError } from '../../util/log'; -> EChartsKit `log.throwError`.

// upstream module `data/helper/dataValueHelper.ts` (free functions) -> caseless enum
// namespace `dataValueHelper` (CONVENTIONS §2). Exported types/classes are kept as
// top-level declarations (mirrors sibling `scale/helper.swift`). Functions are added in
// upstream order via extensions so the file stays diffable against the original.
public enum dataValueHelper {}


// --------- START: Parsers --------

/// Option bag for `parseDataValue` (upstream inline type `{ type?: DimensionType }`).
public struct ParseDataValueOpt {
    public var type: DimensionType?
    public init(type: DimensionType? = nil) {
        self.type = type
    }
}

extension dataValueHelper {

    /**
     * Convert raw the value in to inner value in List.
     *
     * [Performance sensitive]
     *
     * [Caution]: this is the key logic of user value parser.
     * For backward compatibility, do not modify it until you have to!
     */
    public static func parseDataValue(
        _ value: Any?,
        // For high performance, do not omit the second param.
        _ opt: ParseDataValueOpt?
    ) -> ParsedValue {
        // Performance sensitive.
        let dimType = opt?.type
        if dimType == .ordinal {
            // If given value is a category string
            return value as Any
        }

        var value = value
        if dimType == .time
            // spead up when using timestamp
            && !util.isNumber(value)
            && value != nil
            && (value as? String) != "-"
        {
            // upstream: value = +parseDate(value);
            //   `+parseDate(value)` -> the `Date`'s ms-since-epoch timestamp (NaN if invalid).
            value = number.parseDate(value).timeIntervalSince1970 * 1000
        }

        // dimType defaults 'number'.
        // If dimType is not ordinal and value is null or undefined or NaN or '-',
        // parse to NaN.
        // number-like string (like ' 123 ') can be converted to a number.
        // where null/undefined or other string will be converted to NaN.
        return (value == nil || (value as? String) == "")
            ? Double.nan
            // If string (like '-'), using '+' parse to NaN
            // If object, also parse to NaN
            : number.numberCoerce(value)
    }
}




public typealias RawValueParserType = String   // PORT-TODO: upstream union 'number' | 'time' | 'trim'
public typealias RawValueParser = (_ val: Any?) -> Any?

extension dataValueHelper {
    private static let valueParserMap: [RawValueParserType: RawValueParser] = [
        "number": { val in
            // Do not use `numericToNumber` here. We have `numericToNumber` by default.
            // Here the number parser can have loose rule:
            // enable to cut suffix: "120px" => 120, "14%" => 14.
            return number.parseFloatLeading(number.jsString(val))
        },
        "time": { val in
            // return timestamp.
            return number.parseDate(val).timeIntervalSince1970 * 1000
        },
        "trim": { val in
            return util.isString(val) ? (val as! String).trimmingCharacters(in: .whitespacesAndNewlines) : val
        }
    ]

    // upstream returns `RawValueParser` (which may be undefined when `type` is absent);
    // the Swift map lookup is value-returning, hence optional.
    public static func getRawValueParser(_ type: RawValueParserType) -> RawValueParser? {
        return valueParserMap[type]
    }
}

// --------- END: Parsers ---------



// --------- START: Data transformattion filters ---------
// (comprehensive and performance insensitive)

public protocol FilterComparator {
    func evaluate(_ val: Any?) -> Bool
}

// PORT-TODO: upstream types `lval`/`rval` as `unknown`, but in this file the map is only
//            ever invoked with numbers (numericToNumber results), so it is typed
//            (Double, Double) -> Bool.
private let ORDER_COMPARISON_OP_MAP: [OrderRelationOperator: (Double, Double) -> Bool] = [
    "lt": { lval, rval in lval < rval },
    "lte": { lval, rval in lval <= rval },
    "gt": { lval, rval in lval > rval },
    "gte": { lval, rval in lval >= rval }
]

private final class FilterOrderComparator: FilterComparator {
    private var _rvalFloat: Double
    private var _opFn: (Double, Double) -> Bool
    init(_ op: OrderRelationOperator, _ rval: Any?) throws {
        if !util.isNumber(rval) {
            var errMsg = ""
            if __DEV__ {
                errMsg = "rvalue of \"<\", \">\", \"<=\", \">=\" can only be number in filter."
            }
            try log.throwError(errMsg)
        }
        self._opFn = ORDER_COMPARISON_OP_MAP[op]!
        self._rvalFloat = number.numericToNumber(rval)
    }
    // Performance sensitive.
    func evaluate(_ lval: Any?) -> Bool {
        // Most cases is 'number', and typeof maybe 10 times faseter than parseFloat.
        return util.isNumber(lval)
            ? self._opFn(lval as! Double, self._rvalFloat)
            : self._opFn(number.numericToNumber(lval), self._rvalFloat)
    }
}

public final class SortOrderComparator {
    private var _incomparable: Double
    private var _resultLT: Double   // upstream: -1 | 1
    /**
     * @param order by default: 'asc'
     * @param incomparable by default: Always on the tail.
     *        That is, if 'asc' => 'max', if 'desc' => 'min'
     *        See the definition of "incomparable" in [SORT_COMPARISON_RULE].
     */
    public init(_ order: String, _ incomparable: String?) {
        let isDesc = order == "desc"
        self._resultLT = isDesc ? 1 : -1
        var incomparable = incomparable
        if incomparable == nil {
            incomparable = isDesc ? "min" : "max"
        }
        self._incomparable = incomparable == "min" ? -Double.infinity : Double.infinity
    }
    // See [SORT_COMPARISON_RULE].
    // Performance sensitive.
    public func evaluate(_ lval: Any?, _ rval: Any?) -> Double {   // upstream: -1 | 0 | 1
        // Most cases is 'number', and typeof maybe 10 times faseter than parseFloat.
        // `lvalFloat`/`rvalFloat` start as `Double` but may be re-bound to the raw string
        // value (upstream `lval as unknown as number`), so they are modeled as `Any` and
        // compared with `jsLess`/`jsGreater` below.
        var lvalFloat: Any = util.isNumber(lval) ? (lval as! Double) : number.numericToNumber(lval)
        var rvalFloat: Any = util.isNumber(rval) ? (rval as! Double) : number.numericToNumber(rval)
        let lvalNotNumeric = (lvalFloat as! Double).isNaN
        let rvalNotNumeric = (rvalFloat as! Double).isNaN

        if lvalNotNumeric {
            lvalFloat = self._incomparable
        }
        if rvalNotNumeric {
            rvalFloat = self._incomparable
        }
        if lvalNotNumeric && rvalNotNumeric {
            let lvalIsStr = util.isString(lval)
            let rvalIsStr = util.isString(rval)
            if lvalIsStr {
                lvalFloat = rvalIsStr ? lval! : 0.0
            }
            if rvalIsStr {
                rvalFloat = lvalIsStr ? rval! : 0.0
            }
        }

        return jsLess(lvalFloat, rvalFloat) ? self._resultLT
            : jsGreater(lvalFloat, rvalFloat) ? -self._resultLT
            : 0
    }
}

private final class FilterEqualityComparator: FilterComparator {
    private var _isEQ: Bool
    private var _rval: Any?
    private var _rvalTypeof: String
    private var _rvalFloat: Double
    init(_ isEq: Bool, _ rval: Any?) {
        self._rval = rval
        self._isEQ = isEq
        self._rvalTypeof = jsTypeof(rval)
        self._rvalFloat = number.numericToNumber(rval)
    }
    // Performance sensitive.
    func evaluate(_ lval: Any?) -> Bool {
        var eqResult = jsStrictEquals(lval, self._rval)
        if !eqResult {
            let lvalTypeof = jsTypeof(lval)
            if lvalTypeof != self._rvalTypeof && (lvalTypeof == "number" || self._rvalTypeof == "number") {
                eqResult = number.numericToNumber(lval) == self._rvalFloat
            }
        }
        return self._isEQ ? eqResult : !eqResult
    }
}

public typealias OrderRelationOperator = String   // PORT-TODO: upstream union 'lt' | 'lte' | 'gt' | 'gte'
public typealias RelationalOperator = String       // PORT-TODO: upstream OrderRelationOperator | 'eq' | 'ne'

/**
 * [FILTER_COMPARISON_RULE]
 * `lt`|`lte`|`gt`|`gte`:
 * + rval must be a number. And lval will be converted to number (`numericToNumber`) to compare.
 * `eq`:
 * + If same type, compare with `===`.
 * + If there is one number, convert to number (`numericToNumber`) to compare.
 * + Else return `false`.
 * `ne`:
 * + Not `eq`.
 *
 *
 * [SORT_COMPARISON_RULE]
 * All the values are grouped into three categories:
 * + "numeric" (number and numeric string)
 * + "non-numeric-string" (string that excluding numeric string)
 * + "others"
 * "numeric" vs "numeric": values are ordered by number order.
 * "non-numeric-string" vs "non-numeric-string": values are ordered by ES spec (#sec-abstract-relational-comparison).
 * "others" vs "others": do not change order (always return 0).
 * "numeric" vs "non-numeric-string": "non-numeric-string" is treated as "incomparable".
 * "number" vs "others": "others" is treated as "incomparable".
 * "non-numeric-string" vs "others": "others" is treated as "incomparable".
 * "incomparable" will be seen as -Infinity or Infinity (depends on the settings).
 * MEMO:
 *   Non-numeric string sort makes sense when we need to put the items with the same tag together.
 *   But if we support string sort, we still need to avoid the misleading like `'2' > '12'`,
 *   So we treat "numeric-string" sorted by number order rather than string comparison.
 *
 *
 * [CHECK_LIST_OF_THE_RULE_DESIGN]
 * + Do not support string comparison until required. And also need to
 *   avoid the misleading of "2" > "12".
 * + Should avoid the misleading case:
 *   `" 22 " gte "22"` is `true` but `" 22 " eq "22"` is `false`.
 * + JS bad case should be avoided: null <= 0, [] <= 0, ' ' <= 0, ...
 * + Only "numeric" can be converted to comparable number, otherwise converted to NaN.
 *   See `util/number.ts#numericToNumber`.
 *
 * @return If `op` is not `RelationalOperator`, return null;
 */
extension dataValueHelper {
    public static func createFilterComparator(
        _ op: String,
        _ rval: Any? = nil
    ) throws -> FilterComparator? {
        // hasOwn(ORDER_COMPARISON_OP_MAP, op) -> `ORDER_COMPARISON_OP_MAP[op] != nil`.
        return try (op == "eq" || op == "ne")
            ? (FilterEqualityComparator(op == "eq", rval) as FilterComparator)
            : (ORDER_COMPARISON_OP_MAP[op] != nil
                ? (FilterOrderComparator(op, rval) as FilterComparator)
                : nil)
    }
}

// --------- END: Data transformattion filters ---------



// --------- START: Data store sanitization filters ---------
// (simple and performance sensitive)

// g: greater than, ge: greater equal, l: less than, le: less equal
public struct DataSanitizationFilter {
    public var g: Double?
    public var ge: Double?
    public var l: Double?
    public var le: Double?
    public init(g: Double? = nil, ge: Double? = nil, l: Double? = nil, le: Double? = nil) {
        self.g = g
        self.ge = ge
        self.l = l
        self.le = le
    }
}
public struct DataSanitizationFilterParsed {
    public var key: String
    public var g: Double
    public var ge: Double
    public var l: Double
    public var le: Double
    public init(key: String, g: Double, ge: Double, l: Double, le: Double) {
        self.key = key
        self.g = g
        self.ge = ge
        self.l = l
        self.le = le
    }
}

extension dataValueHelper {
    /**
     * @usage
     *  const filterParsed = parseSanitizationFilter(filter);
     *  for( ... ) {
     *      const val = ...;
     *      if (!filter || passesFilter(filterParsed, val)) {
     *          // normal handling
     *      }
     *  }
     */
    public static func parseSanitizationFilter(
        _ filter: DataSanitizationFilter?
    ) -> DataSanitizationFilterParsed {
        var filterKey = ""
        var filterG = -Double.infinity
        var filterGE = -Double.infinity
        var filterL = Double.infinity
        var filterLE = Double.infinity
        if let filter = filter {
            if let g = filter.g {   // filter.g != null
                filterKey += "G" + number.jsNumberString(g)
                filterG = g
            }
            if let ge = filter.ge {   // filter.ge != null
                filterKey += "GE" + number.jsNumberString(ge)
                filterGE = ge
            }
            if let l = filter.l {   // filter.l != null
                filterKey += "L" + number.jsNumberString(l)
                filterL = l
            }
            if let le = filter.le {   // filter.le != null
                filterKey += "LE" + number.jsNumberString(le)
                filterLE = le
            }
        }
        return DataSanitizationFilterParsed(
            key: filterKey,
            g: filterG,
            ge: filterGE,
            l: filterL,
            le: filterLE
        )
    }

    public static func passesSanitizationFilter(_ filterParsed: DataSanitizationFilterParsed, _ value: Double) -> Bool {
        return value > filterParsed.g
            && value >= filterParsed.ge
            && value < filterParsed.l
            && value <= filterParsed.le
    }
}

// --------- END: Data store sanitization filters ---------


// ============================================================================
// PORT-TODO: JS dynamic-operator helpers.
// Upstream relies on JS's runtime-polymorphic `typeof`, `===`, `<` and `>` over `unknown`
// values. Swift has no such polymorphism, so these reproduce the exact value kinds that
// can actually reach the comparators here (number / string / boolean / null).
// ============================================================================

/// JS `typeof x`.
private func jsTypeof(_ val: Any?) -> String {
    switch val {
    // PORT-TODO: JS distinguishes `typeof undefined === 'undefined'` from
    //            `typeof null === 'object'`; null/undefined collapse to `nil` (CONVENTIONS §6).
    case nil: return "undefined"
    case is Bool: return "boolean"
    case is Double: return "number"
    case is String: return "string"
    default: return "object"
    }
}

/// JS strict equality `===` for the value kinds reachable in the equality comparator.
private func jsStrictEquals(_ a: Any?, _ b: Any?) -> Bool {
    switch (a, b) {
    case (nil, nil): return true
    case let (x as Bool, y as Bool): return x == y
    case let (x as Double, y as Double): return x == y
    case let (x as String, y as String): return x == y
    default: return false
    }
}

/// JS `<` for the value kinds reachable in `SortOrderComparator` (both Double or both String).
private func jsLess(_ a: Any, _ b: Any) -> Bool {
    if let x = a as? Double, let y = b as? Double {
        return x < y
    }
    // PORT-TODO: JS compares strings by UTF-16 code units; Swift `String` uses Unicode-aware
    //            ordering (matches for ASCII tags, the intended use case).
    if let x = a as? String, let y = b as? String {
        return x < y
    }
    return false
}

/// JS `>` companion of `jsLess`.
private func jsGreater(_ a: Any, _ b: Any) -> Bool {
    if let x = a as? Double, let y = b as? Double {
        return x > y
    }
    if let x = a as? String, let y = b as? String {
        return x > y
    }
    return false
}
