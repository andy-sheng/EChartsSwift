// Ported from zrender/src/graphic/shape/Rect.ts — keep in sync with upstream

/**
 * 矩形
 * @module zrender/graphic/shape/Rect
 */

// upstream:
// import Path, { PathProps } from '../Path';
// import * as roundRectHelper from '../helper/roundRect';
// import {subPixelOptimizeRect} from '../helper/subPixelOptimize';

import Foundation

// upstream `r?: number | number[]` is an untagged union. Modeled as a tagged enum
//   (no untagged unions in Swift — same pattern as `LineDash`/`ZRColor` in Path.swift).
//   `.number` ⟷ `typeof r === 'number'`, `.array` ⟷ `r instanceof Array`.
public enum RectRadius {
    case number(Double)
    case array([Double])
}

// upstream: export class RectShape { r?: ...; x = 0; y = 0; width = 0; height = 0 }
//   A plain parameter bag (no identity) → `struct` conforming to the `PathShape` marker
//   (CONVENTIONS §4 / Path.swift GENERICS DECISION).
public struct RectShape: PathShape {
    // 左上、右上、右下、左下角的半径依次为r1、r2、r3、r4
    // r缩写为1         相当于 [1, 1, 1, 1]
    // r缩写为[1]       相当于 [1, 1, 1, 1]
    // r缩写为[1, 2]    相当于 [1, 2, 1, 2]
    // r缩写为[1, 2, 3] 相当于 [1, 2, 3, 2]
    public var r: RectRadius?

    public var x: Double = 0
    public var y: Double = 0
    public var width: Double = 0
    public var height: Double = 0

    public init() {}

    // Keyed access for animateTo({shape: {...}}). r (corner radii) is not tweened.
    public func animationGet(_ key: String) -> Any? {
        switch key {
        case "x": return x
        case "y": return y
        case "width": return width
        case "height": return height
        default: return nil
        }
    }

    public mutating func animationSet(_ key: String, _ value: Any?) {
        guard let v = value as? Double else { return }
        switch key {
        case "x": x = v
        case "y": y = v
        case "width": width = v
        case "height": height = v
        default: break
        }
    }
}

// upstream: export interface RectProps extends PathProps { shape?: Partial<RectShape> }
// typed-interface fidelity dropped — PathProps is the dynamic `[String: Any]` prop bag
//   (== DisplayableProps); the `shape?` field is set via the `"shape"` key (see Path._init).
public typealias RectProps = PathProps

// Avoid create repeatly.
// upstream `const subPixelOptimizeOutputShape = {}` is a reused mutable scratch object.
//   Per CONVENTIONS §3 our `subPixelOptimizeRect` is value-returning, so no shared scratch is
//   needed; the optimization is purely a JS GC concern with no observable behavior.

public final class Rect: Path {

    // upstream: shape: RectShape — narrows the inherited `shape: PathShape!`. Accessed via the
    //   `shape` argument of `buildPath` (downcast) and via `self.shape as! RectShape`.

    // upstream: constructor(opts?) { super(opts); }
    public override init(_ opts: ElementProps? = nil) {
        super.init(opts)
        // upstream: Rect.prototype.type = 'rect';
        self.type = "rect"
    }

    public override func getDefaultShape() -> PathShape {
        return RectShape()
    }

    public override func buildPath(_ ctx: PathProxy, _ shapeIn: PathShape, _ inBatch: Bool) {
        var shape = shapeIn as! RectShape
        let x: Double
        let y: Double
        let width: Double
        let height: Double

        if self.subPixelOptimize {
            let optimizedShape = subPixelOptimizeNS.subPixelOptimizeRect(shape, self.pathStyle)!
            x = optimizedShape.x
            y = optimizedShape.y
            width = optimizedShape.width
            height = optimizedShape.height
            var optimized = optimizedShape
            optimized.r = shape.r
            shape = optimized
        }
        else {
            x = shape.x
            y = shape.y
            width = shape.width
            height = shape.height
        }

        // upstream: if (!shape.r) — falsy when r is undefined or the number 0; an array (even
        //   empty) is truthy.
        if !rTruthy(shape.r) {
            _ = ctx.rect(x, y, width, height)
        }
        else {
            roundRect.buildPath(ctx, shape)
        }
    }

    public override func isZeroArea() -> Bool {
        let shape = self.shape as! RectShape
        // upstream: return !this.shape.width || !this.shape.height
        return shape.width == 0 || shape.height == 0
    }
}

// upstream JS truthiness of `r?: number | number[]`: nil / undefined → false, the number 0 →
//   false, any number != 0 → true, any array (incl. empty) → true.
private func rTruthy(_ r: RectRadius?) -> Bool {
    switch r {
    case .none:
        return false
    case .some(.number(let n)):
        return n != 0 && !n.isNaN
    case .some(.array):
        return true
    }
}

// upstream: export default Rect;
