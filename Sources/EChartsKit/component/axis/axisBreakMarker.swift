// PORT-ADDITION (minimal): axis value-break marker glyph.
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

// PORT-SCOPE NOTE:
//   Upstream echarts 6.1 renders axis breaks as a full "break area" (a gap between two split lines
//   whose facing borders are drawn as a zigzag `Polyline`), laid out in `component/axis/AxisView` +
//   `AxisBuilder` via `axisBreakHelper`/`retrieveAxisBreakPairs`. That break-area subsystem is DEFERRED
//   (large; couples split-area, split-line, and label-overlap resolution).
//   This file implements the CORE deliverable: the small zigzag glyph placed AT the break position on
//   the axis line so a broken axis is visually distinguishable. The value mapping itself (removing the
//   [start,end] interval, shifting values above the break down) is fully faithful and lives in the
//   scale layer (`scale/breakImpl.swift` + the `BreakScaleMapper` composition). This marker is a
//   minimal, self-contained addition (guarded by `hasBreaks`), so NON-broken axes are untouched.

// Geometry of one zigzag glyph, in axis-local space (x = coord along the axis, y = perpendicular).
private let AXIS_BREAK_MARKER_HALF_WIDTH: Double = 5
let AXIS_BREAK_MARKER_AMPLITUDE: Double = 4

func axisBreakStyleNumber(_ value: Any?) -> Double? {
    if let value = value as? Double { return value }
    if let value = value as? Int { return Double(value) }
    if let value = value as? NSNumber { return value.doubleValue }
    return nil
}

/// Build a zigzag break-marker glyph for every parsed break of `axis.scale`, positioned at the
/// mid-point (in pixel coord) between the break's `vmin`/`vmax`. Each glyph is added to `group` and
/// also returned (for tests / callers). Returns an empty array when the axis has no breaks.
///
/// - `transformMatrix`: the axis transform (same one `createTicks` applies to tick endpoints); when
///   present the local zigzag points are mapped through it so the glyph aligns with the axis line.
/// - `lineStyle`: the axis-line style; the marker reuses its stroke (fill is cleared — a stroke-only
///   open polyline must NOT inherit the default black fill, see CLAUDE.md trap).
@discardableResult
func buildAxisBreakMarker(
    _ axis: Axis,
    _ group: Group,
    _ transformMatrix: MatrixArray?,
    _ lineStyle: PathStyleProps,
    _ amplitude: Double = AXIS_BREAK_MARKER_AMPLITUDE
) -> [Polyline] {
    let scale = axis.scale
    // `zigzagAmplitude: 0` is the public way to request a flat break edge. In that mode ECharts
    // does not leave a separate zigzag glyph on the axis line either (intraday-breaks-2).
    if !hasBreaks(scale) || amplitude <= 0 {
        return []
    }

    // A stroke-only glyph: copy the axis-line stroke/lineWidth, clear the fill.
    var markerStyle = lineStyle
    markerStyle.fill = .string("none")

    var result: [Polyline] = []
    let breaks = getBreaksUnsafe(scale)
    util.each(breaks) { brk, _ in
        // `brk.vmin`/`vmax` are in the outermost (business) value space; `dataToCoord` runs them
        // through `scale.normalize` (which applies the break transform) → the compressed pixel position.
        let cMin = axis.dataToCoord(brk.vmin)
        let cMax = axis.dataToCoord(brk.vmax)
        let mid = (cMin + cMax) / 2

        let hw = AXIS_BREAK_MARKER_HALF_WIDTH
        let amp = amplitude
        // Zigzag centered on the axis line (perpendicular oscillation), in axis-local coords.
        var localPoints: [VectorArray] = [
            VectorArray(mid - hw, 0),
            VectorArray(mid - hw / 2, -amp),
            VectorArray(mid + hw / 2, amp),
            VectorArray(mid + hw, 0),
        ]
        if let m = transformMatrix {
            localPoints = localPoints.map { vector.applyTransform($0, m) }
        }

        var shape = PolylineShape()
        shape.points = localPoints
        let marker = Polyline()
        marker.setShape(shape)
        marker.useStyle(markerStyle)
        // Stroke-only: ensure the default #000 fill does not survive `useStyle`.
        marker.pathStyle.fill = nil
        marker.z2 = 2
        marker.silent = true
        marker.anid = "break_marker_" + String(brk.vmin) + "_" + String(brk.vmax)

        _ = group.add(marker)
        result.append(marker)
    }
    return result
}
