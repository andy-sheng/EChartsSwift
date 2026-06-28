// Ported from zrender/src/graphic/shape/Star.ts — keep in sync with upstream

/**
 * n角星（n>3）
 * @module zrender/graphic/shape/Star
 */

// upstream: import Path, { PathProps } from '../Path';

import Foundation

// upstream:
//   const PI = Math.PI;
//   const cos = Math.cos;
//   const sin = Math.sin;
//   — inlined as Double.pi / cos / sin below.

// upstream: export class StarShape { cx = 0; cy = 0; n = 3; r0: number; r = 0 }
//   A plain parameter bag → `struct` conforming to the `PathShape` marker
//   (CONVENTIONS §4 / Path.swift GENERICS DECISION). `r0: number` has no initializer
//   upstream (left `undefined`) → modeled as optional with `nil` default.
public struct StarShape: PathShape {
    public var cx: Double = 0
    public var cy: Double = 0
    public var n: Double = 3
    public var r0: Double?
    public var r: Double = 0
    public init() {}

    // Keyed access for animateTo({shape: {...}}) — exposes the animatable numeric fields
    //   (mirrors RectShape). `r0` is optional (nil → auto-computed in buildPath); `n` is numeric.
    public func animationGet(_ key: String) -> Any? {
        switch key {
        case "cx": return cx
        case "cy": return cy
        case "n": return n
        case "r0": return r0
        case "r": return r
        default: return nil
        }
    }

    public mutating func animationSet(_ key: String, _ value: Any?) {
        guard let v = value as? Double else { return }
        switch key {
        case "cx": cx = v
        case "cy": cy = v
        case "n": n = v
        case "r0": r0 = v
        case "r": r = v
        default: break
        }
    }
}

// upstream: export interface StarProps extends PathProps { shape?: Partial<StarShape> }
//   PathProps collapses onto DisplayableProps (see Path.swift); typed-shape fidelity dropped.
public typealias StarProps = PathProps

// upstream: class Star extends Path<StarProps>
public final class Star: Path {

    // upstream: shape: StarShape — narrows the inherited `shape: PathShape` per subclass;
    //   read via downcast inside `buildPath` (the documented GENERICS deviation).

    // upstream: constructor(opts?: StarProps) { super(opts); }
    public override init(_ opts: StarProps? = nil) {
        super.init(opts)
        self.type = "star"   // upstream: Star.prototype.type = 'star'
    }

    public override func getDefaultShape() -> PathShape {
        return StarShape()
    }

    public override func buildPath(_ ctx: PathProxy, _ shapeIn: PathShape, _ inBatch: Bool) {
        let shape = shapeIn as! StarShape

        let n = shape.n
        if n == 0 || n < 2 {
            return
        }

        let x = shape.cx
        let y = shape.cy
        let r = shape.r
        var r0 = shape.r0

        // 如果未指定内部顶点外接圆半径，则自动计算
        if r0 == nil {
            r0 = n > 4
                // 相隔的外部顶点的连线的交点，
                // 被取为内部交点，以此计算r0
                ? r * cos(2 * Double.pi / n) / cos(Double.pi / n)
                // 二三四角星的特殊处理
                : r / 3
        }

        let dStep = Double.pi / n
        var deg = -Double.pi / 2
        let xStart = x + r * cos(deg)
        let yStart = y + r * sin(deg)
        deg += dStep

        // 记录边界点，用于判断inside
        _ = ctx.moveTo(xStart, yStart)
        let end = Int(n) * 2 - 1
        var i = 0
        while i < end {
            let ri = i % 2 == 0 ? r0! : r
            _ = ctx.lineTo(x + ri * cos(deg), y + ri * sin(deg))
            deg += dStep
            i += 1
        }

        _ = ctx.closePath()
    }
}

// upstream: export default Star;
