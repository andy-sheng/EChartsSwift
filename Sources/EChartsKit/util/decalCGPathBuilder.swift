// Port-local: a CoreGraphics `PathRebuilder` used ONLY to rasterize decal-tile symbols
// (util/decal.swift `brushDecal`). EChartsKit cannot depend on NativePainter, so this mirrors
// NativePainter/CGPathRebuilder (same command set + arc convention) for the offscreen decal tile,
// which is drawn into a y-DOWN-flipped CGContext (see the CGPathRebuilder header for the
// `clockwise: anticlockwise` derivation). Not an upstream symbol — the renderer seam (§9).

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
import ZRenderKit

final class DecalCGPathBuilder: PathRebuilder {
    private(set) var path = CGMutablePath()

    func beginPath() { self.path = CGMutablePath() }

    func moveTo(_ x: Double, _ y: Double) {
        self.path.move(to: CGPoint(x: x, y: y))
    }
    func lineTo(_ x: Double, _ y: Double) {
        self.path.addLine(to: CGPoint(x: x, y: y))
    }
    func bezierCurveTo(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, _ x3: Double, _ y3: Double) {
        self.path.addCurve(
            to: CGPoint(x: x3, y: y3),
            control1: CGPoint(x: x1, y: y1),
            control2: CGPoint(x: x2, y: y2)
        )
    }
    func quadraticCurveTo(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) {
        self.path.addQuadCurve(to: CGPoint(x: x2, y: y2), control: CGPoint(x: x1, y: y1))
    }
    func arc(_ cx: Double, _ cy: Double, _ r: Double, _ startAngle: Double, _ endAngle: Double, _ anticlockwise: Bool) {
        self.path.addArc(
            center: CGPoint(x: cx, y: cy), radius: CGFloat(r),
            startAngle: CGFloat(startAngle), endAngle: CGFloat(endAngle),
            clockwise: anticlockwise
        )
    }
    func ellipse(_ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double, _ rotation: Double, _ startAngle: Double, _ endAngle: Double, _ anticlockwise: Bool) {
        var t = CGAffineTransform(translationX: CGFloat(cx), y: CGFloat(cy))
        t = t.rotated(by: CGFloat(rotation))
        t = t.scaledBy(x: CGFloat(rx), y: CGFloat(ry))
        self.path.addArc(
            center: .zero, radius: 1,
            startAngle: CGFloat(startAngle), endAngle: CGFloat(endAngle),
            clockwise: anticlockwise, transform: t
        )
    }
    func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double) {
        self.path.addRect(CGRect(x: x, y: y, width: w, height: h))
    }
    func closePath() {
        self.path.closeSubpath()
    }
}
#endif
