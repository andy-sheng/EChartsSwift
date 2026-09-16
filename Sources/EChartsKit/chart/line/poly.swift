// Ported from echarts/src/chart/line/poly.ts — keep in sync with upstream
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

// Poly path support NaN point

import Foundation
import ZRenderKit

// upstream imports:
// import Path, { PathProps } from 'zrender/src/graphic/Path';       -> ZRenderKit `Path` / `ElementProps`
// import PathProxy from 'zrender/src/core/PathProxy';               -> ZRenderKit `PathProxy`
// import { cubicRootAt, cubicAt } from 'zrender/src/core/curve';    -> `curve.cubicRootAt` / `curve.cubicAt`
// import tokens from '../../visual/tokens';                         -> `tokens` (visual/tokens.swift)
// import { isPointIllegal } from './helper';                        -> `isPointIllegal` (chart/line/helper.swift)

// const mathMin = Math.min;  /  const mathMax = Math.max;
//   -> `Swift.min` / `Swift.max` (CONVENTIONS §5).

// ---------------------------------------------------------------------------
// PORT-LOCAL: upstream reads `points[i]` on a `Float32Array`, where an out-of-range index yields
// `undefined` — which then flows into `isPointIllegal` / arithmetic as NaN. Swift TRAPS on an
// out-of-range subscript, and `drawSegment` deliberately reads out of range (`idx` may reach
// `-1`/`len` before the bounds check, and the smooth branch peeks at `nextIdx`). This accessor
// reproduces the JS semantics (out-of-range → NaN), keeping the function bodies line-for-line
// faithful.
// ---------------------------------------------------------------------------
@inline(__always)
private func polyAt(_ points: [Double], _ i: Int) -> Double {
    return (i >= 0 && i < points.count) ? points[i] : Double.nan
}

/**
 * Draw smoothed line in non-monotone, in may cause undesired curve in extreme
 * situations. This should be used when points are non-monotone neither in x or
 * y dimension.
 */
private func drawSegment(
    _ ctx: PathProxy,
    _ points: [Double],
    _ start: Int,
    _ segLen: Int,
    _ allLen: Int,
    _ dir: Int,
    _ smooth: Double,
    _ smoothMonotone: String?,
    _ connectNulls: Bool
) -> Int {
    var prevX: Double = Double.nan
    var prevY: Double = Double.nan
    var cpx0: Double = Double.nan
    var cpy0: Double = Double.nan
    var cpx1: Double = Double.nan
    var cpy1: Double = Double.nan
    var idx = start
    var k = 0
    // upstream: `for (; k < segLen; k++) { ... }` — the body `continue`s (which runs `k++`) and
    //   `break`s (which does not), and the smooth branch mutates BOTH `k` and `idx`, so the C-style
    //   loop is kept verbatim (CONVENTIONS §7).
    while k < segLen {

        var x = polyAt(points, idx * 2)
        var y = polyAt(points, idx * 2 + 1)

        if idx >= allLen || idx < 0 {
            break
        }
        if isPointIllegal(x, y) {
            if connectNulls {
                idx += dir
                k += 1
                continue
            }
            break
        }

        if idx == start {
            // ctx[dir > 0 ? 'moveTo' : 'lineTo'](x, y);
            if dir > 0 {
                _ = ctx.moveTo(x, y)
            }
            else {
                _ = ctx.lineTo(x, y)
            }
            cpx0 = x
            cpy0 = y
        }
        else {
            var dx = x - prevX
            var dy = y - prevY

            // Ignore tiny segment.
            if (dx * dx + dy * dy) < 0.5 {
                idx += dir
                k += 1
                continue
            }

            if smooth > 0 {
                var nextIdx = idx + dir
                var nextX = polyAt(points, nextIdx * 2)
                var nextY = polyAt(points, nextIdx * 2 + 1)
                // Ignore duplicate point
                while nextX == x && nextY == y && k < segLen {
                    k += 1
                    nextIdx += dir
                    idx += dir
                    nextX = polyAt(points, nextIdx * 2)
                    nextY = polyAt(points, nextIdx * 2 + 1)
                    x = polyAt(points, idx * 2)
                    y = polyAt(points, idx * 2 + 1)
                    dx = x - prevX
                    dy = y - prevY
                }

                var tmpK = k + 1
                if connectNulls {
                    // Find next point not null
                    while isPointIllegal(nextX, nextY) && tmpK < segLen {
                        tmpK += 1
                        nextIdx += dir
                        nextX = polyAt(points, nextIdx * 2)
                        nextY = polyAt(points, nextIdx * 2 + 1)
                    }
                }

                var ratioNextSeg = 0.5
                var vx: Double = 0
                var vy: Double = 0
                var nextCpx0: Double = Double.nan
                var nextCpy0: Double = Double.nan
                // Is last point
                if tmpK >= segLen || isPointIllegal(nextX, nextY) {
                    cpx1 = x
                    cpy1 = y
                }
                else {
                    vx = nextX - prevX
                    vy = nextY - prevY

                    let dx0 = x - prevX
                    let dx1 = nextX - x
                    let dy0 = y - prevY
                    let dy1 = nextY - y
                    var lenPrevSeg: Double
                    var lenNextSeg: Double
                    if smoothMonotone == "x" {
                        lenPrevSeg = Swift.abs(dx0)
                        lenNextSeg = Swift.abs(dx1)
                        let dir = vx > 0 ? 1.0 : -1.0
                        cpx1 = x - dir * lenPrevSeg * smooth
                        cpy1 = y
                        nextCpx0 = x + dir * lenNextSeg * smooth
                        nextCpy0 = y
                    }
                    else if smoothMonotone == "y" {
                        lenPrevSeg = Swift.abs(dy0)
                        lenNextSeg = Swift.abs(dy1)
                        let dir = vy > 0 ? 1.0 : -1.0
                        cpx1 = x
                        cpy1 = y - dir * lenPrevSeg * smooth
                        nextCpx0 = x
                        nextCpy0 = y + dir * lenNextSeg * smooth
                    }
                    else {
                        lenPrevSeg = sqrt(dx0 * dx0 + dy0 * dy0)
                        lenNextSeg = sqrt(dx1 * dx1 + dy1 * dy1)

                        // Use ratio of seg length
                        ratioNextSeg = lenNextSeg / (lenNextSeg + lenPrevSeg)

                        cpx1 = x - vx * smooth * (1 - ratioNextSeg)
                        cpy1 = y - vy * smooth * (1 - ratioNextSeg)

                        // cp0 of next segment
                        nextCpx0 = x + vx * smooth * ratioNextSeg
                        nextCpy0 = y + vy * smooth * ratioNextSeg

                        // Smooth constraint between point and next point.
                        // Avoid exceeding extreme after smoothing.
                        nextCpx0 = Swift.min(nextCpx0, Swift.max(nextX, x))
                        nextCpy0 = Swift.min(nextCpy0, Swift.max(nextY, y))
                        nextCpx0 = Swift.max(nextCpx0, Swift.min(nextX, x))
                        nextCpy0 = Swift.max(nextCpy0, Swift.min(nextY, y))
                        // Reclaculate cp1 based on the adjusted cp0 of next seg.
                        vx = nextCpx0 - x
                        vy = nextCpy0 - y

                        cpx1 = x - vx * lenPrevSeg / lenNextSeg
                        cpy1 = y - vy * lenPrevSeg / lenNextSeg

                        // Smooth constraint between point and prev point.
                        // Avoid exceeding extreme after smoothing.
                        cpx1 = Swift.min(cpx1, Swift.max(prevX, x))
                        cpy1 = Swift.min(cpy1, Swift.max(prevY, y))
                        cpx1 = Swift.max(cpx1, Swift.min(prevX, x))
                        cpy1 = Swift.max(cpy1, Swift.min(prevY, y))

                        // Adjust next cp0 again.
                        vx = x - cpx1
                        vy = y - cpy1
                        nextCpx0 = x + vx * lenNextSeg / lenPrevSeg
                        nextCpy0 = y + vy * lenNextSeg / lenPrevSeg
                    }
                }

                _ = ctx.bezierCurveTo(cpx0, cpy0, cpx1, cpy1, x, y)

                cpx0 = nextCpx0
                cpy0 = nextCpy0
            }
            else {
                _ = ctx.lineTo(x, y)
            }
        }

        prevX = x
        prevY = y
        idx += dir
        k += 1
    }

    return k
}

// upstream: class ECPolylineShape { points; smooth = 0; smoothConstraint = true; smoothMonotone; connectNulls; }
//   PathShape is a value-type protocol in this port (CONVENTIONS §4), so this is a `struct`.
public struct ECPolylineShape: PathShape {
    // upstream: `points: ArrayLike<number>` — the FLAT [x0, y0, x1, y1, …] buffer (Float32Array).
    public var points: [Double] = []
    public var smooth: Double = 0
    public var smoothConstraint: Bool = true
    public var smoothMonotone: String?      // upstream: 'x' | 'y' | 'none'
    public var connectNulls: Bool = false

    // upstream (LineView._doUpdateAnimation): `(polyline.shape as any).__points = diff.current;` — the
    //   UN-stepped point buffer, animated alongside `points` so the symbol `during` callback can read
    //   the interpolated per-datum positions. Declared here (rather than dynamically attached) because
    //   Swift structs have no dynamic properties; it MUST be exposed through animationGet/animationSet
    //   or the animator's track for it would be silently inert.
    public var __points: [Double]?

    public init() {}

    public func animationGet(_ key: String) -> Any? {
        switch key {
        case "points": return points
        case "__points": return __points
        case "smooth": return smooth
        case "smoothConstraint": return smoothConstraint
        case "connectNulls": return connectNulls
        default: return nil
        }
    }

    public mutating func animationSet(_ key: String, _ value: Any?) {
        switch key {
        case "points": if let v = polyPointsFromAny(value) { points = v }
        case "__points": if let v = polyPointsFromAny(value) { __points = v }
        case "smooth": if let v = lineHelperToNumberOpt(value) { smooth = v }
        case "smoothConstraint": if let v = value as? Bool { smoothConstraint = v }
        case "smoothMonotone": smoothMonotone = value as? String
        case "connectNulls": if let v = value as? Bool { connectNulls = v }
        default: break
        }
    }
}

// upstream: export class ECPolyline extends Path<ECPolylineProps>
public final class ECPolyline: Path {

    // readonly type = 'ec-polyline';
    public override init(_ opts: ElementProps? = nil) {
        super.init(opts)
        self.type = "ec-polyline"
    }

    public override func getDefaultStyle() -> PathStyleProps? {
        var style = PathStyleProps()
        style.stroke = .string(tokens.color.neutral99)
        style.fill = nil
        return style
    }

    public override func getDefaultShape() -> PathShape {
        return ECPolylineShape()
    }

    public override func buildPath(_ ctx: PathProxy, _ shape: PathShape, _ inBatch: Bool) {
        guard let shape = shape as? ECPolylineShape else { return }
        let points = shape.points

        var i = 0
        var len = points.count / 2

        // const result = getBoundingBox(points, shape.smoothConstraint);

        if shape.connectNulls {
            // Must remove first and last null values avoid draw error in polygon
            while len > 0 {
                if !isPointIllegal(polyAt(points, len * 2 - 2), polyAt(points, len * 2 - 1)) {
                    break
                }
                len -= 1
            }
            while i < len {
                if !isPointIllegal(polyAt(points, i * 2), polyAt(points, i * 2 + 1)) {
                    break
                }
                i += 1
            }
        }
        while i < len {
            i += drawSegment(
                ctx, points, i, len, len,
                1,
                shape.smooth,
                shape.smoothMonotone, shape.connectNulls
            ) + 1
        }
    }

    // upstream: getPointOn(xOrY: number, dim: 'x' | 'y'): number[]
    //   Returns `undefined` implicitly when nothing is found -> `[Double]?`.
    public func getPointOn(_ xOrY: Double, _ dim: String) -> [Double]? {
        if self.path == nil {
            self.createPathProxy()
            self.buildPath(self.path, self.shape, false)
        }
        let path = self.path!
        let data = path.data
        // const CMD = PathProxy.CMD;

        var x0: Double = Double.nan
        var y0: Double = Double.nan

        let isDimX = dim == "x"

        var i = 0
        while i < data.count {
            let cmd = data[i]; i += 1
            var x: Double
            var y: Double
            var x2: Double
            var y2: Double
            var x3: Double
            var y3: Double
            var t: Double
            switch cmd {
            case PathProxy.CMD.M:
                x0 = data[i]; i += 1
                y0 = data[i]; i += 1
            case PathProxy.CMD.L:
                x = data[i]; i += 1
                y = data[i]; i += 1
                t = isDimX ? (xOrY - x0) / (x - x0)
                    : (xOrY - y0) / (y - y0)
                if t <= 1 && t >= 0 {
                    let val = isDimX ? (y - y0) * t + y0
                        : (x - x0) * t + x0
                    return isDimX ? [xOrY, val] : [val, xOrY]
                }
                x0 = x
                y0 = y
            case PathProxy.CMD.C:
                x = data[i]; i += 1
                y = data[i]; i += 1
                x2 = data[i]; i += 1
                y2 = data[i]; i += 1
                x3 = data[i]; i += 1
                y3 = data[i]; i += 1

                // upstream fills the shared `roots` buffer and returns the count; ours value-returns
                //   the tuple (CONVENTIONS §3).
                let rootsResult = isDimX ? curve.cubicRootAt(x0, x, x2, x3, xOrY)
                    : curve.cubicRootAt(y0, y, y2, y3, xOrY)
                let nRoot = Int(rootsResult.n)
                let roots = rootsResult.roots
                if nRoot > 0 {
                    for i in 0..<nRoot {
                        let t = roots[i]
                        if t <= 1 && t >= 0 {
                            let val = isDimX ? curve.cubicAt(y0, y, y2, y3, t)
                                : curve.cubicAt(x0, x, x2, x3, t)
                            return isDimX ? [xOrY, val] : [val, xOrY]
                        }
                    }
                }

                x0 = x3
                y0 = y3
            default:
                // upstream's `switch` has no default — the other commands (Q/A/Z/R) are never emitted
                //   by `buildPath` above, so nothing consumes their args. Reaching here would desync
                //   the cursor, so bail out (upstream would loop forever / read garbage).
                return nil
            }
        }
        return nil
    }
}

// upstream: class ECPolygonShape extends ECPolylineShape { stackedOnPoints; stackedOnSmooth; }
//   Swift structs cannot inherit, so the ECPolylineShape fields are DUPLICATED here (the
//   `PathShape` value-type model, CONVENTIONS §4). Keep the two in sync.
public struct ECPolygonShape: PathShape {
    public var points: [Double] = []
    public var smooth: Double = 0
    public var smoothConstraint: Bool = true
    public var smoothMonotone: String?
    public var connectNulls: Bool = false

    // Offset between stacked base points and points
    public var stackedOnPoints: [Double] = []
    public var stackedOnSmooth: Double = 0

    public init() {}

    public func animationGet(_ key: String) -> Any? {
        switch key {
        case "points": return points
        case "smooth": return smooth
        case "smoothConstraint": return smoothConstraint
        case "connectNulls": return connectNulls
        case "stackedOnPoints": return stackedOnPoints
        case "stackedOnSmooth": return stackedOnSmooth
        default: return nil
        }
    }

    public mutating func animationSet(_ key: String, _ value: Any?) {
        switch key {
        case "points": if let v = polyPointsFromAny(value) { points = v }
        case "smooth": if let v = lineHelperToNumberOpt(value) { smooth = v }
        case "smoothConstraint": if let v = value as? Bool { smoothConstraint = v }
        case "smoothMonotone": smoothMonotone = value as? String
        case "connectNulls": if let v = value as? Bool { connectNulls = v }
        case "stackedOnPoints": if let v = polyPointsFromAny(value) { stackedOnPoints = v }
        case "stackedOnSmooth": if let v = lineHelperToNumberOpt(value) { stackedOnSmooth = v }
        default: break
        }
    }
}

// upstream: export class ECPolygon extends Path
public final class ECPolygon: Path {

    // readonly type = 'ec-polygon';
    public override init(_ opts: ElementProps? = nil) {
        super.init(opts)
        self.type = "ec-polygon"
    }

    public override func getDefaultShape() -> PathShape {
        return ECPolygonShape()
    }

    public override func buildPath(_ ctx: PathProxy, _ shape: PathShape, _ inBatch: Bool) {
        guard let shape = shape as? ECPolygonShape else { return }
        let points = shape.points
        let stackedOnPoints = shape.stackedOnPoints

        var i = 0
        var len = points.count / 2
        let smoothMonotone = shape.smoothMonotone

        if shape.connectNulls {
            // Must remove first and last null values avoid draw error in polygon
            while len > 0 {
                if !isPointIllegal(polyAt(points, len * 2 - 2), polyAt(points, len * 2 - 1)) {
                    break
                }
                len -= 1
            }
            while i < len {
                if !isPointIllegal(polyAt(points, i * 2), polyAt(points, i * 2 + 1)) {
                    break
                }
                i += 1
            }
        }
        while i < len {
            let k = drawSegment(
                ctx, points, i, len, len,
                1,
                shape.smooth,
                smoothMonotone, shape.connectNulls
            )
            _ = drawSegment(
                ctx, stackedOnPoints, i + k - 1, k, len,
                -1,
                shape.stackedOnSmooth,
                smoothMonotone, shape.connectNulls
            )
            i += k + 1

            _ = ctx.closePath()
        }
    }
}

// PORT-LOCAL: the animator hands back `[Double]` for a 1-D array track, but a caller-supplied prop bag
//   may carry `[Any]` (e.g. from an option dict). Normalise both.
private func polyPointsFromAny(_ value: Any?) -> [Double]? {
    if let v = value as? [Double] { return v }
    if let v = value as? [Any] { return v.map { lineHelperToNumberOpt($0) ?? Double.nan } }
    return nil
}
