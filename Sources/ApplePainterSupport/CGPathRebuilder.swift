// NativePainter — fresh native renderer (Core Graphics / Core Animation).
// This is NOT a translation of zrender's CanvasPainter. It is a hand-written backend
// that satisfies the renderer seam (`PathRebuilder`) exported by ZRenderKit.
//
// CGPathRebuilder turns the path commands replayed by `PathProxy.rebuildPath(ctx, percent)`
// into a `CGMutablePath`. The command set and arg order mirror the `PathRebuilder` protocol
// (moveTo / lineTo / bezierCurveTo / quadraticCurveTo / arc / ellipse / rect / closePath),
// which itself mirrors the `CanvasRenderingContext2D` subset zrender emits.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
import ZRenderKit

/// Consumes `PathProxy` commands into a `CGMutablePath`.
///
/// COORDINATE / ANGLE CONVENTION (the classic arc bug — read carefully):
///   zrender path data is in canvas space: origin top-left, **+y points DOWN**, and the
///   `arc`/`ellipse` `anticlockwise` flag is the HTML-canvas flag (where "clockwise" is the
///   on-screen sense in that y-down space). The built `CGPath` is rendered by `CGRenderer`
///   into a context whose CTM has been flipped to y-down (see CGRenderer), so the numeric
///   coordinates map 1:1 to canvas.
///
///   `CGMutablePath.addArc(..., clockwise:)` interprets `clockwise` in the path's own
///   (geometric, y-up) space — NOT the rendered, flipped space, and NOT like `UIBezierPath`
///   (which pre-flips for you). Deriving the bridge:
///     canvas `anticlockwise == false`  → on-screen clockwise (y-down)
///                                       → geometric counter-clockwise once we flip to y-down
///                                       → `CGMutablePath` `clockwise == false`.
///     canvas `anticlockwise == true`   → ... → `CGMutablePath` `clockwise == true`.
///   So the flag passes straight through: **`clockwise: anticlockwise`**. (It is NOT negated,
///   precisely because we flip the *context* to y-down rather than pre-flipping the path like
///   UIBezierPath does. Negating here is the canonical mistake.)
///
/// `CGMutablePath.addArc` (both overloads) adds a line from the current point to the arc's
/// start point, matching canvas `arc()`/`ellipse()`'s implicit `lineTo` to the start.
public final class CGPathRebuilder: PathRebuilder {

    /// The accumulated path. Reset via `beginPath()` before each shape's `rebuildPath`.
    public private(set) var path = CGMutablePath()

    public init() {}

    /// Start a fresh path (mirrors `PathProxy.beginPath` / a `ctx.beginPath()`).
    public func beginPath() {
        self.path = CGMutablePath()
    }

    public func moveTo(_ x: Double, _ y: Double) {
        self.path.move(to: CGPoint(x: x, y: y))
    }

    public func lineTo(_ x: Double, _ y: Double) {
        self.path.addLine(to: CGPoint(x: x, y: y))
    }

    public func bezierCurveTo(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, _ x3: Double, _ y3: Double) {
        // canvas bezierCurveTo(cp1x, cp1y, cp2x, cp2y, x, y): (x1,y1)=cp1, (x2,y2)=cp2, (x3,y3)=end
        self.path.addCurve(
            to: CGPoint(x: x3, y: y3),
            control1: CGPoint(x: x1, y: y1),
            control2: CGPoint(x: x2, y: y2)
        )
    }

    public func quadraticCurveTo(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) {
        // canvas quadraticCurveTo(cpx, cpy, x, y): (x1,y1)=control, (x2,y2)=end
        self.path.addQuadCurve(
            to: CGPoint(x: x2, y: y2),
            control: CGPoint(x: x1, y: y1)
        )
    }

    public func arc(_ cx: Double, _ cy: Double, _ r: Double, _ startAngle: Double, _ endAngle: Double, _ anticlockwise: Bool) {
        // See the COORDINATE / ANGLE CONVENTION note: `clockwise: anticlockwise` (not negated).
        self.path.addArc(
            center: CGPoint(x: cx, y: cy),
            radius: CGFloat(r),
            startAngle: CGFloat(startAngle),
            endAngle: CGFloat(endAngle),
            clockwise: anticlockwise
        )
    }

    // eslint-disable-next-line max-len
    public func ellipse(_ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double, _ rotation: Double, _ startAngle: Double, _ endAngle: Double, _ anticlockwise: Bool) {
        // Build a unit arc (radius 1 at the origin) and map it onto the ellipse with an affine
        // transform: translate(cx, cy) · rotate(rotation) · scale(rx, ry). `addArc(...,transform:)`
        // applies this to both the arc and the implicit connecting line, so the current point is
        // joined to the (transformed) ellipse start — matching canvas `ellipse()`.
        var t = CGAffineTransform(translationX: CGFloat(cx), y: CGFloat(cy))
        t = t.rotated(by: CGFloat(rotation))
        t = t.scaledBy(x: CGFloat(rx), y: CGFloat(ry))
        self.path.addArc(
            center: .zero,
            radius: 1,
            startAngle: CGFloat(startAngle),
            endAngle: CGFloat(endAngle),
            clockwise: anticlockwise,   // same convention as `arc` above
            transform: t
        )
    }

    public func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double) {
        self.path.addRect(CGRect(x: x, y: y, width: w, height: h))
    }

    public func closePath() {
        self.path.closeSubpath()
    }
}

#endif
