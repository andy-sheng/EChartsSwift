// Ported from zrender/src/graphic/shape/Trochoid.ts — keep in sync with upstream

/**
 * 内外旋轮曲线
 * @module zrender/graphic/shape/Trochold
 */

import Foundation

// upstream: import Path, { PathProps } from '../Path';

// upstream:
//   const cos = Math.cos;
//   const sin = Math.sin;

// upstream:
//   export class TrochoidShape {
//       cx = 0; cy = 0; r = 0; r0 = 0; d = 0; location = 'out'
//   }
//   A plain parameter bag → `struct` conforming to the `PathShape` marker
//   (CONVENTIONS §4 / Path.swift GENERICS DECISION).
public struct TrochoidShape: PathShape {
    public var cx: Double = 0
    public var cy: Double = 0
    public var r: Double = 0
    public var r0: Double = 0
    public var d: Double = 0
    public var location: String = "out"
    public init() {}

    // Keyed access for animateTo({shape: {...}}) — exposes the animatable numeric fields
    //   (mirrors RectShape). `location` (String) is not tweened.
    public func animationGet(_ key: String) -> Any? {
        switch key {
        case "cx": return cx
        case "cy": return cy
        case "r": return r
        case "r0": return r0
        case "d": return d
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
        case "d": d = v
        default: break
        }
    }
}

// upstream: export interface TrochoidProps extends PathProps { shape?: Partial<TrochoidShape> }
//   PathProps collapses onto DisplayableProps (see Path.swift); typed-shape fidelity dropped.
public typealias TrochoidProps = PathProps

// upstream: class Trochoid extends Path<TrochoidProps>
public final class Trochoid: Path {

    // upstream: shape: TrochoidShape — narrows the inherited `shape: PathShape` per subclass.
    //   Accessed via the `shape` argument of `buildPath` (downcast).

    // upstream: constructor(opts?: TrochoidProps) { super(opts); }
    public override init(_ opts: TrochoidProps? = nil) {
        super.init(opts)
        self.type = "trochoid"   // upstream: Trochoid.prototype.type = 'trochoid';
    }

    // upstream: getDefaultStyle() { return { stroke: '#000', fill: null as string }; }
    public override func getDefaultStyle() -> PathStyleProps? {
        var style = PathStyleProps()
        style.stroke = .string("#000")
        style.fill = nil   // fill: null as string
        return style
    }

    public override func getDefaultShape() -> PathShape {
        return TrochoidShape()
    }

    public override func buildPath(_ ctx: PathProxy, _ shape: PathShape, _ inBatch: Bool) {
        let shape = shape as! TrochoidShape
        let R = shape.r
        let r = shape.r0
        let d = shape.d
        let offsetX = shape.cx
        let offsetY = shape.cy
        // upstream: const delta = shape.location === 'out' ? 1 : -1;
        let delta: Double = shape.location == "out" ? 1 : -1
        var x1: Double
        var y1: Double
        var x2: Double
        var y2: Double

        // upstream: if (shape.location && R <= r) { return; }
        //   `shape.location` is truthy when the string is non-empty.
        if !shape.location.isEmpty && R <= r {
            return
        }

        var num: Double = 0
        var i: Double = 1
        var theta: Double

        x1 = (R + delta * r) * cos(0)
            - delta * d * cos(0) + offsetX
        y1 = (R + delta * r) * sin(0)
            - d * sin(0) + offsetY

        _ = ctx.moveTo(x1, y1)

        // 计算结束时的i
        repeat {
            num += 1
        }
        while (r * num).truncatingRemainder(dividingBy: (R + delta * r)) != 0

        repeat {
            theta = Double.pi / 180 * i
            x2 = (R + delta * r) * cos(theta)
                    - delta * d * cos((R / r + delta) * theta)
                    + offsetX
            y2 = (R + delta * r) * sin(theta)
                    - d * sin((R / r + delta) * theta)
                    + offsetY
            _ = ctx.lineTo(x2, y2)
            i += 1
        }
        while i <= (r * num) / (R + delta * r) * 360
    }
}

// upstream: export default Trochoid;
