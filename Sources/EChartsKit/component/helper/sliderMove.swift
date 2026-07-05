// Ported from echarts/src/component/helper/sliderMove.ts — keep in sync with upstream
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

// import { addSafe } from '../../util/number';   -> `number.addSafe` (util/number.swift)

// upstream: handleIndex: 'all' | 0 | 1  ->  a small enum (CONVENTIONS §6: string/number literal union).
public enum SliderMoveHandleIndex {
    case all
    case at(Int)   // 0 | 1
}

/**
 * Calculate slider move result.
 * Usage:
 * (1) If both handle0 and handle1 are needed to be moved, set minSpan the same as
 * maxSpan and the same as `Math.abs(handleEnd[1] - handleEnds[0])`.
 * (2) If handle0 is forbidden to cross handle1, set minSpan as `0`.
 *
 * [CAVEAT]
 *  This method is inefficient due to the use of `addSafe`.
 *
 * @param delta Move length.
 * @param handleEnds handleEnds[0] can be bigger then handleEnds[1].
 *              handleEnds will be modified in this method.
 * @param extent handleEnds is restricted by extent.
 *              extent[0] should less or equals than extent[1].
 * @param handleIndex Can be 'all', means that both move the two handleEnds.
 * @param minSpan The range of dataZoom can not be smaller than that.
 *              If not set, handle0 and cross handle1. If set as a non-negative
 *              number (including `0`), handles will push each other when reaching
 *              the minSpan.
 * @param maxSpan The range of dataZoom can not be larger than that.
 * @return The input handleEnds.
 */
// upstream: `handleEnds` is mutated in place (JS array ref) — modeled as `inout`.
@discardableResult
public func sliderMove(
    _ delta0: Double,
    _ handleEnds: inout [Double],
    _ extent: [Double],
    _ handleIndex0: SliderMoveHandleIndex,
    _ minSpan0: Double? = nil,
    _ maxSpan0: Double? = nil
) -> [Double] {

    // delta = delta || 0;  (JS falsy: NaN/0/undefined -> 0)
    let delta = (delta0.isNaN) ? 0 : delta0

    // Consider `7.1e-9 - 7e-9` get `1.0000000000000007e-10`, so use `addSafe`
    // to remove rounding error whenever possible.
    let extentSpan = number.addSafe(extent[1], -extent[0])

    var minSpan = minSpan0
    var maxSpan = maxSpan0

    // Notice maxSpan and minSpan can be null/undefined.
    if minSpan != nil {
        minSpan = restrictSlider(minSpan!, [0, extentSpan])
    }
    if maxSpan != nil {
        maxSpan = Swift.max(maxSpan!, minSpan != nil ? minSpan! : 0)
    }

    var handleIndex: Int
    switch handleIndex0 {
    case .all:
        var handleSpan = number.mathAbs(number.addSafe(handleEnds[1], -handleEnds[0]))
        handleSpan = restrictSlider(handleSpan, [0, extentSpan])
        let clamped = restrictSlider(handleSpan, [minSpan, maxSpan])
        minSpan = clamped
        maxSpan = clamped
        handleIndex = 0
    case .at(let i):
        handleIndex = i
    }

    handleEnds[0] = restrictSlider(handleEnds[0], extent)
    handleEnds[1] = restrictSlider(handleEnds[1], extent)

    let originalDistSign = getSpanSign(handleEnds, handleIndex)

    handleEnds[handleIndex] += delta

    // Restrict in extent.
    // extentMinSpan = minSpan || 0  (JS falsy: NaN/0/undefined -> 0)
    let extentMinSpan = (minSpan == nil || minSpan!.isNaN || minSpan! == 0) ? 0 : minSpan!
    var realExtent = extent   // extent.slice()
    if originalDistSign.sign < 0 {
        realExtent[0] = number.addSafe(realExtent[0], extentMinSpan)
    }
    else {
        realExtent[1] = number.addSafe(realExtent[1], -extentMinSpan)
    }
    handleEnds[handleIndex] = restrictSlider(handleEnds[handleIndex], realExtent)

    // Expand span.
    var currDistSign = getSpanSign(handleEnds, handleIndex)
    if minSpan != nil && (
        currDistSign.sign != originalDistSign.sign || currDistSign.span < minSpan!
    ) {
        // If minSpan exists, 'cross' is forbidden.
        handleEnds[1 - handleIndex] = number.addSafe(
            handleEnds[handleIndex], Double(originalDistSign.sign) * minSpan!
        )
    }

    // Shrink span.
    currDistSign = getSpanSign(handleEnds, handleIndex)
    if maxSpan != nil && currDistSign.span > maxSpan! {
        handleEnds[1 - handleIndex] = number.addSafe(
            handleEnds[handleIndex], Double(currDistSign.sign) * maxSpan!
        )
    }

    return handleEnds
}

// upstream: getSpanSign(handleEnds, handleIndex): {span, sign}
private func getSpanSign(_ handleEnds: [Double], _ handleIndex: Int) -> (span: Double, sign: Int) {
    let dist = handleEnds[handleIndex] - handleEnds[1 - handleIndex]
    // If `handleEnds[0] === handleEnds[1]`, always believe that handleEnd[0]
    // is at left of handleEnds[1] for non-cross case.
    let sign = dist > 0 ? -1 : dist < 0 ? 1 : (handleIndex != 0 ? -1 : 1)
    return (span: number.mathAbs(dist), sign: sign)
}

// upstream: restrict(value, extend) — bounds can be null/undefined (fallback to +/-Infinity).
private func restrictSlider(_ value: Double, _ extend: [Double?]) -> Double {
    return Swift.min(
        extend[1] != nil ? extend[1]! : Double.infinity,
        Swift.max(extend[0] != nil ? extend[0]! : -Double.infinity, value)
    )
}
private func restrictSlider(_ value: Double, _ extend: [Double]) -> Double {
    // NOTE: annotate `as [Double?]` so this dispatches to the `[Double?]` overload above; without it
    // `[extend[0], extend[1]]` infers `[Double]` and re-dispatches to THIS overload (infinite recursion).
    return restrictSlider(value, [extend[0], extend[1]] as [Double?])
}
