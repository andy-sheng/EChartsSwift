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
// PORT SCOPE (L1c): `limitTurnAngle` / `limitSurfaceAngle` (the leader-line angle limiters the pie
//   label layout calls) + the module-local `projectPointToLine`. The remaining exports of
//   labelGuideHelper.ts — `updateLabelLinePoints`, `buildLabelLinePath`, `setLabelLineStyle`,
//   `getLabelLineStatesModels`, `limitSurfaceAngle`'s callers in LabelManager — are still DEFERRED
//   (pie draws its own leader-line style inline, mirroring FunnelView).

/// Namespace for the ported labelGuideHelper functions (caseless enum, mirrors `labelStyle`).
public enum labelGuideHelper {

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
}
