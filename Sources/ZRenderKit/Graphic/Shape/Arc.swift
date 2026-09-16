// Ported from zrender/src/graphic/shape/Arc.ts — keep in sync with upstream
//
// 圆弧 (a single circular arc stroke)
//
// upstream imports (resolved to the ported modules):
// import Path, { PathProps } from '../Path';
//
// Path<Shape> mapping (see Path.swift "GENERICS DECISION"): `Path` is a NON-generic class;
// the per-subclass shape is a `struct …Shape: PathShape`, returned from `getDefaultShape()`
// and downcast inside `buildPath`.

import Foundation

// upstream: export class ArcShape { cx = 0; cy = 0; r = 0; startAngle = 0;
//   endAngle = Math.PI * 2; clockwise? = true }
public struct ArcShape: PathShape {
    public var cx: Double = 0
    public var cy: Double = 0
    public var r: Double = 0
    public var startAngle: Double = 0
    public var endAngle: Double = Double.pi * 2
    // upstream: `clockwise? = true`. Optional with a prototype default of true.
    public var clockwise: Bool? = true

    public init() {}

    // Keyed access for animateTo({shape: {...}}) — exposes the animatable numeric fields
    //   (mirrors RectShape). `clockwise` (Bool) is not tweened.
    public func animationGet(_ key: String) -> Any? {
        switch key {
        case "cx": return cx
        case "cy": return cy
        case "r": return r
        case "startAngle": return startAngle
        case "endAngle": return endAngle
        default: return nil
        }
    }

    public mutating func animationSet(_ key: String, _ value: Any?) {
        guard let v = value as? Double else { return }
        switch key {
        case "cx": cx = v
        case "cy": cy = v
        case "r": r = v
        case "startAngle": startAngle = v
        case "endAngle": endAngle = v
        default: break
        }
    }
}

// upstream `interface ArcProps extends PathProps { shape?: Partial<ArcShape> }`.
//   `PathProps` is the collapsed `[String: Any]` prop bag (see Path.swift); the typed
//   `shape?: Partial<ArcShape>` narrowing is dropped.
public typealias ArcProps = PathProps

// upstream: class Arc extends Path<ArcProps>
public final class Arc: Path {

    // upstream: shape: ArcShape — narrows the inherited `shape`; modeled via the existential
    //   `PathShape` (downcast in buildPath). See Path.swift GENERICS DECISION.

    public override init(_ opts: ElementProps? = nil) {
        super.init(opts)
        // Arc.prototype.type = 'arc';
        self.type = "arc"
    }

    public override func getDefaultStyle() -> PathStyleProps? {
        var style = PathStyleProps()
        style.stroke = .string("#000")
        style.fill = nil   // upstream: fill: null as string
        return style
    }

    public override func getDefaultShape() -> PathShape {
        return ArcShape()
    }

    public override func buildPath(_ ctx: PathProxy, _ shape: PathShape, _ inBatch: Bool) {
        let shape = shape as! ArcShape

        let x = shape.cx
        let y = shape.cy
        let r = Swift.max(shape.r, 0)
        let startAngle = shape.startAngle
        let endAngle = shape.endAngle
        let clockwise = shape.clockwise

        let unitX = cos(startAngle)
        let unitY = sin(startAngle)

        _ = ctx.moveTo(unitX * r + x, unitY * r + y)
        // upstream: ctx.arc(x, y, r, startAngle, endAngle, !clockwise);
        //   `!clockwise` — `undefined` is falsy, so a missing clockwise yields `!undefined === true`.
        _ = ctx.arc(x, y, r, startAngle, endAngle, !(clockwise ?? false))
    }
}

// upstream: export default Arc;
