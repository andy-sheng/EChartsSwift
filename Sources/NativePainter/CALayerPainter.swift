// NativePainter — fresh native renderer (Core Graphics / Core Animation).
// This is NOT a translation of zrender's CanvasPainter/Layer. It is a hand-written backend.
//
// CALayerPainter owns a root CALayer and renders a hand-built scene graph (Group / Displayable
// tree from ZRenderKit) onto iOS / macOS. It offers two routes that share the same geometry &
// style flattening:
//   1. `render(_:)`      — retained-mode: builds a CAShapeLayer per Path under the root CALayer.
//   2. beginFrame/endFrame (the `Painter` seam) — immediate-mode: composites the scene into an
//      offscreen `CGContext` (via `CGRenderer`) and sets the result as `rootLayer.contents`.
// `renderToImage(group:size:)` is the snapshot convenience used by tests (immediate-mode route,
// the most deterministic — pure Core Graphics, no platform-dependent layer flipping).

import Foundation
#if canImport(CoreGraphics) && canImport(QuartzCore)
import CoreGraphics
import QuartzCore
import ZRenderKit

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - Display list (zlevel / z / z2 ordering, mirrors zrender's Storage)

/// Flatten a scene-graph root into the paint-ordered display list of `Displayable`s.
///
/// DFS over the tree (skipping `ignore`d subtrees), then a STABLE sort by `(zlevel, z, z2)`
/// — exactly zrender's `Storage` ordering. Stability is preserved by carrying the DFS index
/// as the final tiebreak (Swift's `sort` is not guaranteed stable).
public func flattenDisplayList(_ root: Element) -> [Displayable] {
    var collected: [Displayable] = []
    func walk(_ el: Element) {
        if el.ignore { return }
        if el.isGroup, let g = el as? Group {
            let children = g.childrenRef()
            for i in 0..<children.count {
                walk(children[i])
            }
        }
        else if let d = el as? Displayable {
            collected.append(d)
        }
    }
    walk(root)

    return collected.enumerated().sorted { a, b in
        let x = a.element, y = b.element
        if x.zlevel != y.zlevel { return x.zlevel < y.zlevel }
        if x.z != y.z { return x.z < y.z }
        if x.z2 != y.z2 { return x.z2 < y.z2 }
        return a.offset < b.offset   // stable tiebreak
    }.map { $0.element }
}

// MARK: - Immediate-mode scene walk (CGRenderer)

/// Draw the scene rooted at `root` into `renderer`'s context, in display-list order.
/// Only `Path` displayables are painted this phase (Text / Image are PORT-TODO).
public func renderScene(_ root: Element, into renderer: CGRenderer) {
    let list = flattenDisplayList(root)
    for el in list {
        if let p = el as? Path {
            drawPath(p, into: renderer)
        }
        else if let t = el as? TSpan {
            drawTSpan(t, into: renderer)
        }
        else if let img = el as? ZRImage {
            drawZRImage(img, into: renderer)
        }
        // else: unknown Displayable — nothing to paint.
    }
}

private func drawPath(_ p: Path, into r: CGRenderer) {
    if p.invisible { return }
    guard let style = p.pathStyle else { return }
    if style.opacity == 0 { return }

    r.save()
    defer { r.restore() }

    // 1. Clip (applied at the base CTM, with the clip path baked into its own world transform).
    if let clip = p.getClipPath() {
        applyClip(clip, into: r)
    }

    // 2. Element world transform (concatenated onto the base flipped+dpr CTM).
    if let world = p.getComputedTransform() {
        r.transform(AffineTransform(world))
    }

    var paint = PaintStyle.from(style)

    // 2b. Gradient bounding rect (objectBoundingBox / `!global` resolution). zrender resolves
    //     gradient coords against the element's LOCAL bounding rect (canvas/graphic.ts
    //     `rect = el.getBoundingRect()`), in the same space as the replayed path geometry.
    if paint.fillGradient != nil || paint.strokeGradient != nil {
        if let br = p.getBoundingRect() {
            paint.boundingRect = CGRect(x: br.x, y: br.y, width: br.width, height: br.height)
        }
    }

    // 3. Global element alpha.
    if paint.opacity != 1 {
        r.opacity(paint.opacity)
    }

    // 4. Shadow.
    if let shadow = makeShadow(style) {
        r.shadow(shadow)
    }

    // 5. Geometry: replay the Path's PathProxy into the renderer's CGPath rebuilder.
    r.beginPath()
    let pathProxy = p.getUpdatedPathProxy(false)
    pathProxy.rebuildPath(r.pathRebuilder, 1)

    // 6. Paint, honoring strokeFirst (SVG paint-order).
    if paint.strokeFirst {
        r.strokePath(paint)
        r.fillPath(paint)
    }
    else {
        r.fillPath(paint)
        r.strokePath(paint)
    }
}

/// Draw a positioned text run (a `TSpan`) into `r`. The run's anchor (style.x / style.y) and
/// align/baseline drive Core Text placement; the element world transform is concatenated onto the
/// base CTM (matching `drawPath`). Layout was pre-baked upstream (Contain/text + ZRText).
private func drawTSpan(_ t: TSpan, into r: CGRenderer) {
    if t.invisible { return }
    guard let style = t.tspanStyle else { return }
    if (style.opacity ?? 1) == 0 { return }
    guard let text = style.text, !text.isEmpty else { return }

    r.save()
    defer { r.restore() }

    if let clip = t.getClipPath() {
        applyClip(clip, into: r)
    }
    if let world = t.getComputedTransform() {
        r.transform(AffineTransform(world))
    }
    if let op = style.opacity, op != 1 {
        r.opacity(op)
    }
    // Shadow (CommonStyle subset mirrored onto t.style by TSpan._syncCommonStyle).
    if let shadow = makeShadow(t.style) {
        r.shadow(shadow)
    }

    let textStyle = TextStyle.from(style)
    r.drawText(text, x: style.x ?? 0, y: style.y ?? 0, style: textStyle)
}

/// Draw a `ZRImage` into `r`. Resolves the native `CGImage` from the image source (decoded
/// `__image` handle, an `.image(CGImage)` source, or a `.url` string decoded best-effort) and
/// blits it into the dest rect (style.x/y + getWidth/getHeight), honoring the optional source crop.
private func drawZRImage(_ img: ZRImage, into r: CGRenderer) {
    if img.invisible { return }
    guard let style = img.imageStyle else { return }
    if (style.opacity ?? 1) == 0 { return }
    guard let cg = resolveCGImage(img) else {
        // PORT-TODO: image not yet decoded (remote URL via platform.loadImage — renderer seam).
        return
    }

    r.save()
    defer { r.restore() }

    if let clip = img.getClipPath() {
        applyClip(clip, into: r)
    }
    if let world = img.getComputedTransform() {
        r.transform(AffineTransform(world))
    }
    if let op = style.opacity, op != 1 {
        r.opacity(op)
    }
    if let shadow = makeShadow(img.style) {
        r.shadow(shadow)
    }

    let dx = style.x ?? 0
    let dy = style.y ?? 0
    let dw = img.getWidth()
    let dh = img.getHeight()
    if dw <= 0 || dh <= 0 { return }

    // Source crop (sx/sy/sWidth/sHeight) — canvas `drawImage(img, sx, sy, sw, sh, dx, dy, dw, dh)`.
    if let sw = style.sWidth, let sh = style.sHeight, sw > 0, sh > 0 {
        r.drawImage(
            cg,
            sx: style.sx ?? 0, sy: style.sy ?? 0, sw: sw, sh: sh,
            dx: dx, dy: dy, dw: dw, dh: dh
        )
    }
    else {
        r.drawImage(cg, dx: dx, dy: dy, dw: dw, dh: dh)
    }
}

/// Resolve a `ZRImage`'s native `CGImage`. Prefers the painter-decoded `__image` handle, then an
/// inline `.image(CGImage)` source, then a best-effort decode of a `.url` string (file / data URI).
/// PORT-TODO: remote URL loading + async `onload` is the deferred renderer seam (CONVENTIONS §9).
private func resolveCGImage(_ img: ZRImage) -> CGImage? {
    if let cg = asCGImage(img.__image) { return cg }
    if case .some(.image(let like)) = img.imageStyle.image, let cg = asCGImage(like) {
        return cg
    }
    if case .some(.url(let s)) = img.imageStyle.image {
        return loadCGImage(s)
    }
    return nil
}

/// `Any?` → `CGImage?`. `ImageLike` is the opaque `Any` seam (CONVENTIONS §9); a plain
/// `as? CGImage` on `Any` mis-fires for CoreFoundation types, so dispatch on the CFTypeID.
private func asCGImage(_ value: Any?) -> CGImage? {
    guard let value = value else { return nil }
    let cf = value as CFTypeRef
    if CFGetTypeID(cf) == CGImage.typeID {
        return (cf as! CGImage)
    }
    return nil
}

/// Apply `clip` (a clip Path) as a clip region at the renderer's current (base) CTM. The clip's
/// own world transform is baked into the path so the clip is correct regardless of the element's
/// transform (which is concatenated AFTER this).
private func applyClip(_ clip: Path, into r: CGRenderer) {
    let rb = CGPathRebuilder()
    let pp = clip.getUpdatedPathProxy(false)
    pp.rebuildPath(rb, 1)
    var cgPath: CGPath = rb.path
    if let world = clip.getComputedTransform() {
        var t = AffineTransform(world).cg
        if let baked = rb.path.copy(using: &t) {
            cgPath = baked
        }
    }
    r.setClipPath(cgPath)
}

private func makeShadow(_ s: PathStyleProps) -> ShadowStyle? {
    return makeShadowCore(s.shadowBlur, s.shadowOffsetX, s.shadowOffsetY, s.shadowColor)
}

/// CommonStyleProps overload — used by TSpan / ZRImage, whose shadow fields are mirrored onto the
/// inherited `Displayable.style` (CommonStyleProps) by their `_syncCommonStyle()`.
private func makeShadow(_ s: CommonStyleProps) -> ShadowStyle? {
    return makeShadowCore(s.shadowBlur, s.shadowOffsetX, s.shadowOffsetY, s.shadowColor)
}

private func makeShadowCore(
    _ blurOpt: Double?, _ oxOpt: Double?, _ oyOpt: Double?, _ colorStr: String?
) -> ShadowStyle? {
    let blur = blurOpt ?? 0
    let ox = oxOpt ?? 0
    let oy = oyOpt ?? 0
    if blur == 0 && ox == 0 && oy == 0 { return nil }
    guard let cs = colorStr, let arr = color.parse(cs) else { return nil }
    let cg = CGColor(
        srgbRed: CGFloat(arr[0] / 255),
        green: CGFloat(arr[1] / 255),
        blue: CGFloat(arr[2] / 255),
        alpha: CGFloat(arr[3])
    )
    return ShadowStyle(blur: blur, color: cg, offsetX: ox, offsetY: oy)
}

// MARK: - Default device pixel ratio

func defaultDPR() -> Double {
    #if canImport(UIKit)
    return Double(UIScreen.main.scale)
    #elseif canImport(AppKit)
    return Double(NSScreen.main?.backingScaleFactor ?? 2)
    #else
    return 1
    #endif
}

// MARK: - CALayerPainter

public final class CALayerPainter: Painter {

    /// The layer that hosts the rendered scene. Add it to a view's layer for on-screen display.
    public let rootLayer: CALayer

    public let dpr: Double

    /// Logical (point) size of the drawing surface. Drives the offscreen frame buffer in
    /// beginFrame/endFrame.
    public var surfaceSize: CGSize

    /// Background fill for the immediate-mode composite (nil = transparent).
    public var backgroundColor: CGColor?

    private var _frameContext: CGContext?
    private var _frameRenderer: CGRenderer?

    public init(size: CGSize, dpr: Double? = nil, backgroundColor: CGColor? = nil) {
        self.surfaceSize = size
        self.dpr = dpr ?? defaultDPR()
        self.backgroundColor = backgroundColor
        let layer = CALayer()
        layer.bounds = CGRect(origin: .zero, size: size)
        layer.contentsScale = CGFloat(self.dpr)
        #if canImport(AppKit) && !canImport(UIKit)
        // AppKit CALayers are y-up by default; flip so retained-mode shape layers (whose paths are
        // in zrender's y-down space) render upright, matching iOS / canvas.
        layer.isGeometryFlipped = true
        #endif
        self.rootLayer = layer
    }

    // MARK: Retained-mode route — one CAShapeLayer per Path.

    /// Rebuild the root layer's sublayer tree: a `CAShapeLayer` per visible `Path`, added in
    /// display-list (zlevel/z/z2) order. The element world transform is baked into each shape's
    /// `CGPath` (so the shape layers sit at the identity transform and stacking order == array
    /// order).
    public func render(_ root: Element) {
        rootLayer.sublayers = nil
        let list = flattenDisplayList(root)
        for el in list {
            guard let p = el as? Path, !p.invisible, let style = p.pathStyle, style.opacity != 0 else {
                continue
            }
            if let shapeLayer = makeShapeLayer(p, style: style) {
                rootLayer.addSublayer(shapeLayer)
            }
        }
    }

    private func makeShapeLayer(_ p: Path, style: PathStyleProps) -> CAShapeLayer? {
        let rb = CGPathRebuilder()
        let pp = p.getUpdatedPathProxy(false)
        pp.rebuildPath(rb, 1)

        var cgPath: CGPath = rb.path
        if let world = p.getComputedTransform() {
            var t = AffineTransform(world).cg
            if let baked = rb.path.copy(using: &t) {
                cgPath = baked
            }
        }

        let paint = PaintStyle.from(style)

        let sl = CAShapeLayer()
        sl.contentsScale = CGFloat(dpr)
        sl.frame = CGRect(origin: .zero, size: surfaceSize)
        sl.path = cgPath
        sl.fillColor = paint.fill                       // nil => no fill (CAShapeLayer default is black)
        sl.fillRule = (paint.fillRule == .evenOdd) ? .evenOdd : .nonZero
        if let stroke = paint.stroke {
            sl.strokeColor = stroke
            sl.lineWidth = CGFloat(paint.lineWidth)
            sl.lineCap = caLineCap(style.lineCap)
            sl.lineJoin = caLineJoin(style.lineJoin)
            sl.miterLimit = CGFloat(paint.miterLimit)
            if let dash = paint.lineDash, !dash.isEmpty {
                sl.lineDashPattern = dash.map { NSNumber(value: $0) }
                sl.lineDashPhase = CGFloat(paint.lineDashOffset)
            }
        }
        else {
            sl.strokeColor = nil
            sl.lineWidth = 0
        }
        sl.opacity = Float(paint.opacity)

        // Shadow (CAShapeLayer applies it in layer space; offset sign matches canvas on iOS y-down
        // and on the flipped AppKit root layer). PORT-TODO: exact parity with zrender's CG shadow.
        if let shadow = makeShadow(style) {
            sl.shadowColor = shadow.color
            sl.shadowOpacity = 1
            sl.shadowRadius = CGFloat(shadow.blur)
            sl.shadowOffset = CGSize(width: CGFloat(shadow.offsetX), height: CGFloat(shadow.offsetY))
        }

        return sl
    }

    // MARK: Immediate-mode route — the `Painter` seam.

    public func beginFrame() -> Renderer {
        let pxW = Int((surfaceSize.width * CGFloat(dpr)).rounded())
        let pxH = Int((surfaceSize.height * CGFloat(dpr)).rounded())
        let cs = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(
            data: nil,
            width: Swift.max(pxW, 1),
            height: Swift.max(pxH, 1),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!

        if let bg = backgroundColor {
            ctx.setFillColor(bg)
            ctx.fill(CGRect(x: 0, y: 0, width: pxW, height: pxH))
        }

        // Flip to y-down (canvas convention) and apply dpr so 1 user unit == dpr device px.
        ctx.translateBy(x: 0, y: CGFloat(pxH))
        ctx.scaleBy(x: CGFloat(dpr), y: -CGFloat(dpr))

        let renderer = CGRenderer(ctx, flipped: true)
        _frameContext = ctx
        _frameRenderer = renderer
        return renderer
    }

    public func endFrame() {
        guard let ctx = _frameContext else { return }
        if let image = ctx.makeImage() {
            rootLayer.contents = image
        }
        _frameContext = nil
        _frameRenderer = nil
    }

    /// Composite `root` into the offscreen frame buffer and publish it to `rootLayer.contents`.
    public func renderComposite(_ root: Element) {
        let renderer = beginFrame()
        if let cg = renderer as? CGRenderer {
            renderScene(root, into: cg)
        }
        endFrame()
    }
}

// MARK: - PainterBase conformance (the ZRender host-facade seam)

/// `CALayerPainter` is the native implementation of ZRenderKit's `PainterBase` — the painter the
/// `ZRender` host facade drives. ZRenderKit cannot import NativePainter (the dependency runs the
/// other way), so the protocol is declared in ZRenderKit and the conformance lives here, where the
/// file-private draw helpers (`drawPath` / `drawTSpan` / `drawZRImage`) are visible.
///
/// `refresh(_:)` receives the already-flattened, z-sorted display list from `ZRender._refresh`
/// (`storage.getDisplayList(true)`), so it paints in order without re-flattening.
extension CALayerPainter: PainterBase {

    public func refresh(_ displayList: [Displayable]) {
        let renderer = beginFrame()
        if let cg = renderer as? CGRenderer {
            for el in displayList {
                if let p = el as? Path {
                    drawPath(p, into: cg)
                }
                else if let t = el as? TSpan {
                    drawTSpan(t, into: cg)
                }
                else if let img = el as? ZRImage {
                    drawZRImage(img, into: cg)
                }
                // else: unknown Displayable — nothing to paint.
            }
        }
        endFrame()
    }

    public func resize(_ width: Double?, _ height: Double?, _ dpr: Double?) {
        if let w = width, let h = height {
            surfaceSize = CGSize(width: w, height: h)
            rootLayer.bounds = CGRect(origin: .zero, size: surfaceSize)
        }
        // PORT-TODO: `dpr` is immutable on CALayerPainter (set at init); a dpr change needs a fresh
        //   painter / backing store. Honored only for width/height here.
    }

    public func clear() {
        rootLayer.contents = nil
        rootLayer.sublayers = nil
    }

    public func getWidth() -> Double {
        return Double(surfaceSize.width)
    }

    public func getHeight() -> Double {
        return Double(surfaceSize.height)
    }

    /// The host layer the scene is rendered into — the native equivalent of zrender's DOM
    /// `getViewportRoot()`. `ZRenderView` adds this as (a sublayer of) its backing layer, and the
    /// `NativeHandlerProxy` uses it as the coordinate reference for normalizing input.
    public func getViewportRoot() -> Any? {
        return rootLayer
    }

    public func dispose() {
        rootLayer.contents = nil
        rootLayer.sublayers = nil
    }
}

func caLineCap(_ s: String?) -> CAShapeLayerLineCap {
    switch s {
    case "round": return .round
    case "square": return .square
    default: return .butt
    }
}

func caLineJoin(_ s: String?) -> CAShapeLayerLineJoin {
    switch s {
    case "round": return .round
    case "bevel": return .bevel
    default: return .miter
    }
}

// MARK: - Snapshot convenience

/// Render the scene rooted at `group` into a `CGImage` of `size` points (at `dpr`).
///
/// Uses the immediate-mode `CGRenderer` route into a flipped bitmap context (pure Core Graphics,
/// deterministic across platforms) — equivalent geometry to the retained CAShapeLayer tree.
public func renderToImage(
    group: Element,
    size: CGSize,
    dpr: Double? = nil,
    backgroundColor: CGColor? = nil
) -> CGImage? {
    let painter = CALayerPainter(size: size, dpr: dpr, backgroundColor: backgroundColor)
    let renderer = painter.beginFrame()
    guard let cg = renderer as? CGRenderer else { return nil }
    renderScene(group, into: cg)
    return cg.ctx.makeImage()
}

#endif
