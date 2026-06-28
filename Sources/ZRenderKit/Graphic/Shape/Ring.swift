// Ported from zrender/src/graphic/shape/Ring.ts — keep in sync with upstream

import Foundation

// upstream import: import Path, { PathProps } from '../Path';

/**
 * 圆环
 */

// upstream: export class RingShape { cx = 0; cy = 0; r = 0; r0 = 0 }
//   A plain parameter bag → `struct` conforming to the `PathShape` marker
//   (CONVENTIONS §4 / Path.swift GENERICS DECISION).
public struct RingShape: PathShape {
    public var cx: Double = 0
    public var cy: Double = 0
    public var r: Double = 0
    public var r0: Double = 0
    public init() {}

    // Keyed access for animateTo({shape: {...}}) — exposes the animatable numeric fields
    //   (mirrors RectShape; see Path.swift ShapeAnimationAccessor).
    public func animationGet(_ key: String) -> Any? {
        switch key {
        case "cx": return cx
        case "cy": return cy
        case "r": return r
        case "r0": return r0
        default: return nil
        }
    }

    public mutating func animationSet(_ key: String, _ value: Any?) {
        guard let v = value as? Double else { return }
        switch key {
        case "cx": cx = v
        case "cy": cy = v
        case "r": r = v
        case "r0": r0 = v
        default: break
        }
    }
}

// upstream: export interface RingProps extends PathProps { shape?: Partial<RingShape> }
//   PathProps collapses onto DisplayableProps (see Path.swift); typed-shape fidelity dropped.
public typealias RingProps = PathProps

// upstream: class Ring extends Path<RingProps>
public final class Ring: Path {

    // upstream: shape: RingShape — narrows the inherited `shape: PathShape`. The typed shape is
    //   read via downcast inside `buildPath` (the documented GENERICS deviation).

    // upstream: constructor(opts?: RingProps) { super(opts); }
    public override init(_ opts: RingProps? = nil) {
        super.init(opts)
        self.type = "ring"   // upstream: Ring.prototype.type = 'ring'
    }

    public override func getDefaultShape() -> PathShape {
        return RingShape()
    }

    public override func buildPath(_ ctx: PathProxy, _ shape: PathShape, _ inBatch: Bool) {
        let shape = shape as! RingShape
        let x = shape.cx
        let y = shape.cy
        let PI2 = Double.pi * 2
        _ = ctx.moveTo(x + shape.r, y)
        _ = ctx.arc(x, y, shape.r, 0, PI2, false)
        _ = ctx.moveTo(x + shape.r0, y)
        _ = ctx.arc(x, y, shape.r0, 0, PI2, true)
    }
}

// upstream: export default Ring;
