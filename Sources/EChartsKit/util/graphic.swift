// Ported from echarts/src/util/graphic.ts — keep in sync with upstream
// (Partial: only `expandOrShrinkRect` / `expandRectOnOneDimension` are landed here so far.
//  PORT-NOTE (deferred): the rest of util/graphic.ts — createIcon/setTooltipConfig/getTransformedTouches
//  etc. — is not ported here yet.)

import Foundation
import ZRenderKit

// upstream: export function expandOrShrinkRect<TRect extends RectLike>(rect, delta, shrinkOrExpand, noNegative, minSize?)
//   Grows (or shrinks, when `shrinkOrExpand`) `rect` on each side. `delta` is a scalar (applied to all four
//   sides) or a `[top, right, bottom, left]` array; `noNegative` clamps the deltas to >= 0. `minSize`
//   ([w, h], default [0, 0]) is the floor each dimension collapses to. Mutates `rect` IN PLACE — matching the
//   JS (BoundingRect is a reference type). Returns the same rect for chaining.
@discardableResult
public func expandOrShrinkRect(
    _ rect: RectLike,
    _ delta: Any?,
    _ shrinkOrExpand: Bool,
    _ noNegative: Bool,
    _ minSize: [Double]? = nil
) -> RectLike {
    // if (delta == null) { return rect; }
    guard let delta = delta else { return rect }
    var d: [Double]
    if let n = delta as? Double {
        d = [n, n, n, n]
    }
    else if let i = delta as? Int {
        let n = Double(i); d = [n, n, n, n]
    }
    else if let arr = delta as? [Double], arr.count == 4 {
        d = arr
    }
    else if let arr = delta as? [Any], arr.count == 4 {
        d = arr.map { ($0 as? Double) ?? Double(($0 as? Int) ?? 0) }
    }
    else {
        return rect
    }
    // if (noNegative) { each delta = max(0, delta) }
    if noNegative {
        for k in 0..<4 { d[k] = Swift.max(0, d[k]) }
    }
    // if (shrinkOrExpand) { negate each delta }
    if shrinkOrExpand {
        for k in 0..<4 { d[k] = -d[k] }
    }
    // expandRectOnOneDimension(rect, delta, 'x', 'width', 3, 1, minSize?[0] || 0);
    expandRectOnOneDimension(rect, d, true, 3, 1, (minSize.flatMap { $0.count > 0 ? $0[0] : nil }) ?? 0)
    // expandRectOnOneDimension(rect, delta, 'y', 'height', 0, 2, minSize?[1] || 0);
    expandRectOnOneDimension(rect, d, false, 0, 2, (minSize.flatMap { $0.count > 1 ? $0[1] : nil }) ?? 0)
    return rect
}

// upstream: const AXIS_ALIGN_EPSILON = 1e-5;
private let AXIS_ALIGN_EPSILON = 1e-5

/// upstream: export function isBoundingRectAxisAligned(transform)
/// After a boundingRect applying a `transform`, whether to be still parallel screen X and Y.
public func isBoundingRectAxisAligned(_ transform: MatrixArray?) -> Bool {
    guard let transform = transform else { return true }
    return (Swift.abs(transform[1]) < AXIS_ALIGN_EPSILON && Swift.abs(transform[2]) < AXIS_ALIGN_EPSILON)
        || (Swift.abs(transform[0]) < AXIS_ALIGN_EPSILON && Swift.abs(transform[3]) < AXIS_ALIGN_EPSILON)
}

/// upstream: export function ensureCopyRect(target, source)
/// Create or copy to the existing bounding rect to avoid modifying `source`.
public func ensureCopyRect(_ target: BoundingRect?, _ source: BoundingRect) -> BoundingRect {
    if let target = target {
        return BoundingRect.copy(target, source)
    }
    return source.clone()
}

/// upstream: export function ensureCopyTransform(target, source)
/// Create or copy to the existing transform to avoid modifying `source`. `nil` if no transform,
/// following zrender's convention (enables bypassing unnecessary calculation).
/// PORT-NOTE: `matrix.copy` is value-returning here (CONVENTIONS §3), so the incoming `target`
/// scratch buffer is unused and a fresh MatrixArray is returned.
public func ensureCopyTransform(_ target: MatrixArray?, _ source: MatrixArray?) -> MatrixArray? {
    guard let source = source else { return nil }
    return matrix.copy(source)
}

// upstream: function expandRectOnOneDimension(rect, delta, xy, wh, ltIdx, rbIdx, minSize)
//   `isX` selects the x/width pair (true) vs y/height (false). `ltIdx`/`rbIdx` index the left-top /
//   right-bottom delta for that dimension.
private func expandRectOnOneDimension(
    _ rect: RectLike, _ delta: [Double], _ isX: Bool, _ ltIdx: Int, _ rbIdx: Int, _ minSizeIn: Double
) {
    let deltaSum = delta[rbIdx] + delta[ltIdx]
    let oldSize = isX ? rect.width : rect.height
    var newSize = oldSize + deltaSum
    // minSize = max(0, min(minSize, oldSize));
    let minSize = Swift.max(0, Swift.min(minSizeIn, oldSize))
    if newSize < minSize {
        newSize = minSize
        // Try to make the position of the zero rect reasonable in most visual cases.
        let shift: Double =
            delta[ltIdx] >= 0 ? -delta[ltIdx]
            : delta[rbIdx] >= 0 ? oldSize + delta[rbIdx]
            : Swift.abs(deltaSum) > 1e-8 ? (oldSize - minSize) * delta[ltIdx] / deltaSum
            : 0
        if isX { rect.x += shift } else { rect.y += shift }
    }
    else {
        if isX { rect.x -= delta[ltIdx] } else { rect.y -= delta[ltIdx] }
    }
    if isX { rect.width = newSize } else { rect.height = newSize }
}

// ============================================================================
// Transform helpers (upstream util/graphic.ts:331-394) — the pieces the brush cover-drag
// (component/helper/BrushController) needs: the accumulated ancestor transform of an element, a
// vertex transform, and the "which global edge is my local edge" cursor mapping.
// ============================================================================

// upstream: export function getTransform(target: Transformable, ancestor?: Transformable): matrix.MatrixArray
public func getTransform(_ target: Transformable?, _ ancestor: Transformable? = nil) -> MatrixArray {
    // const mat = matrix.identity([]);
    var mat = matrix.identity()

    var target = target
    // while (target && target !== ancestor) { matrix.mul(mat, target.getLocalTransform(), mat); target = target.parent; }
    //   CONVENTIONS §3: `matrix.mul(out, m1, m2)` is value-returning here, so the self-aliased
    //   `mul(mat, ..., mat)` becomes `mat = mul(..., mat)`.
    while let t = target, t !== ancestor {
        mat = matrix.mul(t.getLocalTransform(), mat)
        target = t.parent
    }

    return mat
}

/**
 * Apply transform to an vertex.
 * @param target [x, y]
 * @param transform Transform matrix: like [1, 0, 0, 1, 0, 0]
 * @param invert Whether use invert matrix.
 * @return [x, y]
 */
// upstream: export function applyTransform(target, transform: Transformable | matrix.MatrixArray, invert?)
//   PORT-NOTE: the `Transformable` arm of the union (`transform = Transformable.getLocalTransform(transform)`)
//   is dropped — every call site in the ported code passes a MatrixArray. Pass
//   `Transformable.getLocalTransform(t)` explicitly if a Transformable is ever needed.
public func applyTransform(
    _ target: VectorArray,
    _ transform: MatrixArray?,
    _ invert: Bool? = nil
) -> [Double] {
    var transform = transform

    if invert == true, let t = transform {
        // transform = matrix.invert([], transform);
        transform = matrix.invert(t)
    }

    // return vector.applyTransform([], target, transform);
    guard let t = transform else { return [target[0], target[1]] }
    let out = vector.applyTransform(target, t)
    return [out[0], out[1]]
}

// upstream: export function transformDirection(direction, transform, invert?): 'left'|'right'|'top'|'bottom'
public func transformDirection(
    _ direction: String,
    _ transform: MatrixArray,
    _ invert: Bool? = nil
) -> String {

    // Pick a base, ensure that transform result will not be (0, 0).
    let hBase: Double = (transform[4] == 0 || transform[5] == 0 || transform[0] == 0)
        ? 1 : Swift.abs(2 * transform[4] / transform[0])
    let vBase: Double = (transform[4] == 0 || transform[5] == 0 || transform[2] == 0)
        ? 1 : Swift.abs(2 * transform[4] / transform[2])

    var vertex: VectorArray = VectorArray(
        direction == "left" ? -hBase : direction == "right" ? hBase : 0,
        direction == "top" ? -vBase : direction == "bottom" ? vBase : 0
    )

    let applied = applyTransform(vertex, transform, invert)
    vertex = VectorArray(applied[0], applied[1])

    return Swift.abs(vertex[0]) > Swift.abs(vertex[1])
        ? (vertex[0] > 0 ? "right" : "left")
        : (vertex[1] > 0 ? "bottom" : "top")
}

// upstream: export function clipPointsByRect(points: vector.VectorArray[], rect: ZRRectLike): number[][]
public func clipPointsByRect(_ points: [[Double]], _ rect: RectLike) -> [[Double]] {
    // FIXME: This way might be incorrect when graphic clipped by a corner
    // and when element has a border.
    return util.map(points) { point, _ in
        var x = point[0]
        x = Swift.max(x, rect.x)
        x = Swift.min(x, rect.x + rect.width)
        var y = point[1]
        y = Swift.max(y, rect.y)
        y = Swift.min(y, rect.y + rect.height)
        return [x, y]
    }
}

/**
 * Return `true` if the given line (line `a`) and the given polygon
 * are intersect.
 * Note that we do not count colinear as intersect here because no
 * requirement for that. We could do that if required in future.
 */
// upstream: export function linePolygonIntersect(a1x, a1y, a2x, a2y, points): boolean
public func linePolygonIntersect(
    _ a1x: Double, _ a1y: Double, _ a2x: Double, _ a2y: Double,
    _ points: [[Double]]
) -> Bool {
    if points.isEmpty { return false }
    var p2 = points[points.count - 1]
    for i in 0..<points.count {
        let p = points[i]
        if lineLineIntersect(a1x, a1y, a2x, a2y, p[0], p[1], p2[0], p2[1]) {
            return true
        }
        p2 = p
    }
    // upstream falls off the end -> `undefined` (falsy).
    return false
}

/**
 * Return `true` if the given two lines (line `a` and line `b`)
 * are intersect.
 * Note that we do not count colinear as intersect here because no
 * requirement for that. We could do that if required in future.
 */
// upstream: export function lineLineIntersect(a1x, a1y, a2x, a2y, b1x, b1y, b2x, b2y): boolean
public func lineLineIntersect(
    _ a1x: Double, _ a1y: Double, _ a2x: Double, _ a2y: Double,
    _ b1x: Double, _ b1y: Double, _ b2x: Double, _ b2y: Double
) -> Bool {
    // let `vec_m` to be `vec_a2 - vec_a1` and `vec_n` to be `vec_b2 - vec_b1`.
    let mx = a2x - a1x
    let my = a2y - a1y
    let nx = b2x - b1x
    let ny = b2y - b1y

    // `vec_m` and `vec_n` are parallel iff
    //     existing `k` such that `vec_m = k · vec_n`, equivalent to `vec_m X vec_n = 0`.
    let nmCrossProduct = crossProduct2d(nx, ny, mx, my)
    if nearZero(nmCrossProduct) {
        return false
    }

    // `vec_m` and `vec_n` are intersect iff
    //     existing `p` and `q` in [0, 1] such that `vec_a1 + p * vec_m = vec_b1 + q * vec_n`,
    //     such that `q = ((vec_a1 - vec_b1) X vec_m) / (vec_n X vec_m)`
    //           and `p = ((vec_a1 - vec_b1) X vec_n) / (vec_n X vec_m)`.
    let b1a1x = a1x - b1x
    let b1a1y = a1y - b1y
    let q = crossProduct2d(b1a1x, b1a1y, mx, my) / nmCrossProduct
    if q < 0 || q > 1 {
        return false
    }
    let p = crossProduct2d(b1a1x, b1a1y, nx, ny) / nmCrossProduct
    if p < 0 || p > 1 {
        return false
    }

    return true
}

/**
 * Cross product of 2-dimension vector.
 */
// upstream: function crossProduct2d(x1, y1, x2, y2)
private func crossProduct2d(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) -> Double {
    return x1 * y2 - x2 * y1
}

// upstream: function nearZero(val)
private func nearZero(_ val: Double) -> Bool {
    return val <= 1e-6 && val >= -1e-6
}

// ============================================================================
// The name -> shape-class registry (upstream util/graphic.ts:95-175 + the registrations at :952-960).
//
// `graphic: [{ type: 'polygon', ... }]` names its element by STRING; upstream resolves it through
// this map. It was never ported, so GraphicView could only build group/image/text and asserted on
// everything else — `graphic type polygon can not be found`. 14 official examples use `graphic`.
// ============================================================================

// const _customShapeMap: Dictionary<{ new(): Path }> = {};
//   -> the value is a FACTORY, not a metatype: ZRenderKit's shapes take `init(_ opts: ElementProps?)`,
//      and Swift cannot express "a Path subclass constructible from opts" as a single existential.
private var _customShapeMap: [String: (ElementProps?) -> Path] = [
    // registerShape('circle', Circle); … (upstream util/graphic.ts:952-960)
    "circle":      { Circle($0) },
    "ellipse":     { Ellipse($0) },
    "sector":      { Sector($0) },
    "ring":        { Ring($0) },
    "polygon":     { Polygon($0) },
    "polyline":    { Polyline($0) },
    "rect":        { Rect($0) },
    "line":        { Line($0) },
    "bezierCurve": { BezierCurve($0) }
]

// export function registerShape(name: string, ShapeClass: {new(): Path})
public func registerShape(_ name: String, _ factory: @escaping (ElementProps?) -> Path) {
    _customShapeMap[name] = factory
}

// export function getShapeClass(name: string): {new(): Path}
//   -> returns the FACTORY (see above); nil when the name is unknown, exactly as upstream returns
//      `undefined` (its callers assert on it in DEV).
public func getShapeClass(_ name: String) -> ((ElementProps?) -> Path)? {
    return _customShapeMap[name]
}
