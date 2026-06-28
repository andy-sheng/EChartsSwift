// Ported from zrender/src/graphic/shape/Heart.ts — keep in sync with upstream

/**
 * 心形
 */

import Foundation

// upstream import: import Path, { PathProps } from '../Path';

// upstream: export class HeartShape { cx = 0; cy = 0; width = 0; height = 0 }
//   A plain parameter bag → `struct` conforming to the `PathShape` marker
//   (CONVENTIONS §4 / Path.swift GENERICS DECISION).
public struct HeartShape: PathShape {
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

// upstream: export interface HeartProps extends PathProps { shape?: Partial<HeartShape> }
//   PathProps collapses onto DisplayableProps (see Path.swift); typed-shape fidelity dropped.
public typealias HeartProps = PathProps

// upstream: class Heart extends Path<HeartProps>
public final class Heart: Path {

    // upstream: shape: HeartShape — narrows the inherited `shape: PathShape` per subclass.
    //   The typed shape is read via downcast inside `buildPath` (the documented GENERICS deviation).

    // upstream: constructor(opts?: HeartProps) { super(opts); }
    public override init(_ opts: HeartProps? = nil) {
        super.init(opts)
        self.type = "heart"   // upstream: Heart.prototype.type = 'heart'
    }

    public override func getDefaultShape() -> PathShape {
        return HeartShape()
    }

    public override func buildPath(_ ctx: PathProxy, _ shape: PathShape, _ inBatch: Bool) {
        let shape = shape as! HeartShape
        let x = shape.cx
        let y = shape.cy
        let a = shape.width
        let b = shape.height
        _ = ctx.moveTo(x, y)
        _ = ctx.bezierCurveTo(
            x + a / 2, y - b * 2 / 3,
            x + a * 2, y + b / 3,
            x, y + b
        )
        _ = ctx.bezierCurveTo(
            x - a * 2, y + b / 3,
            x - a / 2, y - b * 2 / 3,
            x, y
        )
    }
}

// upstream: export default Heart;
