// Ported from echarts/src/processor/dataSample.ts — keep in sync with upstream
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

// import { StageHandler, SeriesOption, SeriesSamplingOptionMixin } from '../util/types';
// import { Dictionary } from 'zrender/src/core/types';
// import SeriesModel from '../model/Series';
// import { isFunction, isString } from 'zrender/src/core/util';

// upstream: type Sampler = (frame: ArrayLike<number>) => number;
//   The port's `DataStore.downSample` feeds each sampler a `[ParsedValue]` (Any) frame, so each
//   sampler coerces its elements to `Double` via `dataSampleNum` (JS reads them as plain numbers).
public typealias DataSampler = (_ frame: [ParsedValue]) -> ParsedValueNumeric

// JS numeric coercion of a store value (ParsedValue = Any). nil/non-numeric → NaN, matching how
// the typed-array-backed `dimStore` holds numbers upstream.
private func dataSampleNum(_ v: ParsedValue?) -> Double {
    guard let v = v else { return .nan }
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let n = v as? NSNumber { return n.doubleValue }
    if let s = v as? String { return Double(s) ?? .nan }
    return .nan
}

// const samplers: Dictionary<Sampler> = { ... }
let dataSampleSamplers: [String: DataSampler] = [
    "average": { frame in
        var sum = 0.0
        var count = 0
        for i in 0..<frame.count {
            let f = dataSampleNum(frame[i])
            if !f.isNaN {
                sum += f
                count += 1
            }
        }
        // Return NaN if count is 0
        return count == 0 ? .nan : sum / Double(count)
    },
    "sum": { frame in
        var sum = 0.0
        for i in 0..<frame.count {
            // Ignore NaN
            let f = dataSampleNum(frame[i])
            sum += f.isNaN ? 0 : f
        }
        return sum
    },
    "max": { frame in
        var max = -Double.infinity
        for i in 0..<frame.count {
            let f = dataSampleNum(frame[i])
            if f > max { max = f }
        }
        // NaN will cause illegal axis extent.
        return max.isFinite ? max : .nan
    },
    "min": { frame in
        var min = Double.infinity
        for i in 0..<frame.count {
            let f = dataSampleNum(frame[i])
            if f < min { min = f }
        }
        // NaN will cause illegal axis extent.
        return min.isFinite ? min : .nan
    },
    // TODO
    // Median
    "nearest": { frame in
        return dataSampleNum(frame.first)
    }
]

// const indexSampler = function (frame) { return Math.round(frame.length / 2); };
private let dataSampleIndexSampler: (_ frame: [ParsedValue], _ value: ParsedValueNumeric) -> Int = { frame, _ in
    return Int((Double(frame.count) / 2).rounded())
}

// export default function dataSample(seriesType: string): StageHandler
public func dataSample(_ seriesType: String) -> StageHandler {
    var handler = StageHandler()
    handler.seriesType = seriesType

    // FIXME:TS never used, so comment it
    // modifyOutputEnd: true,

    handler.reset = { seriesModel, ecModel, api, _ in
        let data = seriesModel.getData()
        let sampling = seriesModel.get("sampling")
        // upstream: const coordSys = seriesModel.coordinateSystem;
        //   Only cartesian2d supports down sampling; the `Cartesian2D` cast IS the `coordSys.type ===
        //   'cartesian2d'` check (only Cartesian2D exposes `getBaseAxis(): Axis2D`).
        let coordSys = seriesModel.coordinateSystem as? Cartesian2D
        let count = data.count()
        let samplingKind = dataSampleStringOf(sampling)
        // Only cartesian2d support down sampling. Disable it when there is few data.
        if count > 10, let coordSys = coordSys, dataSampleTruthy(sampling) {
            let baseAxis = coordSys.getBaseAxis()
            let valueAxis = coordSys.getOtherAxis(baseAxis)
            let extent = baseAxis.getExtent()
            let dpr = api.getDevicePixelRatio()
            // Coordinate system has been resized
            let size = abs(extent[1] - extent[0]) * (dpr != 0 ? dpr : 1)
            // upstream: Math.round(count / size). Keep as Double so `isFinite` can gate before the
            //   Int conversion (Int(Infinity)/Int(NaN) would trap in Swift).
            let rateD = (Double(count) / size).rounded()

            if rateD.isFinite && rateD > 1 {
                let rate = Int(rateD)
                guard let valueDim = data.mapDimension(valueAxis.dim) else { return nil }
                if samplingKind == "lttb" {
                    seriesModel.setData(data.lttbDownSample(valueDim, 1.0 / Double(rate)))
                }
                else if samplingKind == "minmax" {
                    seriesModel.setData(data.minmaxDownSample(valueDim, 1.0 / Double(rate)))
                }
                var sampler: DataSampler?
                if let samplingKind = samplingKind {
                    sampler = dataSampleSamplers[samplingKind]
                }
                else if let fn = sampling as? DataSampler {
                    sampler = fn
                }
                if let sampler = sampler {
                    // Only support sample the first dim mapped from value axis.
                    seriesModel.setData(data.downSample(
                        valueDim, 1.0 / Double(rate), sampler, dataSampleIndexSampler
                    ))
                }
            }
        }
        return nil
    }
    return handler
}

// JS truthiness for `seriesModel.get('sampling')` — a non-empty string or a sampler function is truthy.
private func dataSampleTruthy(_ v: Any?) -> Bool {
    guard let v = dataSampleUnwrapOpt(v) else { return false }
    if let b = v as? Bool { return b }
    if let s = v as? String { return !s.isEmpty }
    if v is DataSampler { return true }
    return true
}

// `isString(sampling) ? sampling : undefined` — the string form of the option, else nil (function form).
private func dataSampleStringOf(_ v: Any?) -> String? {
    return dataSampleUnwrapOpt(v) as? String
}

// Recursively unwrap a boxed Optional (`Any` wrapping `String?`), returning nil for `.none`.
private func dataSampleUnwrapOpt(_ v: Any?) -> Any? {
    guard let v = v else { return nil }
    let m = Mirror(reflecting: v)
    if m.displayStyle == .optional {
        guard let child = m.children.first else { return nil }
        return dataSampleUnwrapOpt(child.value)
    }
    return v
}
