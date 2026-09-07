// Native Core Graphics / Core Animation painter.
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

import ApplePainterSupport

// MARK: - CALayerPainter

public final class CALayerPainter: Painter {

    public private(set) var storage: Storage?
    public var type: String { "canvas" }

    public convenience init(_ dom: Any?, _ storage: Storage,
                            _ opts: ZRenderInitOpt?, _ id: Double) {
        let host = dom as? ZRenderHost
        self.init(size: CGSize(width: opts?.width ?? host?.width ?? 0,
                               height: opts?.height ?? host?.height ?? 0),
                  dpr: opts?.devicePixelRatio ?? host?.devicePixelRatio)
        self.storage = storage
    }

    public static func register() {
        ZRenderKit.registerPainter("canvas") { CALayerPainter($0, $1, $2, $3) }
    }

    public func setBackgroundColor(_ backgroundColor: Any?) {
        if let value = backgroundColor as? String, let rgba = color.parse(value) {
            self.backgroundColor = CGColor(srgbRed: rgba[0] / 255, green: rgba[1] / 255,
                                           blue: rgba[2] / 255, alpha: rgba[3])
        } else {
            self.backgroundColor = nil
        }
        rootLayer.isOpaque = (self.backgroundColor?.alpha ?? 0) >= 1
        // PORT-TODO: gradient/pattern backgrounds still use ECharts' scene background element.
    }

    /// The layer that hosts the rendered scene. Add it to a view's layer for on-screen display.
    public let rootLayer: CALayer

    public let dpr: Double

    /// Logical (point) size of the drawing surface. Drives the offscreen frame buffer in
    /// beginFrame/endFrame.
    public var surfaceSize: CGSize

    /// Background fill for the immediate-mode composite (nil = transparent).
    public var backgroundColor: CGColor?

    private let _geometryCache = CGGeometryCache()
    private var _frameContext: CGContext?
    private var _frameRenderer: CGRenderer?

    // Motion-blur layer config (zr.configLayer): instead of clearing each frame, the previous frame is
    // composited at `_lastFrameAlpha`, leaving fading trails. Retained per-zlevel below.
    private var _motionBlur = false
    private var _lastFrameAlpha: Double = 0
    private var _lastFrameImage: CGImage?

    // ---- Per-zlevel LAYERS (faithful to zrender's one-canvas-per-zlevel model, canvas/Layer.ts). ----
    // A chart that calls `configLayer(zlevel, {motionBlur})` (only the lines flying-trail effect does)
    // switches `refresh` from the single-buffer fast path to a per-zlevel path: each distinct zlevel is
    // composited into its OWN transparent CALayer sublayer of `rootLayer`, and motion-blur (the previous
    // frame retained at `lastFrameAlpha`) applies ONLY to the configured zlevel's sublayer — so the effect
    // trail fades on its own layer while the axes/grid/other series (a lower zlevel) stay crisp. Charts
    // that never call configLayer keep the single `rootLayer.contents` bitmap (byte-identical behavior).
    private var _layerConfigs: [Double: LayerConfig] = [:]
    private var _zSublayers: [Double: CALayer] = [:]
    private var _zLastFrame: [Double: CGImage] = [:]   // per-zlevel motion-blur retained frame

    // Retained per-`IncrementalDisplayable` device-pixel bitmaps (keyed by element identity). Accumulate
    // dots across frames so only the pending ones are drawn each flush. See `drawIncrementalRetained`.
    private var _incrementalLayers: [ObjectIdentifier: CGContext] = [:]

    public init(size: CGSize, dpr: Double? = nil, backgroundColor: CGColor? = nil) {
        // Make the SVG `<pattern>` renderer seam available as soon as a native backend exists, so
        // parseSVG can resolve `url(#patternId)` fills to image-tile Patterns (idempotent).
        installSVGPatternRasterizer()
        // Back ZRenderKit's `platform.loadImage` seam with the native ImageIO decode so `.url` image
        // sources resolve through `platformApi.loadImage` (idempotent; CONVENTIONS §9).
        installNativePlatformAPI()
        self.surfaceSize = size
        self.dpr = dpr ?? defaultDPR()
        self.backgroundColor = backgroundColor
        let layer = CALayer()
        layer.bounds = CGRect(origin: .zero, size: size)
        layer.contentsScale = CGFloat(self.dpr)
        layer.actions = CALayerPainter.noImplicitActions
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
        // strokePercent: zrender rebuilds the path to its leading fraction (canvas/graphic.ts:225,
        // `path.rebuildPath(ctx, strokePart ? strokePercent : 1)`); fill and stroke both follow the
        // trimmed geometry ("Not support separate fill and stroke"). Mirror that here — geometry
        // trimming also renders correctly through CALayer.render(in:) (unlike CAShapeLayer.strokeEnd).
        let strokePercent = style.strokePercent ?? 1
        pp.rebuildPath(rb, strokePercent < 1 ? strokePercent : 1)

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
        // and on the flipped AppKit root layer). PORT-NOTE: exact parity with zrender's CG shadow is a platform-specific approximation.
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

        // Motion blur (zr.configLayer): composite the previous frame at `_lastFrameAlpha` over the fresh
        // background BEFORE drawing the new scene, so moving elements leave fading trails. Drawn here in
        // raw pixel space (before the y-flip/dpr below), matching how `endFrame`'s makeImage captured it.
        if _motionBlur, _lastFrameAlpha > 0, let prev = _lastFrameImage {
            ctx.saveGState()
            ctx.setAlpha(CGFloat(_lastFrameAlpha))
            ctx.draw(prev, in: CGRect(x: 0, y: 0, width: pxW, height: pxH))
            ctx.restoreGState()
        }

        // Flip to y-down (canvas convention) and apply dpr so 1 user unit == dpr device px.
        ctx.translateBy(x: 0, y: CGFloat(pxH))
        ctx.scaleBy(x: CGFloat(dpr), y: -CGFloat(dpr))

        let renderer = CGRenderer(ctx, flipped: true, geometryCache: _geometryCache)
        _frameContext = ctx
        _frameRenderer = renderer
        return renderer
    }

    public func endFrame() {
        guard let ctx = _frameContext else { return }
        if let image = ctx.makeImage() {
            // Publish WITHOUT Core Animation's implicit action. `contents` has a default animation — a
            // ~0.25s cross-fade — so assigning a new frame dissolves it over the previous one. With the
            // animation loop running the frames arrive faster than the fade and it mostly hides; but a
            // one-off repaint (drag a dataZoom with chart animation off) visibly GHOSTS the old chart
            // under the new one. Canvas has no such behaviour, and neither does the Metal painter
            // (CAMetalLayer presents drawables directly) — which is exactly why the ghosting only showed
            // up on this backend.
            withoutImplicitAnimation { rootLayer.contents = image }
            // Retain this frame as the source for the next frame's motion-blur composite.
            if _motionBlur { _lastFrameImage = image }
        }
        _frameContext = nil
        _frameRenderer = nil
    }

    /// Run a layer mutation with Core Animation's implicit actions off — a painter publishes finished
    /// frames, so every layer write here is a `set`, never something to animate.
    private func withoutImplicitAnimation(_ body: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        body()
        CATransaction.commit()
    }

    /// Kill Core Animation's implicit actions on every layer this painter owns, declaratively — a
    /// per-call-site `CATransaction` only protects the sites you remember to wrap, and the next
    /// `layer.contents = …` added would silently reintroduce the cross-fade. Canvas (and CAMetalLayer)
    /// have no such behaviour; a painter's layer must not either.
    static let noImplicitActions: [String: CAAction] = [
        "contents": NSNull(), "bounds": NSNull(), "position": NSNull(),
        "sublayers": NSNull(), "onOrderIn": NSNull(), "onOrderOut": NSNull(), "hidden": NSNull()
    ]

    /// upstream painter.configLayer(zLevel, config) — per-zlevel motion-blur config. Storing a config with
    /// `motionBlur == true` for any zlevel switches `refresh` to the per-zlevel layer path (see the
    /// `_layerConfigs` note). `motionBlur == false` clears that zlevel's config + retained frame, so a
    /// series that turns its effect OFF (upstream sets `motionBlur:false` on the old zlevel) reverts the
    /// layer to normal clear-each-frame compositing.
    public func configLayer(_ zLevel: Double, _ config: Any?) {
        guard let c = config as? LayerConfig else { return }
        if c.motionBlur {
            _layerConfigs[zLevel] = c
        }
        else {
            _layerConfigs[zLevel] = nil
            _zLastFrame[zLevel] = nil
        }
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
/// shared drawing helpers are provided by ApplePainterSupport.
///
/// `refresh(_:)` receives the already-flattened, z-sorted display list from `ZRender._refresh`
/// (`storage.getDisplayList(true)`), so it paints in order without re-flattening.
extension CALayerPainter: LayerHostedPainter {

    public func refresh(_ displayList: [Displayable]) {
        // No per-zlevel motion-blur config → single-buffer fast path (byte-identical to before). Every
        // chart except the lines flying-trail effect stays here.
        if _layerConfigs.isEmpty {
            if !_zSublayers.isEmpty { _teardownZLayers() }   // a prior frame used layers; revert cleanly
            _singleLayerRefresh(displayList)
            return
        }
        _perZLevelRefresh(displayList)
    }

    private func _singleLayerRefresh(_ displayList: [Displayable]) {
        let renderer = beginFrame()
        if let cg = renderer as? CGRenderer {
            drawDisplayListRespectingIncrementalLayers(displayList, into: cg) { el, target in
                self._drawOne(el, into: target)
            }
        }
        endFrame()
    }

    /// Draw one live-path element: an `IncrementalDisplayable` through its retained bitmap (O(pending)),
    /// everything else one-shot. Shared by the single-buffer and per-zlevel paths.
    private func _drawOne(_ el: Displayable, into cg: CGRenderer) {
        if let inc = el as? IncrementalDisplayable {
            drawIncrementalRetained(inc, into: cg)
        }
        else {
            drawDisplayable(el, into: cg)
        }
    }

    /// Faithful per-zlevel render (zrender canvas/Layer.ts): each distinct zlevel composites into its own
    /// transparent sublayer of `rootLayer`; motion-blur (previous frame retained at `lastFrameAlpha`)
    /// applies ONLY to a zlevel that was `configLayer`-ed, so the lines effect trail fades on its own layer
    /// while a lower-zlevel base (axes/grid/other series) stays crisp. The display list is already z-sorted,
    /// so same-zlevel elements are contiguous.
    private func _perZLevelRefresh(_ displayList: [Displayable]) {
        let pxW = Int((surfaceSize.width * CGFloat(dpr)).rounded())
        let pxH = Int((surfaceSize.height * CGFloat(dpr)).rounded())
        guard pxW > 0, pxH > 0 else { return }

        var order: [Double] = []
        var byZ: [Double: [Displayable]] = [:]
        for el in displayList {
            let z = el.zlevel
            if byZ[z] == nil { byZ[z] = []; order.append(z) }
            byZ[z]!.append(el)
        }
        let sortedZ = order.sorted()

        // The single-buffer path may have published a bitmap to rootLayer.contents on a prior frame; clear
        // it so the per-zlevel sublayers are what shows.
        rootLayer.contents = nil

        // Drop sublayers + retained frames for zlevels no longer present.
        let present = Set(sortedZ)
        for (z, sub) in _zSublayers where !present.contains(z) {
            sub.removeFromSuperlayer(); _zSublayers[z] = nil; _zLastFrame[z] = nil
        }

        for (i, z) in sortedZ.enumerated() {
            let cfg = _layerConfigs[z]
            guard let ctx = CGContext(
                data: nil, width: pxW, height: pxH, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { continue }

            // Background on the LOWEST zlevel only (drawn in raw pixel space, like beginFrame).
            if i == 0, let bg = backgroundColor {
                ctx.saveGState(); ctx.setFillColor(bg)
                ctx.fill(CGRect(x: 0, y: 0, width: pxW, height: pxH)); ctx.restoreGState()
            }
            // Motion blur: composite THIS zlevel's previous frame at its lastFrameAlpha (raw pixel space).
            if let cfg = cfg, cfg.motionBlur, cfg.lastFrameAlpha > 0, let prev = _zLastFrame[z] {
                ctx.saveGState(); ctx.setAlpha(CGFloat(cfg.lastFrameAlpha))
                ctx.draw(prev, in: CGRect(x: 0, y: 0, width: pxW, height: pxH)); ctx.restoreGState()
            }

            // Flip to y-down + dpr, then draw this zlevel's elements (same base CTM as beginFrame).
            ctx.translateBy(x: 0, y: CGFloat(pxH))
            ctx.scaleBy(x: CGFloat(dpr), y: -CGFloat(dpr))
            let cg = CGRenderer(ctx, flipped: true, geometryCache: _geometryCache)
            drawDisplayListRespectingIncrementalLayers(byZ[z]!, into: cg) { el, target in
                self._drawOne(el, into: target)
            }

            guard let image = ctx.makeImage() else { continue }
            _zLastFrame[z] = (cfg?.motionBlur ?? false) ? image : nil

            let sub = _ensureSublayer(z)
            sub.contents = image
            sub.zPosition = CGFloat(i)
        }
    }

    private func _ensureSublayer(_ z: Double) -> CALayer {
        if let s = _zSublayers[z] { return s }
        let s = CALayer()
        s.frame = CGRect(origin: .zero, size: surfaceSize)
        s.contentsScale = CGFloat(dpr)
        s.actions = CALayerPainter.noImplicitActions
        #if canImport(AppKit) && !canImport(UIKit)
        s.isGeometryFlipped = true   // match rootLayer so the pre-rendered frame image is upright
        #endif
        rootLayer.addSublayer(s)
        _zSublayers[z] = s
        return s
    }

    private func _teardownZLayers() {
        for (_, s) in _zSublayers { s.removeFromSuperlayer() }
        _zSublayers.removeAll()
        _zLastFrame.removeAll()
    }

    /// Test-only: number of live per-zlevel sublayers, and whether a zlevel has a retained motion-blur
    /// frame (proves the trail accumulates on that layer). See LayeredRenderingTests.
    public var _testZSublayerCount: Int { _zSublayers.count }
    public func _testHasRetainedFrame(_ z: Double) -> Bool { _zLastFrame[z] != nil }
    public func _testLayerConfigured(_ z: Double) -> Bool { _layerConfigs[z] != nil }
    public func _testRetainedFrameImage(_ z: Double) -> CGImage? { _zLastFrame[z] }
    public func _testSublayerContents(_ z: Double) -> CGImage? {
        guard let c = _zSublayers[z]?.contents else { return nil }
        return (c as! CGImage)
    }

    /// Render an `IncrementalDisplayable` through a per-element RETAINED device-pixel bitmap: only its
    /// *pending* displayables (the new ones since the last flush, via `eachPendingDisplayable`) are
    /// drawn into the persistent bitmap, then the whole bitmap is composited into the frame in raw pixel
    /// space (the same way `beginFrame` composites the motion-blur `_lastFrameImage`). So already-drawn
    /// dots are never repainted — the per-frame cost stays O(pending), which is what lets the incremental
    /// demo run at the html's real per-frame batch. `clearDisplaybles()` (notClear == false) wipes the
    /// bitmap. The bitmap matches `beginFrame`'s flip+dpr base CTM so element coords map identically.
    private func drawIncrementalRetained(_ inc: IncrementalDisplayable, into cg: CGRenderer) {
        let pxW = Int((surfaceSize.width * CGFloat(dpr)).rounded())
        let pxH = Int((surfaceSize.height * CGFloat(dpr)).rounded())
        guard pxW > 0, pxH > 0 else { return }
        let key = ObjectIdentifier(inc)

        let ic: CGContext
        if let existing = _incrementalLayers[key], existing.width == pxW, existing.height == pxH {
            ic = existing
        }
        else {
            guard let fresh = CGContext(
                data: nil, width: pxW, height: pxH, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            fresh.translateBy(x: 0, y: CGFloat(pxH))     // same flip + dpr base CTM as beginFrame
            fresh.scaleBy(x: CGFloat(dpr), y: -CGFloat(dpr))
            _incrementalLayers[key] = fresh
            ic = fresh
        }

        // clearDisplaybles() → notClear == false: wipe the retained pixels, then consume the signal.
        if inc.notClear == false {
            ic.saveGState()
            ic.concatenate(ic.ctm.inverted())            // raw pixel space
            ic.clear(CGRect(x: 0, y: 0, width: pxW, height: pxH))
            ic.restoreGState()
            inc.notClear = true
        }

        // Draw ONLY the pending displayables into the retained bitmap (blend/transform preserved), then
        // advance the cursor and drop the temp LIST (its pixels remain baked into the bitmap).
        let ir = CGRenderer(ic, flipped: true, geometryCache: _geometryCache)
        inc.eachPendingDisplayable { d in drawDisplayable(d, into: ir) }
        inc.innerAfterBrush()
        inc.clearTemporalDisplayables()

        // Composite the accumulated bitmap into the frame, 1:1 in raw pixel space.
        if let image = ic.makeImage() {
            cg.ctx.saveGState()
            cg.ctx.concatenate(cg.ctx.ctm.inverted())
            cg.ctx.draw(image, in: CGRect(x: 0, y: 0, width: pxW, height: pxH))
            cg.ctx.restoreGState()
        }
    }

    public func resize(_ width: Double?, _ height: Double?, _ dpr: Double?) {
        if let w = width, let h = height {
            surfaceSize = CGSize(width: w, height: h)
            rootLayer.bounds = CGRect(origin: .zero, size: surfaceSize)
            _incrementalLayers.removeAll()   // retained bitmaps are sized to the old surface
        }
        // PORT-NOTE (platform): `dpr` is immutable on CALayerPainter (set at init); a dpr change needs a fresh
        //   painter / backing store. Honored only for width/height here.
    }

    public func clear() {
        _geometryCache.removeAll()
        rootLayer.contents = nil
        rootLayer.sublayers = nil
        _incrementalLayers.removeAll()
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
        _geometryCache.removeAll()
        storage = nil
        rootLayer.contents = nil
        rootLayer.sublayers = nil
        _incrementalLayers.removeAll()
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
    return ApplePainterSupport.renderToImage(group: group, size: size, dpr: dpr,
                                            backgroundColor: backgroundColor)
}

#endif
