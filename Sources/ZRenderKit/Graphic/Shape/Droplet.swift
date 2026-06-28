// Ported from zrender/src/graphic/shape/Droplet.ts — keep in sync with upstream

import Foundation

// upstream import: import Path, { PathProps } from '../Path';

/**
 * 水滴形状
 */

// upstream: export class DropletShape { cx = 0; cy = 0; width = 0; height = 0 }
//   Modeled as a `PathShape`-conforming struct per the GENERICS DECISION in Path.swift.
public struct DropletShape: PathShape {
    public var cx: Double = 0
    public var cy: Double = 0
    public var width: Double = 0
    public var height: Double = 0
    public init() {}

    // Keyed access for animateTo({shape: {...}}) — exposes the animatable numeric fields
    //   (mirrors RectShape; see Path.swift ShapeAnimationAccessor).
    public func animationGet(_ key: String) -> Any? {
        switch key {
        case "cx": return cx
        case "cy": return cy
        case "width": return width
        case "height": return height
        default: return nil
        }
    }

    public mutating func animationSet(_ key: String, _ value: Any?) {
        guard let v = value as? Double else { return }
        switch key {
        case "cx": cx = v
        case "cy": cy = v
        case "width": width = v
        case "height": height = v
        default: break
        }
    }
}

// upstream: export interface DropletProps extends PathProps { shape?: Partial<DropletShape> }
//   PathProps collapses onto DisplayableProps (see Path.swift); typed-shape fidelity dropped.
public typealias DropletProps = PathProps

// upstream: class Droplet extends Path<DropletProps>
public final class Droplet: Path {

    // upstream: shape: DropletShape — narrows the inherited `shape: PathShape` per subclass.
    //   Swift cannot re-type the inherited stored property; the typed shape is read via downcast
    //   inside `buildPath` (the documented GENERICS deviation).

    // upstream: constructor(opts?: DropletProps) { super(opts); }
    public override init(_ opts: DropletProps? = nil) {
        super.init(opts)
        self.type = "droplet"   // upstream: Droplet.prototype.type = 'droplet'
    }

    public override func getDefaultShape() -> PathShape {
        return DropletShape()
    }

    public override func buildPath(_ ctx: PathProxy, _ shape: PathShape, _ inBatch: Bool) {
        let shape = shape as! DropletShape
        let x = shape.cx
        let y = shape.cy
        let a = shape.width
        let b = shape.height

        _ = ctx.moveTo(x, y + a)
        _ = ctx.bezierCurveTo(
            x + a,
            y + a,
            x + a * 3 / 2,
            y - a / 3,
            x,
            y - b
        )
        _ = ctx.bezierCurveTo(
            x - a * 3 / 2,
            y - a / 3,
            x - a,
            y + a,
            x,
            y + a
        )
        _ = ctx.closePath()
    }
}

// upstream: export default Droplet;
