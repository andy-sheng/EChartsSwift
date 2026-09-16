// Ported from echarts/src/component/visualMap/typeDefaulter.ts — keep in sync with upstream
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

// import Component from '../../model/Component';
//   -> `ComponentModel` (model/Component.swift) — carries `registerSubTypeDefaulter`.
// import {VisualMapOption} from './VisualMapModel';
//   -> note: component/visualMap/VisualMapModel.swift is ported. This defaulter still reads the
//      option is read out of the dynamic option bag (`ComponentOption.rawOption`) instead of the typed
//      `VisualMapOption`.
// import {PiecewiseVisualMapOption} from './PiecewiseModel';
//   -> note: component/visualMap/PiecewiseModel.swift is ported; `pieces` / `splitNumber` are read
//      from the same dynamic bag.
// import {ContinuousVisualMapOption} from './ContinuousModel';
//   -> note: component/visualMap/ContinuousModel.swift is ported; `calculable` read from the bag.

// upstream is a module-load side effect:
//
//   Component.registerSubTypeDefaulter(
//       'visualMap', function (option: VisualMapOption) { ... });
//
// Swift libraries have no top-level statements, so the defaulter closure is exposed as
// `visualMapSubTypeDefaulter` and the registration is performed by `registerVisualMapSubTypeDefaulter()`
// (called by the Orchestrate driver, or equivalently by installCommon).
//
// NOTE: `installCommon.ts` registers the IDENTICAL defaulter through
//   `registers.registerSubTypeDefaulter('visualMap', ...)`; both share this one closure so the two
//   upstream code paths stay in lock-step.

public let visualMapSubTypeDefaulter: component.SubTypeDefaulter = { option in
    // upstream reads the typed `VisualMapOption`; here the fields live in the raw dynamic bag.
    let opt = option.rawOption ?? [:]

    // Compatible with ec2, when splitNumber === 0, continuous visualMap will be used.
    // return (
    //     !option.categories
    //     && (
    //         !(
    //             (option as PiecewiseVisualMapOption).pieces
    //                 ? ((option as PiecewiseVisualMapOption)).pieces.length > 0
    //                 : ((option as PiecewiseVisualMapOption)).splitNumber > 0
    //         )
    //         || (option as ContinuousVisualMapOption).calculable
    //     )
    // )
    //     ? 'continuous' : 'piecewise';
    let piecesRaw = opt["pieces"]
    let piecesTest: Bool
    if jsTruthy(piecesRaw) {                                  // (option).pieces ? ... : ...
        // (option).pieces.length > 0
        piecesTest = ((piecesRaw as? [Any])?.count ?? 0) > 0
    }
    else {
        // (option).splitNumber > 0   (INT-or-Double safe read, CONVENTIONS trap #1)
        piecesTest = asDouble(opt["splitNumber"]) > 0
    }

    let calculable = jsTruthy(opt["calculable"])
    let result = !jsTruthy(opt["categories"]) && (!piecesTest || calculable)

    return result ? "continuous" : "piecewise"
}

/// Performs the module-load registration that upstream `typeDefaulter.ts` does implicitly on import.
/// (Also invoked from the `installCommon` integration surface — see installCommon.swift.)
public func registerVisualMapSubTypeDefaulter() {
    ComponentModel.registerSubTypeDefaulter("visualMap", visualMapSubTypeDefaulter)
}

// MARK: - Local JS-coercion helpers (CONVENTIONS trap #1: never read a numeric option with a bare
//   `as? Double`; replicate JS truthiness with `jsTruthy`, not Swift `??`).

private func asDouble(_ v: Any?) -> Double {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let n = v as? NSNumber { return n.doubleValue }
    if let s = v as? String, let d = Double(s) { return d }
    return Double.nan
}

private func jsTruthy(_ v: Any?) -> Bool {
    guard let v = v else { return false }
    if v is NSNull { return false }
    if let b = v as? Bool { return b }
    if let n = v as? Double { return n != 0 && !n.isNaN }
    if let i = v as? Int { return i != 0 }
    if let n = v as? NSNumber { return n.doubleValue != 0 }
    if let s = v as? String { return !s.isEmpty }
    if let a = v as? [Any] { _ = a; return true }   // arrays (even empty) are truthy in JS
    return true
}
