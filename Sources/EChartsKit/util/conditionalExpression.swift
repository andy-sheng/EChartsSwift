// Ported from echarts/src/util/conditionalExpression.ts — keep in sync with upstream
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
//   import { OptionDataValue, DimensionLoose, Dictionary } from './types';
//       -> util/types.swift (same module). `OptionDataValue` = `Any?`, `DimensionLoose` = `Any`.
//          `Dictionary<unknown>` -> Swift `[String: Any]` (see `ValueGetterParam` below).
//   import { keys, isArray, map, isObject, isString, HashMap, isRegExp, isArrayLike, hasOwn, isNumber }
//       from 'zrender/src/core/util';
//       -> `util.keys` / `util.isArrayLike` / `util.isObject` / `util.isString` / `util.isRegExp`
//          / `util.isNumber` (ZRenderKit). `isArray` -> `x is [Any]`. `map` -> Swift `.map`.
//          `hasOwn(o, k)` -> `dict.keys.contains(k)`. `HashMap<boolean, string>` -> the EChartsKit
//          `HashMap<Bool>` shim (util/modelUtil.swift).
//   import { throwError, makePrintable } from './log'; -> `log.throwError` / `log.makePrintable`.
//   import { RawValueParserType, getRawValueParser, RelationalOperator, FilterComparator,
//       createFilterComparator } from '../data/helper/dataValueHelper';
//       -> data/helper/dataValueHelper.swift (same module): `RawValueParserType`, `RawValueParser`,
//          `dataValueHelper.getRawValueParser`, `RelationalOperator`, `FilterComparator`,
//          `dataValueHelper.createFilterComparator`.
import Foundation
import ZRenderKit


// PENDING:
// (1) Support more parser like: `parser: 'trim'`, `parser: 'lowerCase'`, `parser: 'year'`, `parser: 'dayOfWeek'`?
// (2) Support piped parser?
// (3) Support callback parser or callback condition?
// (4) At present do not support string expression yet but only structured expression.


// --------------------------------------------------
// --- Relational Expression --------------------------
// --------------------------------------------------

// upstream: interface RelationalExpressionOptionByOp extends Record<RelationalOperator, OptionDataValue>
//           { reg?: RegExp | string }; plus `dimension?`, `parser?` and the op-alias keys.
// In this port, the whole relational-expression object flows as a dynamic `[String: Any]` option
// bag (CONVENTIONS §2). Keys are read by name (`dimension` / `parser` / op keys / op aliases).
public typealias RelationalExpressionOption = [String: Any]

// upstream: const RELATIONAL_EXPRESSION_OP_ALIAS_MAP = { value:'eq', '<':'lt', ... } as const;
private let RELATIONAL_EXPRESSION_OP_ALIAS_MAP: [String: String] = [
    "value": "eq",

    // PENDING: not good for literal semantic?
    "<": "lt",
    "<=": "lte",
    ">": "gt",
    ">=": "gte",
    "=": "eq",
    "!=": "ne",
    "<>": "ne"

    // Might be misleading for sake of the difference between '==' and '===',
    // so don't support them.
    // '==': 'eq',
    // '===': 'seq',
    // '!==': 'sne'

    // PENDING: Whether support some common alias "ge", "le", "neq"?
    // ge: 'gte',
    // le: 'lte',
    // neq: 'ne',
]

// upstream: class RegExpEvaluator implements FilterComparator
final class RegExpEvaluator: FilterComparator {
    private let _condVal: NSRegularExpression

    init(_ rVal: Any?) throws {
        // Support condVal: RegExp | string
        // upstream: isString(rVal) ? new RegExp(rVal) : isRegExp(rVal) ? rVal : null;
        let condValue: NSRegularExpression?
        if util.isString(rVal) {
            // `new RegExp(str)` — an invalid pattern throws in JS too; `try?` -> nil -> the
            // "Illegal regexp" throwError below (JS would throw a SyntaxError instead; both throw).
            condValue = try? NSRegularExpression(pattern: rVal as! String)
        }
        else if util.isRegExp(rVal) {
            condValue = (rVal as! NSRegularExpression)
        }
        else {
            condValue = nil
        }
        if condValue == nil {   // upstream: if (condValue == null)
            var errMsg = ""
            if __DEV__ {
                errMsg = log.makePrintable("Illegal regexp", rVal, "in")
            }
            try log.throwError(errMsg)
        }
        self._condVal = condValue!
    }

    func evaluate(_ lVal: Any?) -> Bool {
        // upstream:
        //   const type = typeof lVal;
        //   return isString(type) ? this._condVal.test(lVal as string)
        //       : isNumber(type) ? this._condVal.test(lVal + '')
        //       : false;
        // NOTE [upstream quirk]: `type` is the *string* result of `typeof lVal`, so `isString(type)`
        // is always `true` and the first branch always executes; `RegExp.test` coerces its argument
        // to a string. The faithful behavior is therefore "test against the JS string coercion of
        // lVal". The `isNumber(type)` branch is dead but kept for structural fidelity.
        let type = jsTypeof(lVal)
        if util.isString(type) {
            return regexTest(self._condVal, number.jsString(lVal))
        }
        else if util.isNumber(type) {
            return regexTest(self._condVal, number.jsString(lVal))
        }
        return false
    }
}


// --------------------------------------------------
// --- Logical Expression ---------------------------
// --------------------------------------------------

// upstream: interface LogicalExpressionOption { and?; or?; not?; }
//   and: LogicalExpressionSubOption[]; or: LogicalExpressionSubOption[]; not: LogicalExpressionSubOption;
// Modeled dynamically as `[String: Any]` (see `RelationalExpressionOption`); the `and`/`or`/`not`
// keys are detected by truthiness in `parseOption`.


// -----------------------------------------------------
// --- Conditional Expression --------------------------
// -----------------------------------------------------

// upstream: export type TrueExpressionOption = true; export type FalseExpressionOption = false;
//           export type TrueFalseExpressionOption = TrueExpressionOption | FalseExpressionOption;
public typealias TrueFalseExpressionOption = Bool

// upstream: export type ConditionalExpressionOption =
//     LogicalExpressionOption | RelationalExpressionOption | TrueFalseExpressionOption;
//   The union is a `Bool` literal OR an object (`[String: Any]`), so it erases to `Any?`.
public typealias ConditionalExpressionOption = Any?

// upstream: type ValueGetterParam = Dictionary<unknown>;
public typealias ValueGetterParam = [String: Any]

// upstream: interface ConditionalExpressionValueGetterParamGetter<VGP> { (relExpOption): VGP }
public typealias ConditionalExpressionValueGetterParamGetter<VGP> = (RelationalExpressionOption) throws -> VGP
// upstream: interface ConditionalExpressionValueGetter<VGP> { (param: VGP): OptionDataValue }
public typealias ConditionalExpressionValueGetter<VGP> = (VGP) -> OptionDataValue

// upstream: interface ParsedConditionInternal { evaluate(): boolean; }
protocol ParsedConditionInternal {
    func evaluate() -> Bool
}

// upstream: class ConstConditionInternal implements ParsedConditionInternal
final class ConstConditionInternal: ParsedConditionInternal {
    var value: Bool = false
    func evaluate() -> Bool {
        return self.value
    }
}

// upstream: class AndConditionInternal implements ParsedConditionInternal
final class AndConditionInternal: ParsedConditionInternal {
    var children: [ParsedConditionInternal] = []
    func evaluate() -> Bool {
        let children = self.children
        for i in 0..<children.count {
            if !children[i].evaluate() {
                return false
            }
        }
        return true
    }
}

// upstream: class OrConditionInternal implements ParsedConditionInternal
final class OrConditionInternal: ParsedConditionInternal {
    var children: [ParsedConditionInternal] = []
    func evaluate() -> Bool {
        let children = self.children
        for i in 0..<children.count {
            if children[i].evaluate() {
                return true
            }
        }
        return false
    }
}

// upstream: class NotConditionInternal implements ParsedConditionInternal
final class NotConditionInternal: ParsedConditionInternal {
    var child: ParsedConditionInternal!
    func evaluate() -> Bool {
        return !self.child.evaluate()
    }
}

// upstream: class RelationalConditionInternal implements ParsedConditionInternal
final class RelationalConditionInternal<VGP>: ParsedConditionInternal {
    var valueGetterParam: VGP!
    // upstream: valueParser: ReturnType<typeof getRawValueParser>; // If no parser, be null/undefined.
    var valueParser: RawValueParser?
    var getValue: ConditionalExpressionValueGetter<VGP>!
    var subCondList: [FilterComparator] = []

    func evaluate() -> Bool {
        let needParse = self.valueParser != nil   // upstream: !!this.valueParser
        // Call getValue with no `this`.
        let getValue = self.getValue!
        let tarValRaw = getValue(self.valueGetterParam)
        let tarValParsed: Any? = needParse ? self.valueParser!(tarValRaw) : nil

        // Relational cond follow "and" logic internally.
        for i in 0..<self.subCondList.count {
            if !self.subCondList[i].evaluate(needParse ? tarValParsed : tarValRaw) {
                return false
            }
        }
        return true
    }
}

// upstream: function parseOption(exprOption, getters): ParsedConditionInternal
private func parseOption<VGP>(
    _ exprOption: ConditionalExpressionOption,
    _ getters: ConditionalGetters<VGP>
) throws -> ParsedConditionInternal {
    // upstream: if (exprOption === true || exprOption === false)
    if let boolLit = asBoolLiteral(exprOption) {
        let cond = ConstConditionInternal()
        cond.value = boolLit
        return cond
    }

    var errMsg = ""
    if !isObjectNotArray(exprOption) {
        if __DEV__ {
            errMsg = log.makePrintable(
                "Illegal config. Expect a plain object but actually", exprOption
            )
        }
        try log.throwError(errMsg)
    }

    let dict = exprOption as! [String: Any]

    if jsTruthy(dict["and"]) {   // upstream: if ((exprOption as LogicalExpressionOption).and)
        return try parseAndOrOption("and", dict, getters)
    }
    else if jsTruthy(dict["or"]) {   // upstream: else if (...).or
        return try parseAndOrOption("or", dict, getters)
    }
    else if jsTruthy(dict["not"]) {   // upstream: else if (...).not
        return try parseNotOption(dict, getters)
    }

    return try parseRelationalOption(dict, getters)
}

// upstream: function parseAndOrOption(op: 'and' | 'or', exprOption, getters): ParsedConditionInternal
private func parseAndOrOption<VGP>(
    _ op: String,
    _ exprOption: [String: Any],
    _ getters: ConditionalGetters<VGP>
) throws -> ParsedConditionInternal {
    let subOptionArr = exprOption[op]   // upstream: exprOption[op] as ConditionalExpressionOption[]
    var errMsg = ""
    if __DEV__ {
        errMsg = log.makePrintable(
            "\"and\"/\"or\" condition should only be `" + op + ": [...]` and must not be empty array.",
            "Illegal condition:", exprOption
        )
    }
    if !(subOptionArr is [Any]) {   // upstream: if (!isArray(subOptionArr))
        try log.throwError(errMsg)
    }
    let arr = subOptionArr as! [Any]
    if arr.isEmpty {   // upstream: if (!subOptionArr.length)
        try log.throwError(errMsg)
    }
    // upstream: const cond = op === 'and' ? new AndConditionInternal() : new OrConditionInternal();
    //           cond.children = map(subOptionArr, subOption => parseOption(subOption, getters));
    let children = try arr.map { try parseOption($0, getters) }
    if op == "and" {
        let cond = AndConditionInternal()
        cond.children = children
        if cond.children.isEmpty {   // upstream: if (!cond.children.length)
            try log.throwError(errMsg)
        }
        return cond
    }
    else {
        let cond = OrConditionInternal()
        cond.children = children
        if cond.children.isEmpty {
            try log.throwError(errMsg)
        }
        return cond
    }
}

// upstream: function parseNotOption(exprOption, getters): ParsedConditionInternal
private func parseNotOption<VGP>(
    _ exprOption: [String: Any],
    _ getters: ConditionalGetters<VGP>
) throws -> ParsedConditionInternal {
    let subOption = exprOption["not"]   // upstream: exprOption.not as ConditionalExpressionOption
    var errMsg = ""
    if __DEV__ {
        errMsg = log.makePrintable(
            "\"not\" condition should only be `not: {}`.",
            "Illegal condition:", exprOption
        )
    }
    if !isObjectNotArray(subOption) {
        try log.throwError(errMsg)
    }
    let cond = NotConditionInternal()
    cond.child = try parseOption(subOption, getters)
    // upstream: if (!cond.child) throwError(errMsg);
    //   `parseOption` never returns null (it throws on failure), so `cond.child` is always set.
    return cond
}

// upstream: function parseRelationalOption(exprOption, getters): ParsedConditionInternal
private func parseRelationalOption<VGP>(
    _ exprOption: RelationalExpressionOption,
    _ getters: ConditionalGetters<VGP>
) throws -> ParsedConditionInternal {
    var errMsg = ""

    let valueGetterParam = try getters.prepareGetValue(exprOption)

    var subCondList: [FilterComparator] = []
    let exprKeys = util.keys(exprOption)

    let parserName = exprOption["parser"] as? String   // upstream: exprOption.parser
    let valueParser: RawValueParser? = (parserName != nil)
        ? dataValueHelper.getRawValueParser(parserName!)
        : nil

    for i in 0..<exprKeys.count {
        let keyRaw = exprKeys[i]
        // upstream: if (keyRaw === 'parser' || getters.valueGetterAttrMap.get(keyRaw)) continue;
        if keyRaw == "parser" || jsTruthy(getters.valueGetterAttrMap.get(keyRaw)) {
            continue
        }

        // upstream: hasOwn(RELATIONAL_EXPRESSION_OP_ALIAS_MAP, keyRaw)
        //     ? RELATIONAL_EXPRESSION_OP_ALIAS_MAP[keyRaw] : keyRaw
        let op: String = RELATIONAL_EXPRESSION_OP_ALIAS_MAP[keyRaw] ?? keyRaw
        // PORT (Int-vs-Double trap): upstream a relational operand is always a JS number (Double);
        //   in this port a numeric operand from the option bag is boxed as `Int` (e.g. `gt: 15`),
        //   which `util.isNumber` (Double-only, CONVENTIONS §1) would reject in `createFilterComparator`.
        //   Coerce Int-/NSNumber-boxed numbers to Double at this option-read boundary (a genuine string
        //   stays a string, so `eq`/`reg` semantics are unchanged).
        let condValueRaw = jsNumberize(exprOption[keyRaw])
        let condValueParsed: Any? = (valueParser != nil) ? valueParser!(condValueRaw) : condValueRaw

        // upstream: createFilterComparator(op, condValueParsed) || (op === 'reg' && new RegExpEvaluator(...))
        let base = try dataValueHelper.createFilterComparator(op, condValueParsed)
        let evaluator: FilterComparator?
        if base != nil {
            evaluator = base
        }
        else if op == "reg" {
            evaluator = try RegExpEvaluator(condValueParsed)
        }
        else {
            evaluator = nil
        }

        if evaluator == nil {   // upstream: if (!evaluator)
            if __DEV__ {
                errMsg = log.makePrintable(
                    "Illegal relational operation: \"" + keyRaw + "\" in condition:", exprOption
                )
            }
            try log.throwError(errMsg)
        }

        subCondList.append(evaluator!)
    }

    if subCondList.isEmpty {
        if __DEV__ {
            errMsg = log.makePrintable(
                "Relational condition must have at least one operator.",
                "Illegal condition:", exprOption
            )
        }
        // No relational operator always disabled in case of dangers result.
        try log.throwError(errMsg)
    }

    let cond = RelationalConditionInternal<VGP>()
    cond.valueGetterParam = valueGetterParam
    cond.valueParser = valueParser
    cond.getValue = getters.getValue
    cond.subCondList = subCondList

    return cond
}

// upstream: function isObjectNotArray(val): boolean { return isObject(val) && !isArrayLike(val); }
private func isObjectNotArray(_ val: Any?) -> Bool {
    return util.isObject(val) && !util.isArrayLike(val)
}

// upstream: class ConditionalExpressionParsed
public final class ConditionalExpressionParsed {

    private let _cond: ParsedConditionInternal

    // upstream: constructor(exprOption, getters) { this._cond = parseOption(exprOption, getters); }
    init<VGP>(
        _ exprOption: ConditionalExpressionOption,
        _ getters: ConditionalGetters<VGP>
    ) throws {
        self._cond = try parseOption(exprOption, getters)
    }

    public func evaluate() -> Bool {
        return self._cond.evaluate()
    }
}

// upstream: interface ConditionalGetters<VGP> { prepareGetValue; getValue; valueGetterAttrMap; }
public struct ConditionalGetters<VGP> {
    public var prepareGetValue: ConditionalExpressionValueGetterParamGetter<VGP>
    public var getValue: ConditionalExpressionValueGetter<VGP>
    public var valueGetterAttrMap: HashMap<Bool>

    public init(
        prepareGetValue: @escaping ConditionalExpressionValueGetterParamGetter<VGP>,
        getValue: @escaping ConditionalExpressionValueGetter<VGP>,
        valueGetterAttrMap: HashMap<Bool>
    ) {
        self.prepareGetValue = prepareGetValue
        self.getValue = getValue
        self.valueGetterAttrMap = valueGetterAttrMap
    }
}

// upstream: export function parseConditionalExpression<VGP>(exprOption, getters): ConditionalExpressionParsed
public func parseConditionalExpression<VGP>(
    _ exprOption: ConditionalExpressionOption,
    _ getters: ConditionalGetters<VGP>
) throws -> ConditionalExpressionParsed {
    return try ConditionalExpressionParsed(exprOption, getters)
}


// ============================================================================
// Local helpers (not part of upstream): JS value coercions used by the routines above.
// ============================================================================

// JS `exprOption === true || exprOption === false`. Only a genuine boolean qualifies — a `0`/`1`
// number literal must NOT be treated as a bool (Int-vs-Double / NSNumber-bridging trap).
private func asBoolLiteral(_ v: Any?) -> Bool? {
    guard let v = v else { return nil }
    // A Swift `Int`/`Double` never casts to `Bool`; guard the NSNumber-bridging case explicitly.
    if v is Int || v is Double { return nil }
    return v as? Bool
}

// JS `typeof x` for the value kinds reachable by `RegExpEvaluator.evaluate`.
private func jsTypeof(_ val: Any?) -> String {
    switch val {
    case nil: return "undefined"
    case is Bool: return "boolean"
    case is Double: return "number"
    case is String: return "string"
    default: return "object"
    }
}

// JS `RegExp.prototype.test` — whether the pattern matches anywhere in the subject string.
private func regexTest(_ re: NSRegularExpression, _ s: String) -> Bool {
    let range = NSRange(s.startIndex..., in: s)
    return re.firstMatch(in: s, options: [], range: range) != nil
}

// JS truthiness (`if (x)`): 0 / "" / NaN / null / undefined are falsy; objects/arrays are truthy.
private func jsTruthy(_ v: Any?) -> Bool {
    guard let v = v else { return false }
    if v is NSNull { return false }
    if let b = v as? Bool { return b }
    if let n = v as? Double { return n != 0 && !n.isNaN }
    if let i = v as? Int { return i != 0 }
    if let s = v as? String { return !s.isEmpty }
    return true
}

// Coerce an Int-/NSNumber-boxed numeric relational operand to Double, leaving strings, Bool, and
// everything else intact. Upstream a relational operand is always a JS number (Double); an option-bag
// numeric literal boxes as Swift `Int` (e.g. `gt: 15`), which the Double-only `util.isNumber` gate in
// `dataValueHelper.createFilterComparator` would reject — silently disabling order ops (lt/lte/gt/gte)
// for integer thresholds. A genuine string stays a string so `eq`/`reg` string semantics are unchanged.
// (Bool is checked first because it bridges to NSNumber; we must NOT turn `true` into `1.0`.)
private func jsNumberize(_ v: Any?) -> Any? {
    if v is Bool { return v }
    if v is Double { return v }
    if let i = v as? Int { return Double(i) }
    if let n = v as? NSNumber { return n.doubleValue }
    return v
}
