// Ported from zrender/src/core/curve.ts — keep in sync with upstream
/**
 * 曲线辅助模块
 */

// upstream:
// import {
//     create as v2Create,
//     distSquare as v2DistSquare,
//     VectorArray
// } from './vector';
// (vector.swift exposes `vector.create`, `vector.distSquare`, and `VectorArray = SIMD2<Double>`.)
import Foundation
import simd

public enum curve {   // upstream is a free-function module (no namespace alias)

    // const mathPow = Math.pow;
    private static func mathPow(_ x: Double, _ y: Double) -> Double { pow(x, y) }
    // const mathSqrt = Math.sqrt;
    private static func mathSqrt(_ x: Double) -> Double { sqrt(x) }

    private static let EPSILON = 1e-8
    private static let EPSILON_NUMERIC = 1e-4

    private static let THREE_SQRT = mathSqrt(3)
    private static let ONE_THIRD = 1.0 / 3.0

    // 临时变量
    private static var _v0 = vector.create()
    private static var _v1 = vector.create()
    private static var _v2 = vector.create()

    private static func isAroundZero(_ val: Double) -> Bool {
        return val > -EPSILON && val < EPSILON
    }
    private static func isNotAroundZero(_ val: Double) -> Bool {
        return val > EPSILON || val < -EPSILON
    }

    /**
     * 计算三次贝塞尔值
     */
    public static func cubicAt(_ p0: Double, _ p1: Double, _ p2: Double, _ p3: Double, _ t: Double) -> Double {
        let onet = 1 - t
        return onet * onet * (onet * p0 + 3 * t * p1)
                + t * t * (t * p3 + 3 * onet * p2)
    }

    /**
     * 计算三次贝塞尔导数值
     */
    public static func cubicDerivativeAt(_ p0: Double, _ p1: Double, _ p2: Double, _ p3: Double, _ t: Double) -> Double {
        let onet = 1 - t
        return 3 * (
            ((p1 - p0) * onet + 2 * (p2 - p1) * t) * onet
            + (p3 - p2) * t * t
        )
    }

    /**
     * 计算三次贝塞尔方程根，使用盛金公式
     *
     * (was: cubicRootAt(..., roots): number — fills `roots` and returns count.
     *  Per CONVENTIONS §3 the out buffer is value-returned; this multi-output
     *  function returns a tuple `(roots, n)`.)
     */
    public static func cubicRootAt(_ p0: Double, _ p1: Double, _ p2: Double, _ p3: Double, _ val: Double) -> (roots: [Double], n: Double) {
        var roots = [Double](repeating: 0, count: 3)
        // Evaluate roots of cubic functions
        let a = p3 + 3 * (p1 - p2) - p0
        let b = 3 * (p2 - p1 * 2 + p0)
        let c = 3 * (p1 - p0)
        let d = p0 - val

        let A = b * b - 3 * a * c
        let B = b * c - 9 * a * d
        let C = c * c - 3 * b * d

        var n = 0

        if isAroundZero(A) && isAroundZero(B) {
            if isAroundZero(b) {
                roots[0] = 0
            }
            else {
                let t1 = -c / b  //t1, t2, t3, b is not zero
                if t1 >= 0 && t1 <= 1 {
                    roots[n] = t1; n += 1
                }
            }
        }
        else {
            let disc = B * B - 4 * A * C

            if isAroundZero(disc) {
                let K = B / A
                let t1 = -b / a + K  // t1, a is not zero
                let t2 = -K / 2  // t2, t3
                if t1 >= 0 && t1 <= 1 {
                    roots[n] = t1; n += 1
                }
                if t2 >= 0 && t2 <= 1 {
                    roots[n] = t2; n += 1
                }
            }
            else if disc > 0 {
                let discSqrt = mathSqrt(disc)
                var Y1 = A * b + 1.5 * a * (-B + discSqrt)
                var Y2 = A * b + 1.5 * a * (-B - discSqrt)
                if Y1 < 0 {
                    Y1 = -mathPow(-Y1, ONE_THIRD)
                }
                else {
                    Y1 = mathPow(Y1, ONE_THIRD)
                }
                if Y2 < 0 {
                    Y2 = -mathPow(-Y2, ONE_THIRD)
                }
                else {
                    Y2 = mathPow(Y2, ONE_THIRD)
                }
                let t1 = (-b - (Y1 + Y2)) / (3 * a)
                if t1 >= 0 && t1 <= 1 {
                    roots[n] = t1; n += 1
                }
            }
            else {
                let T = (2 * A * b - 3 * a * B) / (2 * mathSqrt(A * A * A))
                let theta = acos(T) / 3
                let ASqrt = mathSqrt(A)
                let tmp = cos(theta)

                let t1 = (-b - 2 * ASqrt * tmp) / (3 * a)
                let t2 = (-b + ASqrt * (tmp + THREE_SQRT * sin(theta))) / (3 * a)
                let t3 = (-b + ASqrt * (tmp - THREE_SQRT * sin(theta))) / (3 * a)
                if t1 >= 0 && t1 <= 1 {
                    roots[n] = t1; n += 1
                }
                if t2 >= 0 && t2 <= 1 {
                    roots[n] = t2; n += 1
                }
                if t3 >= 0 && t3 <= 1 {
                    roots[n] = t3; n += 1
                }
            }
        }
        return (roots, Double(n))
    }

    /**
     * 计算三次贝塞尔方程极限值的位置
     * @return 有效数目
     *
     * (was: cubicExtrema(..., extrema): number — value-returning tuple per CONVENTIONS §3.)
     */
    public static func cubicExtrema(_ p0: Double, _ p1: Double, _ p2: Double, _ p3: Double) -> (extrema: [Double], n: Double) {
        var extrema = [Double](repeating: 0, count: 2)
        let b = 6 * p2 - 12 * p1 + 6 * p0
        let a = 9 * p1 + 3 * p3 - 3 * p0 - 9 * p2
        let c = 3 * p1 - 3 * p0

        var n = 0
        if isAroundZero(a) {
            if isNotAroundZero(b) {
                let t1 = -c / b
                if t1 >= 0 && t1 <= 1 {
                    extrema[n] = t1; n += 1
                }
            }
        }
        else {
            let disc = b * b - 4 * a * c
            if isAroundZero(disc) {
                extrema[0] = -b / (2 * a)
            }
            else if disc > 0 {
                let discSqrt = mathSqrt(disc)
                let t1 = (-b + discSqrt) / (2 * a)
                let t2 = (-b - discSqrt) / (2 * a)
                if t1 >= 0 && t1 <= 1 {
                    extrema[n] = t1; n += 1
                }
                if t2 >= 0 && t2 <= 1 {
                    extrema[n] = t2; n += 1
                }
            }
        }
        return (extrema, Double(n))
    }

    /**
     * 细分三次贝塞尔曲线
     *
     * (was: cubicSubdivide(..., out) — fills `out`; value-returning per CONVENTIONS §3.)
     */
    public static func cubicSubdivide(_ p0: Double, _ p1: Double, _ p2: Double, _ p3: Double, _ t: Double) -> [Double] {
        var out = [Double](repeating: 0, count: 8)
        let p01 = (p1 - p0) * t + p0
        let p12 = (p2 - p1) * t + p1
        let p23 = (p3 - p2) * t + p2

        let p012 = (p12 - p01) * t + p01
        let p123 = (p23 - p12) * t + p12

        let p0123 = (p123 - p012) * t + p012
        // Seg0
        out[0] = p0
        out[1] = p01
        out[2] = p012
        out[3] = p0123
        // Seg1
        out[4] = p0123
        out[5] = p123
        out[6] = p23
        out[7] = p3
        return out
    }

    /**
     * 投射点到三次贝塞尔曲线上，返回投射距离。
     * 投射点有可能会有一个或者多个，这里只返回其中距离最短的一个。
     *
     * (was: cubicProjectPoint(..., out): number — fills `out` with the projected
     *  point and returns the distance; value-returning tuple per CONVENTIONS §3.)
     */
    public static func cubicProjectPoint(
        _ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, _ x3: Double, _ y3: Double,
        _ x: Double, _ y: Double
    ) -> (out: VectorArray, distance: Double) {
        // http://pomax.github.io/bezierinfo/#projections
        var t: Double = 0
        var interval = 0.005
        var d = Double.infinity
        var prev: Double = 0
        var next: Double = 0
        var d1: Double
        var d2: Double
        var out = VectorArray()

        _v0[0] = x
        _v0[1] = y

        // 先粗略估计一下可能的最小距离的 t 值
        // PENDING
        var _t = 0.0
        while _t < 1 {
            _v1[0] = cubicAt(x0, x1, x2, x3, _t)
            _v1[1] = cubicAt(y0, y1, y2, y3, _t)
            d1 = vector.distSquare(_v0, _v1)
            if d1 < d {
                t = _t
                d = d1
            }
            _t += 0.05
        }
        d = Double.infinity

        // At most 32 iteration
        for _ in 0..<32 {
            if interval < EPSILON_NUMERIC {
                break
            }
            prev = t - interval
            next = t + interval
            // t - interval
            _v1[0] = cubicAt(x0, x1, x2, x3, prev)
            _v1[1] = cubicAt(y0, y1, y2, y3, prev)

            d1 = vector.distSquare(_v1, _v0)

            if prev >= 0 && d1 < d {
                t = prev
                d = d1
            }
            else {
                // t + interval
                _v2[0] = cubicAt(x0, x1, x2, x3, next)
                _v2[1] = cubicAt(y0, y1, y2, y3, next)
                d2 = vector.distSquare(_v2, _v0)

                if next <= 1 && d2 < d {
                    t = next
                    d = d2
                }
                else {
                    interval *= 0.5
                }
            }
        }
        // t
        // upstream: if (out) { ... } — `out` is always provided, so always written.
        out[0] = cubicAt(x0, x1, x2, x3, t)
        out[1] = cubicAt(y0, y1, y2, y3, t)
        // console.log(interval, i);
        return (out, mathSqrt(d))
    }

    /**
     * 计算三次贝塞尔曲线长度
     */
    public static func cubicLength(
        _ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, _ x3: Double, _ y3: Double,
        _ iteration: Double
    ) -> Double {
        var px = x0
        var py = y0

        var d = 0.0

        let step = 1 / iteration

        var i = 1
        while Double(i) <= iteration {
            let t = Double(i) * step
            let x = cubicAt(x0, x1, x2, x3, t)
            let y = cubicAt(y0, y1, y2, y3, t)

            let dx = x - px
            let dy = y - py

            d += sqrt(dx * dx + dy * dy)

            px = x
            py = y
            i += 1
        }

        return d
    }

    /**
     * 计算二次方贝塞尔值
     */
    public static func quadraticAt(_ p0: Double, _ p1: Double, _ p2: Double, _ t: Double) -> Double {
        let onet = 1 - t
        return onet * (onet * p0 + 2 * t * p1) + t * t * p2
    }

    /**
     * 计算二次方贝塞尔导数值
     */
    public static func quadraticDerivativeAt(_ p0: Double, _ p1: Double, _ p2: Double, _ t: Double) -> Double {
        return 2 * ((1 - t) * (p1 - p0) + t * (p2 - p1))
    }

    /**
     * 计算二次方贝塞尔方程根
     * @return 有效根数目
     *
     * (was: quadraticRootAt(..., roots): number — value-returning tuple per CONVENTIONS §3.)
     */
    public static func quadraticRootAt(_ p0: Double, _ p1: Double, _ p2: Double, _ val: Double) -> (roots: [Double], n: Double) {
        var roots = [Double](repeating: 0, count: 2)
        let a = p0 - 2 * p1 + p2
        let b = 2 * (p1 - p0)
        let c = p0 - val

        var n = 0
        if isAroundZero(a) {
            if isNotAroundZero(b) {
                let t1 = -c / b
                if t1 >= 0 && t1 <= 1 {
                    roots[n] = t1; n += 1
                }
            }
        }
        else {
            let disc = b * b - 4 * a * c
            if isAroundZero(disc) {
                let t1 = -b / (2 * a)
                if t1 >= 0 && t1 <= 1 {
                    roots[n] = t1; n += 1
                }
            }
            else if disc > 0 {
                let discSqrt = mathSqrt(disc)
                let t1 = (-b + discSqrt) / (2 * a)
                let t2 = (-b - discSqrt) / (2 * a)
                if t1 >= 0 && t1 <= 1 {
                    roots[n] = t1; n += 1
                }
                if t2 >= 0 && t2 <= 1 {
                    roots[n] = t2; n += 1
                }
            }
        }
        return (roots, Double(n))
    }

    /**
     * 计算二次贝塞尔方程极限值
     */
    public static func quadraticExtremum(_ p0: Double, _ p1: Double, _ p2: Double) -> Double {
        let divider = p0 + p2 - 2 * p1
        if divider == 0 {
            // p1 is center of p0 and p2
            return 0.5
        }
        else {
            return (p0 - p1) / divider
        }
    }

    /**
     * 细分二次贝塞尔曲线
     *
     * (was: quadraticSubdivide(..., out) — fills `out`; value-returning per CONVENTIONS §3.)
     */
    public static func quadraticSubdivide(_ p0: Double, _ p1: Double, _ p2: Double, _ t: Double) -> [Double] {
        var out = [Double](repeating: 0, count: 6)
        let p01 = (p1 - p0) * t + p0
        let p12 = (p2 - p1) * t + p1
        let p012 = (p12 - p01) * t + p01

        // Seg0
        out[0] = p0
        out[1] = p01
        out[2] = p012

        // Seg1
        out[3] = p012
        out[4] = p12
        out[5] = p2
        return out
    }

    /**
     * 投射点到二次贝塞尔曲线上，返回投射距离。
     * 投射点有可能会有一个或者多个，这里只返回其中距离最短的一个。
     * @param {number} x0
     * @param {number} y0
     * @param {number} x1
     * @param {number} y1
     * @param {number} x2
     * @param {number} y2
     * @param {number} x
     * @param {number} y
     * @param {Array.<number>} out 投射点
     * @return {number}
     *
     * (was: quadraticProjectPoint(..., out): number — value-returning tuple per CONVENTIONS §3.)
     */
    public static func quadraticProjectPoint(
        _ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double,
        _ x: Double, _ y: Double
    ) -> (out: VectorArray, distance: Double) {
        // http://pomax.github.io/bezierinfo/#projections
        var t: Double = 0
        var interval = 0.005
        var d = Double.infinity
        var out = VectorArray()

        _v0[0] = x
        _v0[1] = y

        // 先粗略估计一下可能的最小距离的 t 值
        // PENDING
        var _t = 0.0
        while _t < 1 {
            _v1[0] = quadraticAt(x0, x1, x2, _t)
            _v1[1] = quadraticAt(y0, y1, y2, _t)
            let d1 = vector.distSquare(_v0, _v1)
            if d1 < d {
                t = _t
                d = d1
            }
            _t += 0.05
        }
        d = Double.infinity

        // At most 32 iteration
        for _ in 0..<32 {
            if interval < EPSILON_NUMERIC {
                break
            }
            let prev = t - interval
            let next = t + interval
            // t - interval
            _v1[0] = quadraticAt(x0, x1, x2, prev)
            _v1[1] = quadraticAt(y0, y1, y2, prev)

            let d1 = vector.distSquare(_v1, _v0)

            if prev >= 0 && d1 < d {
                t = prev
                d = d1
            }
            else {
                // t + interval
                _v2[0] = quadraticAt(x0, x1, x2, next)
                _v2[1] = quadraticAt(y0, y1, y2, next)
                let d2 = vector.distSquare(_v2, _v0)
                if next <= 1 && d2 < d {
                    t = next
                    d = d2
                }
                else {
                    interval *= 0.5
                }
            }
        }
        // t
        // upstream: if (out) { ... } — `out` is always provided, so always written.
        out[0] = quadraticAt(x0, x1, x2, t)
        out[1] = quadraticAt(y0, y1, y2, t)
        // console.log(interval, i);
        return (out, mathSqrt(d))
    }

    /**
     * 计算二次贝塞尔曲线长度
     */
    public static func quadraticLength(
        _ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double,
        _ iteration: Double
    ) -> Double {
        var px = x0
        var py = y0

        var d = 0.0

        let step = 1 / iteration

        var i = 1
        while Double(i) <= iteration {
            let t = Double(i) * step
            let x = quadraticAt(x0, x1, x2, t)
            let y = quadraticAt(y0, y1, y2, t)

            let dx = x - px
            let dy = y - py

            d += sqrt(dx * dx + dy * dy)

            px = x
            py = y
            i += 1
        }

        return d
    }
}
