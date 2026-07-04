// Ported from echarts/src/coord/parallel/parallelPreprocessor.ts — keep in sync with upstream
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
//   import * as zrUtil from 'zrender/src/core/util';                 -> `util.each` / `util.isObject` / `util.merge`.
//   import * as modelUtil from '../../util/model';                   -> `model.normalizeToArray` (util/modelUtil.swift).
//   import { ECUnitOption, SeriesOption } from '../../util/types';   -> ECUnitOption (util/types.swift; == [String: Any]).
//   import { ParallelAxisOption } from './AxisModel';               -> collapsed (dynamic option bag).
//   import { ParallelSeriesOption } from '../../chart/parallel/ParallelSeries';   -> collapsed (dynamic option bag).

// export default function parallelPreprocessor(option: ECUnitOption): void
//
// PORT-TODO: upstream mutates the shared `option` object (and its nested `parallel` / `parallelAxis`
//   items) IN PLACE. Swift `[String: Any]`/`ECUnitOption` are value types, so the port takes `inout`
//   and writes the mutated structures back (mirrors candlestick/preprocessor.swift's precedent). The
//   `OptionPreprocessor` registration is owned by the Integrate stage.
public func parallelPreprocessor(_ option: inout ECUnitOption) {
    // createParallelIfNeeded(option);
    createParallelIfNeeded(&option)
    // mergeAxisOptionFromParallel(option);
    mergeAxisOptionFromParallel(&option)
}

/**
 * Create a parallel coordinate if not exists.
 * @inner
 */
// function createParallelIfNeeded(option: ECUnitOption): void
private func createParallelIfNeeded(_ option: inout ECUnitOption) {
    // if (option.parallel) { return; }
    //   JS truthiness: an object/array is truthy, so only null/undefined skips creation -> nil check.
    if option["parallel"] != nil && !(option["parallel"] is NSNull) {
        return
    }

    // let hasParallelSeries = false;
    var hasParallelSeries = false

    // zrUtil.each(option.series, function (seriesOpt: SeriesOption) {
    //     if (seriesOpt && seriesOpt.type === 'parallel') { hasParallelSeries = true; }
    // });
    //   `option.series` is normally an array; `each` on undefined is a no-op -> pass `as? [Any]`.
    util.each(option["series"] as? [Any]) { seriesOptAny, _ in
        if let seriesOpt = seriesOptAny as? [String: Any], (seriesOpt["type"] as? String) == "parallel" {
            hasParallelSeries = true
        }
    }

    // if (hasParallelSeries) { option.parallel = [{}]; }
    if hasParallelSeries {
        option["parallel"] = [[String: Any]()]
    }
}

/**
 * Merge aixs definition from parallel option (if exists) to axis option.
 * @inner
 */
// function mergeAxisOptionFromParallel(option: ECUnitOption): void
private func mergeAxisOptionFromParallel(_ option: inout ECUnitOption) {
    // const axes = modelUtil.normalizeToArray(option.parallelAxis) as ParallelAxisOption[];
    let rawParallelAxis = option["parallelAxis"]
    var axes: [Any] = model.normalizeToArray(rawParallelAxis)

    // (hoisted once) modelUtil.normalizeToArray(option.parallel) — read per-axis below in upstream, but
    //   invariant across the loop, so evaluated once here.
    let parallelList: [Any] = model.normalizeToArray(option["parallel"])

    // zrUtil.each(axes, function (axisOption) { ... });
    util.each(axes) { axisOptionAny, idx in
        // if (!zrUtil.isObject(axisOption)) { return; }
        guard util.isObject(axisOptionAny), var axisOption = axisOptionAny as? [String: Any] else {
            return
        }

        // const parallelIndex = axisOption.parallelIndex || 0;
        //   `|| 0` (JS falsy): a missing/0 parallelIndex resolves to 0.
        let parallelIndex = Int(numOpt(axisOption["parallelIndex"]) ?? 0)

        // const parallelOption = modelUtil.normalizeToArray(option.parallel)[parallelIndex] as ParallelSeriesOption;
        let parallelOption = (parallelIndex >= 0 && parallelIndex < parallelList.count)
            ? parallelList[parallelIndex] as? [String: Any]
            : nil

        // if (parallelOption && parallelOption.parallelAxisDefault) {
        //     zrUtil.merge(axisOption, parallelOption.parallelAxisDefault, false);
        // }
        //   PORT-TODO: upstream mutates the `axisOption` object in place; Swift value types require the
        //   write-back into `axes[idx]` below.
        if let parallelOption = parallelOption,
           let parallelAxisDefault = parallelOption["parallelAxisDefault"] as? [String: Any] {
            util.merge(&axisOption, parallelAxisDefault, false)
            axes[idx] = axisOption
        }
    }

    // Write the mutated axes back into `option.parallelAxis`, preserving upstream's array/single shape
    // (upstream relies on object identity; the value-type port must re-assign — see PORT-TODO above).
    if util.isArray(rawParallelAxis) {
        option["parallelAxis"] = axes
    }
    else if !axes.isEmpty {
        option["parallelAxis"] = axes[0]
    }
}

// Coerce a dynamic option value to Double, tolerating the Int boxing that `[String: Any]` option
// literals use. A bare `as? Double` returns nil on an Int, silently dropping the value — the
// recurring Int-vs-Double option-read trap.
private func numOpt(_ v: Any?) -> Double? {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let n = v as? NSNumber, !(n === kCFBooleanTrue || n === kCFBooleanFalse) { return n.doubleValue }
    return nil
}
