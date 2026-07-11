// Ported from echarts/src/chart/radar/backwardCompat.ts — keep in sync with upstream
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

// @ts-nocheck

// Backward compat for radar chart in 2

import Foundation
import ZRenderKit

// upstream imports:
//   import * as zrUtil from 'zrender/src/core/util';  -> `util.isArray` / `util.each` (ZRenderKit).

// upstream: export default function radarBackwardCompat(option)
//
// PORT-NOTE: `option.polar` / `option.radar` / `option.series` items are objects that upstream mutates
//   IN PLACE (`polarOpt.shape = ...`, `seriesOpt.radarIndex = ...`). Swift `[String: Any]` is a value
//   type, so the port takes `inout` and writes the mutated items back (mirrors chart/candlestick/
//   preprocessor.swift's `candlestickPreprocessor(_:)`). The `OptionPreprocessor` registration is owned
//   by the Integrate stage.
public func radarBackwardCompat(_ option: inout ECUnitOption) {
    // let polarOptArr = option.polar;
    // if (polarOptArr) { ... }
    //   JS truthiness: any non-null polar value (single object OR array, even empty) enters the block.
    if let polarOptRaw = option["polar"], jsTruthy(polarOptRaw) {
        // if (!zrUtil.isArray(polarOptArr)) { polarOptArr = [polarOptArr]; }
        var polarOptArr: [Any]
        if !util.isArray(polarOptRaw) {
            polarOptArr = [polarOptRaw]
        }
        else {
            polarOptArr = polarOptRaw as! [Any]
        }

        // const polarNotRadar = [];
        var polarNotRadar: [Any] = []

        // zrUtil.each(polarOptArr, function (polarOpt, idx) { ... });
        util.each(polarOptArr) { polarOptAny, _ in
            // upstream `polarOpt` is an option object; the `.indicator`/`.type`/`.shape` accesses require
            //   a keyed bag.
            guard var polarOpt = polarOptAny as? [String: Any] else {
                // Non-object polar entry: it can not carry an `indicator`, so it stays a (non-radar) polar.
                polarNotRadar.append(polarOptAny)
                return
            }

            // if (polarOpt.indicator) {
            if jsTruthy(polarOpt["indicator"]) {
                // if (polarOpt.type && !polarOpt.shape) { polarOpt.shape = polarOpt.type; }
                if jsTruthy(polarOpt["type"]) && !jsTruthy(polarOpt["shape"]) {
                    polarOpt["shape"] = polarOpt["type"]
                }

                // option.radar = option.radar || [];
                var radarVal: Any = jsTruthy(option["radar"]) ? option["radar"]! : [Any]()
                // if (!zrUtil.isArray(option.radar)) { option.radar = [option.radar]; }
                if !util.isArray(radarVal) {
                    radarVal = [radarVal]
                }
                var radarArr = radarVal as! [Any]
                // option.radar.push(polarOpt);
                radarArr.append(polarOpt)
                option["radar"] = radarArr
            }
            else {
                // polarNotRadar.push(polarOpt);
                polarNotRadar.append(polarOpt)
            }
        }

        // option.polar = polarNotRadar;
        option["polar"] = polarNotRadar
    }

    // zrUtil.each(option.series, function (seriesOpt) { ... });
    if var series = option["series"] as? [Any] {
        util.each(series) { seriesOptAny, index in
            // if (seriesOpt && seriesOpt.type === 'radar' && seriesOpt.polarIndex) {
            //     seriesOpt.radarIndex = seriesOpt.polarIndex;
            // }
            if var seriesOpt = seriesOptAny as? [String: Any],
                (seriesOpt["type"] as? String) == "radar",
                jsTruthy(seriesOpt["polarIndex"]) {
                seriesOpt["radarIndex"] = seriesOpt["polarIndex"]
                series[index] = seriesOpt
            }
        }
        option["series"] = series
    }
}

// JS truthiness (nil / NSNull / '' / false / 0 / NaN are falsy). Not an upstream symbol — a file-local
//   helper (same shape as the `jsTruthy` in sibling preprocessor/series ports).
private func jsTruthy(_ v: Any?) -> Bool {
    switch v {
    case nil: return false
    case is NSNull: return false
    case let b as Bool: return b
    case let s as String: return !s.isEmpty
    case let d as Double: return d != 0 && !d.isNaN
    case let i as Int: return i != 0
    default: return true
    }
}
