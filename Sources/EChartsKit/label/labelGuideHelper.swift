// Ported from echarts/src/label/labelGuideHelper.ts — keep in sync with upstream.
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

// upstream imports (only the subset the pie label layout needs is ported here):
//   import { Point } from '../../util/graphic';            -> ZRenderKit.Point.
//   import * as vector from 'zrender/src/core/vector';     -> VectorArray (SIMD2<Double>).
//
// PORT SCOPE: the geometry + candidate-anchor guide-line generation:
//   `limitTurnAngle` / `limitSurfaceAngle` (the leader-line angle limiters the pie label layout
//   calls) + the module-local projection helpers (`projectPointToLine` / `projectPointToArc` /
//   `projectPointToRect` / `nearestPointOnRect` / `nearestPointOnPath` / `getCandidateAnchor`) +
//   the `updateLabelLinePoints` entry point + `getLabelLineStatesModels`.
//   PORTED (leader-line *style/state* creation): `setLabelLineStyle`, `setLabelLineState`,
//   `buildLabelLinePath`. Upstream's per-instance `labelLine.buildPath = buildLabelLinePath` override
//   is routed through the ZRenderKit `Polyline.setBuildPathOverride` seam (backed by the existing
//   `__morphBuildPath` build-hook), added for this port. Pie/funnel may still draw their own
//   leader-line style inline until they wire this helper.

/// Namespace for the ported labelGuideHelper functions (caseless enum, mirrors `labelStyle`).
public enum labelGuideHelper {

    // upstream: const PI2 = Math.PI * 2;
    private static let PI2 = Double.pi * 2

    // upstream: const DEFAULT_SEARCH_SPACE = ['top', 'right', 'bottom', 'left'] as const;
    private static let DEFAULT_SEARCH_SPACE = ["top", "right", "bottom", "left"]

    /// Local numeric coercion (defaultOptions box numbers as Int OR Double — see the
    /// Int-vs-Double option-read trap).
    private static func asDouble(_ v: Any?) -> Double? {
        if let d = v as? Double { return d }
        if let i = v as? Int { return Double(i) }
        return nil
    }

    /// Local truthiness coercion mirroring JS `!!v` for option reads that upstream treats as
    /// booleans (`show`, `showAbove`). A bare `as? Bool` returns nil for an Int-boxed `show: 1`
    /// (see the Int-vs-Double option-read trap), which would flip the value to "hidden".
    private static func asBool(_ v: Any?) -> Bool? {
        if let b = v as? Bool { return b }
        if let i = v as? Int { return i != 0 }
        if let d = v as? Double { return d != 0 && !d.isNaN }
        if let s = v as? String { return !s.isEmpty }
        return nil
    }

    /// upstream module-local:
    ///   function getCandidateAnchor(pos, distance, rect, outPt, outDir)
    /// Writes the anchor point and outward direction for a candidate side of `rect` into the
    /// mutable output points.
    private static func getCandidateAnchor(
        _ pos: String, _ distance: Double, _ rect: BoundingRect, _ outPt: Point, _ outDir: Point
    ) {
        let width = rect.width
        let height = rect.height
        switch pos {
        case "top":
            outPt.set(rect.x + width / 2, rect.y - distance)
            outDir.set(0, -1)
        case "bottom":
            outPt.set(rect.x + width / 2, rect.y + height + distance)
            outDir.set(0, 1)
        case "left":
            outPt.set(rect.x - distance, rect.y + height / 2)
            outDir.set(-1, 0)
        case "right":
            outPt.set(rect.x + width + distance, rect.y + height / 2)
            outDir.set(1, 0)
        default:
            break
        }
    }

    /// upstream module-local:
    ///   function projectPointToArc(cx, cy, r, startAngle, endAngle, anticlockwise, x, y, out): number
    /// Projects (x, y) onto the arc and returns the distance to the projected point.
    @discardableResult
    private static func projectPointToArc(
        _ cx: Double, _ cy: Double, _ r: Double,
        _ startAngleIn: Double, _ endAngleIn: Double, _ anticlockwise: Bool,
        _ xIn: Double, _ yIn: Double, _ out: inout [Double]
    ) -> Double {
        var startAngle = startAngleIn
        var endAngle = endAngleIn
        var x = xIn - cx
        var y = yIn - cy
        let d = (x * x + y * y).squareRoot()
        x /= d
        y /= d

        // Intersect point.
        let ox = x * r + cx
        let oy = y * r + cy

        if (abs(startAngle - endAngle)).truncatingRemainder(dividingBy: PI2) < 1e-4 {
            // Is a circle
            out[0] = ox
            out[1] = oy
            return d - r
        }

        if anticlockwise {
            let tmp = startAngle
            startAngle = containUtil.normalizeRadian(endAngle)
            endAngle = containUtil.normalizeRadian(tmp)
        }
        else {
            startAngle = containUtil.normalizeRadian(startAngle)
            endAngle = containUtil.normalizeRadian(endAngle)
        }
        if startAngle > endAngle {
            endAngle += PI2
        }

        var angle = atan2(y, x)
        if angle < 0 {
            angle += PI2
        }
        if (angle >= startAngle && angle <= endAngle)
            || (angle + PI2 >= startAngle && angle + PI2 <= endAngle) {
            // Project point is on the arc.
            out[0] = ox
            out[1] = oy
            return d - r
        }

        let x1 = r * cos(startAngle) + cx
        let y1 = r * sin(startAngle) + cy

        let x2 = r * cos(endAngle) + cx
        let y2 = r * sin(endAngle) + cy

        // upstream reuses the *normalized* `x`/`y` (after `x /= d`) here, not the
        //   original inputs — mirrored faithfully.
        let d1 = (x1 - x) * (x1 - x) + (y1 - y) * (y1 - y)
        let d2 = (x2 - x) * (x2 - x) + (y2 - y) * (y2 - y)

        if d1 < d2 {
            out[0] = x1
            out[1] = y1
            return d1.squareRoot()
        }
        else {
            out[0] = x2
            out[1] = y2
            return d2.squareRoot()
        }
    }

    /// upstream module-local:
    ///   function projectPointToLine(x1, y1, x2, y2, x, y, out, limitToEnds): number
    /// Projects (x, y) onto the segment (x1,y1)-(x2,y2), writes the projected point into `out`
    /// (out[0]/out[1]) and returns the distance from (x, y) to that projected point.
    @discardableResult
    static func projectPointToLine(
        _ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double,
        _ x: Double, _ y: Double, _ out: inout [Double], _ limitToEnds: Bool
    ) -> Double {
        let dx = x - x1
        let dy = y - y1

        var dx1 = x2 - x1
        var dy1 = y2 - y1

        let lineLen = (dx1 * dx1 + dy1 * dy1).squareRoot()
        dx1 /= lineLen
        dy1 /= lineLen

        // dot product
        let projectedLen = dx * dx1 + dy * dy1
        var t = projectedLen / lineLen
        if limitToEnds {
            t = Swift.min(Swift.max(t, 0), 1)
        }
        t *= lineLen
        let ox = x1 + t * dx1
        let oy = y1 + t * dy1
        out[0] = ox
        out[1] = oy

        return ((ox - x) * (ox - x) + (oy - y) * (oy - y)).squareRoot()
    }

    /// upstream module-local:
    ///   function projectPointToRect(x1, y1, width, height, x, y, out): number
    /// Projects (x, y) onto the (possibly negative-sized) rect, writes the clamped point into
    /// `out` and returns the distance.
    @discardableResult
    private static func projectPointToRect(
        _ x1In: Double, _ y1In: Double, _ widthIn: Double, _ heightIn: Double,
        _ x: Double, _ y: Double, _ out: inout [Double]
    ) -> Double {
        var x1 = x1In
        var y1 = y1In
        var width = widthIn
        var height = heightIn
        if width < 0 {
            x1 = x1 + width
            width = -width
        }
        if height < 0 {
            y1 = y1 + height
            height = -height
        }
        let x2 = x1 + width
        let y2 = y1 + height

        let ox = Swift.min(Swift.max(x, x1), x2)
        let oy = Swift.min(Swift.max(y, y1), y2)
        out[0] = ox
        out[1] = oy

        return ((ox - x) * (ox - x) + (oy - y) * (oy - y)).squareRoot()
    }

    /// upstream module-local: function nearestPointOnRect(pt: Point, rect: RectLike, out: Point)
    @discardableResult
    private static func nearestPointOnRect(_ pt: Point, _ rect: BoundingRect, _ out: Point) -> Double {
        var tmpPt: [Double] = [0, 0]
        let dist = projectPointToRect(
            rect.x, rect.y, rect.width, rect.height,
            pt.x, pt.y, &tmpPt
        )
        out.set(tmpPt[0], tmpPt[1])
        return dist
    }

    /// upstream module-local: function nearestPointOnPath(pt: Point, path: PathProxy, out: Point)
    /// Calculate min distance corresponding point. This method won't evaluate if point is in the path.
    @discardableResult
    private static func nearestPointOnPath(_ pt: Point, _ path: PathProxy, _ out: Point) -> Double {
        var xi: Double = 0
        var yi: Double = 0
        var x0: Double = 0
        var y0: Double = 0
        var x1: Double
        var y1: Double

        var minDist = Double.infinity

        let data = path.data
        let x = pt.x
        let y = pt.y

        var tmpPt: [Double] = [0, 0]

        typealias CMD = PathProxy.CMD

        var i = 0
        while i < data.count {
            let cmd = data[i]; i += 1

            if i == 1 {
                xi = data[i]
                yi = data[i + 1]
                x0 = xi
                y0 = yi
            }

            var d = minDist

            switch cmd {
            case CMD.M:
                // moveTo starts a new subpath and updates the start point (used on closePath)
                x0 = data[i]; i += 1
                y0 = data[i]; i += 1
                xi = x0
                yi = y0
            case CMD.L:
                d = projectPointToLine(xi, yi, data[i], data[i + 1], x, y, &tmpPt, true)
                xi = data[i]; i += 1
                yi = data[i]; i += 1
            case CMD.C:
                let c1x = data[i]; let c1y = data[i + 1]
                let c2x = data[i + 2]; let c2y = data[i + 3]
                let ex = data[i + 4]; let ey = data[i + 5]
                let r = curve.cubicProjectPoint(xi, yi, c1x, c1y, c2x, c2y, ex, ey, x, y)
                d = r.distance
                tmpPt[0] = r.out.x; tmpPt[1] = r.out.y
                xi = ex
                yi = ey
                i += 6
            case CMD.Q:
                let cx1 = data[i]; let cy1 = data[i + 1]
                let ex = data[i + 2]; let ey = data[i + 3]
                let r = curve.quadraticProjectPoint(xi, yi, cx1, cy1, ex, ey, x, y)
                d = r.distance
                tmpPt[0] = r.out.x; tmpPt[1] = r.out.y
                xi = ex
                yi = ey
                i += 4
            case CMD.A:
                let cx = data[i]
                let cy = data[i + 1]
                let rx = data[i + 2]
                let ry = data[i + 3]
                let theta = data[i + 4]
                let dTheta = data[i + 5]
                // skip rotation (psi), then read the anticlockwise flag
                let anticlockwise = (1 - data[i + 7]) != 0
                i += 8
                x1 = cos(theta) * rx + cx
                y1 = sin(theta) * ry + cy
                // not directly using the arc command
                if i <= 1 {
                    // first command start point not yet defined
                    x0 = x1
                    y0 = y1
                }
                // zr scales to emulate an ellipse; scale x accordingly
                let _x = (x - cx) * ry / rx + cx
                d = projectPointToArc(
                    cx, cy, ry, theta, theta + dTheta, anticlockwise,
                    _x, y, &tmpPt
                )
                xi = cos(theta + dTheta) * rx + cx
                yi = sin(theta + dTheta) * ry + cy
            case CMD.R:
                x0 = data[i]; xi = x0; i += 1
                y0 = data[i]; yi = y0; i += 1
                let width = data[i]; i += 1
                let height = data[i]; i += 1
                d = projectPointToRect(x0, y0, width, height, x, y, &tmpPt)
            case CMD.Z:
                d = projectPointToLine(xi, yi, x0, y0, x, y, &tmpPt, true)
                xi = x0
                yi = y0
            default:
                break
            }

            if d < minDist {
                minDist = d
                out.set(tmpPt[0], tmpPt[1])
            }
        }

        return minDist
    }

    /// upstream: export function updateLabelLinePoints(target: Element, labelLineModel: Model<LabelLineOption>)
    /// Calculate a proper guide line based on the label position and graphic element definition.
    public static func updateLabelLinePoints(_ target: Element?, _ labelLineModel: Model) {
        guard let target = target else {
            return
        }

        let labelLine = target.getTextGuideLine()
        let label = target.getTextContent()
        // Needs to create text guide in each charts.
        guard let labelLine = labelLine, let label = label else {
            return
        }

        let labelGuideConfig = target.textGuideLineConfig ?? ElementTextGuideLineConfig()

        var points: [[Double]] = [[0, 0], [0, 0], [0, 0]]

        let searchSpace = labelGuideConfig.candidates ?? DEFAULT_SEARCH_SPACE
        guard let labelRect = label.getBoundingRect()?.clone() else {
            return
        }
        labelRect.applyTransform(label.getComputedTransform())

        var minDist = Double.infinity
        let anchorPoint = labelGuideConfig.anchor
        let targetTransform = target.getComputedTransform()
        let targetInversedTransform = targetTransform.flatMap { matrix.invert($0) }
        let len = asDouble(labelLineModel.get("length2")) ?? 0

        let pt0 = Point()
        let pt1 = Point()
        let pt2 = Point()
        let dir = Point()

        if let anchorPoint = anchorPoint {
            pt2.copy(anchorPoint)
        }
        for candidate in searchSpace {
            getCandidateAnchor(candidate, 0, labelRect, pt0, dir)
            Point.scaleAndAdd(pt1, pt0, dir, len)

            // Transform to target coord space.
            pt1.transform(targetInversedTransform)

            // Note: getBoundingRect will ensure the `path` being created.
            let boundingRect = target.getBoundingRect()
            let dist: Double
            if let anchorPoint = anchorPoint {
                dist = anchorPoint.distance(pt1)
            }
            else if let path = target as? Path {
                dist = nearestPointOnPath(pt1, path.path, pt2)
            }
            else if let boundingRect = boundingRect {
                dist = nearestPointOnRect(pt1, boundingRect, pt2)
            }
            else {
                dist = Double.infinity
            }

            // TODO pt2 is in the path
            if dist < minDist {
                minDist = dist
                // Transform back to global space.
                pt1.transform(targetTransform)
                pt2.transform(targetTransform)

                points[0] = pt2.toArray(points[0])
                points[1] = pt1.toArray(points[1])
                points[2] = pt0.toArray(points[2])
            }
        }

        limitTurnAngle(&points, asDouble(labelLineModel.get("minTurnAngle")) ?? 0)

        labelLine.setShape("points", points)
    }

    /// upstream: export function limitTurnAngle(linePoints: number[][], minTurnAngle: number)
    /// Reduce the line segment attached to the label to limit the turn angle between two segments.
    /// `minTurnAngle` is in degrees (0…180). Mutates `linePoints[1]` in place.
    public static func limitTurnAngle(_ linePoints: inout [[Double]], _ minTurnAngle: Double) {
        var minTurnAngle = minTurnAngle
        if !(minTurnAngle <= 180 && minTurnAngle > 0) {
            return
        }
        minTurnAngle = minTurnAngle / 180 * Double.pi
        // The line points can be
        //      /pt1----pt2 (label)
        //     /
        // pt0/
        let pt0 = Point(); pt0.fromArray(linePoints[0])
        let pt1 = Point(); pt1.fromArray(linePoints[1])
        let pt2 = Point(); pt2.fromArray(linePoints[2])

        let dir = Point()
        let dir2 = Point()
        Point.sub(dir, pt0, pt1)
        Point.sub(dir2, pt2, pt1)

        let len1 = dir.len()
        let len2 = dir2.len()
        if len1 < 1e-3 || len2 < 1e-3 {
            return
        }

        dir.scale(1 / len1)
        dir2.scale(1 / len2)

        let angleCos = dir.dot(dir2)
        let minTurnAngleCos = cos(minTurnAngle)
        if minTurnAngleCos < angleCos {    // Smaller than minTurnAngle
            // Calculate project point of pt0 on pt1-pt2
            var tmpArr: [Double] = [0, 0]
            let d = projectPointToLine(pt1.x, pt1.y, pt2.x, pt2.y, pt0.x, pt0.y, &tmpArr, false)
            let tmpProjPoint = Point(); tmpProjPoint.fromArray(tmpArr)
            // Calculate new projected length with limited minTurnAngle and get the new connect point
            tmpProjPoint.scaleAndAdd(dir2, d / tan(Double.pi - minTurnAngle))
            // Limit the new calculated connect point between pt1 and pt2.
            let t = pt2.x != pt1.x
                ? (tmpProjPoint.x - pt1.x) / (pt2.x - pt1.x)
                : (tmpProjPoint.y - pt1.y) / (pt2.y - pt1.y)
            if t.isNaN {
                return
            }

            if t < 0 {
                Point.copy(tmpProjPoint, pt1)
            }
            else if t > 1 {
                Point.copy(tmpProjPoint, pt2)
            }

            linePoints[1] = tmpProjPoint.toArray(linePoints[1])
        }
    }

    /// upstream: export function limitSurfaceAngle(linePoints, surfaceNormal: Point, maxSurfaceAngle)
    /// Limit the angle between the leader line and the surface normal. `maxSurfaceAngle` in degrees.
    /// Mutates `linePoints[1]` in place.
    public static func limitSurfaceAngle(
        _ linePoints: inout [[Double]], _ surfaceNormal: Point, _ maxSurfaceAngle: Double
    ) {
        var maxSurfaceAngle = maxSurfaceAngle
        if !(maxSurfaceAngle <= 180 && maxSurfaceAngle > 0) {
            return
        }
        maxSurfaceAngle = maxSurfaceAngle / 180 * Double.pi

        let pt0 = Point(); pt0.fromArray(linePoints[0])
        let pt1 = Point(); pt1.fromArray(linePoints[1])
        let pt2 = Point(); pt2.fromArray(linePoints[2])

        let dir = Point()
        let dir2 = Point()
        Point.sub(dir, pt1, pt0)
        Point.sub(dir2, pt2, pt1)

        let len1 = dir.len()
        let len2 = dir2.len()

        if len1 < 1e-3 || len2 < 1e-3 {
            return
        }

        dir.scale(1 / len1)
        dir2.scale(1 / len2)

        let angleCos = dir.dot(surfaceNormal)
        let maxSurfaceAngleCos = cos(maxSurfaceAngle)

        if angleCos < maxSurfaceAngleCos {
            // Calculate project point of pt0 on pt1-pt2
            var tmpArr: [Double] = [0, 0]
            let d = projectPointToLine(pt1.x, pt1.y, pt2.x, pt2.y, pt0.x, pt0.y, &tmpArr, false)
            let tmpProjPoint = Point(); tmpProjPoint.fromArray(tmpArr)

            let HALF_PI = Double.pi / 2
            let angle2 = acos(dir2.dot(surfaceNormal))
            let newAngle = HALF_PI + angle2 - maxSurfaceAngle
            if newAngle >= HALF_PI {
                // parallel
                Point.copy(tmpProjPoint, pt2)
            }
            else {
                // Calculate new projected length with limited minTurnAngle and get the new connect point
                tmpProjPoint.scaleAndAdd(dir2, d / tan(Double.pi / 2 - newAngle))
                // Limit the new calculated connect point between pt1 and pt2.
                let t = pt2.x != pt1.x
                    ? (tmpProjPoint.x - pt1.x) / (pt2.x - pt1.x)
                    : (tmpProjPoint.y - pt1.y) / (pt2.y - pt1.y)
                if t.isNaN {
                    return
                }

                if t < 0 {
                    Point.copy(tmpProjPoint, pt1)
                }
                else if t > 1 {
                    Point.copy(tmpProjPoint, pt2)
                }
            }

            linePoints[1] = tmpProjPoint.toArray(linePoints[1])
        }
    }

    /// upstream: export function getLabelLineStatesModels(itemModel, labelLineName?)
    /// Resolve the per-state (normal/emphasis/blur/select) labelLine models from an item model.
    /// upstream returns `Record<DisplayState, Model<LabelLineOption>>`; the non-generic Swift
    /// `Model` maps that to `[String: Model]`.
    public static func getLabelLineStatesModels(
        _ itemModel: Model, _ labelLineNameIn: String? = nil
    ) -> [String: Model] {
        let labelLineName = labelLineNameIn ?? "labelLine"
        var statesModels: [String: Model] = [
            "normal": itemModel.getModel(labelLineName)
        ]
        for stateName in states.SPECIAL_STATES {
            statesModels[stateName] = itemModel.getModel([stateName, labelLineName])
        }
        return statesModels
    }

    // upstream: type LabelLineModel = Model<LabelLineOption>; -> the non-generic Swift `Model`.

    /// upstream module-local:
    ///   function setLabelLineState(labelLine: Polyline, ignore, stateName, stateModel: Model)
    /// Apply the per-state (`normal`/`emphasis`/`blur`/`select`) ignore/smooth/lineStyle onto the
    /// leader-line Polyline. For `normal` the values land on the element itself; otherwise they land
    /// on the element's `ensureState(stateName)` state object.
    private static func setLabelLineState(
        _ labelLine: Polyline, _ ignore: Bool, _ stateName: String, _ stateModel: Model
    ) {
        let isNormal = stateName == "normal"

        // upstream: let smooth = stateModel.get('smooth');
        //           smooth = smooth === true ? 0.3 : Math.max(+smooth, 0) || 0;
        //   (Int-vs-Double trap: `smooth` may be boxed as Int or Double; Bool-`true` → 0.3.)
        let smoothRaw = stateModel.get("smooth")
        var smooth: Double = 0
        if let b = smoothRaw as? Bool {
            // `true` → 0.3; `false` → `+false` = 0.
            smooth = b ? 0.3 : 0
        }
        else if let n = asDouble(smoothRaw) {
            // Math.max(+smooth, 0) || 0 : NaN (`|| 0`) → 0, negatives clamped to 0.
            smooth = n.isNaN ? 0 : Swift.max(n, 0)
        }

        // upstream: const styleObj = stateModel.getModel('lineStyle').getLineStyle();
        //   getLineStyle() returns the dynamic `LineStyleProps` ([String: Any]) bag.
        let styleObj = stateModel.getModel("lineStyle").getLineStyle()

        if isNormal {
            // upstream: const stateObj = labelLine; stateObj.ignore = ignore;
            labelLine.ignore = ignore
            // upstream: (stateObj.shape as Polyline['shape']).smooth = smooth;  (always set)
            labelLine.setShape("smooth", smooth)
            // upstream: labelLine.useStyle(styleObj) — bridge the [String: Any] to PathStyleProps.
            labelLine.useStyle(barStyleFromDict(styleObj))
        }
        else {
            // upstream: const stateObj = labelLine.ensureState(stateName);
            let stateObj = labelLine.ensureState(stateName)
            stateObj.ignore = ignore
            // upstream: stateObj.shape = stateObj.shape || {}; (stateObj.shape).smooth = smooth;
            var shapeBag = stateObj.shape ?? [:]
            shapeBag["smooth"] = smooth
            stateObj.shape = shapeBag
            // upstream: stateObj.style = styleObj; — the untyped per-state style bag ([String: Any]),
            //   stored RAW exactly as upstream does (upstream has no bridge to do).
            // its consumer is `PathStyleProps.animationSet` (via useState → _transitionState
            //   → animateToShallow → animObjSet), which used to read `value as? Double` / `as? [Double]`
            //   and so silently DROPPED an Int-boxed `lineStyle.width: 2` (→ "lineWidth") and the String
            //   presets of `lineStyle.type` (→ "lineDash": "dashed"/"dotted"/"solid") on
            //   emphasis/blur/select. Fixed at that seam (Int/NSNumber → Double + LineDash coercion in
            //   `PathStyleProps.animationSet`, Path.swift) rather than normalized here, so every state
            //   bag benefits — including the identical ECLine.swift gap — and the bag keeps the untyped
            //   shape upstream expects.
            stateObj.style = styleObj
        }
    }

    /// upstream module-local:
    ///   function buildLabelLinePath(path: CanvasRenderingContext2D, shape: Polyline['shape'])
    /// The custom `buildPath` installed on the leader line: a straight 2-segment polyline, or — when
    /// `smooth > 0` and there are ≥ 3 points — a rounded corner built from two bezier curves.
    private static func buildLabelLinePath(_ path: PathProxy, _ shape: PolylineShape) {
        let smooth = shape.smooth ?? 0
        guard let points = shape.points, !points.isEmpty else {
            return
        }
        _ = path.moveTo(points[0].x, points[0].y)
        if smooth > 0 && points.count >= 3 {
            let len1 = vector.dist(points[0], points[1])
            let len2 = vector.dist(points[1], points[2])
            // upstream: if (!len1 || !len2)
            //   JS falsiness catches NaN as well as 0 (PORTING.md §11), and a NaN datum does reach
            //   leader lines — without the isNaN legs the bezier branch would emit NaN controls.
            if len1 == 0 || len2 == 0 || len1.isNaN || len2.isNaN {
                _ = path.lineTo(points[1].x, points[1].y)
                _ = path.lineTo(points[2].x, points[2].y)
                return
            }

            let moveLen = Swift.min(len1, len2) * smooth

            let midPoint0 = vector.lerp(points[1], points[0], moveLen / len1)
            let midPoint2 = vector.lerp(points[1], points[2], moveLen / len2)

            let midPoint1 = vector.lerp(midPoint0, midPoint2, 0.5)
            _ = path.bezierCurveTo(
                midPoint0.x, midPoint0.y, midPoint0.x, midPoint0.y, midPoint1.x, midPoint1.y
            )
            _ = path.bezierCurveTo(
                midPoint2.x, midPoint2.y, midPoint2.x, midPoint2.y, points[2].x, points[2].y
            )
        }
        else {
            for i in 1..<points.count {
                _ = path.lineTo(points[i].x, points[i].y)
            }
        }
    }

    /// upstream: local `defaults(labelLine.style, defaultStyle)` — fills each style field left
    /// undefined on `style` from `defaultStyle` (target-set values win). Local reimplementation
    /// because ZRenderKit's `extendPathStyle` is module-internal.
    private static func applyStyleDefaults(_ style: inout PathStyleProps, _ defaultStyle: PathStyleProps) {
        if style.shadowBlur == nil { style.shadowBlur = defaultStyle.shadowBlur }
        if style.shadowOffsetX == nil { style.shadowOffsetX = defaultStyle.shadowOffsetX }
        if style.shadowOffsetY == nil { style.shadowOffsetY = defaultStyle.shadowOffsetY }
        if style.shadowColor == nil { style.shadowColor = defaultStyle.shadowColor }
        if style.opacity == nil { style.opacity = defaultStyle.opacity }
        if style.blend == nil { style.blend = defaultStyle.blend }
        if style.fill == nil { style.fill = defaultStyle.fill }
        if style.stroke == nil { style.stroke = defaultStyle.stroke }
        if style.decal == nil { style.decal = defaultStyle.decal }
        if style.strokePercent == nil { style.strokePercent = defaultStyle.strokePercent }
        if style.strokeNoScale == nil { style.strokeNoScale = defaultStyle.strokeNoScale }
        if style.fillOpacity == nil { style.fillOpacity = defaultStyle.fillOpacity }
        if style.strokeOpacity == nil { style.strokeOpacity = defaultStyle.strokeOpacity }
        if style.lineDash == nil { style.lineDash = defaultStyle.lineDash }
        if style.lineDashOffset == nil { style.lineDashOffset = defaultStyle.lineDashOffset }
        if style.lineWidth == nil { style.lineWidth = defaultStyle.lineWidth }
        if style.lineCap == nil { style.lineCap = defaultStyle.lineCap }
        if style.lineJoin == nil { style.lineJoin = defaultStyle.lineJoin }
        if style.miterLimit == nil { style.miterLimit = defaultStyle.miterLimit }
        if style.strokeFirst == nil { style.strokeFirst = defaultStyle.strokeFirst }
    }

    /// upstream: export function setLabelLineStyle(targetEl, statesModels, defaultStyle?)
    /// Create a label line if necessary and set its style.
    public static func setLabelLineStyle(
        _ targetEl: Element,
        _ statesModels: [String: Model],
        _ defaultStyle: PathStyleProps? = nil
    ) {
        var labelLine = targetEl.getTextGuideLine()
        let label = targetEl.getTextContent()
        guard let label = label else {
            // Not show label line if there is no label.
            if labelLine != nil {
                targetEl.removeTextGuideLine()
            }
            return
        }

        // upstream reads `statesModels.normal` unguarded and runs the DISPLAY_STATES loop
        //   regardless — `getLabelLineStatesModels` always populates "normal", so this early return is
        //   the Swift-side Optional safety net, NOT an upstream branch.
        guard let normalModel = statesModels["normal"] else {
            return
        }
        let showNormal = asBool(normalModel.get("show"))
        let labelIgnoreNormal = label.ignore

        for stateName in states.DISPLAY_STATES {
            guard let stateModel = statesModels[stateName] else {
                continue
            }
            let isNormal = stateName == "normal"
            let stateShow = asBool(stateModel.get("show"))
            // upstream: isNormal ? labelIgnoreNormal
            //   : retrieve2(label.states[stateName] && label.states[stateName].ignore, labelIgnoreNormal)
            let isLabelIgnored: Bool = isNormal
                ? labelIgnoreNormal
                : (util.retrieve2(label.states[stateName]?.ignore, labelIgnoreNormal) ?? false)
            if isLabelIgnored  // Not show when label is not shown in this state.
                || !(util.retrieve2(stateShow, showNormal) ?? false) // Use normal state by default if not set.
            {
                // upstream: const stateObj = isNormal ? labelLine : (labelLine && labelLine.states[stateName]);
                if isNormal {
                    labelLine?.ignore = true
                }
                else if let stateObj = labelLine?.states[stateName] {
                    stateObj.ignore = true
                }
                if let labelLine = labelLine {
                    setLabelLineState(labelLine, true, stateName, stateModel)
                }
                continue
            }
            // Create labelLine if not exists
            if labelLine == nil {
                let newLine = Polyline()
                targetEl.setTextGuideLine(newLine)
                labelLine = newLine
                // Reset state of normal because it's new created.
                // NOTE: NORMAL should always been the first!
                if !isNormal && (labelIgnoreNormal || !(showNormal ?? false)) {
                    setLabelLineState(newLine, true, "normal", normalModel)
                }

                // Bind the default proxy to the newly-created guide line itself. The host proxy may
                // not have been installed yet at this render phase, so conditionally copying it (as
                // the dynamic JavaScript implementation does) can leave the guide without any proxy.
                // The element-bound proxy supplies the default 0.1 blur opacity and lets non-focused
                // leader lines fade together with their labels.
                states.setDefaultStateProxy(newLine)
            }

            // `labelLine` is non-nil here (either pre-existing or just created above); bind it so the
            // invariant is compiler-enforced rather than resting on loop-order reasoning.
            if let currentLine = labelLine {
                setLabelLineState(currentLine, false, stateName, stateModel)
            }
        }

        if let labelLine = labelLine {
            // LabelManager may pre-create the guide before this helper runs, bypassing the creation
            // branch above. Ensure those guides also receive their own default-state proxy.
            if labelLine.stateProxy == nil {
                states.setDefaultStateProxy(labelLine)
            }
            // upstream: defaults(labelLine.style, defaultStyle);
            // (`pathStyle` is an IUO always populated by `Path.init` via useStyle/createStyle. The `??`
            //  fallback keeps the mandatory `fill = nil` below on the UNCONDITIONAL path — upstream has
            //  no guard here, and silently skipping it would render the leader line as a black-filled
            //  closed shape. `createStyle()` is the right fallback: its result already has
            //  `zrStyleMagic == true`, whereas a bare `PathStyleProps()` would make `useStyle` re-run
            //  `createStyle`, and `extendPathStyle` skips nil sources — resurrecting `fill = '#000'`.)
            var style = labelLine.pathStyle ?? labelLine.createStyle()
            if let defaultStyle = defaultStyle {
                applyStyleDefaults(&style, defaultStyle)
            }
            // Not fill. (upstream: labelLine.style.fill = null — the createStyle/useStyle merge
            //   would otherwise keep the '#000' default.)
            style.fill = nil
            // assign through `useStyle`, NOT `labelLine.pathStyle = style`. A direct store
            //   skips `dirtyStyle()` — required here, since clearing `fill` must invalidate the cached
            //   paint — and bypasses the Swift-only `_syncCommonStyle()` mirror (private, Path.swift)
            //   that copies opacity/shadow*/blend from `pathStyle` into the inherited
            //   `Displayable.style` read by `shouldBePainted`/`getPaintRect`.
            //   Scope of `applyStyleDefaults`: like upstream's `defaults()` — which reads `target[key]`
            //   through the `createObject(DEFAULT_PATH_STYLE, ...)` prototype — it only fills slots that
            //   are nil, and every CommonStyleProps field (opacity / shadowBlur / shadowOffset* /
            //   shadowColor / blend) already has a non-nil DEFAULT_PATH_STYLE value. So `defaultStyle`
            //   can only ever land the keys left nil in DEFAULT_PATH_STYLE (`stroke`, `decal`,
            //   `lineDash`, `lineJoin`), and `_syncCommonStyle()` is provably a no-op at this call
            //   site — it runs for hygiene, not because a live opacity path exists.
            //   `zrStyleMagic` is pinned true so `useStyle` takes the pure assign + sync + dirty path:
            //   were it ever false, `createStyle`/`extendPathStyle` would re-merge DEFAULT_PATH_STYLE
            //   and — skipping the nil source — restore `fill = '#000'`.
            style.zrStyleMagic = true
            labelLine.useStyle(style)

            let showAbove = asBool(normalModel.get("showAbove"))

            // upstream: const labelLineConfig = (targetEl.textGuideLineConfig = targetEl.textGuideLineConfig || {});
            var labelLineConfig = targetEl.textGuideLineConfig ?? ElementTextGuideLineConfig()
            labelLineConfig.showAbove = showAbove ?? false
            targetEl.textGuideLineConfig = labelLineConfig

            // Custom the buildPath. (upstream: labelLine.buildPath = buildLabelLinePath — routed
            //   through the per-instance `setBuildPathOverride` seam on Polyline.)
            labelLine.setBuildPathOverride(buildLabelLinePath)
        }
    }
}
