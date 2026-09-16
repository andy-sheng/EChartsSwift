// Ported from echarts/src/chart/pie/labelLayout.ts — keep in sync with upstream.
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

// upstream imports resolve to:
//   parsePercent -> number.parsePercent; limitTurnAngle/limitSurfaceAngle -> labelGuideHelper;
//   computeLabelGeometry(computeLabelGlobalRect)/shiftLayoutOnXY -> labelLayoutHelper;
//   ZRText/Polyline/Point/BoundingRect -> ZRenderKit.

private let RADIAN = Double.pi / 180

/// upstream: interface LabelLayout — the per-label placement record built in `pieLabelLayout` and
/// mutated by `avoidOverlap` / `shiftLayoutOnXY`. A reference type (class) because `shiftLayoutOnXY`
/// mutates `rect` / `label` through the shared list, and `linePoints` is mutated in place.
final class PieLabelLayout: labelLayoutHelper.ShiftLayoutItem {
    let label: ZRText
    let labelLine: Polyline?
    let position: String?           // 'outer' | 'inside' | 'inner' | 'center' | ...
    let len: Double
    let len2: Double
    let minTurnAngle: Double
    let maxSurfaceAngle: Double
    let surfaceNormal: Point
    var linePoints: [[Double]]?
    let textAlign: TextAlign?
    let labelDistance: Double
    let labelAlignTo: String        // 'none' | 'labelLine' | 'edge'
    let edgeDistance: Double
    let bleedMargin: Double
    let rect: BoundingRect
    /// user-set style.width (nil unless the user pinned it) — highest priority in `constrainTextWidth`.
    let labelStyleWidth: Double?
    var unconstrainedWidth: Double
    var targetTextWidth: Double?

    init(
        label: ZRText, labelLine: Polyline?, position: String?, len: Double, len2: Double,
        minTurnAngle: Double, maxSurfaceAngle: Double, surfaceNormal: Point, linePoints: [[Double]]?,
        textAlign: TextAlign?, labelDistance: Double, labelAlignTo: String, edgeDistance: Double,
        bleedMargin: Double, rect: BoundingRect, labelStyleWidth: Double?, unconstrainedWidth: Double
    ) {
        self.label = label; self.labelLine = labelLine; self.position = position
        self.len = len; self.len2 = len2; self.minTurnAngle = minTurnAngle
        self.maxSurfaceAngle = maxSurfaceAngle; self.surfaceNormal = surfaceNormal
        self.linePoints = linePoints; self.textAlign = textAlign; self.labelDistance = labelDistance
        self.labelAlignTo = labelAlignTo; self.edgeDistance = edgeDistance; self.bleedMargin = bleedMargin
        self.rect = rect; self.labelStyleWidth = labelStyleWidth; self.unconstrainedWidth = unconstrainedWidth
    }
}

// upstream: function isPositionCenter — center labels are not x-shifted.
private func isPositionCenter(_ sectorShape: PieLabelLayout) -> Bool {
    return sectorShape.position == "center"
}

// upstream: function computeLabelGlobalRect(out, label) — the pie geometry opt
//   ({ minMarginForce: [null,0,null,0], marginDefault: [1,0,1,0] }) is baked into
//   labelLayoutHelper.computeLabelGlobalRect.
private func computeLabelGlobalRect(_ out: BoundingRect, _ label: ZRText) {
    labelLayoutHelper.computeLabelGlobalRect(out, label)
}

// The horizontal inner padding (padding[1] + padding[3]) of the label style, or 0.
private func paddingH(_ label: ZRText) -> Double {
    guard let p = label.textStyle.padding else { return 0 }
    switch p {
    case .array(let a):
        // upstream `padding` normalized to 4-length [top,right,bottom,left].
        if a.count >= 4 { return a[1] + a[3] }
        if a.count == 2 { return a[1] * 2 }
        if a.count == 1 { return a[0] * 2 }
        return 0
    case .number(let n):
        return n * 2
    }
}

private func hasBackground(_ label: ZRText) -> Bool {
    return label.textStyle.backgroundColor != nil
}

/**
 * upstream: function constrainTextWidth(layout, availableWidth, forceRecalculate)
 * Set max width of each label and wrap/truncate to that width.
 */
private func constrainTextWidth(_ layout: PieLabelLayout, _ availableWidth: Double, _ forceRecalculate: Bool) {
    if layout.labelStyleWidth != nil {
        // User-defined style.width has the highest priority.
        return
    }

    let label = layout.label
    let textRect = layout.rect
    let bgColor = label.textStyle.backgroundColor
    let padH = paddingH(label)
    let overflow = label.textStyle.overflow

    // textRect.width already contains paddingH if bgColor is set.
    let oldOuterWidth = textRect.width + (bgColor != nil ? 0 : padH)
    if availableWidth < oldOuterWidth || forceRecalculate {
        if let overflow = overflow, overflow.contains("break") {
            // Temporarily set background to null to calculate the bounding box without background.
            label.textStyle.backgroundColor = nil
            label.textStyle.width = availableWidth - padH
            label.dirtyStyle()

            // Real bounding box of the text without padding.
            let innerRect = label.getBoundingRect() ?? BoundingRect(0, 0, 0, 0)

            label.textStyle.width = innerRect.width.rounded(.up)
            label.textStyle.backgroundColor = bgColor
            label.dirtyStyle()
        }
        else {
            let availableInnerWidth = availableWidth - padH
            let newWidth: Double?
            if availableWidth < oldOuterWidth {
                // Current text is too wide, use `availableWidth` as max width.
                newWidth = availableInnerWidth
            }
            else if forceRecalculate {
                // Current available width is enough, but the text may have already been wrapped
                //   with a smaller available width.
                newWidth = availableInnerWidth > layout.unconstrainedWidth
                    ? nil                    // available is larger than text width — don't constrain.
                    : availableInnerWidth    // available is smaller — constrain to it.
            }
            else {
                newWidth = nil
            }
            label.textStyle.width = newWidth
            label.dirtyStyle()
        }

        computeLabelGlobalRect(textRect, label)
    }
}

/// upstream: function adjustSingleSide(list, cx, cy, r, dir, viewWidth, viewHeight, viewLeft, viewTop, farthestX)
private func adjustSingleSide(
    _ list: [PieLabelLayout], _ cx: Double, _ cy: Double, _ r: Double, _ dir: Double,
    _ viewWidth: Double, _ viewHeight: Double, _ viewLeft: Double, _ viewTop: Double, _ farthestX: Double
) {
    if list.count < 2 {
        return
    }

    struct SemiInfo {
        var list: [PieLabelLayout] = []
        var rB: Double = 0
        var maxY: Double = 0
    }

    func recalculateXOnSemiToAlignOnEllipseCurve(_ semi: SemiInfo) {
        let rB = semi.rB
        let rB2 = rB * rB
        for item in semi.list {
            let dy = abs((item.label.y) - cy)
            // horizontal r is always same with original r because x is not changed.
            let rA = r + item.len
            let rA2 = rA * rA
            // Use ellipse implicit function to calculate x.
            let dx = (abs((1 - dy * dy / rB2) * rA2)).squareRoot()
            let newX = cx + (dx + item.len2) * dir
            let deltaX = newX - (item.label.x)
            let newTargetWidth = (item.targetTextWidth ?? 0) - deltaX * dir
            // text x is changed, so need to recalculate width.
            constrainTextWidth(item, newTargetWidth, true)
            item.label.x = newX
        }
    }

    // Adjust X based on the shifted y. Make tight labels aligned on an ellipse curve.
    func recalculateX(_ items: [PieLabelLayout]) {
        var topSemi = SemiInfo()
        var bottomSemi = SemiInfo()

        for item in items {
            if item.labelAlignTo != "none" {
                continue
            }
            let labelY = item.label.y
            let dy = abs(labelY - cy)
            let isBottom = labelY > cy
            let semiMaxY = isBottom ? bottomSemi.maxY : topSemi.maxY
            if dy >= semiMaxY {
                let dx = (item.label.x) - cx - item.len2 * dir
                // horizontal r is always same with original r because x is not changed.
                let rA = r + item.len
                // Calculate rB based on the topest / bottommost label.
                let rB = abs(dx) < rA
                    ? (dy * dy / (1 - dx * dx / rA / rA)).squareRoot()
                    : rA
                if isBottom { bottomSemi.rB = rB; bottomSemi.maxY = dy }
                else { topSemi.rB = rB; topSemi.maxY = dy }
            }
            if isBottom { bottomSemi.list.append(item) } else { topSemi.list.append(item) }
        }

        recalculateXOnSemiToAlignOnEllipseCurve(topSemi)
        recalculateXOnSemiToAlignOnEllipseCurve(bottomSemi)
    }

    for item in list {
        if item.position == "outer" && item.labelAlignTo == "labelLine" {
            let dx = (item.label.x) - farthestX
            if item.linePoints != nil {
                item.linePoints![1][0] += dx
            }
            item.label.x = farthestX
        }
    }

    if labelLayoutHelper.shiftLayoutOnXY(list, 1, viewTop, viewTop + viewHeight) {
        recalculateX(list)
    }
}

/// upstream: function avoidOverlap(labelLayoutList, cx, cy, r, viewWidth, viewHeight, viewLeft, viewTop)
private func avoidOverlap(
    _ labelLayoutList: [PieLabelLayout], _ cx: Double, _ cy: Double, _ r: Double,
    _ viewWidth: Double, _ viewHeight: Double, _ viewLeft: Double, _ viewTop: Double
) {
    var leftList: [PieLabelLayout] = []
    var rightList: [PieLabelLayout] = []
    var leftmostX = Double.greatestFiniteMagnitude
    var rightmostX = -Double.greatestFiniteMagnitude
    for layout in labelLayoutList {
        if isPositionCenter(layout) {
            continue
        }
        let x = layout.label.x
        if x < cx {
            leftmostX = Swift.min(leftmostX, x)
            leftList.append(layout)
        }
        else {
            rightmostX = Swift.max(rightmostX, x)
            rightList.append(layout)
        }
    }

    for layout in labelLayoutList {
        if !isPositionCenter(layout), let linePoints = layout.linePoints {
            if layout.labelStyleWidth != nil {
                continue
            }

            let x = layout.label.x
            var targetTextWidth: Double
            if layout.labelAlignTo == "edge" {
                if x < cx {
                    targetTextWidth = linePoints[2][0] - layout.labelDistance - viewLeft - layout.edgeDistance
                }
                else {
                    targetTextWidth = viewLeft + viewWidth - layout.edgeDistance - linePoints[2][0] - layout.labelDistance
                }
            }
            else if layout.labelAlignTo == "labelLine" {
                if x < cx {
                    targetTextWidth = leftmostX - viewLeft - layout.bleedMargin
                }
                else {
                    targetTextWidth = viewLeft + viewWidth - rightmostX - layout.bleedMargin
                }
            }
            else {
                if x < cx {
                    targetTextWidth = x - viewLeft - layout.bleedMargin
                }
                else {
                    targetTextWidth = viewLeft + viewWidth - x - layout.bleedMargin
                }
            }
            layout.targetTextWidth = targetTextWidth

            constrainTextWidth(layout, targetTextWidth, false)
        }
    }

    adjustSingleSide(rightList, cx, cy, r, 1, viewWidth, viewHeight, viewLeft, viewTop, rightmostX)
    adjustSingleSide(leftList, cx, cy, r, -1, viewWidth, viewHeight, viewLeft, viewTop, leftmostX)

    for layout in labelLayoutList {
        guard !isPositionCenter(layout), var linePoints = layout.linePoints else {
            continue
        }
        let label = layout.label
        let x = label.x
        let isAlignToEdge = layout.labelAlignTo == "edge"
        let padH = paddingH(label)
        // textRect.width already contains paddingH if bgColor is set.
        let extraPaddingH = hasBackground(label) ? 0 : padH
        let realTextWidth = layout.rect.width + extraPaddingH
        let dist = linePoints[1][0] - linePoints[2][0]
        if isAlignToEdge {
            if x < cx {
                linePoints[2][0] = viewLeft + layout.edgeDistance + realTextWidth + layout.labelDistance
            }
            else {
                linePoints[2][0] = viewLeft + viewWidth - layout.edgeDistance - realTextWidth - layout.labelDistance
            }
        }
        else {
            if x < cx {
                linePoints[2][0] = x + layout.labelDistance
            }
            else {
                linePoints[2][0] = x - layout.labelDistance
            }
            linePoints[1][0] = linePoints[2][0] + dist
        }
        linePoints[1][1] = label.y
        linePoints[2][1] = label.y
        layout.linePoints = linePoints
    }
}

/// upstream: export default function pieLabelLayout(seriesModel: PieSeriesModel)
func pieLabelLayout(_ seriesModel: PieSeriesModel) {
    let data = seriesModel.getData()
    var labelLayoutList: [PieLabelLayout] = []
    var cx = 0.0
    var cy = 0.0
    var hasLabelRotate = false
    let minShowLabelRadian = (pieAsDouble(seriesModel.get("minShowLabelAngle")) ?? 0) * RADIAN

    guard let viewRect = data.getLayout("viewRect") as? BoundingRect else { return }
    let r = pieAsDouble(data.getLayout("r")) ?? 0
    let viewWidth = viewRect.width
    let viewLeft = viewRect.x
    let viewTop = viewRect.y
    let viewHeight = viewRect.height

    func setNotShow(_ states: Dictionary<ElementState>) {
        for (_, state) in states { state.ignore = true }
    }

    func isLabelShown(_ label: ZRText) -> Bool {
        if !label.ignore {
            return true
        }
        for (_, state) in label.states {
            if state.ignore == false {
                return true
            }
        }
        return false
    }

    for idx in 0..<data.count() {
        guard let sector = data.getItemGraphicEl(idx) as? Path,
              let sectorShape = sector.shape as? SectorShape,
              let label = sector.getTextContent() else {
            continue
        }
        let labelLine = sector.getTextGuideLine()

        let itemModel = data.getItemModel(idx)
        let labelModel = itemModel.getModel("label")
        // Use position in normal or emphasis
        let labelPosition = (labelModel.get("position") as? String)
            ?? (itemModel.get(["emphasis", "label", "position"]) as? String)
        let labelDistance = pieAsDouble(labelModel.get("distanceToLabelLine")) ?? 0
        let labelAlignTo = (labelModel.get("alignTo") as? String) ?? "none"
        let edgeDistance = number.parsePercent(labelModel.get("edgeDistance"), viewWidth)
        var bleedMargin = pieAsDouble(labelModel.get("bleedMargin"))
        if bleedMargin == nil {
            // An arbitrary strategy for small viewRect (pie in calendar / matrix coord sys).
            bleedMargin = Swift.min(viewWidth, viewHeight) > 200 ? 10 : 2
        }

        let labelLineModel = itemModel.getModel("labelLine")
        let labelLineLen = number.parsePercent(labelLineModel.get("length"), viewWidth)
        let labelLineLen2 = number.parsePercent(labelLineModel.get("length2"), viewWidth)

        if abs(sectorShape.endAngle - sectorShape.startAngle) < minShowLabelRadian {
            setNotShow(label.states)
            label.ignore = true
            if let labelLine = labelLine {
                setNotShow(labelLine.states)
                labelLine.ignore = true
            }
            continue
        }

        if !isLabelShown(label) {
            continue
        }

        let midAngle = (sectorShape.startAngle + sectorShape.endAngle) / 2
        let nx = cos(midAngle)
        let ny = sin(midAngle)

        var textX: Double
        var textY: Double
        var linePoints: [[Double]]? = nil
        var textAlign: TextAlign

        cx = sectorShape.cx
        cy = sectorShape.cy

        let isLabelInside = labelPosition == "inside" || labelPosition == "inner"
        if labelPosition == "center" {
            textX = sectorShape.cx
            textY = sectorShape.cy
            textAlign = .center
        }
        else {
            let x1 = (isLabelInside ? (sectorShape.r + sectorShape.r0) / 2 * nx : sectorShape.r * nx) + cx
            let y1 = (isLabelInside ? (sectorShape.r + sectorShape.r0) / 2 * ny : sectorShape.r * ny) + cy

            textX = x1 + nx * 3
            textY = y1 + ny * 3

            if !isLabelInside {
                // For roseType
                let x2 = x1 + nx * (labelLineLen + r - sectorShape.r)
                let y2 = y1 + ny * (labelLineLen + r - sectorShape.r)
                let x3 = x2 + ((nx < 0 ? -1 : 1) * labelLineLen2)
                let y3 = y2

                if labelAlignTo == "edge" {
                    // Adjust textX because text align of edge is opposite.
                    textX = nx < 0
                        ? viewLeft + edgeDistance
                        : viewLeft + viewWidth - edgeDistance
                }
                else {
                    textX = x3 + (nx < 0 ? -labelDistance : labelDistance)
                }
                textY = y3
                linePoints = [[x1, y1], [x2, y2], [x3, y3]]
            }

            textAlign = isLabelInside
                ? .center
                : (labelAlignTo == "edge"
                    ? (nx > 0 ? .right : .left)
                    : (nx > 0 ? .left : .right))
        }

        let PI = Double.pi
        var labelRotate = 0.0
        let rotate = labelModel.get("rotate")
        if let rotateNum = pieAsDouble(rotate), !(rotate is String) {
            labelRotate = rotateNum * (PI / 180)
        }
        else if labelPosition == "center" {
            labelRotate = 0
        }
        else if (rotate as? String) == "radial" || (rotate as? Bool) == true {
            let radialAngle = nx < 0 ? -midAngle + PI : -midAngle
            labelRotate = radialAngle
        }
        else if (rotate as? String) == "tangential"
            || ((rotate as? String) == "tangential-noflip"
                && labelPosition != "outside" && labelPosition != "outer") {
            var rad = atan2(nx, ny)
            if rad < 0 {
                rad = PI * 2 + rad
            }
            let isDown = ny > 0
            if isDown && (rotate as? String) != "tangential-noflip" {
                rad = PI + rad
            }
            labelRotate = rad - PI
        }

        hasLabelRotate = labelRotate != 0

        label.x = textX
        label.y = textY
        label.rotation = labelRotate

        label.textStyle.verticalAlign = .middle

        // Not the inside label
        if !isLabelInside {
            let textRect = BoundingRect(0, 0, 0, 0)
            computeLabelGlobalRect(textRect, label)

            labelLayoutList.append(PieLabelLayout(
                label: label,
                labelLine: labelLine,
                position: labelPosition,
                len: labelLineLen,
                len2: labelLineLen2,
                minTurnAngle: pieAsDouble(labelLineModel.get("minTurnAngle")) ?? 0,
                maxSurfaceAngle: pieAsDouble(labelLineModel.get("maxSurfaceAngle")) ?? 0,
                surfaceNormal: Point(nx, ny),
                linePoints: linePoints,
                textAlign: textAlign,
                labelDistance: labelDistance,
                labelAlignTo: labelAlignTo,
                edgeDistance: edgeDistance,
                bleedMargin: bleedMargin ?? 0,
                rect: textRect,
                labelStyleWidth: label.textStyle.width,
                unconstrainedWidth: textRect.width
            ))
        }
        else {
            label.textStyle.align = textAlign
            if let selectState = label.states["select"] {
                selectState.x = (selectState.x ?? 0) + (label.x)
                selectState.y = (selectState.y ?? 0) + (label.y)
            }
        }
        // sector.setTextConfig({ inside: isLabelInside }): the label uses its own absolute x/y/rotation
        //   (textConfig.position stays nil), and `inside` drives the inside/outside auto text colour.
        var tc = ElementTextConfig()
        tc.inside = isLabelInside
        sector.setTextConfig(tc)
    }

    if !hasLabelRotate && (seriesModel.get("avoidLabelOverlap") as? Bool) != false {
        avoidOverlap(labelLayoutList, cx, cy, r, viewWidth, viewHeight, viewLeft, viewTop)
    }

    for layout in labelLayoutList {
        let label = layout.label
        let labelLine = layout.labelLine
        let notShowLabel = label.x.isNaN || label.y.isNaN
        if let ta = layout.textAlign {
            if label.textStyle.align != ta {
                label.textStyle.align = ta
                // The text may already have materialized TSpan children during the earlier geometry
                // measurement. Mark it dirty so a left-side outer label rebuilds those children with
                // `.right` alignment instead of keeping the default `.left` and growing into the pie.
                label.dirtyStyle()
            }
        }
        if notShowLabel {
            setNotShow(label.states)
            label.ignore = true
        }
        if let selectState = label.states["select"] {
            selectState.x = (selectState.x ?? 0) + (label.x)
            selectState.y = (selectState.y ?? 0) + (label.y)
        }
        if let labelLine = labelLine {
            if notShowLabel || layout.linePoints == nil {
                setNotShow(labelLine.states)
                labelLine.ignore = true
            }
            else {
                var linePoints = layout.linePoints!
                labelGuideHelper.limitTurnAngle(&linePoints, layout.minTurnAngle)
                labelGuideHelper.limitSurfaceAngle(&linePoints, layout.surfaceNormal, layout.maxSurfaceAngle)
                layout.linePoints = linePoints

                // upstream: labelLine.setShape({ points: linePoints }) — a PARTIAL object that
                //   `extend`s into the existing shape, preserving fields set earlier (notably
                //   `smooth`, stamped by `labelGuideHelper.setLabelLineStyle`).
                // Swift's `Path.setShape(_ obj: PathShape)` REPLACES the shape wholesale
                //   (Path.swift), so a partial-object upstream call must be read-modify-write here or
                //   `smooth` (and any other previously set field) is silently reset to its default —
                //   which would make `buildLabelLinePath`'s bezier rounded-corner branch unreachable.
                var lineShape = (labelLine.shape as? PolylineShape) ?? PolylineShape()
                lineShape.points = linePoints.map { VectorArray($0[0], $0[1]) }
                labelLine.setShape(lineShape)

                // Set the anchor to the midpoint of sector (linePoints[0]).
                var guideConfig = ElementTextGuideLineConfig()
                guideConfig.anchor = Point(linePoints[0][0], linePoints[0][1])
                sectorTextGuideHost(label)?.textGuideLineConfig = guideConfig
            }
        }
    }
}

// upstream `label.__hostTarget` — the sector hosting this label. Used to stamp textGuideLineConfig.
private func sectorTextGuideHost(_ label: ZRText) -> Element? {
    return label.__hostTarget
}

// Numeric coercion (defaultOptions box numbers as Int OR Double — see the Int-vs-Double trap).
//   Module-internal so the sibling pie files (PieView) share ONE copy instead of re-deriving it.
func pieAsDouble(_ v: Any?) -> Double? {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    return nil
}
