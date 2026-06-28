// Ported from zrender/src/core/PathProxy.ts — keep in sync with upstream

import Foundation

/// The consumer interface of `PathProxy.rebuildPath`.
///
/// In upstream zrender this is the `PathRebuilder` interface declared at the bottom
/// of `core/PathProxy.ts`. `rebuildPath(ctx: PathRebuilder, percent)` replays the
/// recorded path commands onto `ctx`. The native renderer (NativePainter) — and any
/// other path consumer (hit testing, SVG `d` generation, bounding rect) — conforms to
/// this protocol. This is the seam where Core Graphics plugs in.
///
/// Upstream TS signature (PathProxy.ts):
/// ```
/// export interface PathRebuilder {
///     moveTo(x: number, y: number): void
///     lineTo(x: number, y: number): void
///     bezierCurveTo(x: number, y: number, x2: number, y2: number, x3: number, y3: number): void
///     quadraticCurveTo(x: number, y: number, x2: number, y2: number): void
///     arc(cx: number, cy: number, r: number, startAngle: number, endAngle: number, anticlockwise: boolean): void
///     ellipse(cx: number, cy: number, radiusX: number, radiusY: number, rotation: number, startAngle: number, endAngle: number, anticlockwise: boolean): void
///     rect(x: number, y: number, width: number, height: number): void
///     closePath(): void
/// }
/// ```
public protocol PathRebuilder: AnyObject {

    func moveTo(_ x: Double, _ y: Double)

    func lineTo(_ x: Double, _ y: Double)

    func bezierCurveTo(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, _ x3: Double, _ y3: Double)

    func quadraticCurveTo(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double)

    func arc(_ cx: Double, _ cy: Double, _ r: Double, _ startAngle: Double, _ endAngle: Double, _ anticlockwise: Bool)

    // eslint-disable-next-line max-len
    func ellipse(_ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double, _ rotation: Double, _ startAngle: Double, _ endAngle: Double, _ anticlockwise: Bool)

    func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double)

    func closePath()
}
