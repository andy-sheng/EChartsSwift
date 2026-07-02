// Ported from echarts/src/util/vendor.ts — keep in sync with upstream
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

// import { assert } from 'zrender/src/core/util';        -> util.assert (ZRenderKit)
// import { error } from './log';                         -> log.error (util/log.swift)
// import { UNDEFINED_STR } from './types';               -> (JS `typeof` guard; N/A in Swift, ctors always present)
// import { MAX_SAFE_INTEGER } from './number';           -> number.MAX_SAFE_INTEGER (util/number.swift)

// upstream: the typed-array constructors (each `undefined` when the env lacks it). Swift has no JS
//   TypedArray; the constructor identity is modeled as a marker enum of the element kind. All kinds
//   are always available, so the ctor values are non-nil (mirrors browser/node).
public enum TypedArrayCtor {
    case int8, int16, int32, uint8, uint16, uint32, uint8Clamped, float32, float64
}

// upstream: `TypedArrayType` union of the concrete typed-array instances. Swift models every typed
//   array's storage uniformly as `[Double]` (the only element type consumed by the coord phase).
public typealias TypedArrayType = [Double]

/**
 * Use Typed Array if possible for performance optimization, otherwise fallback to a normal array.
 *
 * Usage
 *  const tyArr = tryEnsureCompatibleTypedArray({ctor: Float64ArrayCtor}, capacity);
 */
// upstream: `type CompatibleTypedArray = { arr?, typed?, ctor }`. Ported as a reference type (`final
//   class`) so `tryEnsureTypedArray` can mutate the passed-in bag in place (JS mutates the object).
public final class CompatibleTypedArray {
    // Write by `tryEnsureTypedArray`. If empty, create one. Never null/undefined after that call.
    public var arr: [Double]
    // Write by `tryEnsureTypedArray`. Whether it is actually a typed array.
    public var typed: Bool
    // Need to be provided by callers. Expected constructor. Do not change it.
    public let ctor: TypedArrayCtor?

    public init(ctor: TypedArrayCtor?, arr: [Double] = [], typed: Bool = false) {
        self.ctor = ctor
        self.arr = arr
        self.typed = typed
    }
}

public enum vendor {

    public static let Int8ArrayCtor: TypedArrayCtor? = .int8
    public static let Int16ArrayCtor: TypedArrayCtor? = .int16
    public static let Int32ArrayCtor: TypedArrayCtor? = .int32
    public static let Uint8ArrayCtor: TypedArrayCtor? = .uint8
    public static let Uint16ArrayCtor: TypedArrayCtor? = .uint16
    public static let Uint32ArrayCtor: TypedArrayCtor? = .uint32
    public static let Uint8ClampedArrayCtor: TypedArrayCtor? = .uint8Clamped
    public static let Float32ArrayCtor: TypedArrayCtor? = .float32
    public static let Float64ArrayCtor: TypedArrayCtor? = .float64

    public static func createFloat32Array(_ capacity: Double) -> [Double] {
        return tryEnsureTypedArray(CompatibleTypedArray(ctor: Float32ArrayCtor), capacity).arr
    }

    public static func tryEnsureTypedArray(
        _ tyArr: CompatibleTypedArray,
        // Can add more types if needed.
        // NOTICE: Callers need to manage data length themselves.
        // Do not consider `capacity` as the data length.
        _ capacity: Double
    ) -> CompatibleTypedArray {
        if __DEV__ {
            util.assert(
                capacity.isFinite && capacity >= 0
            )
        }
        let existingArr = tyArr.arr
        let ctor = tyArr.ctor

        var capacity = capacity
        if capacity > number.MAX_SAFE_INTEGER {
            capacity = number.MAX_SAFE_INTEGER
        }

        // upstream `!existingArr` (missing / never created) is modeled by the `typed == false && empty`
        //   default state; once created, `arr` is non-empty for a positive capacity.
        let notCreated = existingArr.isEmpty && !tyArr.typed
        if notCreated || (tyArr.typed && Double(existingArr.count) < capacity) {
            var nextArr: [Double]
            if ctor != nil {
                // A large contiguous memory allocation may cause OOM.
                nextArr = [Double](repeating: 0, count: Int(capacity))
                tyArr.typed = true
                // existingArr && nextArr.set(existingArr);
                for i in 0..<Swift.min(existingArr.count, nextArr.count) {
                    nextArr[i] = existingArr[i]
                }
            }
            else {
                nextArr = []
                tyArr.typed = false
                for i in 0..<existingArr.count {
                    if i < nextArr.count { nextArr[i] = existingArr[i] } else { nextArr.append(existingArr[i]) }
                }
            }
            tyArr.arr = nextArr
        }

        return tyArr
    }
}
