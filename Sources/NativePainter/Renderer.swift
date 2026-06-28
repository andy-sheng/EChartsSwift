// NativePainter — fresh native renderer (Core Graphics / Core Animation).
// This is NOT a translation of zrender's CanvasPainter. It is a hand-written backend
// that satisfies the renderer seam exported by ZRenderKit (see PathRebuilder).
//
// This file only sketches the contract. No implementation yet — every body is a
// PORT-TODO stub. The intent is to pin down the ~8 paint operations the rest of the
// stack (style flattening, layering, hit testing) will be written against.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
import ZRenderKit

// MARK: - Opaque style payloads

#if canImport(CoreGraphics)

/// Resolved fill/stroke style for a single paint call. Mirrors the subset of
/// zrender's `PathStyleProps` the native backend actually consumes (solid color,
/// line width, dash, caps/joins, miter, fill-rule, opacity).
///
/// This is a *flattened* paint descriptor: the `ZRColor`/gradient/pattern union and
/// the `lineDash` enum from `PathStyleProps` are resolved into concrete Core Graphics
/// values by `PaintStyle.from(_:dpr:)` (see CGRenderer.swift). Gradient / pattern fills
/// are PORT-TODO this phase (they resolve to `nil` paint and are skipped).
public struct PaintStyle {
    /// Resolved solid fill color (premultiplied with `fillOpacity * opacity`). `nil` if
    /// no fill (or fill is `'none'` / a gradient / a pattern — PORT-TODO).
    public var fill: CGColor?
    /// Resolved solid stroke color (premultiplied with `strokeOpacity * opacity`).
    public var stroke: CGColor?

    public var lineWidth: Double = 1
    /// `nil` means a solid line (no dash).
    public var lineDash: [Double]?
    public var lineDashOffset: Double = 0
    public var lineCap: CGLineCap = .butt
    public var lineJoin: CGLineJoin = .miter
    public var miterLimit: Double = 10

    /// nonzero (`.winding`) vs even-odd. zrender's `PathStyleProps` has no fill-rule field;
    /// canvas defaults to nonzero. PORT-TODO: even-odd is never selected this phase.
    public var fillRule: CGPathFillRule = .winding

    /// Global element alpha (`style.opacity`), applied to ALL subsequent paint ops via
    /// `CGContext.setAlpha`. The per-paint `fillOpacity`/`strokeOpacity` are already baked
    /// into `fill`/`stroke` alpha above.
    public var opacity: Double = 1

    /// Paint order. `true` => stroke before fill (SVG `paint-order`). Matches upstream
    /// `PathStyleProps.strokeFirst`.
    public var strokeFirst: Bool = false

    // MARK: Gradient / pattern paint (resolved from the `ZRColor` union)

    /// Gradient fill object (`LinearGradient` / `RadialGradient`). When set, `fill` is `nil` and the
    /// gradient is drawn clipped to the path (see `CGRenderer.fillPath`). Mirrors zrender's
    /// `getCanvasGradient` (canvas/helper.ts) resolution.
    public var fillGradient: Gradient?
    /// Gradient stroke object. Stroked via `replacePathWithStrokedPath` + clip + gradient draw.
    public var strokeGradient: Gradient?

    /// Pattern fill object (best-effort tiled image — exotic cases are PORT-TODO).
    public var fillPattern: Pattern?
    /// Pattern stroke object.
    public var strokePattern: Pattern?

    /// `fillOpacity` (resp. `strokeOpacity`) — multiplied into gradient/pattern stop alpha. Solid
    /// colors already bake this into `fill`/`stroke` alpha, so this is only consumed by the
    /// gradient/pattern paths.
    public var fillAlpha: Double = 1
    public var strokeAlpha: Double = 1

    /// Element-local bounding rect, used for `objectBoundingBox` gradient coordinate resolution
    /// (`!global`). Populated by the painter from `el.getBoundingRect()` before painting; mirrors
    /// upstream's `rect = el.getBoundingRect()`. `nil` for `userSpaceOnUse` (`global`) gradients.
    public var boundingRect: CGRect?

    public init() {}
}

/// Resolved text style for `drawText` — flattened from a `TSpanStyleProps` by `TextStyle.from`.
/// Drives Core Text (CTLine) rendering in `CGRenderer.drawText`.
public struct TextStyle {
    /// CSS font shorthand (e.g. "italic bold 12px sans-serif"). Parsed by `parseCSSFont`.
    public var font: String?
    /// Discrete font fields (win over `font` when set). `fontSize` is in px.
    public var fontSize: Double?
    public var fontFamily: String?
    public var bold: Bool = false
    public var italic: Bool = false

    /// Resolved fill / stroke colors (per-glyph opacity already baked in).
    public var fill: CGColor?
    public var stroke: CGColor?
    public var lineWidth: Double = 1

    /// Canvas `textAlign` ('left'|'right'|'center'|'start'|'end') / `textBaseline`
    /// ('top'|'hanging'|'middle'|'alphabetic'|'ideographic'|'bottom').
    public var textAlign: String?
    public var textBaseline: String?

    /// Paint order (SVG paint-order). `true` => stroke before fill.
    public var strokeFirst: Bool = false

    public init() {}
}

/// Affine transform matching zrender's 2x3 `MatrixArray` (`[a, b, c, d, e, f]`).
///
/// zrender applies a point as `x' = a*x + c*y + e`, `y' = b*x + d*y + f`, which is exactly
/// Core Graphics' `CGAffineTransform(a, b, c, d, tx, ty)`. The component order is identical,
/// so the bridge is a direct field copy (no transpose / sign flip).
public struct AffineTransform {
    public var cg: CGAffineTransform

    public init(_ cg: CGAffineTransform) {
        self.cg = cg
    }

    /// Bridge from zrender's `MatrixArray` (`[a, b, c, d, e, f]`).
    public init(_ m: MatrixArray) {
        // upstream MatrixArray is `[a, b, c, d, e, f]`; CGAffineTransform is `(a, b, c, d, tx, ty)`.
        self.cg = CGAffineTransform(
            a: CGFloat(m[0]), b: CGFloat(m[1]),
            c: CGFloat(m[2]), d: CGFloat(m[3]),
            tx: CGFloat(m[4]), ty: CGFloat(m[5])
        )
    }

    public static let identity = AffineTransform(CGAffineTransform.identity)
}

/// Shadow parameters (shadowBlur / shadowColor / shadowOffsetX / shadowOffsetY).
public struct ShadowStyle {
    public var blur: Double
    public var color: CGColor
    public var offsetX: Double
    public var offsetY: Double

    public init(blur: Double, color: CGColor, offsetX: Double, offsetY: Double) {
        self.blur = blur
        self.color = color
        self.offsetX = offsetX
        self.offsetY = offsetY
    }
}

// MARK: - Renderer seam

/// The ~8 primitive paint operations the native backend must provide.
///
/// `Painter` is the high-level surface owner (a layer / context lifecycle); `Renderer`
/// is the per-frame drawing API the scene graph emits into. They are split because a
/// `Painter` may own several `Renderer`-backed layers (mirrors zrender's Painter/Layer).
public protocol Renderer: AnyObject {

    /// Append a shape's geometry. The shape replays its `PathProxy` commands into this
    /// rebuilder; the renderer accumulates them into a native path for the next fill/stroke.
    var pathRebuilder: PathRebuilder { get }

    /// 1. Fill the current path with `style`.
    func fillPath(_ style: PaintStyle)

    /// 2. Stroke the current path with `style`.
    func strokePath(_ style: PaintStyle)

    /// 3. Draw a bitmap image into the destination rect (optionally from a source rect).
    func drawImage(_ image: CGImage, dx: Double, dy: Double, dw: Double, dh: Double)

    /// 4. Draw a run of text at a point.
    func drawText(_ text: String, x: Double, y: Double, style: TextStyle)

    /// 5. Set / push the current clip region from the current path (nil clears clip).
    func setClip(_ path: PathRebuilder?)

    /// 6. Replace the current transform (concatenation is the caller's job, matching zrender).
    func transform(_ m: AffineTransform)

    /// 7. Set the global alpha applied to subsequent paint ops.
    func opacity(_ alpha: Double)

    /// 8. Set / clear the shadow applied to subsequent paint ops.
    func shadow(_ shadow: ShadowStyle?)
}

/// Surface owner: creates layers, drives the frame/flush lifecycle. Mirrors zrender's
/// `PainterBase`. PORT-TODO: resize, refresh, getRenderedCanvas/snapshot, dispose.
public protocol Painter: AnyObject {

    /// Device pixel ratio. PORT-TODO: wire to screen scale.
    var dpr: Double { get }

    /// Begin a frame and hand back the `Renderer` to draw into.
    func beginFrame() -> Renderer

    /// Commit the frame to the backing surface/layer.
    func endFrame()
}

#endif
