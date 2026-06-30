// Ported from zrender/src/animation/easing.ts — keep in sync with upstream
//
// 缓动代码来自 https://github.com/sole/tween.js/blob/master/src/Tween.js
// @see http://sole.github.io/tween.js/examples/03_graphs.html
// @exports zrender/animation/easing

import Foundation

// upstream: type easingFunc = (percent: number) => number;
public typealias EasingFunc = (_ percent: Double) -> Double

/// upstream: export type AnimationEasing = keyof typeof easingFuncs | easingFunc;
///
/// In TS this is a union of "a named built-in easing (string key of `easingFuncs`)"
/// or "a custom easing function". Swift has no `keyof`, so we model the union
/// explicitly as a two-case enum. Faithful call-site mapping:
///   - upstream string literal `'cubicOut'`   → `.named("cubicOut")`
///   - upstream function value `(k) => k`      → `.function({ k in k })`
public enum AnimationEasing {
    case named(String)
    case function(EasingFunc)
}

/// upstream: const easingFuncs = { linear, quadraticIn, ... }; export default easingFuncs;
///
/// The free-function table is modeled as a caseless `enum` namespace (CONVENTIONS §2).
/// Each upstream member is a `static func` (so that `bounceIn`/`bounceInOut` can refer
/// to `bounceOut`/`bounceIn`, exactly as upstream does), and `easingFuncs` is the
/// name→function dictionary that backs the `AnimationEasing` string lookup.
public enum easing {   // upstream default export: `easingFuncs`

    /**
    * @param {number} k
    * @return {number}
    */
    public static func linear(_ k: Double) -> Double {
        return k
    }

    /**
    * @param {number} k
    * @return {number}
    */
    public static func quadraticIn(_ k: Double) -> Double {
        return k * k
    }
    /**
    * @param {number} k
    * @return {number}
    */
    public static func quadraticOut(_ k: Double) -> Double {
        return k * (2 - k)
    }
    /**
    * @param {number} k
    * @return {number}
    */
    public static func quadraticInOut(_ k: Double) -> Double {
        var k = k
        if (k * 2) < 1 {
            k *= 2
            return 0.5 * k * k
        }
        k *= 2
        k -= 1
        return -0.5 * (k * (k - 2) - 1)
    }

    // 三次方的缓动（t^3）
    /**
    * @param {number} k
    * @return {number}
    */
    public static func cubicIn(_ k: Double) -> Double {
        return k * k * k
    }
    /**
    * @param {number} k
    * @return {number}
    */
    public static func cubicOut(_ k: Double) -> Double {
        let k = k - 1
        return k * k * k + 1
    }
    /**
    * @param {number} k
    * @return {number}
    */
    public static func cubicInOut(_ k: Double) -> Double {
        var k = k
        if (k * 2) < 1 {
            k *= 2
            return 0.5 * k * k * k
        }
        k *= 2
        k -= 2
        return 0.5 * (k * k * k + 2)
    }

    // 四次方的缓动（t^4）
    /**
    * @param {number} k
    * @return {number}
    */
    public static func quarticIn(_ k: Double) -> Double {
        return k * k * k * k
    }
    /**
    * @param {number} k
    * @return {number}
    */
    public static func quarticOut(_ k: Double) -> Double {
        let k = k - 1
        return 1 - (k * k * k * k)
    }
    /**
    * @param {number} k
    * @return {number}
    */
    public static func quarticInOut(_ k: Double) -> Double {
        var k = k
        if (k * 2) < 1 {
            k *= 2
            return 0.5 * k * k * k * k
        }
        k *= 2
        k -= 2
        return -0.5 * (k * k * k * k - 2)
    }

    // 五次方的缓动（t^5）
    /**
    * @param {number} k
    * @return {number}
    */
    public static func quinticIn(_ k: Double) -> Double {
        return k * k * k * k * k
    }
    /**
    * @param {number} k
    * @return {number}
    */
    public static func quinticOut(_ k: Double) -> Double {
        let k = k - 1
        return k * k * k * k * k + 1
    }
    /**
    * @param {number} k
    * @return {number}
    */
    public static func quinticInOut(_ k: Double) -> Double {
        var k = k
        if (k * 2) < 1 {
            k *= 2
            return 0.5 * k * k * k * k * k
        }
        k *= 2
        k -= 2
        return 0.5 * (k * k * k * k * k + 2)
    }

    // 正弦曲线的缓动（sin(t)）
    /**
    * @param {number} k
    * @return {number}
    */
    public static func sinusoidalIn(_ k: Double) -> Double {
        return 1 - cos(k * Double.pi / 2)
    }
    /**
    * @param {number} k
    * @return {number}
    */
    public static func sinusoidalOut(_ k: Double) -> Double {
        return sin(k * Double.pi / 2)
    }
    /**
    * @param {number} k
    * @return {number}
    */
    public static func sinusoidalInOut(_ k: Double) -> Double {
        return 0.5 * (1 - cos(Double.pi * k))
    }

    // 指数曲线的缓动（2^t）
    /**
    * @param {number} k
    * @return {number}
    */
    public static func exponentialIn(_ k: Double) -> Double {
        return k == 0 ? 0 : pow(1024, k - 1)
    }
    /**
    * @param {number} k
    * @return {number}
    */
    public static func exponentialOut(_ k: Double) -> Double {
        return k == 1 ? 1 : 1 - pow(2, -10 * k)
    }
    /**
    * @param {number} k
    * @return {number}
    */
    public static func exponentialInOut(_ k: Double) -> Double {
        var k = k
        if k == 0 {
            return 0
        }
        if k == 1 {
            return 1
        }
        if (k * 2) < 1 {
            k *= 2
            return 0.5 * pow(1024, k - 1)
        }
        k *= 2
        return 0.5 * (-pow(2, -10 * (k - 1)) + 2)
    }

    // 圆形曲线的缓动（sqrt(1-t^2)）
    /**
    * @param {number} k
    * @return {number}
    */
    public static func circularIn(_ k: Double) -> Double {
        return 1 - sqrt(1 - k * k)
    }
    /**
    * @param {number} k
    * @return {number}
    */
    public static func circularOut(_ k: Double) -> Double {
        let k = k - 1
        return sqrt(1 - (k * k))
    }
    /**
    * @param {number} k
    * @return {number}
    */
    public static func circularInOut(_ k: Double) -> Double {
        var k = k
        if (k * 2) < 1 {
            k *= 2
            return -0.5 * (sqrt(1 - k * k) - 1)
        }
        k *= 2
        k -= 2
        return 0.5 * (sqrt(1 - k * k) + 1)
    }

    // 创建类似于弹簧在停止前来回振荡的动画
    /**
    * @param {number} k
    * @return {number}
    */
    public static func elasticIn(_ k: Double) -> Double {
        var k = k
        let s: Double
        var a = 0.1
        let p = 0.4
        if k == 0 {
            return 0
        }
        if k == 1 {
            return 1
        }
        if a == 0 || a < 1 {
            a = 1
            s = p / 4
        }
        else {
            s = p * asin(1 / a) / (2 * Double.pi)
        }
        k -= 1
        return -(a * pow(2, 10 * k)
                    * sin((k - s) * (2 * Double.pi) / p))
    }
    /**
    * @param {number} k
    * @return {number}
    */
    public static func elasticOut(_ k: Double) -> Double {
        let s: Double
        var a = 0.1
        let p = 0.4
        if k == 0 {
            return 0
        }
        if k == 1 {
            return 1
        }
        if a == 0 || a < 1 {
            a = 1
            s = p / 4
        }
        else {
            s = p * asin(1 / a) / (2 * Double.pi)
        }
        return (a * pow(2, -10 * k)
                    * sin((k - s) * (2 * Double.pi) / p) + 1)
    }
    /**
    * @param {number} k
    * @return {number}
    */
    public static func elasticInOut(_ k: Double) -> Double {
        var k = k
        let s: Double
        var a = 0.1
        let p = 0.4
        if k == 0 {
            return 0
        }
        if k == 1 {
            return 1
        }
        if a == 0 || a < 1 {
            a = 1
            s = p / 4
        }
        else {
            s = p * asin(1 / a) / (2 * Double.pi)
        }
        if (k * 2) < 1 {
            k *= 2
            k -= 1
            return -0.5 * (a * pow(2, 10 * k)
                * sin((k - s) * (2 * Double.pi) / p))
        }
        k *= 2
        k -= 1
        return a * pow(2, -10 * k)
                * sin((k - s) * (2 * Double.pi) / p) * 0.5 + 1

    }

    // 在某一动画开始沿指示的路径进行动画处理前稍稍收回该动画的移动
    /**
    * @param {number} k
    * @return {number}
    */
    public static func backIn(_ k: Double) -> Double {
        let s = 1.70158
        return k * k * ((s + 1) * k - s)
    }
    /**
    * @param {number} k
    * @return {number}
    */
    public static func backOut(_ k: Double) -> Double {
        let k = k - 1
        let s = 1.70158
        return k * k * ((s + 1) * k + s) + 1
    }
    /**
    * @param {number} k
    * @return {number}
    */
    public static func backInOut(_ k: Double) -> Double {
        var k = k
        let s = 1.70158 * 1.525
        if (k * 2) < 1 {
            k *= 2
            return 0.5 * (k * k * ((s + 1) * k - s))
        }
        k *= 2
        k -= 2
        return 0.5 * (k * k * ((s + 1) * k + s) + 2)
    }

    // 创建弹跳效果
    /**
    * @param {number} k
    * @return {number}
    */
    public static func bounceIn(_ k: Double) -> Double {
        return 1 - bounceOut(1 - k)
    }
    /**
    * @param {number} k
    * @return {number}
    */
    public static func bounceOut(_ k: Double) -> Double {
        var k = k
        if k < (1 / 2.75) {
            return 7.5625 * k * k
        }
        else if k < (2 / 2.75) {
            k -= (1.5 / 2.75)
            return 7.5625 * k * k + 0.75
        }
        else if k < (2.5 / 2.75) {
            k -= (2.25 / 2.75)
            return 7.5625 * k * k + 0.9375
        }
        else {
            k -= (2.625 / 2.75)
            return 7.5625 * k * k + 0.984375
        }
    }
    /**
    * @param {number} k
    * @return {number}
    */
    public static func bounceInOut(_ k: Double) -> Double {
        if k < 0.5 {
            return bounceIn(k * 2) * 0.5
        }
        return bounceOut(k * 2 - 1) * 0.5 + 0.5
    }

    /// upstream animation/cubicEasing.ts — parse a `cubic-bezier(a, b, c, d)` easing string into an
    /// easing function (CSS-style cubic-bezier). Returns nil if the string isn't a valid cubic-bezier.
    /// Used as the fallback when a named easing misses `easingFuncs` (Clip.setEasing / Animator).
    public static func createCubicEasingFunc(_ cubicEasingStr: String) -> EasingFunc? {
        // regexp: /cubic-bezier\(([0-9,\.e ]+)\)/
        guard let open = cubicEasingStr.range(of: "cubic-bezier("),
              let close = cubicEasingStr.range(of: ")", range: open.upperBound..<cubicEasingStr.endIndex)
        else { return nil }
        let nums = cubicEasingStr[open.upperBound..<close.lowerBound]
            .split(separator: ",").map { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard nums.count >= 4, let a = nums[0], let b = nums[1], let c = nums[2], let d = nums[3] else {
            return nil
        }
        if (a + b + c + d).isNaN { return nil }
        return { p in
            if p <= 0 { return 0 }
            if p >= 1 { return 1 }
            // p<=0?0 : p>=1?1 : cubicRootAt(0,a,c,1,p) && cubicAt(0,b,d,1,roots[0])
            let r = curve.cubicRootAt(0, a, c, 1, p)
            return r.n >= 1 ? curve.cubicAt(0, b, d, 1, r.roots[0]) : 0
        }
    }

    /// upstream: `const easingFuncs = { ... }; export default easingFuncs;`
    /// Name → function table backing the `AnimationEasing` string lookup.
    public static let easingFuncs: [String: EasingFunc] = [
        "linear": linear,
        "quadraticIn": quadraticIn,
        "quadraticOut": quadraticOut,
        "quadraticInOut": quadraticInOut,
        "cubicIn": cubicIn,
        "cubicOut": cubicOut,
        "cubicInOut": cubicInOut,
        "quarticIn": quarticIn,
        "quarticOut": quarticOut,
        "quarticInOut": quarticInOut,
        "quinticIn": quinticIn,
        "quinticOut": quinticOut,
        "quinticInOut": quinticInOut,
        "sinusoidalIn": sinusoidalIn,
        "sinusoidalOut": sinusoidalOut,
        "sinusoidalInOut": sinusoidalInOut,
        "exponentialIn": exponentialIn,
        "exponentialOut": exponentialOut,
        "exponentialInOut": exponentialInOut,
        "circularIn": circularIn,
        "circularOut": circularOut,
        "circularInOut": circularInOut,
        "elasticIn": elasticIn,
        "elasticOut": elasticOut,
        "elasticInOut": elasticInOut,
        "backIn": backIn,
        "backOut": backOut,
        "backInOut": backInOut,
        "bounceIn": bounceIn,
        "bounceOut": bounceOut,
        "bounceInOut": bounceInOut
    ]
}
