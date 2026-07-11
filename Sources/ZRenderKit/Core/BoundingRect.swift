// Ported from zrender/src/core/BoundingRect.ts — keep in sync with upstream

import Foundation
import simd

// upstream: import * as matrix from './matrix';  (matrix namespace + MatrixArray = [Double])
// upstream: import * as vector from './vector';  (vector namespace + VectorArray = SIMD2<Double>)
// upstream: import Point, { PointLike } from './Point';  (owned by Point.swift)
// upstream: import { NullUndefined } from './types';  (collapses to `nil`, CONVENTIONS §6)

// const mathMin = Math.min;
// const mathMax = Math.max;
// const mathAbs = Math.abs;
// JS `Math.min`/`Math.max` propagate NaN (any NaN operand => NaN); `Swift.min`/`Swift.max`
// do not. These accumulate transformed-corner / union bounds, so NaN must taint the result
// exactly as upstream. Faithful NaN-propagating helpers (PORT_STATUS §3 item 2 policy).
@inline(__always) private func mathMin(_ a: Double, _ b: Double) -> Double {
    return (a.isNaN || b.isNaN) ? Double.nan : Swift.min(a, b)
}
@inline(__always) private func mathMin(_ a: Double, _ b: Double, _ c: Double, _ d: Double) -> Double {
    return (a.isNaN || b.isNaN || c.isNaN || d.isNaN) ? Double.nan : Swift.min(a, b, c, d)
}
@inline(__always) private func mathMax(_ a: Double, _ b: Double) -> Double {
    return (a.isNaN || b.isNaN) ? Double.nan : Swift.max(a, b)
}
@inline(__always) private func mathMax(_ a: Double, _ b: Double, _ c: Double, _ d: Double) -> Double {
    return (a.isNaN || b.isNaN || c.isNaN || d.isNaN) ? Double.nan : Swift.max(a, b, c, d)
}
@inline(__always) private func mathAbs(_ a: Double) -> Double { return Swift.abs(a) }

// const XY = ['x', 'y'] as const;
// const WH = ['width', 'height'] as const;
// PORT-NOTE: JS indexes Point/RectLike by these string keys (e.g. `_minTv[updateDim]`,
// `outIntersectRect[wh]`). Swift has no string-keyed stored-property access; we index by
// dimension number (0 => x/width, 1 => y/height) via the helpers below.
private func pointSet(_ p: Point, _ dim: Int, _ v: Double) { if dim == 0 { p.x = v } else { p.y = v } }
private func rectXYSet(_ r: RectLike, _ dim: Int, _ v: Double) { if dim == 0 { r.x = v } else { r.y = v } }
private func rectWHSet(_ r: RectLike, _ dim: Int, _ v: Double) { if dim == 0 { r.width = v } else { r.height = v } }

private let lt = Point()
private let rb = Point()
private let lb = Point()
private let rt = Point()

private let _intersectCtx = createIntersectContext()
private let _minTv = _intersectCtx.minTv
private let _maxTv = _intersectCtx.maxTv
// [min, max]
private var _lenMinMax: [Double] = [0, 0]

public final class BoundingRect: RectLike {

    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(_ x: Double, _ y: Double, _ width: Double, _ height: Double) {
        // PORT-NOTE: stored props must be initialized before passing `self` to
        // boundingRectSet; pre-set to 0, then boundingRectSet normalizes/overwrites.
        self.x = 0
        self.y = 0
        self.width = 0
        self.height = 0
        boundingRectSet(self, x, y, width, height)
    }

    @discardableResult
    public static func set<TTarget: RectLike>(
        _ target: TTarget, _ x: Double, _ y: Double, _ width: Double, _ height: Double
    ) -> TTarget {
        var x = x
        var y = y
        var width = width
        var height = height
        if width < 0 {
            x = x + width
            width = -width
        }
        if height < 0 {
            y = y + height
            height = -height
        }

        target.x = x
        target.y = y
        target.width = width
        target.height = height

        return target
    }

    public func union(_ other: BoundingRect) {
        let x = mathMin(other.x, self.x)
        let y = mathMin(other.y, self.y)

        // If x is -Infinity and width is Infinity (like in the case of
        // IncrementalDisplayable), x + width would be NaN
        if self.x.isFinite && self.width.isFinite {
            self.width = mathMax(
                other.x + other.width,
                self.x + self.width
            ) - x
        }
        else {
            self.width = other.width
        }

        if self.y.isFinite && self.height.isFinite {
            self.height = mathMax(
                other.y + other.height,
                self.y + self.height
            ) - y
        }
        else {
            self.height = other.height
        }

        self.x = x
        self.y = y
    }

    public func applyTransform(_ m: MatrixArray?) {
        BoundingRect.applyTransform(self, self, m)
    }

    public func calculateTransform(_ b: RectLike) -> MatrixArray {
        return boundingRectCalculateTransform(matrix.create(), self, b)
    }

    /**
     * @see `static intersect`
     */
    public func intersect(
        _ b: RectLike,
        _ mtv: PointLike? = nil,
        _ opt: BoundingRectIntersectOpt? = nil
    ) -> Bool {
        return BoundingRect.intersect(self, b, mtv, opt)
    }

    /**
     * [NOTICE]
     *  Touching the edge is considered an intersection.
     *  zero-width/height can still cause intersection if `touchThreshold` is 0.
     *  See more in `BoundingRectIntersectOpt['touchThreshold']`
     *
     * @param mtv
     *  If it's not overlapped. it means needs to move `b` rect with Maximum Translation Vector to be overlapped.
     *  Else it means needs to move `b` rect with Minimum Translation Vector to be not overlapped.
     */
    public static func intersect(
        _ a: RectLike?,
        _ b: RectLike?,
        _ mtv: PointLike? = nil,
        _ opt: BoundingRectIntersectOpt? = nil
    ) -> Bool {
        var a = a
        var b = b
        if let mtv = mtv {
            Point.set(mtv, 0, 0)
        }
        let outIntersectRect = opt?.outIntersectRect
        let clamp = opt?.clamp
        if let outIntersectRect = outIntersectRect {
            outIntersectRect.x = Double.nan
            outIntersectRect.y = Double.nan
            outIntersectRect.width = Double.nan
            outIntersectRect.height = Double.nan
        }

        if a == nil || b == nil {
            return false
        }

        // Normalize negative width/height.
        if !(a is BoundingRect) {
            a = boundingRectSet(_tmpIntersectA, a!.x, a!.y, a!.width, a!.height)
        }
        if !(b is BoundingRect) {
            b = boundingRectSet(_tmpIntersectB, b!.x, b!.y, b!.width, b!.height)
        }

        let useMTV = mtv != nil

        _intersectCtx.reset(opt, useMTV)

        let touchThreshold = _intersectCtx.touchThreshold

        let ax0 = a!.x + touchThreshold
        let ax1 = a!.x + a!.width - touchThreshold
        let ay0 = a!.y + touchThreshold
        let ay1 = a!.y + a!.height - touchThreshold

        let bx0 = b!.x + touchThreshold
        let bx1 = b!.x + b!.width - touchThreshold
        let by0 = b!.y + touchThreshold
        let by1 = b!.y + b!.height - touchThreshold

        if ax0 > ax1 || ay0 > ay1 || bx0 > bx1 || by0 > by1 {
            return false
        }

        let overlap = !(ax1 < bx0 || bx1 < ax0 || ay1 < by0 || by1 < ay0)

        if useMTV || outIntersectRect != nil {
            _lenMinMax[0] = Double.infinity
            _lenMinMax[1] = 0

            intersectOneDim(ax0, ax1, bx0, bx1, 0, useMTV, outIntersectRect, clamp)
            intersectOneDim(ay0, ay1, by0, by1, 1, useMTV, outIntersectRect, clamp)

            if useMTV {
                Point.copy(
                    mtv!,
                    overlap
                        ? (_intersectCtx.useDir ? _intersectCtx.dirMinTv : _minTv)
                        : _maxTv
                )
            }
        }

        return overlap
    }

    public static func contain(_ rect: RectLike, _ x: Double, _ y: Double) -> Bool {
        return x >= rect.x
            && x <= (rect.x + rect.width)
            && y >= rect.y
            && y <= (rect.y + rect.height)
    }

    public func contain(_ x: Double, _ y: Double) -> Bool {
        return BoundingRect.contain(self, x, y)
    }

    public func clone() -> BoundingRect {
        return BoundingRect(self.x, self.y, self.width, self.height)
    }

    /**
     * Copy from another rect
     */
    public func copy(_ other: RectLike) {
        boundingRectCopy(self, other)
    }

    public func plain() -> RectLike {
        // PORT-NOTE: upstream returns an object literal { x, y, width, height } typed RectLike.
        // Swift RectLike is AnyObject-constrained, so we return a concrete reference holder.
        return _PlainRect(
            x: self.x,
            y: self.y,
            width: self.width,
            height: self.height
        )
    }

    /**
     * If not having NaN or Infinity with attributes
     */
    public func isFinite() -> Bool {
        return self.x.isFinite
            && self.y.isFinite
            && self.width.isFinite
            && self.height.isFinite
    }

    public func isZero() -> Bool {
        return self.width == 0 || self.height == 0
    }

    public static func create(_ rect: RectLike? = nil) -> BoundingRect {
        return BoundingRect(
            rect != nil ? rect!.x : 0,
            rect != nil ? rect!.y : 0,
            rect != nil ? rect!.width : 0,
            rect != nil ? rect!.height : 0
        )
    }

    @discardableResult
    public static func copy<TTarget: RectLike>(_ target: TTarget, _ source: RectLike) -> TTarget {
        target.x = source.x
        target.y = source.y
        target.width = source.width
        target.height = source.height

        return target
    }

    public static func applyTransform(_ target: RectLike, _ source: RectLike, _ m: MatrixArray?) {
        // In case usage like this
        // el.getBoundingRect().applyTransform(el.transform)
        // And element has no transform
        if m == nil {
            if target !== source {
                boundingRectCopy(target, source)
            }
            return
        }
        let m = m!
        // Fast path when there is no rotation in matrix.
        if m[1] < 1e-5 && m[1] > -1e-5 && m[2] < 1e-5 && m[2] > -1e-5 {
            let sx = m[0]
            let sy = m[3]
            let tx = m[4]
            let ty = m[5]
            target.x = source.x * sx + tx
            target.y = source.y * sy + ty
            target.width = source.width * sx
            target.height = source.height * sy
            if target.width < 0 {
                target.x += target.width
                target.width = -target.width
            }
            if target.height < 0 {
                target.y += target.height
                target.height = -target.height
            }
            return
        }

        // source and target can be same instance.
        lt.x = source.x; lb.x = source.x
        lt.y = source.y; rt.y = source.y
        rb.x = source.x + source.width; rt.x = source.x + source.width
        rb.y = source.y + source.height; lb.y = source.y + source.height

        lt.transform(m)
        rt.transform(m)
        rb.transform(m)
        lb.transform(m)

        target.x = mathMin(lt.x, rb.x, lb.x, rt.x)
        target.y = mathMin(lt.y, rb.y, lb.y, rt.y)
        let maxX = mathMax(lt.x, rb.x, lb.x, rt.x)
        let maxY = mathMax(lt.y, rb.y, lb.y, rt.y)
        target.width = maxX - target.x
        target.height = maxY - target.y
    }

    public static func calculateTransform(_ out: MatrixArray?, _ a: RectLike, _ b: RectLike) -> MatrixArray {
        let sx = b.width / a.width
        let sy = b.height / a.height

        // PORT-NOTE: upstream reuses `out || []` as scratch (`out = matrix.identity(out || [])`).
        // Our matrix.* funcs are value-returning (CONVENTIONS §3), so the incoming `out` scratch
        // is unused and a fresh matrix is allocated.
        var m = matrix.identity()

        m = matrix.translate(m, vector.set(-a.x, -a.y))
        m = matrix.scale(m, vector.set(sx, sy))
        m = matrix.translate(m, vector.set(b.x, b.y))

        return m
    }

}

// upstream: export const boundingRectCreate = BoundingRect.create; (etc.)
// Generic static methods can't be stored as `let` values in Swift, so these re-exports
// are thin forwarding free functions preserving the upstream names.
@discardableResult
public func boundingRectCreate(_ rect: RectLike? = nil) -> BoundingRect {
    return BoundingRect.create(rect)
}
@discardableResult
public func boundingRectSet<TTarget: RectLike>(
    _ target: TTarget, _ x: Double, _ y: Double, _ width: Double, _ height: Double
) -> TTarget {
    return BoundingRect.set(target, x, y, width, height)
}
@discardableResult
public func boundingRectCopy<TTarget: RectLike>(_ target: TTarget, _ source: RectLike) -> TTarget {
    return BoundingRect.copy(target, source)
}
public func boundingRectCalculateTransform(_ out: MatrixArray?, _ a: RectLike, _ b: RectLike) -> MatrixArray {
    return BoundingRect.calculateTransform(out, a, b)
}
public func boundingRectApplyTransform(_ target: RectLike, _ source: RectLike, _ m: MatrixArray?) {
    BoundingRect.applyTransform(target, source, m)
}
public func boundingRectContain(_ rect: RectLike, _ x: Double, _ y: Double) -> Bool {
    return BoundingRect.contain(rect, x, y)
}

private let _tmpIntersectA = BoundingRect(0, 0, 0, 0)
private let _tmpIntersectB = BoundingRect(0, 0, 0, 0)
// const _tmpCalcTrans: vector.VectorArray = [];
// PORT-NOTE: dropped — `vector.set` is value-returning (CONVENTIONS §3), no scratch buffer needed.


private func intersectOneDim(
    _ a0: Double, _ a1: Double, _ b0: Double, _ b1: Double,
    _ updateDimIdx: Int,
    _ useMTV: Bool,
    _ outIntersectRect: RectLike?,
    _ clamp: Bool?
) {
    let d0 = mathAbs(a1 - b0)
    let d1 = mathAbs(b1 - a0)
    let d01min = mathMin(d0, d1)
    // const updateDim = XY[updateDimIdx];
    // const zeroDim = XY[1 - updateDimIdx];
    // const wh = WH[updateDimIdx];
    let zeroDimIdx = 1 - updateDimIdx

    if a1 < b0 || b1 < a0 { // No intersection on this dimension.
        if d0 < d1 {
            if useMTV {
                pointSet(_maxTv, updateDimIdx, -d0) // b is on the right/bottom(larger x/y)
            }
            if clamp == true {
                // PORT-TODO: upstream assumes outIntersectRect is present whenever clamp is set.
                rectXYSet(outIntersectRect!, updateDimIdx, a1)
                rectWHSet(outIntersectRect!, updateDimIdx, 0)
            }
        }
        else {
            if useMTV {
                pointSet(_maxTv, updateDimIdx, d1) // b is on the left/top(smaller x/y)
            }
            if clamp == true {
                rectXYSet(outIntersectRect!, updateDimIdx, a0)
                rectWHSet(outIntersectRect!, updateDimIdx, 0)
            }
        }
    }
    else { // Has intersection
        if let outIntersectRect = outIntersectRect {
            let updateVal = mathMax(a0, b0)
            rectXYSet(outIntersectRect, updateDimIdx, updateVal)
            rectWHSet(outIntersectRect, updateDimIdx, mathMin(a1, b1) - updateVal)
        }
        if useMTV {
            if d01min < _lenMinMax[0] || _intersectCtx.useDir {
                // If bidirectional, both dist0 dist1 need to check,
                // otherwise only check the smaller one.
                _lenMinMax[0] = mathMin(d01min, _lenMinMax[0])
                if d0 < d1 || !_intersectCtx.bidirectional {
                    pointSet(_minTv, updateDimIdx, d0) // b is on the right/bottom(larger x/y)
                    pointSet(_minTv, zeroDimIdx, 0)
                    if _intersectCtx.useDir {
                        _intersectCtx.calcDirMTV()
                    }
                }
                if d0 >= d1 || !_intersectCtx.bidirectional {
                    pointSet(_minTv, updateDimIdx, -d1) // b is on the left/top(smaller x/y)
                    pointSet(_minTv, zeroDimIdx, 0)
                    if _intersectCtx.useDir {
                        _intersectCtx.calcDirMTV()
                    }
                }
            }
        }
    }
}


// export type RectLike = { x, y, width, height }
// PORT-NOTE: upstream RectLike is a structural type that plain objects also satisfy. We
// constrain it to AnyObject so (a) mutation through a `RectLike` existential propagates to
// the caller (the out-param `outIntersectRect`/`target` pattern relies on this) and (b)
// identity comparison `target !== source` in `applyTransform` is expressible.
public protocol RectLike: AnyObject {
    var x: Double { get set }
    var y: Double { get set }
    var width: Double { get set }
    var height: Double { get set }
}

// Concrete reference holder for `plain()` (upstream returns an anonymous object literal).
private final class _PlainRect: RectLike {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public struct BoundingRectIntersectOpt {
    /**
     * If specified, when overlapping, the output `mtv` is still a minimal vector that can resolve the overlap.
     * However it is not Minimum Translation Vector, but a vector follow the direction.
     * Be a radian, representing a vector direction.
     * `direction=atan2(y, x)`, i.e., `direction=0` is vector(1,0), `direction=PI/4` is vector(1,1).
     */
    public var direction: Double?
    /**
     * By default `true`. It means whether `BoundingRectIntersectOpt['direction']` is bidirectional. If `true`,
     * the returned mtv is the minimal among both `opt.direction` and `opt.direction + Math.PI`.
     */
    public var bidirectional: Bool?
    /**
     * Two rects that touch but are within the threshold do not be considered an intersection.
     * Scenarios:
     *  - Without a `touchThreshold`, zero-width/height can still cause intersection.
     *    In some scenarios, a rect with border styles still needs to display even if width/height is zero;
     *    but in some other scenarios, zero-width/height represents "nothing", such as in HTML
     *    BoundingClientRect, or when zrender.Group has all children `ignored: true`. In this case, we can use
     *    a non-negative `touchThreshold` to form a "minus width/height" and force it to never cause an
     *    intersection. And in this case, mtv will not be calculated.
     *  - Without a `touchThreshold`, touching the edge is considered an intersection.
     *  - Having a `touchThreshold`, elements can use the same rect instance to achieve compact layout while
     *    still passing through the overlap-hiding handler.
     *  - a positive near-zero number is commonly used in `touchThreshold` for aggressive overlap handling,
     *    such as:
     *    - Hide one element if overlapping.
     *    - Two elements are vertically touching at top/bottom edges, but are restricted to move along
     *      the horizontal direction to resolve overlap.
     */
    public var touchThreshold: Double?

    /**
     * - If an intersection occur, set the intersection rect to it.
     * - Otherwise,
     *   - If `clamp: true`, `outIntersectRect` is set with a clamped rect that is on the edge or corner
     *     of the first rect input to `intersect` method.
     *   - Otherwise, set to all NaN (it will not pass `contain` and `intersect`).
     */
    public var outIntersectRect: RectLike?
    public var clamp: Bool?

    public init(
        direction: Double? = nil,
        bidirectional: Bool? = nil,
        touchThreshold: Double? = nil,
        outIntersectRect: RectLike? = nil,
        clamp: Bool? = nil
    ) {
        self.direction = direction
        self.bidirectional = bidirectional
        self.touchThreshold = touchThreshold
        self.outIntersectRect = outIntersectRect
        self.clamp = clamp
    }
}

/**
 * [CAVEAT] Do not use it other than in `BoundingRect` and `OrientedBoundingRect`.
 */
// PORT-NOTE: upstream returns a closure-based object literal `_ctx` capturing `_direction`,
// `_dirCheckVec`, `_dirTmp`, and `nearZero`. Modeled as a `final class` with those as private
// members so call sites (`_intersectCtx.reset(...)`, `.calcDirMTV()`) stay identical.
public func createIntersectContext() -> IntersectContext {
    return IntersectContext()
}

public final class IntersectContext {

    fileprivate var _direction: Double = 0
    fileprivate let _dirCheckVec = Point()
    fileprivate let _dirTmp = Point()

    public let minTv = Point()
    public let maxTv = Point()
    public var useDir: Bool = false
    public let dirMinTv = Point()
    public var touchThreshold: Double = 0
    public var bidirectional: Bool = true

    public var negativeSize: Bool = false

    public func reset(_ opt: BoundingRectIntersectOpt?, _ useMTV: Bool) {
        touchThreshold = 0
        if let opt = opt, opt.touchThreshold != nil {
            touchThreshold = mathMax(0, opt.touchThreshold!)
        }
        negativeSize = false

        if !useMTV {
            return
        }

        minTv.set(Double.infinity, Double.infinity)
        maxTv.set(0, 0)
        useDir = false

        if let opt = opt, opt.direction != nil {
            useDir = true
            dirMinTv.copy(minTv)
            _dirTmp.copy(minTv)
            _direction = opt.direction!
            bidirectional = opt.bidirectional == nil || opt.bidirectional!
            if !bidirectional {
                _dirCheckVec.set(cos(_direction), sin(_direction))
            }
        }
    }

    public func calcDirMTV() {
        let minTv = self.minTv
        let dirMinTv = self.dirMinTv
        let squareMag = minTv.y * minTv.y + minTv.x * minTv.x
        let dirSin = sin(_direction)
        let dirCos = cos(_direction)
        let dotProd = dirSin * minTv.y + dirCos * minTv.x

        if nearZero(dotProd) {
            if nearZero(minTv.x) && nearZero(minTv.y) {
                // The two OBBs touch at the edges.
                dirMinTv.set(0, 0)
            }
            // Otherwise `minTv` is perpendicular to `this.direction`.
            return
        }

        _dirTmp.x = squareMag * dirCos / dotProd
        _dirTmp.y = squareMag * dirSin / dotProd
        if nearZero(_dirTmp.x) && nearZero(_dirTmp.y) {
            // The result includes near-(0,0) regardless of `bidirectional`.
            dirMinTv.set(0, 0)
            return
        }

        if (
                bidirectional
                || _dirCheckVec.dot(_dirTmp) > 0
            )
            && _dirTmp.len() < dirMinTv.len()
        {
            dirMinTv.copy(_dirTmp)
        }
    }

    private func nearZero(_ val: Double) -> Bool {
        return mathAbs(val) < 1e-10 // Empirically OK for pixel-scale values.
    }
}
