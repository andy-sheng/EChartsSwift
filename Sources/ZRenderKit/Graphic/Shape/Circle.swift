// Ported from zrender/src/graphic/shape/Circle.ts — keep in sync with upstream

import Foundation

// upstream import: import Path, { PathProps } from '../Path';

/**
 * 圆形
 */

// upstream: export class CircleShape { cx = 0; cy = 0; r = 0 }
//   Modeled as a `PathShape`-conforming struct per the GENERICS DECISION in Path.swift.
public struct CircleShape: PathShape {
    public var cx: Double = 0
    public var cy: Double = 0
    public var r: Double = 0
    public init() {}

    // Keyed access for animateTo({shape: {...}}) — exposes the animatable numeric fields
    //   (mirrors RectShape; see Path.swift ShapeAnimationAccessor).
    public func animationGet(_ key: String) -> Any? {
        switch key {
        case "cx": return cx
        case "cy": return cy
        case "r": return r
        default: return nil
        }
    }

    public mutating func animationSet(_ key: String, _ value: Any?) {
        guard let v = value as? Double else { return }
        switch key {
        case "cx": cx = v
        case "cy": cy = v
        case "r": r = v
        default: break
        }
    }
}

// upstream: export interface CircleProps extends PathProps { shape?: Partial<CircleShape> }
//   PathProps collapses onto DisplayableProps (see Path.swift); typed-shape fidelity dropped.
public typealias CircleProps = PathProps

// upstream: class Circle extends Path<CircleProps>
public final class Circle: Path {

    // upstream: shape: CircleShape — narrows the inherited `shape: PathShape` per subclass.
    //   Swift cannot re-type the inherited stored property; the typed shape is read via downcast
    //   inside `buildPath` (the documented GENERICS deviation).

    // upstream: constructor(opts?: CircleProps) { super(opts); }
    public override init(_ opts: CircleProps? = nil) {
        super.init(opts)
        self.type = "circle"   // upstream: Circle.prototype.type = 'circle'
    }

    public override func getDefaultShape() -> PathShape {
        return CircleShape()
    }

    public override func buildPath(_ ctx: PathProxy, _ shape: PathShape, _ inBatch: Bool) {
        let shape = shape as! CircleShape
        // Use moveTo to start a new sub path.
        // Or it will be connected to other subpaths when in CompoundPath
        _ = ctx.moveTo(shape.cx + shape.r, shape.cy)
        _ = ctx.arc(shape.cx, shape.cy, shape.r, 0, Double.pi * 2)
    }
}

// upstream: export default Circle;
