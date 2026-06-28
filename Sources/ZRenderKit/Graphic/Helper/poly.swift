// Ported from zrender/src/graphic/helper/poly.ts — keep in sync with upstream

import Foundation

// upstream:
//   import smoothBezier from './smoothBezier';
//   import { VectorArray } from '../../core/vector';
//   import PathProxy from '../../core/PathProxy';

// upstream models `shape` as an inline anonymous type `{ points, smooth?, smoothConstraint? }`.
//   Shared by Polygon and Polyline shapes — modeled as a protocol both conform to.
// PORT-TODO: upstream's inline structural type → a Swift protocol (no structural typing).
public protocol PolyBuildPathShape {
    var points: [VectorArray]? { get }
    var smooth: Double? { get }
    var smoothConstraint: [VectorArray]? { get }
}

public enum poly {   // upstream alias: `polyHelper`

    public static func buildPath(
        _ ctx: PathProxy,
        _ shape: PolyBuildPathShape,
        _ closePath: Bool
    ) {
        let smooth = shape.smooth
        let points = shape.points
        if let points = points, points.count >= 2 {
            // if (smooth) — JS truthiness: a non-zero, non-NaN number.
            if let smooth = smooth, smooth != 0 && !smooth.isNaN {
                let controlPoints = smoothBezier(
                    points, smooth, closePath, shape.smoothConstraint
                )

                _ = ctx.moveTo(points[0][0], points[0][1])
                let len = points.count
                let count = closePath ? len : len - 1
                for i in 0..<count {
                    let cp1 = controlPoints[i * 2]
                    let cp2 = controlPoints[i * 2 + 1]
                    let p = points[(i + 1) % len]
                    _ = ctx.bezierCurveTo(
                        cp1[0], cp1[1], cp2[0], cp2[1], p[0], p[1]
                    )
                }
            }
            else {
                _ = ctx.moveTo(points[0][0], points[0][1])
                let l = points.count
                for i in 1..<l {
                    _ = ctx.lineTo(points[i][0], points[i][1])
                }
            }

            if closePath {
                _ = ctx.closePath()
            }
        }
    }
}
