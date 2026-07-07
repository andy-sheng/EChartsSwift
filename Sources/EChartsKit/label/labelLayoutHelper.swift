// Ported from echarts/src/label/labelLayoutHelper.ts — keep in sync with upstream.
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

// PORT SCOPE (L1c): the subset the pie label layout consumes —
//   - `computeLabelGeometry` / `computeLabelGlobalRect`: the label's GLOBAL bounding rect
//     (localRect + marginDefault expansion, then the label's computed transform).
//   - `shiftLayoutOnXY`: the along-axis overlap resolver (pie's `avoidOverlap` shifts labels on Y).
//
//   DEFERRED (the OBB / axis-label machinery): `LabelGeometry` dirty-bit caching, `ensureOBB`,
//   `labelIntersect`, `hideOverlap`, `restoreIgnore`, `newLabelLayoutWithGeometry`,
//   `labelLayoutApplyTranslation`. AxisBuilder's `hideOverlap` PORT-TODO and the axis-name overlap
//   resolver still wait on those. This file lands only what the pie leader-line layout needs.

/// Namespace for the ported labelLayoutHelper functions (caseless enum, mirrors `labelStyle`).
public enum labelLayoutHelper {

    // XY / WH dimension name tables (upstream `const XY = ['x', 'y']; const WH = ['width', 'height'];`).
    // Modeled as index-based accessors on BoundingRect / ZRText below.

    /// upstream: `computeLabelGlobalRect(out, label)` (chart/pie/labelLayout.ts) via
    ///   `computeLabelGeometry(_tmpLabelGeometry, label, _computeLabelGeometryOpt)`.
    /// Fills `out` (a global BoundingRect) with the label's local bounding rect expanded by the pie
    /// `marginDefault` ([1, 0, 1, 0] = top/bottom 1px) and then transformed by the label's computed
    /// transform (its x / y / rotation).
    ///
    /// PORT NOTE: upstream resolves `textMargin` vs `minMargin` from `style.margin` / `__marginType`.
    /// The `__marginType` plumbing is a documented gap in the port's `labelStyle` (margin machinery
    /// deferred), so labels carry no explicit margin and this always takes the `marginDefault`
    /// (textMargin) branch — faithful for pie's default labels.
    public static func computeLabelGlobalRect(_ out: BoundingRect, _ label: ZRText) {
        let rawTransform = label.getComputedTransform()

        // NOTE: getBoundingRect must be called AFTER getComputedTransform (upstream note): the latter
        //   runs the host's `updateInnerText`, which may relayout the label.
        let localRect = (label.getBoundingRect() ?? BoundingRect(0, 0, 0, 0)).clone()

        // marginDefault = [1, 0, 1, 0] (top, right, bottom, left); marginType == textMargin.
        //   expandOrShrinkRect(localRect, margin, expand): x -= left; width += left + right;
        //                                                  y -= top;  height += top + bottom.
        let marginTop = 1.0, marginRight = 0.0, marginBottom = 1.0, marginLeft = 0.0
        localRect.x -= marginLeft
        localRect.width += marginLeft + marginRight
        localRect.y -= marginTop
        localRect.height += marginTop + marginBottom

        out.copy(localRect)
        if let t = rawTransform {
            out.applyTransform(t)
        }
    }

    /// An item participating in `shiftLayoutOnXY`: carries a global `rect` (mutated in place) and the
    /// backing `label` whose element x / y are shifted alongside.
    public protocol ShiftLayoutItem: AnyObject {
        var rect: BoundingRect { get }
        var label: ZRText { get }
    }

    // rect[xyDim] / rect[sizeDim] accessors keyed on `xyDimIdx` (0 = x/width, 1 = y/height).
    private static func rectXY(_ r: BoundingRect, _ dim: Int) -> Double {
        dim == 0 ? r.x : r.y
    }
    private static func setRectXY(_ r: BoundingRect, _ dim: Int, _ v: Double) {
        if dim == 0 { r.x = v } else { r.y = v }
    }
    private static func rectWH(_ r: BoundingRect, _ dim: Int) -> Double {
        dim == 0 ? r.width : r.height
    }
    private static func labelXY(_ l: ZRText, _ dim: Int) -> Double {
        (dim == 0 ? l.x : l.y) ?? 0
    }
    private static func setLabelXY(_ l: ZRText, _ dim: Int, _ v: Double) {
        if dim == 0 { l.x = v } else { l.y = v }
    }

    /// upstream: export function shiftLayoutOnXY(list, xyDimIdx, minBound, maxBound, balanceShift?)
    /// Sort labels along the axis and shift them so their global `rect`s do not overlap, staying
    /// within [minBound, maxBound]. Mutates each item's `rect[xyDim]` and `label[xyDim]`.
    /// @return whether any label was adjusted.
    @discardableResult
    public static func shiftLayoutOnXY(
        _ list: [ShiftLayoutItem],
        _ xyDimIdx: Int,             // 0 for x, 1 for y
        _ minBound: Double,          // for x, leftBound; for y, topBound
        _ maxBound: Double,          // for x, rightBound; for y, bottomBound
        _ balanceShift: Bool = false
    ) -> Bool {
        let len = list.count

        if len < 2 {
            return false
        }

        // list.sort((a, b) => a.rect[xyDim] - b.rect[xyDim])
        var list = list
        list.sort { rectXY($0.rect, xyDimIdx) < rectXY($1.rect, xyDimIdx) }

        var lastPos = 0.0
        var adjusted = false

        var totalShifts = 0.0
        for i in 0..<len {
            let item = list[i]
            let rect = item.rect
            let delta = rectXY(rect, xyDimIdx) - lastPos
            if delta < 0 {
                setRectXY(rect, xyDimIdx, rectXY(rect, xyDimIdx) - delta)
                setLabelXY(item.label, xyDimIdx, labelXY(item.label, xyDimIdx) - delta)
                adjusted = true
            }
            let shift = Swift.max(-delta, 0)
            totalShifts += shift

            lastPos = rectXY(rect, xyDimIdx) + rectWH(rect, xyDimIdx)
        }

        // shiftList mutates list[start..<end] along the axis (both rect and label).
        func shiftList(_ delta: Double, _ start: Int, _ end: Int) {
            if delta != 0 {
                adjusted = true
            }
            for i in start..<end {
                let item = list[i]
                let rect = item.rect
                setRectXY(rect, xyDimIdx, rectXY(rect, xyDimIdx) + delta)
                setLabelXY(item.label, xyDimIdx, labelXY(item.label, xyDimIdx) + delta)
            }
        }

        if totalShifts > 0 && balanceShift {
            // Shift back to make the distribution more equal.
            shiftList(-totalShifts / Double(len), 0, len)
        }

        let first = list[0]
        let last = list[len - 1]
        var minGap = 0.0
        var maxGap = 0.0
        func updateMinMaxGap() {
            minGap = rectXY(first.rect, xyDimIdx) - minBound
            maxGap = maxBound - rectXY(last.rect, xyDimIdx) - rectWH(last.rect, xyDimIdx)
        }

        // Squeeze gaps if the labels exceed margin.
        func squeezeGaps(_ delta: Double, _ maxSqeezePercent: Double) {
            var gaps: [Double] = []
            var totalGaps = 0.0
            for i in 1..<len {
                let prevItemRect = list[i - 1].rect
                let gap = Swift.max(
                    rectXY(list[i].rect, xyDimIdx) - rectXY(prevItemRect, xyDimIdx) - rectWH(prevItemRect, xyDimIdx),
                    0
                )
                gaps.append(gap)
                totalGaps += gap
            }
            if totalGaps == 0 {
                return
            }

            let squeezePercent = Swift.min(abs(delta) / totalGaps, maxSqeezePercent)

            if delta > 0 {
                for i in 0..<(len - 1) {
                    // Distribute the shift delta to all gaps (forward).
                    let movement = gaps[i] * squeezePercent
                    shiftList(movement, 0, i + 1)
                }
            }
            else {
                // Backward
                var i = len - 1
                while i > 0 {
                    let movement = gaps[i - 1] * squeezePercent
                    shiftList(-movement, i, len)
                    i -= 1
                }
            }
        }

        func takeBoundsGap(_ gapThisBound: Double, _ gapOtherBound: Double, _ moveDir: Double) {
            if gapThisBound < 0 {
                // Move from other gap if can.
                let moveFromMaxGap = Swift.min(gapOtherBound, -gapThisBound)
                if moveFromMaxGap > 0 {
                    shiftList(moveFromMaxGap * moveDir, 0, len)
                    let remained = moveFromMaxGap + gapThisBound
                    if remained < 0 {
                        squeezeGaps(-remained * moveDir, 1)
                    }
                }
                else {
                    squeezeGaps(-gapThisBound * moveDir, 1)
                }
            }
        }

        /// Squeeze to allow overlap if there is no more space available.
        func squeezeWhenBailout(_ delta: Double) {
            let dir = delta < 0 ? -1.0 : 1.0
            var delta = abs(delta)
            let moveForEachLabel = (delta / Double(len - 1)).rounded(.up)

            for i in 0..<(len - 1) {
                if dir > 0 {
                    // Forward
                    shiftList(moveForEachLabel, 0, i + 1)
                }
                else {
                    // Backward
                    shiftList(-moveForEachLabel, len - i - 1, len)
                }

                delta -= moveForEachLabel

                if delta <= 0 {
                    return
                }
            }
        }

        updateMinMaxGap()

        // If ends exceed two bounds, squeeze at most 80%, then take the gap of two bounds.
        if minGap < 0 { squeezeGaps(-minGap, 0.8) }
        if maxGap < 0 { squeezeGaps(maxGap, 0.8) }
        updateMinMaxGap()
        takeBoundsGap(minGap, maxGap, 1)
        takeBoundsGap(maxGap, minGap, -1)

        // Handle bailout when there is not enough space.
        updateMinMaxGap()

        if minGap < 0 {
            squeezeWhenBailout(-minGap)
        }
        if maxGap < 0 {
            squeezeWhenBailout(maxGap)
        }

        return adjusted
    }
}
