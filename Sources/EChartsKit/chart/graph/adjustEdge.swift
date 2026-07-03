// Ported from echarts/src/chart/graph/adjustEdge.ts — keep in sync with upstream
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

// upstream imports:
//   import * as curveTool from 'zrender/src/core/curve';             -> `curve.*` (ZRenderKit).
//   import * as vec2 from 'zrender/src/core/vector';                 -> `vector.*` (ZRenderKit).
//   import {getSymbolSize} from './graphHelper';                     -> `graphHelper.getSymbolSize` (PORT-TODO: chart/graph/graphHelper.ts not ported yet).
//   import Graph from '../../data/Graph';                            -> Graph (PORT-TODO: data/Graph.ts not ported yet).

// const v1: number[] = []; const v2: number[] = []; const v3: number[] = [];
// (module-level 2-vector scratch buffers; sized to 2 so index writes are valid.)
private var v1: [Double] = [0, 0]
private var v2: [Double] = [0, 0]
private var v3: [Double] = [0, 0]
// const quadraticAt = curveTool.quadraticAt;  -> curve.quadraticAt (call sites keep the name).
// const v2DistSquare = vec2.distSquare;        -> vector.distSquare.
// const mathAbs = Math.abs;                    -> Swift.abs.

private func intersectCurveCircle(
    _ curvePoints: [[Double]],
    _ center: [Double],
    _ radius: Double
) -> Double {
    let p0 = curvePoints[0]
    let p1 = curvePoints[1]
    let p2 = curvePoints[2]

    var d = Double.infinity
    var t: Double = 0
    let radiusSquare = radius * radius
    var interval = 0.1

    var _t = 0.1
    while _t <= 0.9 {
        v1[0] = curve.quadraticAt(p0[0], p1[0], p2[0], _t)
        v1[1] = curve.quadraticAt(p0[1], p1[1], p2[1], _t)
        let diff = Swift.abs(vector.distSquare(toV(v1), toV(center)) - radiusSquare)
        if diff < d {
            d = diff
            t = _t
        }
        _t += 0.1
    }

    // Assume the segment is monotone，Find root through Bisection method
    // At most 32 iteration
    for _ in 0..<32 {
        // let prev = t - interval;
        let next = t + interval
        // v1[0] = quadraticAt(p0[0], p1[0], p2[0], prev);
        // v1[1] = quadraticAt(p0[1], p1[1], p2[1], prev);
        v2[0] = curve.quadraticAt(p0[0], p1[0], p2[0], t)
        v2[1] = curve.quadraticAt(p0[1], p1[1], p2[1], t)
        v3[0] = curve.quadraticAt(p0[0], p1[0], p2[0], next)
        v3[1] = curve.quadraticAt(p0[1], p1[1], p2[1], next)

        let diff = vector.distSquare(toV(v2), toV(center)) - radiusSquare
        if Swift.abs(diff) < 1e-2 {
            break
        }

        // let prevDiff = v2DistSquare(v1, center) - radiusSquare;
        let nextDiff = vector.distSquare(toV(v3), toV(center)) - radiusSquare

        interval /= 2
        if diff < 0 {
            if nextDiff >= 0 {
                t = t + interval
            }
            else {
                t = t - interval
            }
        }
        else {
            if nextDiff >= 0 {
                t = t - interval
            }
            else {
                t = t + interval
            }
        }
    }

    return t
}

// Adjust edge to avoid
// upstream: export default function adjustEdge(graph, scale)
public func adjustEdge(_ graph: Graph, _ scale: Double) {
    var tmp0: [Double] = []
    // const quadraticSubdivide = curveTool.quadraticSubdivide;  -> curve.quadraticSubdivide (value-returning).
    var pts: [[Double]] = [[0, 0], [0, 0], [0, 0]]
    var pts2: [[Double]] = [[0, 0], [0, 0]]
    var v: [Double] = [0, 0]
    var scale = scale
    scale /= 2

    graph.eachEdge { edge, idx in
        // const linePoints = edge.getLayout();
        var linePoints = asPointsLayout(edge.getLayout())
        let fromSymbol = edge.getVisual("fromSymbol") as? String
        let toSymbol = edge.getVisual("toSymbol") as? String

        // PORT-TODO: upstream caches the pristine points on `linePoints.__original` (an attached property
        // on the JS layout array) so repeated calls don't re-shrink. We rebuild the edge layout from
        // scratch each pass (CONVENTIONS §5 static render), so `linePoints` is already pristine here;
        // originalPoints is taken directly from it (equivalent to first-run behavior).
        var originalPoints: [[Double]] = [
            linePoints[0],
            linePoints[1]
        ]
        if linePoints.count > 2 {
            originalPoints.append(linePoints[2])
        }

        // Quadratic curve — if (linePoints[2] != null)
        if linePoints.count > 2 {
            // vec2.copy — value copy of a [Double] point (CONVENTIONS §3/§4).
            pts[0] = originalPoints[0]
            pts[1] = originalPoints[2]
            pts[2] = originalPoints[1]
            if let fromSymbol = fromSymbol, fromSymbol != "none" {
                let symbolSize = graphHelper.getSymbolSize(edge.node1)

                let t = intersectCurveCircle(pts, originalPoints[0], symbolSize * scale)
                // Subdivide and get the second
                tmp0 = curve.quadraticSubdivide(pts[0][0], pts[1][0], pts[2][0], t)
                pts[0][0] = tmp0[3]
                pts[1][0] = tmp0[4]
                tmp0 = curve.quadraticSubdivide(pts[0][1], pts[1][1], pts[2][1], t)
                pts[0][1] = tmp0[3]
                pts[1][1] = tmp0[4]
            }
            if let toSymbol = toSymbol, toSymbol != "none" {
                let symbolSize = graphHelper.getSymbolSize(edge.node2)

                let t = intersectCurveCircle(pts, originalPoints[1], symbolSize * scale)
                // Subdivide and get the first
                tmp0 = curve.quadraticSubdivide(pts[0][0], pts[1][0], pts[2][0], t)
                pts[1][0] = tmp0[1]
                pts[2][0] = tmp0[2]
                tmp0 = curve.quadraticSubdivide(pts[0][1], pts[1][1], pts[2][1], t)
                pts[1][1] = tmp0[1]
                pts[2][1] = tmp0[2]
            }
            // Copy back to layout
            linePoints[0] = pts[0]
            linePoints[1] = pts[2]
            linePoints[2] = pts[1]
        }
        // Line
        else {
            pts2[0] = originalPoints[0]
            pts2[1] = originalPoints[1]

            v = toArr(vector.sub(toV(pts2[1]), toV(pts2[0])))
            v = toArr(vector.normalize(toV(v)))
            if let fromSymbol = fromSymbol, fromSymbol != "none" {

                let symbolSize = graphHelper.getSymbolSize(edge.node1)

                pts2[0] = toArr(vector.scaleAndAdd(toV(pts2[0]), toV(v), symbolSize * scale))
            }
            if let toSymbol = toSymbol, toSymbol != "none" {
                let symbolSize = graphHelper.getSymbolSize(edge.node2)

                pts2[1] = toArr(vector.scaleAndAdd(toV(pts2[1]), toV(v), -symbolSize * scale))
            }
            linePoints[0] = pts2[0]
            linePoints[1] = pts2[1]
        }

        // PORT-TODO: upstream mutates `linePoints` in place (the JS array is the same object stored in
        // the layout); Swift [Double] arrays are value types (CONVENTIONS §3/§4), so we write the
        // adjusted points back to the store here to make the mutation visible.
        _ = idx
        edge.setLayout(linePoints)
    }
}

// MARK: - Port helpers (not upstream symbols)

// Bridge a JS `number[]` 2-vector (<->) to `VectorArray` (SIMD2<Double>) for the vec2 math helpers.
private func toV(_ p: [Double]) -> VectorArray { VectorArray(p[0], p[1]) }
private func toArr(_ v: VectorArray) -> [Double] { [v[0], v[1]] }

private func asPoint(_ p: Any?) -> [Double] {
    if let a = p as? [Double] { return a }
    if let a = p as? [Any] {
        return a.map { (($0 as? Double) ?? Double(($0 as? Int) ?? 0)) }
    }
    return [Double.nan, Double.nan]
}

// The edge layout is a list of `number[]` points ([p1, p2] or [p1, p2, cp1]).
private func asPointsLayout(_ layout: Any?) -> [[Double]] {
    if let a = layout as? [[Double]] { return a }
    if let a = layout as? [Any] { return a.map { asPoint($0) } }
    return []
}
