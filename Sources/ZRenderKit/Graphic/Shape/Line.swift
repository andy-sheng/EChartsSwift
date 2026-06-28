// Ported from zrender/src/graphic/shape/Line.ts — keep in sync with upstream

/**
 * 直线
 * @module zrender/graphic/shape/Line
 */

// upstream:
// import Path, { PathProps } from '../Path';
// import {subPixelOptimizeLine} from '../helper/subPixelOptimize';
// import { VectorArray } from '../../core/vector';

import Foundation

// Avoid create repeatly.
// PORT-TODO: upstream `const subPixelOptimizeOutputShape = {}` is a reused mutable scratch object.
//   Per CONVENTIONS §3 our `subPixelOptimizeLine` is value-returning, so no shared scratch is
//   needed; the optimization is purely a JS GC concern with no observable behavior.

// upstream: export class LineShape { x1 = 0; y1 = 0; x2 = 0; y2 = 0; percent = 1 }
//   A plain parameter bag → `struct` conforming to the `PathShape` marker (CONVENTIONS §4).
public struct LineShape: PathShape {
    // Start point
    public var x1: Double = 0
    public var y1: Double = 0
    // End point
    public var x2: Double = 0
    public var y2: Double = 0

    public var percent: Double = 1

    public init() {}

    // Keyed access for animateTo({shape: {...}}) — exposes the animatable numeric fields
    //   (mirrors RectShape). `percent` is the draw-on field commonly animated.
    public func animationGet(_ key: String) -> Any? {
        switch key {
        case "x1": return x1
        case "y1": return y1
        case "x2": return x2
        case "y2": return y2
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
        case "percent": percent = v
        default: break
        }
    }
}

// upstream: export interface LineProps extends PathProps { shape?: Partial<LineShape> }
//   PathProps collapses onto DisplayableProps (see Path.swift); typed-shape fidelity dropped.
public typealias LineProps = PathProps

// upstream: class Line extends Path<LineProps>
public final class Line: Path {

    // upstream: shape: LineShape — narrows the inherited `shape: PathShape` per subclass; the typed
    //   shape is read via downcast inside `buildPath` / `pointAt` (the documented GENERICS deviation).

    // upstream: constructor(opts?: LineProps) { super(opts); }
    public override init(_ opts: LineProps? = nil) {
        super.init(opts)
        self.type = "line"   // upstream: Line.prototype.type = 'line'
    }

    public override func getDefaultStyle() -> PathStyleProps? {
        var style = PathStyleProps()
        style.stroke = .string("#000")
        style.fill = nil   // upstream: fill: null as string
        return style
    }

    public override func getDefaultShape() -> PathShape {
        return LineShape()
    }

    public override func buildPath(_ ctx: PathProxy, _ shapeIn: PathShape, _ inBatch: Bool) {
        let shape = shapeIn as! LineShape
        let x1: Double
        let y1: Double
        var x2: Double
        var y2: Double

        if self.subPixelOptimize {
            let optimizedShape = subPixelOptimizeNS.subPixelOptimizeLine(
                subPixelOptimizeNS.LineShape(x1: shape.x1, y1: shape.y1, x2: shape.x2, y2: shape.y2),
                self.pathStyle
            )!
            x1 = optimizedShape.x1
            y1 = optimizedShape.y1
            x2 = optimizedShape.x2
            y2 = optimizedShape.y2
        }
        else {
            x1 = shape.x1
            y1 = shape.y1
            x2 = shape.x2
            y2 = shape.y2
        }

        let percent = shape.percent

        if percent == 0 {
            return
        }

        _ = ctx.moveTo(x1, y1)

        if percent < 1 {
            x2 = x1 * (1 - percent) + x2 * percent
            y2 = y1 * (1 - percent) + y2 * percent
        }
        _ = ctx.lineTo(x2, y2)
    }

    /**
     * Get point at percent
     */
    // upstream: pointAt(p: number): VectorArray — `VectorArray` (number[]) modeled as `[Double]`
    //   (same return-type choice as `BezierCurve.pointAt`).
    public func pointAt(_ p: Double) -> [Double] {
        let shape = self.shape as! LineShape
        return [
            shape.x1 * (1 - p) + shape.x2 * p,
            shape.y1 * (1 - p) + shape.y2 * p
        ]
    }
}

// upstream: export default Line;
