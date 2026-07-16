// Ported from echarts/src/util/jitter.ts — keep in sync with upstream.
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

// upstream imports resolve to:
//   import { calcBandWidth } from '../coord/axisBand';              -> `calcBandWidth` (coord/axisBand.swift).
//   import Axis2D from '../coord/cartesian/Axis2D';                 -> `Axis2D` (coord/cartesian/Axis2D.swift).
//   import { COORD_SYS_TYPE_CARTESIAN_2D } / COORD_SYS_TYPE_SINGLE  -> the coord-sys type constants.
//   import SingleAxis from '../coord/single/SingleAxis';            -> `SingleAxis` (coord/single/SingleAxis.swift).
//   import { isOrdinalScale } from '../scale/helper';               -> `helper.isOrdinalScale` (scale/helper.swift).
//   import { makeInner } from './model';                            -> per-axis inner store, modeled below by an
//       ObjectIdentifier-keyed module dictionary (a fresh coord-sys/axis instance per full render resets it,
//       matching upstream makeInner's per-instance lifetime for the static render path).

// upstream: export function needFixJitter(seriesModel, axis): boolean
//   True when the series lives on a jitter-capable coord (cartesian2d w/ ordinal base axis, OR singleAxis)
//   AND the axis's `jitter` option is > 0.
public func needFixJitter(_ seriesModel: SeriesModel, _ axis: Axis) -> Bool {
    let coordinateSystem = seriesModel.coordinateSystem
    // coordType === COORD_SYS_TYPE_CARTESIAN_2D / COORD_SYS_TYPE_SINGLE — derived from the concrete
    //   coord-sys type (Cartesian2D / Single) rather than a stringly `.type` (Cartesian2D exposes none).
    //   `axis` is the coord system's base axis at every call site, so its scale type is the base scale
    //   type (upstream `coordinateSystem.getBaseAxis().scale.type`).
    let scaleType = axis.scale.type

    // const seriesValid = coordType === COORD_SYS_TYPE_CARTESIAN_2D && scaleType === 'ordinal'
    //     || coordType === COORD_SYS_TYPE_SINGLE;
    let seriesValid = (coordinateSystem is Cartesian2D && scaleType == "ordinal")
        || coordinateSystem is Single

    // const axisValid = (axis.model as AxisBaseModel).get('jitter') > 0;
    let axisValid = jitterAsDouble(axis.model.get("jitter")) > 0
    return seriesValid && axisValid
}

// upstream: type JitterData = { fixedCoord, floatCoord, r }
struct JitterData {
    var fixedCoord: Double
    var floatCoord: Double
    var r: Double
}

// upstream: const inner = makeInner<{ items: JitterData[] }, Axis2D | SingleAxis>();
//   Per-axis accumulator for the avoid-overlaps path (jitterOverlap === false). Keyed by the axis
//   instance identity; a full render rebuilds the coord system (fresh axis), so this resets per render.
private var jitterInnerStore: [ObjectIdentifier: [JitterData]] = [:]

/// Reset the avoid-overlaps accumulator for an axis (called once before a series' jitter pass so the
///   overlap set does not leak across re-renders that reuse the same axis instance).
public func resetJitterStore(_ axis: Axis) {
    jitterInnerStore[ObjectIdentifier(axis)] = []
}

/**
 * Fix jitter for overlapping data points.
 *
 * @param fixedAxis The axis whose coord doesn't change with jitter.
 * @param fixedCoord The coord of fixedAxis.
 * @param floatCoord The coord of the other axis, which should be changed with jittering.
 * @param radius The radius of the data point, considering the symbol is a circle.
 * @returns updated floatCoord.
 */
// upstream: export function fixJitter(fixedAxis, fixedCoord, floatCoord, radius): number
public func fixJitter(
    _ fixedAxis: Axis,
    _ fixedCoord: Double,
    _ floatCoord: Double,
    _ radius: Double
) -> Double {
    // if (fixedAxis instanceof Axis2D) { if (fixedAxis.scale.type !== 'ordinal') return floatCoord; }
    if fixedAxis is Axis2D {
        if fixedAxis.scale.type != "ordinal" {
            return floatCoord
        }
    }
    let axisModel = fixedAxis.model
    let jitter = jitterAsDouble(axisModel?.get("jitter"))
    if !(jitter > 0) {
        return floatCoord
    }
    let jitterOverlap = (axisModel?.get("jitterOverlap") as? Bool) ?? true
    let jitterMargin = jitterAsDouble(axisModel?.get("jitterMargin"))
    // Get band width to limit jitter range.
    let bandWidth: Double? = helper.isOrdinalScale(fixedAxis.scale)
        ? calcBandWidth(fixedAxis).w
        : nil
    if jitterOverlap {
        return fixJitterIgnoreOverlaps(floatCoord, jitter, bandWidth, radius)
    }
    return fixJitterAvoidOverlaps(fixedAxis, fixedCoord, floatCoord, radius, jitter, jitterMargin)
}

// upstream: function fixJitterIgnoreOverlaps(floatCoord, jitter, bandWidth, radius)
private func fixJitterIgnoreOverlaps(
    _ floatCoord: Double,
    _ jitter: Double,
    _ bandWidth: Double?,
    _ radius: Double
) -> Double {
    // Don't clamp single axis.
    guard let bandWidth = bandWidth else {
        return floatCoord + (jitterRandom() - 0.5) * jitter
    }
    let maxJitter = bandWidth - radius * 2
    let actualJitter = Swift.min(Swift.max(0, jitter), maxJitter)
    return floatCoord + (jitterRandom() - 0.5) * actualJitter
}

// upstream: function fixJitterAvoidOverlaps(fixedAxis, fixedCoord, floatCoord, radius, jitter, margin)
private func fixJitterAvoidOverlaps(
    _ fixedAxis: Axis,
    _ fixedCoord: Double,
    _ floatCoord: Double,
    _ radius: Double,
    _ jitter: Double,
    _ margin: Double
) -> Double {
    let key = ObjectIdentifier(fixedAxis)
    var items = jitterInnerStore[key] ?? []

    // Try both positive and negative directions, choose the one with smaller movement.
    let overlapA = placeJitterOnDirection(items, fixedCoord, floatCoord, radius, jitter, margin, 1)
    let overlapB = placeJitterOnDirection(items, fixedCoord, floatCoord, radius, jitter, margin, -1)
    let minFloat = abs(overlapA - floatCoord) < abs(overlapB - floatCoord) ? overlapA : overlapB

    // Clamp only category axis.
    let bandWidth: Double? = helper.isOrdinalScale(fixedAxis.scale)
        ? calcBandWidth(fixedAxis).w
        : nil
    let distance = abs(minFloat - floatCoord)

    if distance > jitter / 2 || (bandWidth != nil && distance > bandWidth! / 2 - radius) {
        // If the new item is moved too far, then give up. Fall back to random jitter.
        return fixJitterIgnoreOverlaps(floatCoord, jitter, bandWidth, radius)
    }

    // Add new point to array.
    items.append(JitterData(fixedCoord: fixedCoord, floatCoord: minFloat, r: radius))
    jitterInnerStore[key] = items

    return minFloat
}

// upstream: function placeJitterOnDirection(items, fixedCoord, floatCoord, radius, jitter, margin, direction)
private func placeJitterOnDirection(
    _ items: [JitterData],
    _ fixedCoord: Double,
    _ floatCoord: Double,
    _ radius: Double,
    _ jitter: Double,
    _ margin: Double,
    _ direction: Double
) -> Double {
    var y = floatCoord

    // Check all existing items for overlap and find the maximum adjustment needed.
    var i = 0
    while i < items.count {
        let item = items[i]
        let dx = fixedCoord - item.fixedCoord
        let dy = y - item.floatCoord
        let d2 = dx * dx + dy * dy
        let r = radius + item.r + margin

        if d2 < r * r {
            // Has overlap, calculate required adjustment.
            let requiredY = item.floatCoord + (r * r - dx * dx).squareRoot() * direction

            // Check if this adjustment would move too far.
            if abs(requiredY - floatCoord) > jitter / 2 {
                return Double.greatestFiniteMagnitude // Give up.
            }

            // Update y only when it's larger to the center.
            if (direction == 1 && requiredY > y) || (direction == -1 && requiredY < y) {
                y = requiredY
                i = -1 // Reset index to recheck all items.
                i += 1
                continue // Recalculate with the new y position.
            }
        }
        i += 1
    }

    return y
}

// MARK: - port helpers

// JS `Math.random()` → a deterministic (seeded) 0..<1 stream so the native render is reproducible.
//   The upstream jitter is itself `Math.random()`-based (the reference pane is non-deterministic frame
//   to frame), so exact pixel parity is impossible either way; a fixed seed keeps the native cloud stable.
private var jitterRngState: UInt64 = 0x2545_F491_4F6C_DD1D

private func jitterRandom() -> Double {
    // xorshift64* — fast, well-distributed, deterministic.
    var x = jitterRngState
    x ^= x >> 12
    x ^= x << 25
    x ^= x >> 27
    jitterRngState = x
    let v = (x &* 0x2545_F491_4F6C_DD1D) >> 11
    return Double(v) / Double(1 << 53)
}

/// Reseed the jitter RNG so a render pass is reproducible run-to-run.
public func resetJitterRandom() {
    jitterRngState = 0x2545_F491_4F6C_DD1D
}

// `axisModel.get('jitter' | 'jitterMargin')` box as Int OR Double (the Int-vs-Double option-read trap).
private func jitterAsDouble(_ v: Any?) -> Double {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let n = v as? NSNumber { return n.doubleValue }
    return 0
}
