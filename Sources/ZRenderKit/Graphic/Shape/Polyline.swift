// Ported from zrender/src/graphic/shape/Polyline.ts — keep in sync with upstream
//
// @module zrender/graphic/shape/Polyline

import Foundation

// upstream:
//   import Path, { PathProps } from '../Path';
//   import * as polyHelper from '../helper/poly';
//   import { VectorArray } from '../../core/vector';

// upstream: export class PolylineShape {
//     points = null
//     percent? = 1   // Percent of displayed polyline. For animating purpose
//     smooth? = 0
//     smoothConstraint? = null
//   }
//   Conforms to `PathShape` (the per-subclass shape marker, see Path.swift GENERICS DECISION) and
//   to `PolyBuildPathShape` (the structural input to poly.buildPath).
public struct PolylineShape: PathShape, PolyBuildPathShape {
    public var points: [VectorArray]? = nil
    // Percent of displayed polyline. For animating purpose
    public var percent: Double? = 1
    public var smooth: Double? = 0
    public var smoothConstraint: [VectorArray]? = nil

    public init() {}

    // Keyed access for animateTo({shape: {...}}). Upstream animates `points` as an array; here the
    //   value-type `[VectorArray]` is exposed as a `[[Double]]` (the shape the Animator's 2D-array
    //   interpolation consumes — see Animator.interpolate2DArray) and accepts `[[Double]]` or
    //   `[VectorArray]` on set. This is the line/area morph case. `percent` (draw-on) and `smooth`
    //   are numeric fields.
    // PORT-NOTE: `smoothConstraint` ([VectorArray]) is not exposed for keyed animation.
    public func animationGet(_ key: String) -> Any? {
        switch key {
        case "points":
            guard let pts = points else { return nil }
            return pts.map { [$0.x, $0.y] }
        case "percent": return percent
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
        case "percent":
            if let v = value as? Double { percent = v }
        case "smooth":
            if let v = value as? Double { smooth = v }
        default: break
        }
    }
}

// upstream: export interface PolylineProps extends PathProps { shape?: Partial<PolylineShape> }
// PORT-NOTE: PolylineProps (typed-interface fidelity) collapses onto the dynamic PathProps bag.
public typealias PolylineProps = PathProps

// upstream: class Polyline extends Path<PolylineProps>
public final class Polyline: Path {

    // upstream: shape: PolylineShape — narrows the inherited `shape: PathShape!`.

    // upstream: constructor(opts?: PolylineProps) { super(opts); }
    public override init(_ opts: ElementProps? = nil) {
        super.init(opts)
        // upstream: Polyline.prototype.type = 'polyline';
        self.type = "polyline"
    }

    // upstream: getDefaultStyle() { return { stroke: '#000', fill: null as string }; }
    public override func getDefaultStyle() -> PathStyleProps? {
        var style = PathStyleProps()
        style.stroke = .string("#000")
        style.fill = nil   // upstream: fill: null as string
        return style
    }

    public override func getDefaultShape() -> PathShape {
        return PolylineShape()
    }

    public override func buildPath(_ ctx: PathProxy, _ shape: PathShape, _ inBatch: Bool) {
        let shape = shape as! PolylineShape
        poly.buildPath(ctx, shape, false)
    }
}

// upstream: export default Polyline;
