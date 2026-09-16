// Ported from zrender/src/graphic/helper/subPixelOptimize.ts — keep in sync with upstream

// upstream: import { PathStyleProps } from '../Path';

/**
 * Sub-pixel optimize for canvas rendering, prevent from blur
 * when rendering a thin vertical/horizontal line.
 */

import Foundation

// upstream marker: free-function module → caseless `enum` namespace (CONVENTIONS §2).
public enum subPixelOptimizeNS {

    // const round = Math.round;
    // JS `Math.round` rounds half toward +Infinity (Math.round(2.5)===3,
    //   Math.round(-2.5)===-2). Replicate with `floor(x + 0.5)` (CONVENTIONS §5).
    static func round(_ x: Double) -> Double {
        return floor(x + 0.5)
    }

    // upstream: type LineShape = { x1, y1, x2, y2 }
    public struct LineShape {
        public var x1: Double
        public var y1: Double
        public var x2: Double
        public var y2: Double
        public init(x1: Double = 0, y1: Double = 0, x2: Double = 0, y2: Double = 0) {
            self.x1 = x1; self.y1 = y1; self.x2 = x2; self.y2 = y2
        }
    }

    // upstream: type RectShape = { x, y, width, height, r? } — modeled by the `RectShape`
    //   struct in Rect.swift, reused here.

    /**
     * Sub pixel optimize line for canvas
     *
     * upstream signature mutates `outputShape` in place and returns it. Per CONVENTIONS §3
     * (no out-params), this returns a fresh `LineShape`.
     */
    public static func subPixelOptimizeLine(
        _ inputShape: LineShape?,
        _ style: PathStyleProps?   // DO not optimize when lineWidth is 0
    ) -> LineShape? {
        // upstream: if (!inputShape) return;
        guard let inputShape = inputShape else {
            return nil
        }

        let x1 = inputShape.x1
        let x2 = inputShape.x2
        let y1 = inputShape.y1
        let y2 = inputShape.y2

        var outputShape = LineShape()
        outputShape.x1 = x1
        outputShape.x2 = x2
        outputShape.y1 = y1
        outputShape.y2 = y2

        let lineWidth = style?.lineWidth
        // upstream: if (!lineWidth) return outputShape;
        if lineWidth == nil || lineWidth == 0 {
            return outputShape
        }
        let lw = lineWidth!

        if round(x1 * 2) == round(x2 * 2) {
            let v = subPixelOptimize(x1, lw, true)
            outputShape.x1 = v; outputShape.x2 = v
        }
        if round(y1 * 2) == round(y2 * 2) {
            let v = subPixelOptimize(y1, lw, true)
            outputShape.y1 = v; outputShape.y2 = v
        }

        return outputShape
    }

    /**
     * Sub pixel optimize rect for canvas
     *
     * upstream signature mutates `outputShape` in place and returns it. Per CONVENTIONS §3
     * (no out-params), this returns a fresh `RectShape`.
     */
    public static func subPixelOptimizeRect(
        _ inputShape: RectShape?,
        _ style: PathStyleProps?   // DO not optimize when lineWidth is 0
    ) -> RectShape? {
        // upstream: if (!inputShape) return;
        guard let inputShape = inputShape else {
            return nil
        }

        let originX = inputShape.x
        let originY = inputShape.y
        let originWidth = inputShape.width
        let originHeight = inputShape.height

        var outputShape = RectShape()
        outputShape.x = originX
        outputShape.y = originY
        outputShape.width = originWidth
        outputShape.height = originHeight

        let lineWidth = style?.lineWidth
        // upstream: if (!lineWidth) return outputShape;
        if lineWidth == nil || lineWidth == 0 {
            return outputShape
        }
        let lw = lineWidth!

        outputShape.x = subPixelOptimize(originX, lw, true)
        outputShape.y = subPixelOptimize(originY, lw, true)
        outputShape.width = Swift.max(
            subPixelOptimize(originX + originWidth, lw, false) - outputShape.x,
            originWidth == 0 ? 0 : 1
        )
        outputShape.height = Swift.max(
            subPixelOptimize(originY + originHeight, lw, false) - outputShape.y,
            originHeight == 0 ? 0 : 1
        )

        return outputShape
    }

    /**
     * Sub pixel optimize for canvas
     *
     * @param position Coordinate, such as x, y
     * @param lineWidth If `null`/`undefined`/`0`, do not optimize.
     * @param positiveOrNegative Default false (negative).
     * @return Optimized position.
     */
    public static func subPixelOptimize(
        _ position: Double,
        _ lineWidth: Double? = nil,
        _ positiveOrNegative: Bool? = nil
    ) -> Double {
        // upstream: if (!lineWidth) return position;
        if lineWidth == nil || lineWidth == 0 {
            return position
        }
        let lineWidth = lineWidth!
        // Assure that (position + lineWidth / 2) is near integer edge,
        // otherwise line will be fuzzy in canvas.
        let doubledPosition = round(position * 2)
        return (doubledPosition + round(lineWidth)).truncatingRemainder(dividingBy: 2) == 0
            ? doubledPosition / 2
            : (doubledPosition + ((positiveOrNegative ?? false) ? 1 : -1)) / 2
    }
}
