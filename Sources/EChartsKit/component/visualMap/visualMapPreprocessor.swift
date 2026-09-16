// Ported from echarts/src/component/visualMap/preprocessor.ts — keep in sync with upstream
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
import Foundation
import ZRenderKit

// import * as zrUtil from 'zrender/src/core/util';   -> `util.isArray` / `util.isObject` (ZRenderKit).
// const each = zrUtil.each;                           -> Swift `for` loops (value-type writeback, see below).

// upstream registration (installCommon.ts): `registers.registerPreprocessor(preprocessor)`.
//   The preprocessor is real option-normalization logic, so it is ported as the standalone
//   `visualMapPreprocessor` function below for the Orchestrate driver to register.

// export default function visualMapPreprocessor(option) { ... }
//
// note (CONVENTIONS §3 value-type writeback): upstream mutates the `opt` / `piece` OBJECTS in
//   place through JS references, so the changes propagate back into `option.visualMap` even though the
//   local `visualMap` variable is only reassigned (never written back). Swift dictionaries/arrays are
//   value types, so we mutate copies and WRITE THE NORMALIZED ARRAY BACK to `option["visualMap"]`.
//   Consequence/deviation: a single-object `visualMap` is normalized to a one-element array here,
//   whereas upstream leaves it as a single object (only the referenced object receives the
//   pieces/min/max mutations). Re-normalization downstream is idempotent, so this is behavior-safe.
public func visualMapPreprocessor(_ option: inout ECUnitOption) {
    // let visualMap = option && option.visualMap;
    let visualMap = option["visualMap"]

    // if (!zrUtil.isArray(visualMap)) { visualMap = visualMap ? [visualMap] : []; }
    var visualMapArr: [Any]
    if let arr = visualMap as? [Any] {
        visualMapArr = arr
    }
    else {
        visualMapArr = jsTruthy(visualMap) ? [visualMap!] : []
    }

    // each(visualMap, function (opt) { ... });
    for i in 0..<visualMapArr.count {
        // if (!opt) { return; }
        guard jsTruthy(visualMapArr[i]), var opt = visualMapArr[i] as? [String: Any] else {
            continue
        }

        // rename splitList to pieces
        // if (has(opt, 'splitList') && !has(opt, 'pieces')) { opt.pieces = opt.splitList; delete opt.splitList; }
        if opt["splitList"] != nil && opt["pieces"] == nil {
            opt["pieces"] = opt["splitList"]
            opt["splitList"] = nil
        }

        // const pieces = opt.pieces;
        // if (pieces && zrUtil.isArray(pieces)) { each(pieces, function (piece) { ... }); }
        if var pieces = opt["pieces"] as? [Any] {
            for j in 0..<pieces.count {
                // if (zrUtil.isObject(piece)) { ... }
                guard var piece = pieces[j] as? [String: Any] else {
                    continue
                }
                // if (has(piece, 'start') && !has(piece, 'min')) { piece.min = piece.start; }
                if piece["start"] != nil && piece["min"] == nil {
                    piece["min"] = piece["start"]
                }
                // if (has(piece, 'end') && !has(piece, 'max')) { piece.max = piece.end; }
                if piece["end"] != nil && piece["max"] == nil {
                    piece["max"] = piece["end"]
                }
                pieces[j] = piece
            }
            opt["pieces"] = pieces
        }

        // Validate seriesTargets
        // if (__DEV__) {
        //     const seriesTargets = opt.seriesTargets;
        //     if (seriesTargets && zrUtil.isArray(seriesTargets)) {
        //         each(seriesTargets, function (target) {
        //             if (!zrUtil.isObject(target) || target.dimension == null) {
        //                 console.warn('Each seriesTarget should have a dimension property');
        //             }
        //             if (target.seriesIndex == null && target.seriesId == null) {
        //                 console.warn('Each seriesTarget should have either seriesIndex or seriesId');
        //             }
        //         });
        //     }
        // }
        // dev-only (`__DEV__`) validation warnings preserved above; not executed in the port.

        visualMapArr[i] = opt
    }

    // value-type writeback (see the top-of-function note).
    option["visualMap"] = visualMapArr
}

// function has(obj, name) { return obj && obj.hasOwnProperty && obj.hasOwnProperty(name); }
//   -> inlined above as `dict["name"] != nil` (CONVENTIONS §8).

// MARK: - Local JS-coercion helper (replicate JS truthiness, not Swift `??`).

private func jsTruthy(_ v: Any?) -> Bool {
    guard let v = v else { return false }
    if v is NSNull { return false }
    if let b = v as? Bool { return b }
    if let n = v as? Double { return n != 0 && !n.isNaN }
    if let i = v as? Int { return i != 0 }
    if let n = v as? NSNumber { return n.doubleValue != 0 }
    if let s = v as? String { return !s.isEmpty }
    if let a = v as? [Any] { _ = a; return true }   // arrays (even empty) are truthy in JS
    if let d = v as? [String: Any] { _ = d; return true }
    return true
}
