// Ported from zrender/src/core/vector.ts — keep in sync with upstream
/**
 * @deprecated
 * Use zrender.Point class instead
 */
// upstream: import { MatrixArray } from './matrix';  (MatrixArray = [Double], owned by matrix.swift)
import simd

/* global Float32Array */

// const ArrayCtor = typeof Float32Array === 'undefined'
//     ? Array
//     : Float32Array;

// upstream: export type VectorArray = number[]
// Per CONVENTIONS §3: vectors use SIMD2<Double> (value semantics, out-param dropped).
public typealias VectorArray = SIMD2<Double>

// JS `Math.min`/`Math.max` propagate NaN (any NaN operand => NaN); `Swift.min`/`Swift.max`
// return the non-NaN operand. The vector min/max below are bbox/bounds accumulators, so a
// NaN coordinate must taint the result exactly as upstream. These faithful helpers restore
// NaN propagation (CONVENTIONS §5 normally maps Math.min→Swift.min; this is the documented
// single-policy exception, see PORT_STATUS §3 item 2).
@inline(__always) private func mathMin(_ a: Double, _ b: Double) -> Double {
    return (a.isNaN || b.isNaN) ? Double.nan : Swift.min(a, b)
}
@inline(__always) private func mathMax(_ a: Double, _ b: Double) -> Double {
    return (a.isNaN || b.isNaN) ? Double.nan : Swift.max(a, b)
}

public enum vector {   // upstream alias: `vec2`

    /**
     * 创建一个向量
     */
    public static func create(_ x: Double? = nil, _ y: Double? = nil) -> VectorArray {
        var x = x
        var y = y
        if x == nil {
            x = 0
        }
        if y == nil {
            y = 0
        }
        return [x!, y!]
    }

    /**
     * 复制向量数据
     * (was: copy(out, v) — out-param dropped, value-returning per CONVENTIONS §3)
     */
    public static func copy(_ v: VectorArray) -> VectorArray {
        var out = VectorArray()
        out[0] = v[0]
        out[1] = v[1]
        return out
    }

    /**
     * 克隆一个向量
     */
    public static func clone(_ v: VectorArray) -> VectorArray {
        return [v[0], v[1]]
    }

    /**
     * 设置向量的两个项
     * (was: set(out, a, b) — out-param dropped, value-returning per CONVENTIONS §3)
     */
    public static func set(_ a: Double, _ b: Double) -> VectorArray {
        var out = VectorArray()
        out[0] = a
        out[1] = b
        return out
    }

    /**
     * 向量相加
     * (was: add(out, v1, v2) — out-param dropped, value-returning per CONVENTIONS §3)
     */
    public static func add(_ v1: VectorArray, _ v2: VectorArray) -> VectorArray {
        var out = VectorArray()
        out[0] = v1[0] + v2[0]
        out[1] = v1[1] + v2[1]
        return out
    }

    /**
     * 向量缩放后相加
     * (was: scaleAndAdd(out, v1, v2, a) — out-param dropped, value-returning per CONVENTIONS §3)
     */
    public static func scaleAndAdd(_ v1: VectorArray, _ v2: VectorArray, _ a: Double) -> VectorArray {
        var out = VectorArray()
        out[0] = v1[0] + v2[0] * a
        out[1] = v1[1] + v2[1] * a
        return out
    }

    /**
     * 向量相减
     * (was: sub(out, v1, v2) — out-param dropped, value-returning per CONVENTIONS §3)
     */
    public static func sub(_ v1: VectorArray, _ v2: VectorArray) -> VectorArray {
        var out = VectorArray()
        out[0] = v1[0] - v2[0]
        out[1] = v1[1] - v2[1]
        return out
    }

    /**
     * 向量长度
     */
    public static func len(_ v: VectorArray) -> Double {
        return sqrt(lenSquare(v))
    }
    // upstream: export const length = len;
    public static let length = len

    /**
     * 向量长度平方
     */
    public static func lenSquare(_ v: VectorArray) -> Double {
        return v[0] * v[0] + v[1] * v[1]
    }
    // upstream: export const lengthSquare = lenSquare;
    public static let lengthSquare = lenSquare

    /**
     * 向量乘法
     * (was: mul(out, v1, v2) — out-param dropped, value-returning per CONVENTIONS §3)
     */
    public static func mul(_ v1: VectorArray, _ v2: VectorArray) -> VectorArray {
        var out = VectorArray()
        out[0] = v1[0] * v2[0]
        out[1] = v1[1] * v2[1]
        return out
    }

    /**
     * 向量除法
     * (was: div(out, v1, v2) — out-param dropped, value-returning per CONVENTIONS §3)
     */
    public static func div(_ v1: VectorArray, _ v2: VectorArray) -> VectorArray {
        var out = VectorArray()
        out[0] = v1[0] / v2[0]
        out[1] = v1[1] / v2[1]
        return out
    }

    /**
     * 向量点乘
     */
    public static func dot(_ v1: VectorArray, _ v2: VectorArray) -> Double {
        return v1[0] * v2[0] + v1[1] * v2[1]
    }

    /**
     * 向量缩放
     * (was: scale(out, v, s) — out-param dropped, value-returning per CONVENTIONS §3)
     */
    public static func scale(_ v: VectorArray, _ s: Double) -> VectorArray {
        var out = VectorArray()
        out[0] = v[0] * s
        out[1] = v[1] * s
        return out
    }

    /**
     * 向量归一化
     * (was: normalize(out, v) — out-param dropped, value-returning per CONVENTIONS §3)
     */
    public static func normalize(_ v: VectorArray) -> VectorArray {
        var out = VectorArray()
        let d = len(v)
        if d == 0 {
            out[0] = 0
            out[1] = 0
        }
        else {
            out[0] = v[0] / d
            out[1] = v[1] / d
        }
        return out
    }

    /**
     * 计算向量间距离
     */
    public static func distance(_ v1: VectorArray, _ v2: VectorArray) -> Double {
        return sqrt(
            (v1[0] - v2[0]) * (v1[0] - v2[0])
            + (v1[1] - v2[1]) * (v1[1] - v2[1])
        )
    }
    // upstream: export const dist = distance;
    public static let dist = distance

    /**
     * 向量距离平方
     */
    public static func distanceSquare(_ v1: VectorArray, _ v2: VectorArray) -> Double {
        return (v1[0] - v2[0]) * (v1[0] - v2[0])
            + (v1[1] - v2[1]) * (v1[1] - v2[1])
    }
    // upstream: export const distSquare = distanceSquare;
    public static let distSquare = distanceSquare

    /**
     * 求负向量
     * (was: negate(out, v) — out-param dropped, value-returning per CONVENTIONS §3)
     */
    public static func negate(_ v: VectorArray) -> VectorArray {
        var out = VectorArray()
        out[0] = -v[0]
        out[1] = -v[1]
        return out
    }

    /**
     * 插值两个点
     * (was: lerp(out, v1, v2, t) — out-param dropped, value-returning per CONVENTIONS §3)
     */
    public static func lerp(_ v1: VectorArray, _ v2: VectorArray, _ t: Double) -> VectorArray {
        var out = VectorArray()
        out[0] = v1[0] + t * (v2[0] - v1[0])
        out[1] = v1[1] + t * (v2[1] - v1[1])
        return out
    }

    /**
     * 矩阵左乘向量
     * (was: applyTransform(out, v, m) — out-param dropped, value-returning per CONVENTIONS §3)
     */
    public static func applyTransform(_ v: VectorArray, _ m: MatrixArray) -> VectorArray {
        var out = VectorArray()
        let x = v[0]
        let y = v[1]
        out[0] = m[0] * x + m[2] * y + m[4]
        out[1] = m[1] * x + m[3] * y + m[5]
        return out
    }

    /**
     * 求两个向量最小值
     * (was: min(out, v1, v2) — out-param dropped, value-returning per CONVENTIONS §3)
     */
    public static func min(_ v1: VectorArray, _ v2: VectorArray) -> VectorArray {
        var out = VectorArray()
        out[0] = mathMin(v1[0], v2[0])
        out[1] = mathMin(v1[1], v2[1])
        return out
    }

    /**
     * 求两个向量最大值
     * (was: max(out, v1, v2) — out-param dropped, value-returning per CONVENTIONS §3)
     */
    public static func max(_ v1: VectorArray, _ v2: VectorArray) -> VectorArray {
        var out = VectorArray()
        out[0] = mathMax(v1[0], v2[0])
        out[1] = mathMax(v1[1], v2[1])
        return out
    }
}
