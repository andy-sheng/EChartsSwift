// Ported from echarts/src/component/transform/filterTransform.ts — keep in sync with upstream
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
//   import { DataTransformOption, ExternalDataTransform, DataTransformDataItem,
//       ExternalDataTransformResultItem } from '../../data/helper/transform';
//     -> data/helper/transform.swift (Phase 27): `DataTransformOption`, `ExternalDataTransform`,
//        `DataTransformDataItem` (= Any?), `ExternalDataTransformResultItem` (has `.data`).
//   import { DimensionIndex } from '../../util/types';   -> util/types.swift (`DimensionIndex` = Double).
//   import { parseConditionalExpression, ConditionalExpressionOption }
//       from '../../util/conditionalExpression';
//     -> util/conditionalExpression.swift: `parseConditionalExpression` / `ConditionalExpressionOption`
//        / `ConditionalGetters` (REUSED, not reimplemented).
//   import { hasOwn, createHashMap } from 'zrender/src/core/util';
//     -> `hasOwn(o, k)` -> `dict.keys.contains(k)`; `createHashMap` -> the `HashMap<Bool>` shim
//        (util/modelUtil.swift) built then populated (the shim ctor takes no seed object).
//   import { makePrintable, throwError } from '../../util/log';   -> `log.makePrintable` / `log.throwError`.
import Foundation
import ZRenderKit

// upstream:
//   export interface FilterTransformOption extends DataTransformOption {
//       type: 'filter';
//       config: ConditionalExpressionOption;
//   }
// PORT: kept as a Swift struct for the typed/programmatic path; at runtime `params.config` flows
//   from the dynamic option bag (CONVENTIONS §2) and is consumed directly as `ConditionalExpressionOption`.
public struct FilterTransformOption {
    public var type: String = "filter"
    public var config: ConditionalExpressionOption

    public init(config: ConditionalExpressionOption) {
        self.config = config
    }
}

// Value-getter param for the filter condition (upstream inline generic `{ dimIdx: DimensionIndex }`).
private struct FilterValueGetterParam {
    let dimIdx: DimensionIndex
}

// upstream: export const filterTransform: ExternalDataTransform<FilterTransformOption> = { type, transform }
public let filterTransform: ExternalDataTransform = ExternalDataTransform(
    type: "echarts:filter",

    // PENDING: enhance to filter by index rather than create new data
    transform: { params in
        // [Caveat] Fail-Fast:
        // Do not return the whole dataset unless user config indicates it explicitly.
        // For example, if no condition is specified by mistake, returning an empty result
        // is better than returning the entire raw source for the user to find the mistake.

        let upstream = params.upstream
        // upstream: `let rawItem: DataTransformDataItem;` — set per-iteration below and captured
        //   (by reference) by the `getValue` closure. Swift closes over the local `var` box; it must
        //   be initialized before the capturing closure is formed, so seed it to nil (JS `undefined`).
        var rawItem: DataTransformDataItem = nil

        // upstream: createHashMap<boolean, string>({ dimension: true })
        let valueGetterAttrMap: HashMap<Bool> = createHashMap()
        _ = valueGetterAttrMap.set("dimension", true)

        // upstream: const condition = parseConditionalExpression<{ dimIdx: DimensionIndex }>(params.config, {...})
        // PORT: the `transform` closure type is non-throwing; upstream `throwError` throws an uncaught
        //   Error that halts the pipeline. `try!` reproduces that fatal-on-invalid-config behavior — it
        //   is only reached on user misconfiguration (missing/unknown dimension, illegal operator, etc.).
        let condition = try! parseConditionalExpression(
            params.config,
            ConditionalGetters<FilterValueGetterParam>(
                prepareGetValue: { exprOption in
                    var errMsg = ""
                    let dimLoose = exprOption["dimension"]   // upstream: exprOption.dimension
                    // upstream: if (!hasOwn(exprOption, 'dimension')) { ... throwError }
                    if !exprOption.keys.contains("dimension") {
                        if __DEV__ {
                            errMsg = log.makePrintable(
                                "Relation condition must has prop \"dimension\" specified.",
                                "Illegal condition:", exprOption
                            )
                        }
                        try log.throwError(errMsg)
                    }

                    // upstream: const dimInfo = upstream.getDimensionInfo(dimLoose);
                    let dimInfo = upstream.getDimensionInfo(dimLoose)
                    if dimInfo == nil {   // upstream: if (!dimInfo)
                        if __DEV__ {
                            errMsg = log.makePrintable(
                                "Can not find dimension info via: " + jsToDisplayString(dimLoose) + ".\n",
                                "Existing dimensions: ", upstream.cloneAllDimensionInfo(), ".\n",
                                "Illegal condition:", exprOption, ".\n"
                            )
                        }
                        try log.throwError(errMsg)
                    }

                    // upstream: return { dimIdx: dimInfo.index };
                    return FilterValueGetterParam(dimIdx: dimInfo!.index)
                },

                getValue: { param in
                    // upstream: return upstream.retrieveValueFromItem(rawItem, param.dimIdx);
                    return upstream.retrieveValueFromItem(rawItem, param.dimIdx)
                },

                valueGetterAttrMap: valueGetterAttrMap
            )
        )

        // upstream:
        //   const resultData = [];
        //   for (let i = 0, len = upstream.count(); i < len; i++) {
        //       rawItem = upstream.getRawDataItem(i);
        //       if (condition.evaluate()) { resultData.push(rawItem); }
        //   }
        var resultData: [Any] = []
        let len = Int(upstream.count())
        var i = 0
        while i < len {
            // PORT: `getRawDataItem` is a `throws` stored closure, but for a BUILT-IN transform it is
            //   overridden with the (non-throwing) raw-source getter, so `try!` never actually traps.
            //   A nil item is normalized to `NSNull` (JS `null`) so `result.data` stays a `[Any]`.
            rawItem = try! upstream.getRawDataItem(Double(i))
            if condition.evaluate() {
                resultData.append(rawItem ?? NSNull())
            }
            i += 1
        }

        // upstream: return { data: resultData };
        return ExternalDataTransformResultItem(data: resultData)
    }
)


// ============================================================================
// Local helpers (not part of upstream): JS value coercion for the dev-only error message.
// ============================================================================

// Best-effort JS `'' + value` for the dev-only "Can not find dimension" message
// (a dimension reference is a string or a number).
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
