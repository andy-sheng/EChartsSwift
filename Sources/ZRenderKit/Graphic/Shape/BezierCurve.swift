// Ported from zrender/src/graphic/shape/BezierCurve.ts — keep in sync with upstream
/**
 * 贝塞尔曲线
 */

import Foundation

// upstream imports (resolved to the ported modules):
// import Path, { PathProps } from '../Path';            → Path, PathProps
// import * as vec2 from '../../core/vector';            → vector  (alias vec2)
// import { quadraticSubdivide, cubicSubdivide, quadraticAt, cubicAt,
//          quadraticDerivativeAt, cubicDerivativeAt } from '../../core/curve';  → curve.*

// upstream: const out: number[] = [];   — a shared module-level scratch buffer for the
//   subdivide out-params. DROPPED: per CONVENTIONS §3 the ported `curve.*Subdivide`
//   functions are value-returning ([Double]), so each call returns its own array.

public struct BezierCurveShape: PathShape {
    public var x1: Double = 0
    public var y1: Double = 0
    public var x2: Double = 0
    public var y2: Double = 0
    public var cpx1: Double = 0
    public var cpy1: Double = 0
    public var cpx2: Double?
    public var cpy2: Double?
    // Curve show percent, for animating
    public var percent: Double = 1

    public init() {}

    // Keyed access for animateTo({shape: {...}}) — exposes the animatable numeric fields
    //   (mirrors RectShape). `cpx2`/`cpy2` are optional (nil when the curve is quadratic);
    //   `percent` is the draw-on field commonly animated.
    public func animationGet(_ key: String) -> Any? {
        switch key {
        case "x1": return x1
        case "y1": return y1
        case "x2": return x2
        case "y2": return y2
        case "cpx1": return cpx1
        case "cpy1": return cpy1
        case "cpx2": return cpx2
        case "cpy2": return cpy2
        case "percent": return percent
        default: return nil
        }
    }

    public mutating func animationSet(_ key: String, _ value: Any?) {
        guard let v = value as? Double else { return }
        switch key {
        case "x1": x1 = v
        case "y1": y1 = v
        case "x2": x2 = v
        case "y2": y2 = v
        case "cpx1": cpx1 = v
        case "cpy1": cpy1 = v
        case "cpx2": cpx2 = v
        case "cpy2": cpy2 = v
        case "percent": percent = v
        default: break
        }
    }
}

// was: function someVectorAt(shape, t, isTangent): number[]
private func someVectorAt(_ shape: BezierCurveShape, _ t: Double, _ isTangent: Bool) -> [Double] {
    let cpx2 = shape.cpx2
    let cpy2 = shape.cpy2
    if cpx2 != nil || cpy2 != nil {
        // PORT-TODO: upstream passes `shape.cpx2`/`shape.cpy2` (number | undefined) straight into the
        //   cubic helpers; a `null` operand becomes NaN in JS arithmetic. Replicated via `?? .nan`.
        return [
            (isTangent ? curve.cubicDerivativeAt : curve.cubicAt)(shape.x1, shape.cpx1, shape.cpx2 ?? Double.nan, shape.x2, t),
            (isTangent ? curve.cubicDerivativeAt : curve.cubicAt)(shape.y1, shape.cpy1, shape.cpy2 ?? Double.nan, shape.y2, t)
        ]
    }
    else {
        return [
            (isTangent ? curve.quadraticDerivativeAt : curve.quadraticAt)(shape.x1, shape.cpx1, shape.x2, t),
            (isTangent ? curve.quadraticDerivativeAt : curve.quadraticAt)(shape.y1, shape.cpy1, shape.y2, t)
        ]
    }
}

// upstream: interface BezierCurveProps extends PathProps { shape?: Partial<BezierCurveShape> }
//   collapsed onto PathProps (the dynamic prop bag) per Path.swift's PathProps typealias.
public typealias BezierCurveProps = PathProps

public final class BezierCurve: Path {

    // upstream: shape: BezierCurveShape — narrows the inherited existential `shape: PathShape!`.
    //   Per Path.swift's GENERICS DECISION the property stays `PathShape!`; `buildPath` downcasts.

    public override init(_ opts: ElementProps? = nil) {
        super.init(opts)
        // BezierCurve.prototype.type = 'bezier-curve'
        self.type = "bezier-curve"
    }

    public override func getDefaultStyle() -> PathStyleProps? {
        var style = PathStyleProps()
        style.stroke = .string("#000")
        style.fill = nil   // fill: null as string
        return style
    }

    public override func getDefaultShape() -> PathShape {
        return BezierCurveShape()
    }

    public override func buildPath(_ ctx: PathProxy, _ shape: PathShape, _ inBatch: Bool) {
        let shape = shape as! BezierCurveShape
        let x1 = shape.x1
        let y1 = shape.y1
        var x2 = shape.x2
        var y2 = shape.y2
        var cpx1 = shape.cpx1
        var cpy1 = shape.cpy1
        var cpx2 = shape.cpx2
        var cpy2 = shape.cpy2
        let percent = shape.percent
        if percent == 0 {
            return
        }

        _ = ctx.moveTo(x1, y1)

        if cpx2 == nil || cpy2 == nil {
            if percent < 1 {
                var out = curve.quadraticSubdivide(x1, cpx1, x2, percent)
                cpx1 = out[1]
                x2 = out[2]
                out = curve.quadraticSubdivide(y1, cpy1, y2, percent)
                cpy1 = out[1]
                y2 = out[2]
            }

            _ = ctx.quadraticCurveTo(
                cpx1, cpy1,
                x2, y2
            )
        }
        else {
            if percent < 1 {
                var out = curve.cubicSubdivide(x1, cpx1, cpx2!, x2, percent)
                cpx1 = out[1]
                cpx2 = out[2]
                x2 = out[3]
                out = curve.cubicSubdivide(y1, cpy1, cpy2!, y2, percent)
                cpy1 = out[1]
                cpy2 = out[2]
                y2 = out[3]
            }
            _ = ctx.bezierCurveTo(
                cpx1, cpy1,
                cpx2!, cpy2!,
                x2, y2
            )
        }
    }

    /**
     * Get point at percent
     */
    public func pointAt(_ t: Double) -> [Double] {
        return someVectorAt(self.shape as! BezierCurveShape, t, false)
    }

    /**
     * Get tangent at percent
     */
    public func tangentAt(_ t: Double) -> [Double] {
        let p = someVectorAt(self.shape as! BezierCurveShape, t, true)
        // upstream: return vec2.normalize(p, p);  — value-returning normalize per CONVENTIONS §3.
        let n = vector.normalize(VectorArray(p[0], p[1]))
        return [n[0], n[1]]
    }
}

// upstream: export default BezierCurve;
