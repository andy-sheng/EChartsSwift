// Ported from echarts/src/component/dataZoom/dataZoomAction.ts — keep in sync with upstream
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
//   import GlobalModel from '../../model/Global';                     -> `GlobalModel`
//   import { findEffectedDataZooms } from './helper';                 -> dataZoomHelper.swift
//   import { EChartsExtensionInstallRegisters } from '../../extension'; -> `EChartsExtensionInstallRegisters` (coord/axisStatistics.swift stub)
//   import { each } from 'zrender/src/core/util';                     -> `util.each`

// ============================================================================
// TASK 1 (DataZoomModel) SURFACE additionally consumed here:
//   - dataZoomModel.setRawRange(start:end:startValue:endValue:)
// ============================================================================

// upstream: export default function installDataZoomAction(registers: EChartsExtensionInstallRegisters)
//   registers.registerAction('dataZoom', handler)
// PORT-NOTE: the `EChartsExtensionInstallRegisters` stub (coord/axisStatistics.swift) does not yet model
//   `registerAction`, so this calls the Phase-29 module-level `registerAction(type, action)` directly.
//   The integrator wires this from `installCommon` (like the visualMap action). `registers` is retained
//   in the signature to mirror upstream and for when the registrar gains `registerAction`.
public func installDataZoomAction(_ registers: EChartsExtensionInstallRegisters) {
    _ = registers
    registerAction("dataZoom") { payload, ecModel, _ in

        let effectedModels = findEffectedDataZooms(ecModel, payload)

        util.each(effectedModels) { dataZoomModel, _ in
            // upstream: dataZoomModel.setRawRange({ start, end, startValue, endValue }) from the payload.
            //   `start`/`end` are percents (coerce Int->Double per the option-read trap);
            //   `startValue`/`endValue` are raw values (number|string|Date) passed through.
            //   `setRawRange(_ opt:)` reads fields via `!= null`, so omit absent keys.
            var rangeOpt: [String: Any] = [:]
            if let s = dzActionCoerceNumber(payload.other["start"]) { rangeOpt["start"] = s }
            if let e = dzActionCoerceNumber(payload.other["end"]) { rangeOpt["end"] = e }
            if let sv = payload.other["startValue"], !(sv is NSNull) { rangeOpt["startValue"] = sv }
            if let ev = payload.other["endValue"], !(ev is NSNull) { rangeOpt["endValue"] = ev }
            dataZoomModel.setRawRange(rangeOpt)
        }

        return nil   // upstream returns void
    }
}

// Int-vs-Double payload-read trap: coerce a numeric payload field to `Double?` (nil for absent/non-numeric).
private func dzActionCoerceNumber(_ v: Any?) -> Double? {
    if v == nil || v is NSNull { return nil }
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let f = v as? CGFloat { return Double(f) }
    return nil
}
