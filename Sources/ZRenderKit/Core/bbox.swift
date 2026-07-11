// Ported from zrender/src/core/bbox.ts — keep in sync with upstream

/**
 * @author Yi Shen(https://github.com/pissang)
 */

import Foundation

// upstream: import * as vec2 from './vector';
// upstream: import * as curve  from './curve';

// const mathMin = Math.min;  -> NaN-propagating helper below (see PORT_STATUS §3 item 2)
// const mathMax = Math.max;  -> NaN-propagating helper below
// const mathSin = Math.sin;  -> use Foundation sin
// const mathCos = Math.cos;  -> use Foundation cos

// JS `Math.min`/`Math.max` propagate NaN (any NaN operand => NaN); `Swift.min`/`Swift.max`
// do not. These are the bbox accumulators, so a NaN coordinate must taint the box exactly
// as upstream. Faithful NaN-propagating helpers (single layer-wide policy, PORT_STATUS §3
// item 2). 2-arg and 3-arg arities mirror upstream `mathMin(a, b)` / `mathMin(a, b, c)`.
@inline(__always) private func mathMin(_ a: Double, _ b: Double) -> Double {
    return (a.isNaN || b.isNaN) ? Double.nan : Swift.min(a, b)
}
@inline(__always) private func mathMin(_ a: Double, _ b: Double, _ c: Double) -> Double {
    return (a.isNaN || b.isNaN || c.isNaN) ? Double.nan : Swift.min(a, b, c)
}
@inline(__always) private func mathMax(_ a: Double, _ b: Double) -> Double {
    return (a.isNaN || b.isNaN) ? Double.nan : Swift.max(a, b)
}
@inline(__always) private func mathMax(_ a: Double, _ b: Double, _ c: Double) -> Double {
    return (a.isNaN || b.isNaN || c.isNaN) ? Double.nan : Swift.max(a, b, c)
}

public enum bbox {   // upstream is a free-function module (no alias)

    private static let PI2 = Double.pi * 2

    // Module-level scratch vectors (upstream: vec2.create()).
    // Kept as static scratch to mirror upstream structure; reassigned per CONVENTIONS §3.
    private static var start = vector.create()
    private static var end = vector.create()
    private static var extremity = vector.create()

    /**
     * 从顶点数组中计算出最小包围盒，写入`min`和`max`中
     */
    // out-param dropped, value-returning per CONVENTIONS §3.
    // `min`/`max` are passed in so the empty-`points` early-return can leave them unchanged
    // (upstream does not touch them when `points.length === 0`).
    public static func fromPoints(
        _ points: [[Double]], _ min: VectorArray, _ max: VectorArray
    ) -> (min: VectorArray, max: VectorArray) {
        var min = min
        var max = max
        if points.count == 0 {
            return (min, max)
        }
        var p = points[0]
        var left = p[0]
        var right = p[0]
        var top = p[1]
        var bottom = p[1]

        for i in 1..<points.count {
            p = points[i]
            left = mathMin(left, p[0])
            right = mathMax(right, p[0])
            top = mathMin(top, p[1])
            bottom = mathMax(bottom, p[1])
        }

        min[0] = left
        min[1] = top
        max[0] = right
        max[1] = bottom
        return (min, max)
    }

    // out-param dropped, value-returning per CONVENTIONS §3.
    public static func fromLine(
        _ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double
    ) -> (min: VectorArray, max: VectorArray) {
        var min = VectorArray()
        var max = VectorArray()
        min[0] = mathMin(x0, x1)
        min[1] = mathMin(y0, y1)
        max[0] = mathMax(x0, x1)
        max[1] = mathMax(y0, y1)
        return (min, max)
    }

    // const xDim: number[] = [];
    // const yDim: number[] = [];
    // PORT-NOTE: upstream uses module-level scratch buffers xDim/yDim as the out-param of
    // curve.cubicExtrema. Since curve.cubicExtrema is value-returning per CONVENTIONS §3,
    // these buffers are no longer needed; the extrema array is returned directly below.

    /**
     * 从三阶贝塞尔曲线(p0, p1, p2, p3)中计算出最小包围盒，写入`min`和`max`中
     */
    // out-param dropped, value-returning per CONVENTIONS §3.
    public static func fromCubic(
        _ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double,
        _ x2: Double, _ y2: Double, _ x3: Double, _ y3: Double
    ) -> (min: VectorArray, max: VectorArray) {
        var min = VectorArray()
        var max = VectorArray()
        let cubicExtrema = curve.cubicExtrema
        let cubicAt = curve.cubicAt
        // curve.cubicExtrema value-returns (extrema: [Double], n: Double): `extrema` is a
        // fixed length-2 buffer, `n` is the count of valid roots at the front (mirrors upstream
        // out-param + returned count). Iterate only the first `n` entries.
        let xDim = cubicExtrema(x0, x1, x2, x3)
        var n = Int(xDim.n)
        min[0] = Double.infinity
        min[1] = Double.infinity
        max[0] = -Double.infinity
        max[1] = -Double.infinity

        for i in 0..<n {
            let x = cubicAt(x0, x1, x2, x3, xDim.extrema[i])
            min[0] = mathMin(x, min[0])
            max[0] = mathMax(x, max[0])
        }
        let yDim = cubicExtrema(y0, y1, y2, y3)
        n = Int(yDim.n)
        for i in 0..<n {
            let y = cubicAt(y0, y1, y2, y3, yDim.extrema[i])
            min[1] = mathMin(y, min[1])
            max[1] = mathMax(y, max[1])
        }

        min[0] = mathMin(x0, min[0])
        max[0] = mathMax(x0, max[0])
        min[0] = mathMin(x3, min[0])
        max[0] = mathMax(x3, max[0])

        min[1] = mathMin(y0, min[1])
        max[1] = mathMax(y0, max[1])
        min[1] = mathMin(y3, min[1])
        max[1] = mathMax(y3, max[1])
        return (min, max)
    }

    /**
     * 从二阶贝塞尔曲线(p0, p1, p2)中计算出最小包围盒，写入`min`和`max`中
     */
    // out-param dropped, value-returning per CONVENTIONS §3.
    public static func fromQuadratic(
        _ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double
    ) -> (min: VectorArray, max: VectorArray) {
        var min = VectorArray()
        var max = VectorArray()
        let quadraticExtremum = curve.quadraticExtremum
        let quadraticAt = curve.quadraticAt
        // Find extremities, where derivative in x dim or y dim is zero
        let tx =
            mathMax(
                mathMin(quadraticExtremum(x0, x1, x2), 1), 0
            )
        let ty =
            mathMax(
                mathMin(quadraticExtremum(y0, y1, y2), 1), 0
            )

        let x = quadraticAt(x0, x1, x2, tx)
        let y = quadraticAt(y0, y1, y2, ty)

        min[0] = mathMin(x0, x2, x)
        min[1] = mathMin(y0, y2, y)
        max[0] = mathMax(x0, x2, x)
        max[1] = mathMax(y0, y2, y)
        return (min, max)
    }

    /**
     * 从圆弧中计算出最小包围盒，写入`min`和`max`中
     */
    // out-param dropped, value-returning per CONVENTIONS §3.
    public static func fromArc(
        _ x: Double, _ y: Double, _ rx: Double, _ ry: Double,
        _ startAngle: Double, _ endAngle: Double, _ anticlockwise: Bool
    ) -> (min: VectorArray, max: VectorArray) {
        var startAngle = startAngle
        var endAngle = endAngle
        var min = VectorArray()
        var max = VectorArray()
        let vec2Min = vector.min
        let vec2Max = vector.max

        let diff = Swift.abs(startAngle - endAngle)


        if diff.truncatingRemainder(dividingBy: PI2) < 1e-4 && diff > 1e-4 {
            // Is a circle
            min[0] = x - rx
            min[1] = y - ry
            max[0] = x + rx
            max[1] = y + ry
            return (min, max)
        }

        start[0] = cos(startAngle) * rx + x
        start[1] = sin(startAngle) * ry + y

        end[0] = cos(endAngle) * rx + x
        end[1] = sin(endAngle) * ry + y

        min = vec2Min(start, end)
        max = vec2Max(start, end)

        // Thresh to [0, Math.PI * 2]
        startAngle = startAngle.truncatingRemainder(dividingBy: PI2)
        if startAngle < 0 {
            startAngle = startAngle + PI2
        }
        endAngle = endAngle.truncatingRemainder(dividingBy: PI2)
        if endAngle < 0 {
            endAngle = endAngle + PI2
        }

        if startAngle > endAngle && !anticlockwise {
            endAngle += PI2
        }
        else if startAngle < endAngle && anticlockwise {
            startAngle += PI2
        }
        if anticlockwise {
            let tmp = endAngle
            endAngle = startAngle
            startAngle = tmp
        }

        // const number = 0;
        // const step = (anticlockwise ? -Math.PI : Math.PI) / 2;
        var angle = 0.0
        while angle < endAngle {
            if angle > startAngle {
                extremity[0] = cos(angle) * rx + x
                extremity[1] = sin(angle) * ry + y

                min = vec2Min(extremity, min)
                max = vec2Max(extremity, max)
            }
            angle += Double.pi / 2
        }
        return (min, max)
    }
}
