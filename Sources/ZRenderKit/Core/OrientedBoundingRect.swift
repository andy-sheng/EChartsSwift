// Ported from zrender/src/core/OrientedBoundingRect.ts — keep in sync with upstream.

import Foundation

// upstream: import Point, { PointLike } from './Point';
// upstream: import BoundingRect, { BoundingRectIntersectOpt, createIntersectContext } from './BoundingRect';
// upstream: import { MatrixArray } from './matrix';  (MatrixArray = [Double], owned by matrix.swift)

@inline(__always) private func mathMin(_ a: Double, _ b: Double) -> Double { return Swift.min(a, b) }
@inline(__always) private func mathMax(_ a: Double, _ b: Double) -> Double { return Swift.max(a, b) }
@inline(__always) private func mathAbs(_ a: Double) -> Double { return Swift.abs(a) }

// upstream module-level scratch arrays. OBB projects corners onto an axis and writes the
// [min, max] extent into these. Kept file-private (upstream `_extent`/`_extent2`).
private var _extent: [Double] = [0, 0]
private var _extent2: [Double] = [0, 0]

// upstream: `const _intersectCtx = createIntersectContext();` — OBB owns its OWN intersect
// context, distinct from the one in BoundingRect.swift (which is file-private there).
private let _intersectCtx = createIntersectContext()
private let _minTv = _intersectCtx.minTv
private let _maxTv = _intersectCtx.maxTv

public final class OrientedBoundingRect {

    // lt, rt, rb, lb
    private var _corners: [Point] = []

    private var _axes: [Point] = []

    private var _origin: [Double] = [0, 0]

    public init(_ rect: BoundingRect? = nil, _ transform: MatrixArray? = nil) {
        for _ in 0..<4 {
            self._corners.append(Point())
        }
        for _ in 0..<2 {
            self._axes.append(Point())
        }

        if let rect = rect {
            self.fromBoundingRect(rect, transform)
        }
    }

    public func fromBoundingRect(_ rect: BoundingRect, _ transform: MatrixArray? = nil) {
        let corners = self._corners
        let axes = self._axes
        let x = rect.x
        let y = rect.y
        let x2 = x + rect.width
        let y2 = y + rect.height
        corners[0].set(x, y)
        corners[1].set(x2, y)
        corners[2].set(x2, y2)
        corners[3].set(x, y2)

        if let transform = transform {
            for i in 0..<4 {
                corners[i].transform(transform)
            }
        }

        // Calculate axes
        Point.sub(axes[0], corners[1], corners[0])
        Point.sub(axes[1], corners[3], corners[0])
        axes[0].normalize()
        axes[1].normalize()

        // Calculate projected origin
        for i in 0..<2 {
            self._origin[i] = axes[i].dot(corners[0])
        }
    }

    /**
     * If intersect with another OBB.
     *
     * [NOTICE]
     *  Touching the edge is considered an intersection.
     *  zero-width/height can still cause intersection if `touchThreshold` is 0.
     *  See more in `BoundingRectIntersectOpt['touchThreshold']`
     *
     * @param other Bounding rect to be intersected with
     * @param mtv
     *  If it's not overlapped. it means needs to move `other` rect with Maximum Translation Vector to be overlapped.
     *      FIXME: Maximum Translation Vector is buggy. Fix it before using it. See case in `test/obb-collide.html`.
     *  Else it means needs to move `other` rect with Minimum Translation Vector to be not overlapped.
     */
    @discardableResult
    public func intersect(
        _ other: OrientedBoundingRect,
        _ mtv: PointLike? = nil,
        _ opt: BoundingRectIntersectOpt? = nil
    ) -> Bool {
        // OBB collision with SAT method

        var overlapped = true
        let noMtv = mtv == nil

        if let mtv = mtv {
            Point.set(mtv, 0, 0)
        }

        _intersectCtx.reset(opt, !noMtv)

        // Check two axes for both two obb.
        if !self._intersectCheckOneSide(self, other, noMtv, 1) {
            overlapped = false
            if noMtv {
                // Early return if no need to calculate mtv
                return overlapped
            }
        }
        if !self._intersectCheckOneSide(other, self, noMtv, -1) {
            overlapped = false
            if noMtv {
                return overlapped
            }
        }

        if !noMtv && !_intersectCtx.negativeSize {
            Point.copy(
                mtv!,
                overlapped
                    ? (_intersectCtx.useDir ? _intersectCtx.dirMinTv : _minTv)
                    : _maxTv
            )
        }

        return overlapped
    }

    // [CAVEAT] Must not use `self` in this method (upstream operates only on `selfObb`/`otherObb`).
    private func _intersectCheckOneSide(
        _ selfObb: OrientedBoundingRect,
        _ otherObb: OrientedBoundingRect,
        _ noMtv: Bool,
        _ inverse: Double  // 1 | -1
    ) -> Bool {

        var overlapped = true
        for i in 0..<2 {
            let axis = selfObb._axes[i]
            selfObb._getProjMinMaxOnAxis(i, selfObb._corners, &_extent)
            selfObb._getProjMinMaxOnAxis(i, otherObb._corners, &_extent2)

            // Following the behavior in `BoundingRect.ts`, touching the edge is considered
            //  an overlap, but get a mtv [0, 0].
            if _intersectCtx.negativeSize || _extent[1] < _extent2[0] || _extent[0] > _extent2[1] {
                // Not overlap on the any axis.
                overlapped = false
                if _intersectCtx.negativeSize || noMtv {
                    return overlapped
                }
                let dist0 = mathAbs(_extent2[0] - _extent[1])
                let dist1 = mathAbs(_extent[0] - _extent2[1])

                // Find longest distance of all axes.
                if mathMin(dist0, dist1) > _maxTv.len() {
                    if dist0 < dist1 {
                        Point.scale(_maxTv, axis, -dist0 * inverse)
                    }
                    else {
                        Point.scale(_maxTv, axis, dist1 * inverse)
                    }
                }
            }
            else if !noMtv {
                let dist0 = mathAbs(_extent2[0] - _extent[1])
                let dist1 = mathAbs(_extent[0] - _extent2[1])

                if _intersectCtx.useDir || mathMin(dist0, dist1) < _minTv.len() {
                    // If bidirectional, both dist0 dist1 need to check,
                    // otherwise only check the smaller one.
                    if dist0 < dist1 || !_intersectCtx.bidirectional {
                        Point.scale(_minTv, axis, dist0 * inverse)
                        if _intersectCtx.useDir {
                            _intersectCtx.calcDirMTV()
                        }
                    }
                    if dist0 >= dist1 || !_intersectCtx.bidirectional {
                        Point.scale(_minTv, axis, -dist1 * inverse)
                        if _intersectCtx.useDir {
                            _intersectCtx.calcDirMTV()
                        }
                    }
                }
            }
        }
        return overlapped
    }

    private func _getProjMinMaxOnAxis(_ dim: Int, _ corners: [Point], _ out: inout [Double]) {
        let axis = self._axes[dim]
        let origin = self._origin
        let proj0 = corners[0].dot(axis) + origin[dim]
        var min = proj0
        var max = proj0

        for i in 1..<corners.count {
            let proj = corners[i].dot(axis) + origin[dim]
            min = mathMin(proj, min)
            max = mathMax(proj, max)
        }

        out[0] = min + _intersectCtx.touchThreshold
        out[1] = max - _intersectCtx.touchThreshold

        _intersectCtx.negativeSize = out[1] < out[0]
    }
}
