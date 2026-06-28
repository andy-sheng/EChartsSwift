// Ported from zrender/src/graphic/shape/Ellipse.ts — keep in sync with upstream

import Foundation

// upstream import: import Path, { PathProps } from '../Path';

/**
 * 椭圆形状
 */

// upstream: export class EllipseShape { cx = 0; cy = 0; rx = 0; ry = 0 }
//   Modeled as a `PathShape`-conforming struct per the GENERICS DECISION in Path.swift.
public struct EllipseShape: PathShape {
    public var cx: Double = 0
    public var cy: Double = 0
    public var rx: Double = 0
    public var ry: Double = 0
    public init() {}

    // Keyed access for animateTo({shape: {...}}) — exposes the animatable numeric fields
    //   (mirrors RectShape; see Path.swift ShapeAnimationAccessor).
    public func animationGet(_ key: String) -> Any? {
        switch key {
        case "cx": return cx
        case "cy": return cy
        case "rx": return rx
        case "ry": return ry
        default: return nil
        }
    }

    public mutating func animationSet(_ key: String, _ value: Any?) {
        guard let v = value as? Double else { return }
        switch key {
        case "cx": cx = v
        case "cy": cy = v
        case "rx": rx = v
        case "ry": ry = v
        default: break
        }
    }
}

// upstream: export interface EllipseProps extends PathProps { shape?: Partial<EllipseShape> }
//   PathProps collapses onto DisplayableProps (see Path.swift); typed-shape fidelity dropped.
public typealias EllipseProps = PathProps

// upstream: class Ellipse extends Path<EllipseProps>
public final class Ellipse: Path {

    // upstream: shape: EllipseShape — narrows the inherited `shape: PathShape` per subclass.
    //   Swift cannot re-type the inherited stored property; the typed shape is read via downcast
    //   inside `buildPath` (the documented GENERICS deviation).

    // upstream: constructor(opts?: EllipseProps) { super(opts); }
    public override init(_ opts: EllipseProps? = nil) {
        super.init(opts)
        self.type = "ellipse"   // upstream: Ellipse.prototype.type = 'ellipse'
    }

    public override func getDefaultShape() -> PathShape {
        return EllipseShape()
    }

    public override func buildPath(_ ctx: PathProxy, _ shape: PathShape, _ inBatch: Bool) {
        let shape = shape as! EllipseShape
        let k = 0.5522848
        let x = shape.cx
        let y = shape.cy
        let a = shape.rx
        let b = shape.ry
        let ox = a * k // 水平控制点偏移量
        let oy = b * k // 垂直控制点偏移量
        // 从椭圆的左端点开始顺时针绘制四条三次贝塞尔曲线
        _ = ctx.moveTo(x - a, y)
        _ = ctx.bezierCurveTo(x - a, y - oy, x - ox, y - b, x, y - b)
        _ = ctx.bezierCurveTo(x + ox, y - b, x + a, y - oy, x + a, y)
        _ = ctx.bezierCurveTo(x + a, y + oy, x + ox, y + b, x, y + b)
        _ = ctx.bezierCurveTo(x - ox, y + b, x - a, y + oy, x - a, y)
        _ = ctx.closePath()
    }
}

// upstream: export default Ellipse;
