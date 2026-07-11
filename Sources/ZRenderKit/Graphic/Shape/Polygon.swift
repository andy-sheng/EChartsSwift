// Ported from zrender/src/graphic/shape/Polygon.ts — keep in sync with upstream
//
// 多边形
// @module zrender/shape/Polygon

import Foundation

// upstream:
//   import Path, { PathProps } from '../Path';
//   import * as polyHelper from '../helper/poly';
//   import { VectorArray } from '../../core/vector';

// upstream: export class PolygonShape { points = null; smooth? = 0; smoothConstraint? = null }
//   Conforms to `PathShape` (the per-subclass shape marker, see Path.swift GENERICS DECISION) and
//   to `PolyBuildPathShape` (the structural input to poly.buildPath).
public struct PolygonShape: PathShape, PolyBuildPathShape {
    public var points: [VectorArray]? = nil
    public var smooth: Double? = 0
    public var smoothConstraint: [VectorArray]? = nil

    public init() {}

    // Keyed access for animateTo({shape: {...}}). Upstream animates `points` as an array; here the
    //   value-type `[VectorArray]` is exposed as a `[[Double]]` (the shape the Animator's 2D-array
    //   interpolation consumes — see Animator.interpolate2DArray) and accepts `[[Double]]` or
    //   `[VectorArray]` on set. This is the line/area morph case. `smooth` is a numeric field.
    // PORT-NOTE: `smoothConstraint` ([VectorArray]) is not exposed for keyed animation.
    public func animationGet(_ key: String) -> Any? {
        switch key {
        case "points":
            guard let pts = points else { return nil }
            return pts.map { [$0.x, $0.y] }
        case "smooth": return smooth
        default: return nil
        }
    }

    public mutating func animationSet(_ key: String, _ value: Any?) {
        switch key {
        case "points":
            if let arr = value as? [[Double]] {
                points = arr.map { VectorArray($0.count > 0 ? $0[0] : 0, $0.count > 1 ? $0[1] : 0) }
            }
            else if let arr = value as? [VectorArray] {
                points = arr
            }
        case "smooth":
            if let v = value as? Double { smooth = v }
        default: break
        }
    }
}

// upstream: export interface PolygonProps extends PathProps { shape?: Partial<PolygonShape> }
// PORT-NOTE: PolygonProps (typed-interface fidelity) collapses onto the dynamic PathProps bag.
public typealias PolygonProps = PathProps

// upstream: class Polygon extends Path<PolygonProps>
public final class Polygon: Path {

    // upstream: shape: PolygonShape — narrows the inherited `shape: PathShape!`.

    // upstream: constructor(opts?: PolygonProps) { super(opts); }
    public override init(_ opts: ElementProps? = nil) {
        super.init(opts)
        // upstream: Polygon.prototype.type = 'polygon';
        self.type = "polygon"
    }

    public override func getDefaultShape() -> PathShape {
        return PolygonShape()
    }

    public override func buildPath(_ ctx: PathProxy, _ shape: PathShape, _ inBatch: Bool) {
        let shape = shape as! PolygonShape
        poly.buildPath(ctx, shape, true)
    }
}

// upstream: export default Polygon;
