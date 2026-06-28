// Ported from zrender/src/graphic/shape/Isogon.ts — keep in sync with upstream

/**
 * 正多边形
 */

// upstream: import Path, { PathProps } from '../Path';

import Foundation

// upstream: const PI = Math.PI; const sin = Math.sin; const cos = Math.cos;

// upstream: export class IsogonShape { x = 0; y = 0; r = 0; n = 0 }
//   A plain parameter bag → `struct` conforming to the `PathShape` marker
//   (CONVENTIONS §4 / Path.swift GENERICS DECISION).
public struct IsogonShape: PathShape {
    public var x: Double = 0
    public var y: Double = 0
    public var r: Double = 0
    public var n: Double = 0
    public init() {}

    // Keyed access for animateTo({shape: {...}}) — exposes the animatable numeric fields
    //   (mirrors RectShape; see Path.swift ShapeAnimationAccessor). `n` (side count) is numeric.
    public func animationGet(_ key: String) -> Any? {
        switch key {
        case "x": return x
        case "y": return y
        case "r": return r
        case "n": return n
        default: return nil
        }
    }

    public mutating func animationSet(_ key: String, _ value: Any?) {
        guard let v = value as? Double else { return }
        switch key {
        case "x": x = v
        case "y": y = v
        case "r": r = v
        case "n": n = v
        default: break
        }
    }
}

// upstream: export interface IsogonProps extends PathProps { shape?: Partial<IsogonShape> }
//   PathProps collapses onto DisplayableProps (see Path.swift); typed-shape fidelity dropped.
public typealias IsogonProps = PathProps

// upstream: class Isogon extends Path<IsogonProps>
public final class Isogon: Path {

    // upstream: shape: IsogonShape — narrows the inherited `shape: PathShape`; read via downcast
    //   inside `buildPath` (the documented GENERICS deviation).

    // upstream: constructor(opts?: IsogonProps) { super(opts); }
    public override init(_ opts: IsogonProps? = nil) {
        super.init(opts)
        self.type = "isogon"   // upstream: Isogon.prototype.type = 'isogon'
    }

    public override func getDefaultShape() -> PathShape {
        return IsogonShape()
    }

    public override func buildPath(_ ctx: PathProxy, _ shape: PathShape, _ inBatch: Bool) {
        let shape = shape as! IsogonShape
        let n = shape.n
        // upstream: if (!n || n < 2) { return; }
        if n == 0 || n.isNaN || n < 2 {
            return
        }

        let x = shape.x
        let y = shape.y
        let r = shape.r

        let dStep = 2 * Double.pi / n
        var deg = -Double.pi / 2

        _ = ctx.moveTo(x + r * cos(deg), y + r * sin(deg))
        // upstream: for (let i = 0, end = n - 1; i < end; i++)
        var i = 0
        let end = n - 1
        while Double(i) < end {
            deg += dStep
            _ = ctx.lineTo(x + r * cos(deg), y + r * sin(deg))
            i += 1
        }

        _ = ctx.closePath()

        return
    }
}

// upstream: export default Isogon;
