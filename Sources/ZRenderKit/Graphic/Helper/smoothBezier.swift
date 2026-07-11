// Ported from zrender/src/graphic/helper/smoothBezier.ts — keep in sync with upstream
//
// 贝塞尔平滑曲线
//
// CONVENTIONS §3: upstream uses gl-matrix out-param vector functions (v2Min/v2Max/v2Scale/
//   v2Add/v2Sub etc.) that mutate a caller-owned array in place. The Phase-0 `vector` enum is
//   value-returning, so every `v2Foo(out, a, b)` becomes `out = vector.foo(a, b)`.

import Foundation

// upstream:
//   import { min as v2Min, max as v2Max, scale as v2Scale, distance as v2Distance,
//            add as v2Add, clone as v2Clone, sub as v2Sub, VectorArray } from '../../core/vector';

/// 贝塞尔平滑曲线
/// - Parameters:
///   - points: 线段顶点数组
///   - smooth: 平滑等级, 0-1
///   - isLoop:
///   - constraint: 将计算出来的控制点约束在一个包围盒内
///                 比如 [[0, 0], [100, 100]], 这个包围盒会与
///                 整个折线的包围盒做一个并集用来约束控制点。
/// - Returns: 计算出来的控制点数组
public func smoothBezier(
    _ points: [VectorArray],
    _ smooth: Double? = nil,
    _ isLoop: Bool? = nil,
    _ constraint: [VectorArray]? = nil
) -> [VectorArray] {
    var cps: [VectorArray] = []

    var v: VectorArray = VectorArray()
    var v1: VectorArray = VectorArray()
    var v2: VectorArray = VectorArray()
    var prevPoint: VectorArray = VectorArray()
    var nextPoint: VectorArray = VectorArray()

    var min: VectorArray = VectorArray()
    var max: VectorArray = VectorArray()
    if let constraint = constraint {
        min = VectorArray(Double.infinity, Double.infinity)
        max = VectorArray(-Double.infinity, -Double.infinity)
        for i in 0..<points.count {
            min = vector.min(min, points[i])
            max = vector.max(max, points[i])
        }
        // 与指定的包围盒做并集
        min = vector.min(min, constraint[0])
        max = vector.max(max, constraint[1])
    }

    let len = points.count
    for i in 0..<len {
        let point = points[i]

        if isLoop ?? false {
            prevPoint = points[i != 0 ? i - 1 : len - 1]
            nextPoint = points[(i + 1) % len]
        }
        else {
            if i == 0 || i == len - 1 {
                cps.append(vector.clone(points[i]))
                continue
            }
            else {
                prevPoint = points[i - 1]
                nextPoint = points[i + 1]
            }
        }

        v = vector.sub(nextPoint, prevPoint)

        // use degree to scale the handle length
        // PORT-NOTE: `smooth` is optional upstream; `scale` needs a Double. Callers (poly.buildPath)
        //   only invoke smoothBezier when `smooth` is truthy, so `?? 0` is never the live path.
        v = vector.scale(v, smooth ?? 0)

        var d0 = vector.distance(point, prevPoint)
        var d1 = vector.distance(point, nextPoint)
        let sum = d0 + d1
        if sum != 0 {
            d0 /= sum
            d1 /= sum
        }

        v1 = vector.scale(v, -d0)
        v2 = vector.scale(v, d1)
        var cp0 = vector.add(point, v1)
        var cp1 = vector.add(point, v2)
        if constraint != nil {
            cp0 = vector.max(cp0, min)
            cp0 = vector.min(cp0, max)
            cp1 = vector.max(cp1, min)
            cp1 = vector.min(cp1, max)
        }
        cps.append(cp0)
        cps.append(cp1)
    }

    if isLoop ?? false {
        cps.append(cps.removeFirst())   // upstream: cps.push(cps.shift())
    }

    return cps
}
