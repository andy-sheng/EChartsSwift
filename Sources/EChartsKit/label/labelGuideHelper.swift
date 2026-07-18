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
//   DEFERRED (leader-line *style/state* creation): `setLabelLineStyle`, `setLabelLineState`,
//   `buildLabelLinePath`. These require a per-instance `labelLine.buildPath = …` override, which the
//   Swift `Polyline` (method override + value-type shape) does not expose — that is a ZRenderKit
//   cross-file change. Pie/funnel keep drawing their own leader-line style inline for now.

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

        // PORT-NOTE: upstream reuses the *normalized* `x`/`y` (after `x /= d`) here, not the
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
}
