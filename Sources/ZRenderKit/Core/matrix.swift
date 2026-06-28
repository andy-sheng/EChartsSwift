// Ported from zrender/src/core/matrix.ts — keep in sync with upstream

/**
 * 3x2矩阵操作类
 * @exports zrender/tool/matrix
 */

/* global Float32Array */

import simd

// upstream: import {VectorArray} from './vector'  (VectorArray = SIMD2<Double>)

public typealias MatrixArray = [Double]

public enum matrix {

    /**
     * Create a identity matrix.
     */
    public static func create() -> MatrixArray {
        return [1, 0, 0, 1, 0, 0]
    }

    /**
     * 设置矩阵为单位矩阵
     */
    // out-param dropped, value-returning per CONVENTIONS §3
    // upstream: export function identity(out: MatrixArray): MatrixArray
    public static func identity() -> MatrixArray {
        var out = MatrixArray(repeating: 0, count: 6)
        out[0] = 1
        out[1] = 0
        out[2] = 0
        out[3] = 1
        out[4] = 0
        out[5] = 0
        return out
    }

    /**
     * 复制矩阵
     */
    // out-param dropped, value-returning per CONVENTIONS §3
    // upstream: export function copy(out: MatrixArray, m: MatrixArray): MatrixArray
    public static func copy(_ m: MatrixArray) -> MatrixArray {
        var out = MatrixArray(repeating: 0, count: 6)
        out[0] = m[0]
        out[1] = m[1]
        out[2] = m[2]
        out[3] = m[3]
        out[4] = m[4]
        out[5] = m[5]
        return out
    }

    /**
     * 矩阵相乘
     */
    // out-param dropped, value-returning per CONVENTIONS §3
    // upstream: export function mul(out: MatrixArray, m1: MatrixArray, m2: MatrixArray): MatrixArray
    public static func mul(_ m1: MatrixArray, _ m2: MatrixArray) -> MatrixArray {
        var out = MatrixArray(repeating: 0, count: 6)
        // Consider matrix.mul(m, m2, m);
        // where out is the same as m2.
        // So use temp constiable to escape error.
        let out0 = m1[0] * m2[0] + m1[2] * m2[1]
        let out1 = m1[1] * m2[0] + m1[3] * m2[1]
        let out2 = m1[0] * m2[2] + m1[2] * m2[3]
        let out3 = m1[1] * m2[2] + m1[3] * m2[3]
        let out4 = m1[0] * m2[4] + m1[2] * m2[5] + m1[4]
        let out5 = m1[1] * m2[4] + m1[3] * m2[5] + m1[5]
        out[0] = out0
        out[1] = out1
        out[2] = out2
        out[3] = out3
        out[4] = out4
        out[5] = out5
        return out
    }

    /**
     * 平移变换
     */
    // out-param dropped, value-returning per CONVENTIONS §3
    // upstream: export function translate(out: MatrixArray, a: MatrixArray, v: VectorArray): MatrixArray
    public static func translate(_ a: MatrixArray, _ v: VectorArray) -> MatrixArray {
        var out = MatrixArray(repeating: 0, count: 6)
        out[0] = a[0]
        out[1] = a[1]
        out[2] = a[2]
        out[3] = a[3]
        out[4] = a[4] + v[0]
        out[5] = a[5] + v[1]
        return out
    }

    /**
     * Suppose positive y is towards screen-bottom and positive x is towards screen-right;
     * positive rotation means rotating anticlockwise. (opposite to CSS transform rotate)
     */
    // out-param dropped, value-returning per CONVENTIONS §3
    // upstream: export function rotate(out, a, rad, pivot = [0, 0]): MatrixArray
    public static func rotate(
        _ a: MatrixArray,
        _ rad: Double,
        _ pivot: VectorArray = VectorArray(0, 0)
    ) -> MatrixArray {
        var out = MatrixArray(repeating: 0, count: 6)
        let aa = a[0]
        let ac = a[2]
        let atx = a[4]
        let ab = a[1]
        let ad = a[3]
        let aty = a[5]
        let st = sin(rad)
        let ct = cos(rad)

        out[0] = aa * ct + ab * st
        out[1] = -aa * st + ab * ct
        out[2] = ac * ct + ad * st
        out[3] = -ac * st + ct * ad
        out[4] = ct * (atx - pivot[0]) + st * (aty - pivot[1]) + pivot[0]
        out[5] = ct * (aty - pivot[1]) - st * (atx - pivot[0]) + pivot[1]
        return out
    }

    /**
     * 缩放变换
     */
    // out-param dropped, value-returning per CONVENTIONS §3
    // upstream: export function scale(out: MatrixArray, a: MatrixArray, v: VectorArray): MatrixArray
    public static func scale(_ a: MatrixArray, _ v: VectorArray) -> MatrixArray {
        var out = MatrixArray(repeating: 0, count: 6)
        let vx = v[0]
        let vy = v[1]
        out[0] = a[0] * vx
        out[1] = a[1] * vy
        out[2] = a[2] * vx
        out[3] = a[3] * vy
        out[4] = a[4] * vx
        out[5] = a[5] * vy
        return out
    }

    /**
     * 求逆矩阵
     */
    // out-param dropped, value-returning per CONVENTIONS §3
    // upstream: export function invert(out: MatrixArray, a: MatrixArray): MatrixArray | null
    public static func invert(_ a: MatrixArray) -> MatrixArray? {
        var out = MatrixArray(repeating: 0, count: 6)

        let aa = a[0]
        let ac = a[2]
        let atx = a[4]
        let ab = a[1]
        let ad = a[3]
        let aty = a[5]

        var det = aa * ad - ab * ac
        if det == 0 || det.isNaN {   // upstream: if (!det) — JS falsy covers 0 and NaN
            return nil
        }
        det = 1.0 / det

        out[0] = ad * det
        out[1] = -ab * det
        out[2] = -ac * det
        out[3] = aa * det
        out[4] = (ac * aty - ad * atx) * det
        out[5] = (ab * atx - aa * aty) * det
        return out
    }

    /**
     * Clone a new matrix.
     */
    public static func clone(_ a: MatrixArray) -> MatrixArray {
        var b = create()
        b = copy(a)
        return b
    }
}
