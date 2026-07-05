// Ported from echarts/src/component/transform/sortTransform.ts — keep in sync with upstream
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

// upstream imports (mapped to this port; `→` marks the Swift symbol used):
//   import { DataTransformOption, ExternalDataTransform, ExternalDataTransformResultItem }
//       from '../../data/helper/transform';
//     -> `DataTransformOption` / `ExternalDataTransform` / `ExternalDataTransformResultItem`
//        (data/helper/transform.swift — Phase 27).
//   import { DimensionLoose, DimensionIndex, OptionDataValue, SOURCE_FORMAT_ARRAY_ROWS,
//       SOURCE_FORMAT_OBJECT_ROWS } from '../../util/types';
//     -> util/types.swift (`DimensionLoose` = Any, `DimensionIndex` = Double,
//        `OptionDataValue` = Any?, the two SOURCE_FORMAT_* string constants).
//   import { makePrintable, throwError } from '../../util/log';   -> `log.makePrintable` / `log.throwError`.
//   import { each } from 'zrender/src/core/util';                 -> inlined as a Swift `for` loop.
//   import { normalizeToArray } from '../../util/model';          -> `model.normalizeToArray`.
//   import { RawValueParserType, getRawValueParser, SortOrderComparator }
//       from '../../data/helper/dataValueHelper';
//     -> `RawValueParserType` / `dataValueHelper.getRawValueParser` / `SortOrderComparator`
//        (data/helper/dataValueHelper.swift — REUSED, not reimplemented).

import Foundation
import ZRenderKit

/**
 * @usage
 *
 * ```js
 * transform: {
 *     type: 'sort',
 *     config: { dimension: 'score', order: 'asc' }
 * }
 * transform: {
 *     type: 'sort',
 *     config: [
 *         { dimension: 1, order: 'asc' },
 *         { dimension: 'age', order: 'desc' }
 *     ]
 * }
 * ```
 */

// upstream:
//   export interface SortTransformOption extends DataTransformOption {
//       type: 'sort';
//       config: OrderExpression | OrderExpression[];
//   }
//   type OrderExpression = {
//       dimension: DimensionLoose;
//       order: 'asc' | 'desc';
//       parser?: RawValueParserType;
//       incomparable?: 'min' | 'max';
//   };
//
// PORT: the config option interfaces are kept as Swift structs for the programmatic/typed path.
//   At runtime `params.config` flows from the dynamic `[String: Any]` option bag (CONVENTIONS §2),
//   so the transform below reads each order via `readOrderExpr` which accepts BOTH an
//   `OrderExpression` struct and a raw `[String: Any]` dict.

// PENDING (upstream): whether support { dimension: 'score', order: 'asc' } ?
public struct OrderExpression {
    // upstream: dimension: DimensionLoose (string | number).
    public var dimension: DimensionLoose?
    // upstream: order: 'asc' | 'desc'.
    public var order: String
    // upstream: parser?: RawValueParserType.
    public var parser: RawValueParserType?
    // The meaning of "incomparable": see [SORT_COMPARISON_RULE] in `data/helper/dataValueHelper`.
    // upstream: incomparable?: 'min' | 'max'.
    public var incomparable: String?

    public init(
        dimension: DimensionLoose? = nil,
        order: String,
        parser: RawValueParserType? = nil,
        incomparable: String? = nil
    ) {
        self.dimension = dimension
        self.order = order
        self.parser = parser
        self.incomparable = incomparable
    }
}

// upstream: `SortTransformOption extends DataTransformOption { type: 'sort'; config: ... }`.
//   Provided for the typed/programmatic path; the field-level narrowing over `config` mirrors upstream.
public struct SortTransformOption {
    public var type: String = "sort"
    // upstream: OrderExpression | OrderExpression[].
    public var config: Any?

    public init(config: Any?) {
        self.config = config
    }
}

// upstream:
//   let sampleLog = '';
//   if (__DEV__) { sampleLog = [...].join(' '); }
private let sampleLog: String = {
    if __DEV__ {
        return [
            "Valid config is like:",
            "{ dimension: \"age\", order: \"asc\" }",
            "or [{ dimension: \"age\", order: \"asc\"], { dimension: \"date\", order: \"desc\" }]"
        ].joined(separator: " ")
    }
    return ""
}()

// A resolved order key (upstream inline object in `orderDefList`).
private struct OrderDef {
    let dimIdx: DimensionIndex               // upstream: dimIdx: DimensionIndex
    let parser: RawValueParser?              // upstream: parser: ReturnType<typeof getRawValueParser>
    let comparator: SortOrderComparator      // upstream: comparator: SortOrderComparator
}

// upstream: export const sortTransform: ExternalDataTransform<SortTransformOption> = { type, transform }
public let sortTransform: ExternalDataTransform = ExternalDataTransform(
    type: "echarts:sort",
    transform: { params in
        let upstream = params.upstream
        let config = params.config
        var errMsg = ""

        // Normalize
        // upstream: const orderExprList: OrderExpression[] = normalizeToArray(config);
        //   `config` is a single order (struct/dict) or an array of them; normalize to a list.
        let orderExprList: [Any] = model.normalizeToArray(config)

        if orderExprList.isEmpty {
            if __DEV__ {
                errMsg = "Empty `config` in sort transform."
            }
            // PORT: the `transform` closure type is non-throwing; upstream `throwError` throws an
            //   uncaught Error that halts the pipeline. `try!` reproduces that fatal-on-invalid-config
            //   behavior (the branch is only reached on user misconfiguration).
            try! log.throwError(errMsg)
        }

        var orderDefList: [OrderDef] = []
        // upstream: each(orderExprList, function (orderExpr) { ... })
        for orderExprAny in orderExprList {
            let orderExpr = readOrderExpr(orderExprAny)
            let dimLoose = orderExpr.dimension        // upstream: orderExpr.dimension
            let order = orderExpr.order               // upstream: orderExpr.order
            let parserName = orderExpr.parser         // upstream: orderExpr.parser
            let incomparable = orderExpr.incomparable // upstream: orderExpr.incomparable

            // upstream: if (dimLoose == null) { ... throwError }
            if isNullish(dimLoose) {
                if __DEV__ {
                    errMsg = "Sort transform config must has \"dimension\" specified." + sampleLog
                }
                try! log.throwError(errMsg)
            }

            // upstream: if (order !== 'asc' && order !== 'desc') { ... throwError }
            if order != "asc" && order != "desc" {
                if __DEV__ {
                    errMsg = "Sort transform config must has \"order\" specified." + sampleLog
                }
                try! log.throwError(errMsg)
            }

            // upstream: if (incomparable && (incomparable !== 'min' && incomparable !== 'max')) { ... }
            //   JS truthiness on a string: nil/"" are falsy — use `jsTruthy`.
            if jsTruthy(incomparable) && (incomparable != "min" && incomparable != "max") {
                var errMsg = ""
                if __DEV__ {
                    errMsg = "incomparable must be \"min\" or \"max\" rather than \""
                        + (incomparable ?? "") + "\"."
                }
                try! log.throwError(errMsg)
            }
            // upstream: (duplicated order check) if (order !== 'asc' && order !== 'desc') { ... }
            if order != "asc" && order != "desc" {
                var errMsg = ""
                if __DEV__ {
                    errMsg = "order must be \"asc\" or \"desc\" rather than \"" + order + "\"."
                }
                try! log.throwError(errMsg)
            }

            // upstream: const dimInfo = upstream.getDimensionInfo(dimLoose);
            let dimInfo = upstream.getDimensionInfo(dimLoose)
            guard let dimInfo = dimInfo else {
                // upstream: if (!dimInfo) { ... makePrintable(...); throwError }
                if __DEV__ {
                    errMsg = log.makePrintable(
                        "Can not find dimension info via: " + jsToDisplayString(dimLoose) + ".\n",
                        "Existing dimensions: ", upstream.cloneAllDimensionInfo(), ".\n",
                        "Illegal config:", orderExprAny, ".\n"
                    )
                }
                try! log.throwError(errMsg)
                // unreachable: throwError always throws.
                fatalError("unreachable")
            }

            // upstream: const parser = parserName ? getRawValueParser(parserName) : null;
            //   JS truthiness on `parserName` (nil/"" falsy) — use `jsTruthy`.
            let parser = jsTruthy(parserName) ? dataValueHelper.getRawValueParser(parserName!) : nil
            // upstream: if (parserName && !parser) { ... throwError }
            if jsTruthy(parserName) && parser == nil {
                if __DEV__ {
                    errMsg = log.makePrintable(
                        "Invalid parser name " + (parserName ?? "") + ".\n",
                        "Illegal config:", orderExprAny, ".\n"
                    )
                }
                try! log.throwError(errMsg)
            }

            // upstream: orderDefList.push({ dimIdx: dimInfo.index, parser, comparator: new SortOrderComparator(order, incomparable) });
            orderDefList.append(OrderDef(
                dimIdx: dimInfo.index,
                parser: parser,
                comparator: SortOrderComparator(order, incomparable)
            ))
        }

        // TODO (upstream): support it?
        // upstream: const sourceFormat = upstream.sourceFormat;
        let sourceFormat = upstream.sourceFormat
        if sourceFormat != SOURCE_FORMAT_ARRAY_ROWS
            && sourceFormat != SOURCE_FORMAT_OBJECT_ROWS
        {
            if __DEV__ {
                errMsg = "sourceFormat \"" + sourceFormat + "\" is not supported yet"
            }
            try! log.throwError(errMsg)
        }

        // Other upstream format are all array.
        // upstream:
        //   const resultData = [];
        //   for (let i = 0, len = upstream.count(); i < len; i++) { resultData.push(upstream.getRawDataItem(i)); }
        var resultData: [Any] = []
        let len = Int(upstream.count())
        var i = 0
        while i < len {
            // PORT: `getRawDataItem` is a `throws` stored closure, but for a BUILT-IN transform it is
            //   overridden with the (non-throwing) raw-source getter, so `try!` never actually traps.
            //   A nil item is normalized to `NSNull` (JS `null`) so `result.data` stays a `[Any]`
            //   (downstream `detectSourceFormat` / header-concat casts to `[Any]`).
            let item = try! upstream.getRawDataItem(Double(i))
            resultData.append(item ?? NSNull())
            i += 1
        }

        // upstream: resultData.sort(function (item0, item1) { ... });
        //   `Array.prototype.sort` is stable (ES2019); Swift `sort(by:)` is NOT — decorate with the
        //   original index and use it as the final tiebreak to reproduce stable ordering.
        var indexed: [(Int, Any)] = resultData.enumerated().map { ($0.offset, $0.element) }
        indexed.sort { a, b in
            let item0 = a.1
            let item1 = b.1
            for orderDef in orderDefList {
                // upstream: let val0 = upstream.retrieveValueFromItem(item0, orderDef.dimIdx);
                var val0: OptionDataValue = upstream.retrieveValueFromItem(item0, orderDef.dimIdx)
                var val1: OptionDataValue = upstream.retrieveValueFromItem(item1, orderDef.dimIdx)
                // upstream: if (orderDef.parser) { val0 = orderDef.parser(val0); val1 = orderDef.parser(val1); }
                if let parser = orderDef.parser {
                    val0 = parser(val0)
                    val1 = parser(val1)
                }
                // upstream: const result = orderDef.comparator.evaluate(val0, val1); if (result !== 0) { return result; }
                //   `evaluate` returns -1|0|1 already honoring order (asc/desc) & incomparable
                //   (min/max) placement — see SortOrderComparator in dataValueHelper.
                let result = orderDef.comparator.evaluate(val0, val1)
                if result != 0 {
                    return result < 0   // areInIncreasingOrder: item0 before item1 iff comparator < 0
                }
            }
            // upstream `return 0;` -> equal keys: preserve original order (stable tiebreak).
            return a.0 < b.0
        }
        resultData = indexed.map { $0.1 }

        // upstream: return { data: resultData };
        return ExternalDataTransformResultItem(data: resultData)
    }
)


// ============================================================================
// Local helpers (not part of upstream): config field reads + JS value coercions.
// ============================================================================

// Read an order expression from either an `OrderExpression` struct (typed/programmatic path) or a
// raw `[String: Any]` dict (option-bag path). Mirrors upstream's plain-object property reads.
private func readOrderExpr(_ raw: Any) -> OrderExpression {
    if let expr = raw as? OrderExpression {
        return expr
    }
    if let dict = raw as? [String: Any] {
        return OrderExpression(
            dimension: dict["dimension"],                   // DimensionLoose (string | number)
            order: (dict["order"] as? String) ?? "",        // 'asc' | 'desc' (invalid -> "" fails the guard)
            parser: dict["parser"] as? String,              // RawValueParserType?
            incomparable: dict["incomparable"] as? String   // 'min' | 'max'
        )
    }
    // Neither struct nor dict: an order with no dimension (fails the `dimLoose == null` guard, matching
    // upstream reading properties off a non-object).
    return OrderExpression(order: "")
}

// JS `x == null` (null or undefined). NSNull models an explicit JS `null`.
private func isNullish(_ v: Any?) -> Bool {
    return v == nil || v is NSNull
}

// JS truthiness for the string-typed config fields reached here (nil / "" are falsy).
private func jsTruthy(_ v: String?) -> Bool {
    guard let v = v else { return false }
    return !v.isEmpty
}

// Best-effort JS `'' + value` for the dev-only error message (dimension is a string or number).
private func jsToDisplayString(_ v: Any?) -> String {
    switch v {
    case nil: return "undefined"
    case is NSNull: return "null"
    case let s as String: return s
    case let d as Double:
        if d == d.rounded() && Swift.abs(d) < 1e15 { return String(Int(d)) }
        return String(d)
    case let i as Int: return String(i)
    default: return String(describing: v!)
    }
}
