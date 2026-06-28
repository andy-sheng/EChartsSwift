// Ported from zrender/src/graphic/shape/Rose.ts — keep in sync with upstream

/**
 * 玫瑰线
 * @module zrender/graphic/shape/Rose
 */

import Foundation

// upstream: import Path, { PathProps } from '../Path';

// upstream:
//   const sin = Math.sin;
//   const cos = Math.cos;
//   const radian = Math.PI / 180;
private let radian = Double.pi / 180

// upstream: export class RoseShape { cx = 0; cy = 0; r: number[] = []; k = 0; n = 1 }
//   A plain parameter bag → `struct` conforming to the `PathShape` marker
//   (CONVENTIONS §4 / Path.swift GENERICS DECISION).
public struct RoseShape: PathShape {
    public var cx: Double = 0
    public var cy: Double = 0
    public var r: [Double] = []
    public var k: Double = 0
    public var n: Double = 1
    public init() {}

    // Keyed access for animateTo({shape: {...}}) — exposes the animatable fields (mirrors
    //   RectShape). `r` is the radii array, exposed as a [Double] (1D-array interpolation);
    //   `k`/`n` are numeric. `cx`/`cy` are numeric.
    public func animationGet(_ key: String) -> Any? {
        switch key {
        case "cx": return cx
        case "cy": return cy
        case "r": return r
        case "k": return k
        case "n": return n
        default: return nil
        }
    }

    public mutating func animationSet(_ key: String, _ value: Any?) {
        switch key {
        case "cx": if let v = value as? Double { cx = v }
        case "cy": if let v = value as? Double { cy = v }
        case "r": if let v = value as? [Double] { r = v }
        case "k": if let v = value as? Double { k = v }
        case "n": if let v = value as? Double { n = v }
        default: break
        }
    }
}

// upstream: export interface RoseProps extends PathProps { shape?: Partial<RoseShape> }
//   PathProps collapses onto DisplayableProps (see Path.swift); typed-shape fidelity dropped.
public typealias RoseProps = PathProps

// upstream: class Rose extends Path<RoseProps>
public final class Rose: Path {

    // upstream: shape: RoseShape — narrows the inherited `shape: PathShape` per subclass.
    //   Accessed via the `shape` argument of `buildPath` (downcast).

    // upstream: constructor(opts?: RoseProps) { super(opts); }
    public override init(_ opts: RoseProps? = nil) {
        super.init(opts)
        self.type = "rose"   // upstream: Rose.prototype.type = 'rose';
    }

    // upstream: getDefaultStyle() { return { stroke: '#000', fill: null as string }; }
    public override func getDefaultStyle() -> PathStyleProps? {
        var style = PathStyleProps()
        style.stroke = .string("#000")
        style.fill = nil   // fill: null as string
        return style
    }

    public override func getDefaultShape() -> PathShape {
        return RoseShape()
    }

    public override func buildPath(_ ctx: PathProxy, _ shape: PathShape, _ inBatch: Bool) {
        let shape = shape as! RoseShape
        let R = shape.r
        let k = shape.k
        let n = shape.n
        let x0 = shape.cx
        let y0 = shape.cy
        var x: Double
        var y: Double
        var r: Double

        _ = ctx.moveTo(x0, y0)

        var i = 0
        let len = R.count
        while i < len {
            r = R[i]

            var j = 0
            while Double(j) <= 360 * n {
                let jd = Double(j)
                // upstream: k / n * j % 360 — `/ * %` are left-assoc & equal precedence in JS,
                //   so the modulo applies to the whole `k / n * j` product, not just `j`.
                let theta = (k / n * jd).truncatingRemainder(dividingBy: 360) * radian
                x = r
                        * sin(theta)
                        * cos(jd * radian)
                        + x0
                y = r
                        * sin(theta)
                        * sin(jd * radian)
                        + y0
                _ = ctx.lineTo(x, y)
                j += 1
            }
            i += 1
        }
    }
}

// upstream: export default Rose;
