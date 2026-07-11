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
//   Most of the OBB / axis-label machinery (`ensureOBB`, `labelIntersect`, `hideOverlap`,
//   `restoreIgnore`, `newLabelLayoutWithGeometry`) has since landed in this file and is wired into
//   AxisBuilder's overlap-resolution pass; `labelLayoutApplyTranslation` (and `LabelGeometry`
//   dirty-bit caching) remain deferred. This L1c pass landed only what the pie leader-line layout needs.

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

    // ─────────────────────────── LabelGeometry / hideOverlap (L2c) ───────────────────────────
    //
    // Ported the rotated-rect OBB overlap machinery that was DEFERRED in the L1c pass above:
    //   `LabelLayoutData` (the `LabelLayoutBase & LabelGeometry` union), `computeLabelGeometry`,
    //   the dirty-bit cache (`setLabelLayoutDirty` / `ensureLabelLayoutWithGeometry`), `ensureOBB`,
    //   `labelIntersect`, `hideOverlap` and `restoreIgnore`. These drive the global label-overlap
    //   stage (upstream `LabelManager.layout` → `hideOverlap`).
    //
    // MARGIN gap (unchanged from L1c): upstream `computeLabelGeometry` resolves `style.margin` vs
    //   `style.__marginType` (textMargin/minMargin) plus the `marginForce`/`minMarginForce`/
    //   `marginDefault` overrides. `__marginType` is a documented gap in the port's `labelStyle`, so
    //   labels carry no explicit margin here and no margin expansion is applied (all four terms are
    //   0). Faithful for the default labels the driver produces.

    // upstream:
    //   const LABEL_LAYOUT_DIRTY_BIT_OTHERS = 1;
    //   const LABEL_LAYOUT_DIRTY_BIT_OBB = 2;
    //   const LABEL_LAYOUT_DIRTY_ALL = OTHERS | OBB;
    public static let LABEL_LAYOUT_DIRTY_BIT_OTHERS = 1
    public static let LABEL_LAYOUT_DIRTY_BIT_OBB = 2
    public static let LABEL_LAYOUT_DIRTY_ALL = 1 | 2

    /// upstream: setLabelLayoutDirty(labelGeometry, dirtyOrClear, dirtyBits?)
    /// `dirty` is `nil` when uninitialized (upstream `NullUndefined`); JS coerces it to 0 in the
    /// bitwise ops, so treat `nil` as 0 here.
    public static func setLabelLayoutDirty(
        _ g: LabelLayoutData, _ dirtyOrClear: Bool, _ dirtyBits: Int? = nil
    ) {
        let bits = dirtyBits ?? LABEL_LAYOUT_DIRTY_ALL
        g.dirty = dirtyOrClear
            ? (g.dirty ?? 0) | bits
            : (g.dirty ?? 0) & ~bits
    }

    /// upstream: function isLabelLayoutDirty(labelGeometry, dirtyBits?)
    private static func isLabelLayoutDirty(_ g: LabelLayoutData, _ dirtyBits: Int? = nil) -> Bool {
        let bits = dirtyBits ?? LABEL_LAYOUT_DIRTY_ALL
        return g.dirty == nil || (g.dirty! & bits) != 0
    }

    /// upstream: export function ensureLabelLayoutWithGeometry(labelLayout)
    /// Recompute the label's geometry if the dirty bit is set; returns the same object.
    @discardableResult
    public static func ensureLabelLayoutWithGeometry(_ labelLayout: LabelLayoutData?) -> LabelLayoutData? {
        guard let labelLayout = labelLayout else { return nil }
        if isLabelLayoutDirty(labelLayout) {
            computeLabelGeometry(labelLayout, labelLayout.label)
        }
        return labelLayout
    }

    /// upstream: export function newLabelLayoutWithGeometry(newBaseWithDefaults, source)
    /// Duplicate a `LabelLayoutData` (sharing the same `label` element) and recompute its geometry, so
    /// a caller can apply an `ignoreMargin`/`marginForce` variation without mutating the original.
    ///
    /// upstream copies `LABEL_LAYOUT_BASE_PROPS` (label, labelLine, layoutOption, priority, defaultAttr,
    ///   marginForce, minMarginForce, marginDefault, suggestIgnore) from `source` into the partial
    ///   `newBaseWithDefaults`, then calls `ensureLabelLayoutWithGeometry`. The MARGIN machinery
    ///   (`marginForce`/`minMarginForce`/`marginDefault`) is a documented no-op in this port (see the
    ///   note above `computeLabelGeometry`), so the only variation upstream drives through this
    ///   function — a `marginForce` override — has no effect here; the copy carries the same geometry as
    ///   `source`. Faithful for the default labels the axis path produces.
    public static func newLabelLayoutWithGeometry(_ source: LabelLayoutData) -> LabelLayoutData? {
        let out = LabelLayoutData(
            label: source.label,
            labelLine: source.labelLine,
            layoutOption: source.layoutOption,
            layoutCallback: source.layoutCallback,
            dataIndex: source.dataIndex,
            dataType: source.dataType,
            seriesIndex: source.seriesIndex,
            priority: source.priority,
            defaultAttr: source.defaultAttr,
            suggestIgnore: source.suggestIgnore
        )
        return ensureLabelLayoutWithGeometry(out)
    }

    /// upstream: export function computeLabelGeometry(out, label, opt?)
    /// Fills `out`'s geometry props (transform / localRect / global rect / axisAligned / ignore) from
    /// the live label. See the MARGIN gap note above (no margin expansion in the port).
    public static func computeLabelGeometry(_ out: LabelLayoutData, _ label: ZRText) {
        // [CAUTION] These props may be modified directly for performance consideration.
        let rawTransform = label.getComputedTransform()
        out.transform = ensureCopyTransform(out.transform, rawTransform)

        // NOTE: getBoundingRect must be called AFTER getComputedTransform (upstream note): the latter
        //   runs the host's `updateInnerText`, which may relayout the label.
        let outLocalRect = ensureCopyRect(out.localRect, label.getBoundingRect() ?? BoundingRect(0, 0, 0, 0))
        out.localRect = outLocalRect

        // MARGIN gap: `__marginType`/`margin` machinery deferred → no `expandOrShrinkRect` expansion.

        let outGlobalRect = ensureCopyRect(out.rect, outLocalRect)
        out.rect = outGlobalRect
        if let t = rawTransform {
            outGlobalRect.applyTransform(t)
        }

        out.axisAligned = isBoundingRectAxisAligned(rawTransform)

        out.geomIgnore = label.ignore

        setLabelLayoutDirty(out, false)                                   // clear ALL
        setLabelLayoutDirty(out, true, LABEL_LAYOUT_DIRTY_BIT_OBB)        // OBB stays dirty (lazy)
        // Do not remove `obb` (if existing) for reuse, just reset the dirty bit.
    }

    /// upstream: function ensureOBB(labelGeometry)
    /// Create the OBB lazily (only when a rotated-rect check is actually needed) and cache it.
    @discardableResult
    public static func ensureOBB(_ g: LabelLayoutData) -> OrientedBoundingRect {
        var obb = g.obb
        if obb == nil || isLabelLayoutDirty(g, LABEL_LAYOUT_DIRTY_BIT_OBB) {
            obb = obb ?? OrientedBoundingRect()
            g.obb = obb
            obb!.fromBoundingRect(g.localRect ?? BoundingRect(0, 0, 0, 0), g.transform)
            setLabelLayoutDirty(g, false, LABEL_LAYOUT_DIRTY_BIT_OBB)
        }
        return obb!
    }

    /// upstream: export function labelIntersect(baseLayoutInfo, targetLayoutInfo, mtv?, intersectOpt?)
    /// Fast axis-aligned rejection first, then the rotated-rect OBB test if either is rotated.
    @discardableResult
    public static func labelIntersect(
        _ baseLayoutInfo: LabelLayoutData?,
        _ targetLayoutInfo: LabelLayoutData?,
        _ mtv: PointLike? = nil,
        _ intersectOpt: BoundingRectIntersectOpt? = nil
    ) -> Bool {
        guard let base = baseLayoutInfo, let target = targetLayoutInfo else {
            return false
        }
        if base.geomIgnore || target.geomIgnore {
            return false
        }
        // Fast rejection.
        if !base.rect.intersect(target.rect, mtv, intersectOpt) {
            return false
        }
        if base.axisAligned && target.axisAligned {
            return true // obb is the same as the normal bounding rect.
        }
        return ensureOBB(base).intersect(ensureOBB(target), mtv, intersectOpt)
    }

    /// upstream: export function restoreIgnore(labelList)
    /// Restore each label's (and its guide line's) `ignore` to the saved default before re-resolving.
    public static func restoreIgnore(_ labelList: [LabelLayoutData]) {
        for labelItem in labelList {
            labelItem.label.attr("ignore", labelItem.defaultAttr.ignore)
            if let labelLine = labelItem.labelLine {
                labelLine.attr("ignore", labelItem.defaultAttr.labelGuideIgnore)
            }
        }
    }

    /// upstream: export function hideOverlap(labelList)
    /// Resolve cross-label overlap globally: higher-priority labels win, each subsequent label that
    /// overlaps an already-displayed one is set `ignore = true` (kept visible only on emphasis).
    public static func hideOverlap(_ labelList: [LabelLayoutData]) {
        var displayedLabels: [LabelLayoutData] = []

        // TODO, render overflow visible first, put in the displayedLabels.
        var labelList = labelList
        labelList.sort { a, b in
            let bySuggest = (b.suggestIgnore ? 1 : 0) - (a.suggestIgnore ? 1 : 0)
            if bySuggest != 0 {
                return bySuggest < 0
            }
            return (b.priority - a.priority) < 0
        }

        func hideEl(_ el: Element) {
            if !el.ignore {
                // Show on emphasis.
                let emphasisState = el.ensureState("emphasis")
                if emphasisState.ignore == nil {
                    emphasisState.ignore = false
                }
            }
            el.ignore = true
        }

        for i in 0..<labelList.count {
            guard let labelItem = ensureLabelLayoutWithGeometry(labelList[i]) else { continue }

            // The current `el.ignore` is involved, since some previous overlap
            // resolving strategies may have set `el.ignore` to true.
            if labelItem.label.ignore {
                continue
            }

            let label = labelItem.label
            let labelLine = labelItem.labelLine

            var overlapped = false
            for j in 0..<displayedLabels.count {
                if labelIntersect(
                    labelItem, displayedLabels[j], nil,
                    BoundingRectIntersectOpt(touchThreshold: 0.05)
                ) {
                    overlapped = true
                    break
                }
            }

            // TODO Callback to determine if this overlap should be handled?
            if overlapped {
                hideEl(label)
                if let labelLine = labelLine {
                    hideEl(labelLine)
                }
            }
            else {
                displayedLabels.append(labelItem)
            }
        }
    }
}

/// upstream: `LabelLayoutData = LabelLayoutBase & Partial<LabelGeometry>` (labelLayoutHelper.ts).
/// A reference type: `hideOverlap` / `shiftLayoutOnXY` mutate `rect` (a shared `BoundingRect`) and
/// `label` in place. Conforms to `labelLayoutHelper.ShiftLayoutItem` so the moveOverlap resolver
/// (`shiftLayoutOnXY`) accepts it directly.
///
/// The `label` in upstream's `LabelGeometry` is `Pick<ZRText, 'ignore'>`; in the union it collapses
/// to the real `ZRText` (the base's `label`), and `computeLabelGeometry`'s `out.label.ignore = ...`
/// is effectively a snapshot. Here `geomIgnore` carries that snapshot; `label` is the real element.
public final class LabelLayoutData: labelLayoutHelper.ShiftLayoutItem {
    // ─── LabelLayoutBase ───
    public let label: ZRText
    public var labelLine: Element?
    public var layoutOption: LabelLayoutOption?
    /// upstream `LabelDesc['layoutOptionOrCb']`'s function arm. When set, `updateLayoutConfig` builds
    ///   `prepareLayoutCallbackParams` and calls this to derive `layoutOption` per-label (the
    ///   option-object arm leaves this `nil` and uses `layoutOption` directly).
    public var layoutCallback: LabelLayoutOptionCallback?
    /// Identity of the data this label represents (upstream `LabelDesc.dataIndex`/`.dataType` +
    ///   `seriesModel.seriesIndex`), threaded so the callback params can be built.
    public var dataIndex: Double?
    public var dataType: SeriesDataType?
    public var seriesIndex: Double
    public var priority: Double
    public var defaultAttr: SavedLabelAttr
    public var suggestIgnore: Bool

    // ─── LabelGeometry ───
    /// `nil` == fully dirty (upstream uninitialized `NullUndefined`).
    public var dirty: Int?
    /// Global rect from `localRect` + transform. `ShiftLayoutItem.rect` is non-optional, so it is
    /// force-unwrapped there — it is always populated by `ensureLabelLayoutWithGeometry` before use.
    public var rect: BoundingRect
    public var localRect: BoundingRect?
    public var axisAligned: Bool
    public var obb: OrientedBoundingRect?
    public var transform: MatrixArray?
    /// `out.label.ignore` snapshot (upstream `LabelGeometry.label.ignore`).
    public var geomIgnore: Bool

    public init(
        label: ZRText,
        labelLine: Element? = nil,
        layoutOption: LabelLayoutOption? = nil,
        layoutCallback: LabelLayoutOptionCallback? = nil,
        dataIndex: Double? = nil,
        dataType: SeriesDataType? = nil,
        seriesIndex: Double = 0,
        priority: Double = 0,
        defaultAttr: SavedLabelAttr = SavedLabelAttr(),
        suggestIgnore: Bool = false
    ) {
        self.label = label
        self.labelLine = labelLine
        self.layoutOption = layoutOption
        self.layoutCallback = layoutCallback
        self.dataIndex = dataIndex
        self.dataType = dataType
        self.seriesIndex = seriesIndex
        self.priority = priority
        self.defaultAttr = defaultAttr
        self.suggestIgnore = suggestIgnore
        self.dirty = nil
        self.rect = BoundingRect(0, 0, 0, 0)
        self.localRect = nil
        self.axisAligned = false
        self.obb = nil
        self.transform = nil
        self.geomIgnore = false
    }
}

/// upstream: `interface SavedLabelAttr` (LabelManager.ts). Only the fields the ported stage reads are
/// carried; the drag / attached-text-config fields are PORT-TODO (see `LabelManager.swift`).
public struct SavedLabelAttr {
    public var ignore: Bool
    public var labelGuideIgnore: Bool
    public var x: Double
    public var y: Double
    public var scaleX: Double
    public var scaleY: Double
    public var rotation: Double
    public var styleX: Double?
    public var styleY: Double?
    public var align: ZRTextAlign?
    public var verticalAlign: ZRTextVerticalAlign?
    public var width: Double?
    public var height: Double?
    public var fontSize: Any?

    public init(
        ignore: Bool = false,
        labelGuideIgnore: Bool = false,
        x: Double = 0,
        y: Double = 0,
        scaleX: Double = 1,
        scaleY: Double = 1,
        rotation: Double = 0,
        styleX: Double? = nil,
        styleY: Double? = nil,
        align: ZRTextAlign? = nil,
        verticalAlign: ZRTextVerticalAlign? = nil,
        width: Double? = nil,
        height: Double? = nil,
        fontSize: Any? = nil
    ) {
        self.ignore = ignore
        self.labelGuideIgnore = labelGuideIgnore
        self.x = x
        self.y = y
        self.scaleX = scaleX
        self.scaleY = scaleY
        self.rotation = rotation
        self.styleX = styleX
        self.styleY = styleY
        self.align = align
        self.verticalAlign = verticalAlign
        self.width = width
        self.height = height
        self.fontSize = fontSize
    }
}
