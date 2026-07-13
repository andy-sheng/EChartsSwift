// RasterizerPainter — EXPERIMENTAL alternative live painter over mindbrix/Rasterizer
// (third_party/Rasterizer, GPU/Metal). NOT a translation of anything upstream; it satisfies
// the same `PainterBase` seam as `CALayerPainter` and can be injected into `ZRenderView`.
//
// Model mismatch it bridges: our pipeline is immediate-mode ("here is the z-sorted display
// list, repaint"), Rasterizer is scene-mode ("build an RAScene of path+paint+ctm records,
// the engine rasterizes it"). Both rebuild the full frame each refresh, so the bridge is a
// straight in-order translation: one `addFill`/`addStroke` per paint op, insertion order ==
// z order. zrender's y-down world becomes the engine's y-up scene via one global flip on
// `RASceneList.ctm` (exactly how the engine's own SVG importer handles y-down documents).
//
// PERFORMANCE: the engine's CPU stage is very fast (0.4ms for 5000 paths); the naive
// per-frame translation was the bottleneck (16ms for animationStart's 5000 dots). Three
// caches bring it down: geometry (RAPath per Path element, invalidated by a PathProxy data
// snapshot — animation usually moves transforms, not shapes), solid paints (by quantized
// RGBA), and text glyph outlines (by font+text).
//
// MOTION BLUR (zr.configLayer): implemented in the ENGINE layer (a local modification to
// the vendored RasterizerLayer) as a feedback pass — a persistent texture retains each
// presented frame, and the next frame composites it at lastFrameAlpha over the clear color
// before the scene renders; the drawable is blitted back after. That is byte-for-byte the
// zrender canvas/Layer.ts back-buffer mechanism (and the CG painter's port of it), so
// self-overlap, non-solid paints and edge accumulation all match pixel-wise.
// PORT-NOTE: the feedback covers the WHOLE layer (max lastFrameAlpha across configured
// zlevels), not per-zlevel — non-blurred zlevels redraw opaquely each frame so static
// content stays crisp; only MOVING content on a non-blurred zlevel would incorrectly trail.
// PORT-NOTE: the headless CG reference render (renderToImage) has no feedback loop — use
// renderMetalFrame() (real pipeline readback) to verify blur.
//
// KNOWN GAPS (PORT-NOTEs inline):
//   - shadows (shadowBlur/offset)      — engine has no shadow support; skipped.
//   - blend modes (style.blend)        — engine composites source-over only; skipped.
//   - bevel join / miterLimit          — engine joins are miter|round; bevel falls back to miter.
//   - clip chains longer than 1        — engine takes ONE clip path + one rect per record;
//     the innermost path + the intersected bounding rect of the chain approximates nesting.
//   - incremental displayables         — redrawn in full each frame (the engine's model);
//     temporal displayables are NOT discarded after paint, so they survive scene rebuilds.
//   - image paint opacity              — RAPaint carries no global alpha for image fills.

import Foundation
#if canImport(QuartzCore) && canImport(Metal)
import CoreGraphics
import CoreText
import QuartzCore
import ZRenderKit
import NativePainter
import RasterizerObjC

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

public final class RasterizerPainter {

    /// The Metal-backed layer (`RasterizerLayer`) the scene renders into.
    public let rootLayer: CALayer

    public let dpr: Double

    public private(set) var surfaceSize: CGSize

    /// Frame clear color (nil = transparent).
    public var backgroundColor: CGColor?

    /// The most recently published scene list — kept for the headless CG reference render.
    public private(set) var lastSceneList: RASceneList?

    private let host: RARenderHost

    // MARK: Caches (see PERFORMANCE note in the header)

    /// Per-element translated geometry. Weak keys so entries die with their elements;
    /// pointer-personality so lookup is identity, not isEqual.
    private let _geomCache = NSMapTable<AnyObject, GeomEntry>(
        keyOptions: [.weakMemory, .objectPointerPersonality], valueOptions: .strongMemory)

    private final class GeomEntry {
        var dataSnapshot: ContiguousArray<Double>
        var strokePercent: Double
        var cgPath: CGPath
        var raPath: RAPath
        // Solid-paint fast path: fill/stroke PaintOp templates (ctm/clip refreshed per frame),
        // valid while `styleSig` matches the element's current style inputs. nil sig => the
        // style has gradient/pattern arms (or hasn't been built) -> full flattening path.
        var styleSig: StyleSig?
        var fillTemplate: PaintOp?
        var strokeTemplate: PaintOp?
        var strokeFirst = false
        init(dataSnapshot: ContiguousArray<Double>, strokePercent: Double,
             cgPath: CGPath, raPath: RAPath) {
            self.dataSnapshot = dataSnapshot
            self.strokePercent = strokePercent
            self.cgPath = cgPath
            self.raPath = raPath
        }
    }

    /// The raw style inputs the solid fill/stroke flattening consumes — comparing these per
    /// frame (String compares hit the identical-storage fast path) replaces re-running
    /// PaintStyle.from + color.parse + CGColor allocation for every element every frame.
    private struct StyleSig: Equatable {
        var fillStr: String?
        var strokeStr: String?
        var opacity: Double
        var fillOpacity: Double
        var strokeOpacity: Double
        var lineWidth: Double
        var lineDashOffset: Double
        var miterLimit: Double
        var lineCap: String?
        var lineJoin: String?
        var strokeFirst: Bool
        var lineScale: Double      // strokeNoScale divides width by the transform's scale
        var dashCase: Int          // 0 none/solid, 1 dashed, 2 dotted, 3 explicit values
        var dashValues: [Double]?
    }

    /// Build the signature, or nil when the style needs the full path (gradient/pattern arms).
    private func makeStyleSig(_ p: ZRenderKit.Path, _ style: PathStyleProps) -> StyleSig? {
        var fillStr: String? = nil
        switch style.fill {
        case nil: break
        case .string(let str)?: fillStr = str
        default: return nil
        }
        var strokeStr: String? = nil
        switch style.stroke {
        case nil: break
        case .string(let str)?: strokeStr = str
        default: return nil
        }
        var dashCase = 0
        var dashValues: [Double]? = nil
        switch style.lineDash {
        case nil: break
        case .some(.dashed): dashCase = 1
        case .some(.dotted): dashCase = 2
        case .some(.values(let v)): dashCase = 3; dashValues = v
        default: break
        }
        return StyleSig(
            fillStr: fillStr, strokeStr: strokeStr,
            opacity: style.opacity ?? 1,
            fillOpacity: style.fillOpacity ?? 1,
            strokeOpacity: style.strokeOpacity ?? 1,
            lineWidth: style.lineWidth ?? 1,
            lineDashOffset: style.lineDashOffset ?? 0,
            miterLimit: style.miterLimit ?? 10,
            lineCap: style.lineCap, lineJoin: style.lineJoin,
            strokeFirst: style.strokeFirst ?? false,
            lineScale: style.strokeNoScale == true ? p.getLineScale() : 1,
            dashCase: dashCase, dashValues: dashValues
        )
    }

    /// Solid RAPaints by quantized RGBA (8 bits/channel — the engine quantizes anyway).
    private var _paintCache: [UInt32: RAPaint] = [:]

    /// Glyph outlines by font+text (TSpans are often rebuilt objects, so key by content).
    private final class GlyphEntry {
        let raPath: RAPath?      // nil => no outline glyphs (e.g. emoji-only run)
        let width: Double
        let ascent: CGFloat
        let descent: CGFloat
        init(raPath: RAPath?, width: Double, ascent: CGFloat, descent: CGFloat) {
            self.raPath = raPath; self.width = width; self.ascent = ascent; self.descent = descent
        }
    }
    private var _glyphCache: [String: GlyphEntry] = [:]

    /// Pre-flipped image paints keyed by CGImage identity (NSCache: strong keys, identity
    /// isEqual for CF types, memory-pressure eviction).
    private let _imagePaintCache = NSCache<AnyObject, RAPaint>()

    // MARK: Motion blur (engine feedback pass; see MOTION BLUR note in the header)

    private var _layerConfigs: [Double: LayerConfig] = [:]

    public init(size: CGSize, dpr: Double? = nil, backgroundColor: CGColor? = nil) {
        let scale = dpr ?? Self.defaultScale()
        self.dpr = scale
        self.surfaceSize = size
        self.backgroundColor = backgroundColor
        self.host = RARenderHost(scale: CGFloat(scale))
        self.rootLayer = host.layer
        rootLayer.bounds = CGRect(origin: .zero, size: size)
        rootLayer.isOpaque = (backgroundColor?.alpha ?? 0) >= 1
        // Upstream RasterizerLayer sets magnificationFilter = nearest (pixel inspection in
        // their demo app). Under a fit-scaling host (the galleries magnify the pane up for
        // small demos) nearest turns edge anti-aliasing into visible stair-steps — composite
        // like CALayerPainter's layer (default linear) so both backends scale identically.
        rootLayer.magnificationFilter = .linear
        rootLayer.minificationFilter = .linear
    }

    private static func defaultScale() -> Double {
        #if canImport(UIKit)
        return Double(UIScreen.main.scale)
        #elseif canImport(AppKit)
        return Double(NSScreen.main?.backingScaleFactor ?? 2)
        #else
        return 1
        #endif
    }

    // MARK: - Paint ops (the unit of emission — recordable for motion-blur replay)

    private struct PaintOp {
        var path: RAPath
        var ctm: CGAffineTransform
        var paint: RAPaint
        var isFill: Bool
        var evenOdd: Bool = false
        var width: Double = 0
        var cap: RACapStyle = .capButt
        var join: RAJoinStyle = .joinMiter
        var clipRect: CGRect = .null
        var clipPath: RAPath?
    }

    private func apply(_ op: PaintOp, to scene: RAScene) {
        if op.isFill {
            scene.addFill(op.path, ctm: op.ctm, color: op.paint, evenOdd: op.evenOdd,
                          clip: op.clipRect, clipPath: op.clipPath)
        } else {
            scene.addStroke(op.path, ctm: op.ctm, color: op.paint, width: op.width,
                            capStyle: op.cap, joinStyle: op.join,
                            clip: op.clipRect, clipPath: op.clipPath)
        }
    }

    // MARK: - Display list -> RASceneList

    /// Translate the (already flattened + z-sorted) display list into an engine scene list.
    /// Public so the headless verification path can build + CPU-render without a display.
    public func buildSceneList(_ displayList: [Displayable]) -> RASceneList {
        let scene = RAScene()
        for el in displayList {
            addDisplayable(el) { self.apply($0, to: scene) }
        }

        let list = RASceneList(scene: scene)
        // zrender's y-down world -> the engine's y-up scene (mirrors RasterizerSVG's
        // `Transform(1, 0, 0, -1, 0, height)` for y-down SVG documents).
        list.ctm = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: surfaceSize.height)
        list.useClips = true
        list.useCurves = true
        if let bg = backgroundColor {
            list.clearColor = RAPaint(cgColor: bg)
        }
        return list
    }

    private func addDisplayable(_ el: Displayable, _ sink: (PaintOp) -> Void) {
        if let p = el as? ZRenderKit.Path {
            addPath(p, sink)
        }
        else if let t = el as? TSpan {
            addTSpan(t, sink)
        }
        else if let img = el as? ZRImage {
            addImage(img, sink)
        }
        else if let inc = el as? IncrementalDisplayable {
            // PORT-NOTE (engine model): the scene is rebuilt every frame, so ALL accumulated
            // displayables redraw each refresh (no retained-bitmap O(pending) shortcut here),
            // and temporal displayables must NOT be cleared or they vanish next frame.
            for d in inc.getDisplayables() { addDisplayable(d, sink) }
            for d in inc.getTemporalDisplayables() { addDisplayable(d, sink) }
        }
        // else: unknown Displayable — nothing to paint.
    }

    // MARK: Path

    /// Cached geometry lookup: rebuild only when the PathProxy's replayed data changed
    /// (compared against a snapshot — transform-only animation reuses the same RAPath).
    private func geometry(for p: ZRenderKit.Path, strokePercent: Double) -> GeomEntry? {
        let pp = p.getCachedPathProxy(false)
        let len = Int(pp.len())
        if len <= 0 { return nil }
        if let e = _geomCache.object(forKey: p),
           e.strokePercent == strokePercent,
           e.dataSnapshot.count == len,
           // memcmp, not elementsEqual — the generic path iterates via protocol witnesses
           // and dominated the profile at 5000 elements/frame.
           e.dataSnapshot.withUnsafeBufferPointer({ a in
               pp.data.withUnsafeBufferPointer { b in
                   memcmp(a.baseAddress!, b.baseAddress!, len * MemoryLayout<Double>.stride) == 0
               }
           }) {
            return e
        }
        let rb = CGPathRebuilder()
        pp.rebuildPath(rb, strokePercent)
        if rb.path.isEmpty { return nil }
        let entry = GeomEntry(
            dataSnapshot: ContiguousArray(pp.data[0..<len]),
            strokePercent: strokePercent,
            cgPath: rb.path,
            raPath: RAPath(cgPath: rb.path)
        )
        _geomCache.setObject(entry, forKey: p)
        return entry
    }

    private func addPath(_ p: ZRenderKit.Path, _ sink: (PaintOp) -> Void) {
        if p.invisible { return }
        guard let style = p.pathStyle else { return }
        if style.opacity == 0 { return }

        let clip = resolveClip(p)
        if clip.clippedOut { return }

        let world = (p.getComputedTransform().map { AffineTransform($0).cg }) ?? .identity

        // Geometry (strokePercent trims the replayed path, mirroring CALayerPainter.drawPath).
        let strokePercent = style.strokePercent ?? 1
        guard let geom = geometry(for: p, strokePercent: strokePercent < 1 ? strokePercent : 1) else {
            return
        }

        // FAST PATH: solid fill/stroke with an unchanged style — re-emit the cached PaintOp
        // templates with this frame's ctm/clip (skips PaintStyle.from / color.parse / paint
        // construction entirely; see the PERFORMANCE header note).
        let sig = makeStyleSig(p, style)
        if let sig = sig, geom.styleSig == sig {
            func emitTemplate(_ tmpl: PaintOp?) {
                guard var op = tmpl else { return }
                op.ctm = world
                op.clipRect = clip.rect
                op.clipPath = clip.path
                sink(op)
            }
            if geom.strokeFirst {
                emitTemplate(geom.strokeTemplate); emitTemplate(geom.fillTemplate)
            } else {
                emitTemplate(geom.fillTemplate); emitTemplate(geom.strokeTemplate)
            }
            return
        }

        var paint = PaintStyle.from(style)
        if style.strokeNoScale == true {
            let lineScale = p.getLineScale()
            if lineScale > 1e-10 { paint.lineWidth /= lineScale }
        }

        let alpha = paint.opacity
        let localRect: CGRect? = (paint.fillGradient != nil || paint.strokeGradient != nil
                                  || paint.fillPattern != nil)
            ? p.getBoundingRect().map { CGRect(x: $0.x, y: $0.y, width: $0.width, height: $0.height) }
            : nil

        // Capture the built ops as templates for the fast path (solid styles only).
        geom.styleSig = sig
        geom.fillTemplate = nil
        geom.strokeTemplate = nil
        geom.strokeFirst = paint.strokeFirst
        let capturingSink: (PaintOp) -> Void = { op in
            if sig != nil {
                if op.isFill { geom.fillTemplate = op } else { geom.strokeTemplate = op }
            }
            sink(op)
        }

        // PORT-NOTE: shadows (style.shadowBlur/...) and blend modes (style.blend) are
        // unsupported by the engine and skipped here.
        if paint.strokeFirst {
            emitStroke(geom, paint: paint, alpha: alpha, localRect: localRect,
                       world: world, clip: clip, capturingSink)
            emitFill(geom, paint: paint, alpha: alpha, localRect: localRect,
                     world: world, clip: clip, capturingSink)
        } else {
            emitFill(geom, paint: paint, alpha: alpha, localRect: localRect,
                     world: world, clip: clip, capturingSink)
            emitStroke(geom, paint: paint, alpha: alpha, localRect: localRect,
                       world: world, clip: clip, capturingSink)
        }
    }

    private func emitFill(
        _ geom: GeomEntry, paint: PaintStyle, alpha: Double, localRect: CGRect?,
        world: CGAffineTransform, clip: ResolvedClip, _ sink: (PaintOp) -> Void
    ) {
        let evenOdd = paint.fillRule == .evenOdd
        if let g = paint.fillGradient {
            if let gp = makeGradientPaint(g, alpha: paint.fillAlpha * alpha, localRect: localRect) {
                sink(PaintOp(path: geom.raPath, ctm: world, paint: gp,
                             isFill: true, evenOdd: evenOdd,
                             clipRect: clip.rect, clipPath: clip.path))
            }
            return
        }
        if let pat = paint.fillPattern {
            // Cover rect from the CGPath — RAPath.bounds is uninitialized until the path
            // enters a scene. (The engine stretches the texture over the path's own bounds.)
            if let pp = makePatternPaint(pat, coverRect: geom.cgPath.boundingBoxOfPath,
                                         alpha: paint.fillAlpha * alpha) {
                sink(PaintOp(path: geom.raPath, ctm: world, paint: pp,
                             isFill: true, evenOdd: evenOdd,
                             clipRect: clip.rect, clipPath: clip.path))
            }
            return
        }
        guard let fill = paint.fill else { return }
        sink(PaintOp(path: geom.raPath, ctm: world, paint: solidPaint(fill, alpha: alpha),
                     isFill: true, evenOdd: evenOdd,
                     clipRect: clip.rect, clipPath: clip.path))
    }

    private func emitStroke(
        _ geom: GeomEntry, paint: PaintStyle, alpha: Double, localRect: CGRect?,
        world: CGAffineTransform, clip: ResolvedClip, _ sink: (PaintOp) -> Void
    ) {
        guard paint.lineWidth > 0 else { return }

        // Gradient/pattern stroke: outline the stroke (CG's stroked-path copy) and fill the
        // outline — the same emulation CGRenderer.strokeWithPaint uses.
        if paint.strokeGradient != nil || paint.strokePattern != nil {
            let outlined = geom.cgPath.copy(
                strokingWithWidth: CGFloat(paint.lineWidth),
                lineCap: paint.lineCap, lineJoin: paint.lineJoin,
                miterLimit: CGFloat(paint.miterLimit)
            )
            if outlined.isEmpty { return }
            let outlinePath = RAPath(cgPath: outlined)
            if let g = paint.strokeGradient,
               let gp = makeGradientPaint(g, alpha: paint.strokeAlpha * alpha, localRect: localRect) {
                sink(PaintOp(path: outlinePath, ctm: world, paint: gp,
                             isFill: true, clipRect: clip.rect, clipPath: clip.path))
            }
            else if let pat = paint.strokePattern,
                    let pp = makePatternPaint(pat, coverRect: outlined.boundingBoxOfPath,
                                              alpha: paint.strokeAlpha * alpha) {
                sink(PaintOp(path: outlinePath, ctm: world, paint: pp,
                             isFill: true, clipRect: clip.rect, clipPath: clip.path))
            }
            return
        }

        guard let stroke = paint.stroke else { return }
        var strokePath = geom.raPath
        if let dash = paint.lineDash, !dash.isEmpty {
            // Canvas repeats an odd-length dash array to even length; the engine's dasher
            // needs >= 2 lengths (it returns the path unchanged for fewer).
            let lengths = dash.count % 2 == 0 ? dash : dash + dash
            strokePath = geom.raPath.dashedCopy(withPhase: paint.lineDashOffset,
                                                lengths: lengths.map { NSNumber(value: $0) })
        }
        sink(PaintOp(path: strokePath, ctm: world,
                     paint: solidPaint(stroke, alpha: alpha),
                     isFill: false,
                     width: paint.lineWidth,
                     cap: mapCap(paint.lineCap),
                     join: mapJoin(paint.lineJoin),   // PORT-NOTE: bevel falls back to miter
                     clipRect: clip.rect, clipPath: clip.path))
    }

    // MARK: Text (TSpan -> glyph outlines)

    /// A TSpan is one pre-positioned single-line run. The engine renders text as glyph
    /// outlines; extracting them ourselves (CTLine -> CTRun -> CTFontCreatePathForGlyph)
    /// keeps the anchor math EXACTLY CGRenderer.drawText's (same CTLine metrics), instead
    /// of trusting a CTFramesetter to reproduce the same layout inside a rect. Outlines +
    /// metrics are cached by font+text (TSpan objects are often rebuilt, so key by content).
    /// PORT-NOTE: bitmap/color glyphs (emoji) have no outline path and are skipped.
    private func glyphs(for text: String, style textStyle: TextStyle) -> GlyphEntry {
        let key = "\(textStyle.fontSize ?? -1)|\(textStyle.fontFamily ?? "")|\(textStyle.font ?? "")|\(textStyle.bold)|\(textStyle.italic)|\(text)"
        if let e = _glyphCache[key] { return e }

        let font = textStyle.makeCTFont()
        let attr = NSAttributedString(string: text, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font
        ])
        let line = CTLineCreateWithAttributedString(attr)
        var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
        let width = CTLineGetTypographicBounds(line, &ascent, &descent, &leading)

        // Collect the glyph outlines in y-UP text space, baseline at the origin.
        let glyphPath = CGMutablePath()
        let runs = CTLineGetGlyphRuns(line) as NSArray
        for i in 0..<runs.count {
            let run = runs[i] as! CTRun
            let count = CTRunGetGlyphCount(run)
            if count == 0 { continue }
            var glyphIds = [CGGlyph](repeating: 0, count: count)
            var positions = [CGPoint](repeating: .zero, count: count)
            CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &glyphIds)
            CTRunGetPositions(run, CFRange(location: 0, length: 0), &positions)
            let attrs = CTRunGetAttributes(run) as NSDictionary
            let runFont = (attrs[kCTFontAttributeName as String] as! CTFont)
            for j in 0..<count {
                if let gp = CTFontCreatePathForGlyph(runFont, glyphIds[j], nil) {
                    let shift = CGAffineTransform(translationX: positions[j].x, y: positions[j].y)
                    glyphPath.addPath(gp, transform: shift)
                }
            }
        }
        let entry = GlyphEntry(
            raPath: glyphPath.isEmpty ? nil : RAPath(cgPath: glyphPath),
            width: width, ascent: ascent, descent: descent
        )
        if _glyphCache.count > 2048 { _glyphCache.removeAll(keepingCapacity: true) }
        _glyphCache[key] = entry
        return entry
    }

    private func addTSpan(_ t: TSpan, _ sink: (PaintOp) -> Void) {
        if t.invisible { return }
        guard let style = t.tspanStyle else { return }
        if (style.opacity ?? 1) == 0 { return }
        guard let text = style.text, !text.isEmpty else { return }

        let clip = resolveClip(t)
        if clip.clippedOut { return }

        let textStyle = TextStyle.from(style)
        guard textStyle.fill != nil || textStyle.stroke != nil else { return }

        let entry = glyphs(for: text, style: textStyle)
        guard let raPath = entry.raPath else { return }

        // Anchor math — keep identical to CGRenderer.drawText.
        let dx: CGFloat
        switch textStyle.textAlign {
        case "right", "end": dx = -CGFloat(entry.width)
        case "center": dx = -CGFloat(entry.width) / 2
        default: dx = 0
        }
        let by: CGFloat
        switch textStyle.textBaseline {
        case "top", "hanging": by = entry.ascent
        case "middle": by = (entry.ascent - entry.descent) / 2
        case "bottom", "ideographic": by = -entry.descent
        default: by = 0   // alphabetic
        }
        let px = CGFloat(style.x ?? 0) + dx
        let py = CGFloat(style.y ?? 0) + by

        // Glyphs are y-up; the scene is globally y-flipped. Flip locally about the baseline
        // anchor so the net glyph orientation on screen is upright:
        //   textLocal (gx, gy) -> world (px + gx, py - gy).
        let anchor = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: px, ty: py)
        let world = (t.getComputedTransform().map { AffineTransform($0).cg }) ?? .identity
        let ctm = anchor.concatenating(world)

        let alpha = style.opacity ?? 1
        func emitTextFill() {
            if let fill = textStyle.fill {
                sink(PaintOp(path: raPath, ctm: ctm, paint: solidPaint(fill, alpha: alpha),
                             isFill: true,
                             clipRect: clip.rect, clipPath: clip.path))
            }
        }
        func emitTextStroke() {
            if let stroke = textStyle.stroke, textStyle.lineWidth > 0 {
                sink(PaintOp(path: raPath, ctm: ctm, paint: solidPaint(stroke, alpha: alpha),
                             isFill: false,
                             width: textStyle.lineWidth,
                             clipRect: clip.rect, clipPath: clip.path))
            }
        }
        if textStyle.strokeFirst {
            emitTextStroke(); emitTextFill()
        } else {
            emitTextFill(); emitTextStroke()
        }
    }

    // MARK: Image

    private func addImage(_ img: ZRImage, _ sink: (PaintOp) -> Void) {
        if img.invisible { return }
        guard let style = img.imageStyle else { return }
        if (style.opacity ?? 1) == 0 { return }
        guard var cg = resolveCGImage(img) else { return }

        let clip = resolveClip(img)
        if clip.clippedOut { return }

        let dx = style.x ?? 0
        let dy = style.y ?? 0
        let dw = img.getWidth()
        let dh = img.getHeight()
        if dw <= 0 || dh <= 0 { return }

        // Source crop (canvas drawImage(img, sx, sy, sw, sh, ...)).
        if let sw = style.sWidth, let sh = style.sHeight, sw > 0, sh > 0 {
            let crop = CGRect(x: style.sx ?? 0, y: style.sy ?? 0, width: sw, height: sh)
            cg = cg.cropping(to: crop) ?? cg
        }

        // An image paint stretches over its path's bounds; under the global y-flip the
        // texture reads upside-down (texCtm maps the MIN-corner of the device quad to v=0,
        // and the paint buffer stores rows top-first), so pre-flip the pixels once (cached
        // by source-image identity).
        let paint: RAPaint
        if let cached = _imagePaintCache.object(forKey: cg) {
            paint = cached
        } else {
            guard let flipped = Self.verticallyFlipped(cg) else { return }
            // PORT-NOTE: RAPaint carries no global alpha for image fills — style.opacity is
            // not applied to images.
            paint = RAPaint(cgImage: flipped)
            _imagePaintCache.setObject(paint, forKey: cg)
        }
        let raPath = RAPath(rect: CGRect(x: 0, y: 0, width: dw, height: dh))
        let world = (img.getComputedTransform().map { AffineTransform($0).cg }) ?? .identity
        let ctm = CGAffineTransform(translationX: dx, y: dy).concatenating(world)
        sink(PaintOp(path: raPath, ctm: ctm, paint: paint, isFill: true,
                     clipRect: clip.rect, clipPath: clip.path))
    }

    private func resolveCGImage(_ img: ZRImage) -> CGImage? {
        if let cg = Self.asCGImage(img.__image) { return cg }
        if case .some(.image(let like)) = img.imageStyle.image, let cg = Self.asCGImage(like) {
            return cg
        }
        if case .some(.url(let s)) = img.imageStyle.image {
            return loadCGImage(s)
        }
        return nil
    }

    /// `Any?` -> `CGImage?` via CFTypeID (an `as? CGImage` on `Any` mis-fires for CF types).
    private static func asCGImage(_ value: Any?) -> CGImage? {
        guard let value = value else { return nil }
        let cf = value as CFTypeRef
        if CFGetTypeID(cf) == CGImage.typeID {
            return (cf as! CGImage)
        }
        return nil
    }

    // MARK: Clip

    private struct ResolvedClip {
        var rect: CGRect = .null      // .null/.infinite => no rect clip (the bridge treats it as huge)
        var path: RAPath? = nil
        var clippedOut = false
    }

    /// Bake the element's inherited clip chain (`__clipPaths`, world transforms baked in —
    /// same as CALayerPainter.applyClipChain) into what the engine can express: ONE clip
    /// path + one rect per record. The innermost path is passed exactly; the rest of the
    /// chain contributes its intersected bounding rect.
    /// PORT-NOTE: a chain of 2+ non-rectangular clips is approximated (bbox ∩ innermost).
    private func resolveClip(_ el: Displayable) -> ResolvedClip {
        var chain: [ZRenderKit.Path] = el.__clipPaths ?? []
        if chain.isEmpty, let own = el.getClipPath() { chain = [own] }
        if chain.isEmpty { return ResolvedClip() }

        var rect = CGRect.infinite
        var innermost: CGPath?
        for clip in chain {
            let rb = CGPathRebuilder()
            clip.getUpdatedPathProxy(false).rebuildPath(rb, 1)
            var baked: CGPath = rb.path
            if let world = clip.getComputedTransform() {
                var t = AffineTransform(world).cg
                if let copy = rb.path.copy(using: &t) { baked = copy }
            }
            rect = rect.intersection(baked.boundingBoxOfPath)
            innermost = baked
        }
        if rect.isNull || rect.isEmpty {
            return ResolvedClip(rect: .zero, path: nil, clippedOut: true)
        }
        var out = ResolvedClip()
        out.rect = rect
        out.path = innermost.map { RAPath(cgPath: $0) }
        return out
    }

    // MARK: Paint helpers

    /// Solid paint, cached by quantized RGBA (color decayed by `alpha`).
    private func solidPaint(_ color: CGColor, alpha: Double) -> RAPaint {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 1
        if let comps = color.components {
            if comps.count >= 4 {
                r = comps[0]; g = comps[1]; b = comps[2]; a = comps[3]
            } else if comps.count >= 2 {
                r = comps[0]; g = comps[0]; b = comps[0]; a = comps[1]
            }
        }
        a *= CGFloat(Swift.max(0, Swift.min(1, alpha)))
        let key = (UInt32(UInt8(clamping: Int(r * 255 + 0.5))) << 24)
                | (UInt32(UInt8(clamping: Int(g * 255 + 0.5))) << 16)
                | (UInt32(UInt8(clamping: Int(b * 255 + 0.5))) << 8)
                |  UInt32(UInt8(clamping: Int(a * 255 + 0.5)))
        if let cached = _paintCache[key] { return cached }
        if _paintCache.count > 4096 { _paintCache.removeAll(keepingCapacity: true) }
        let paint = RAPaint(red: Double(r), green: Double(g), blue: Double(b), alpha: Double(a))
        _paintCache[key] = paint
        return paint
    }

    /// Gradient -> RAPaint, with objectBoundingBox (`!global`) coordinates resolved against
    /// the element-local bounding rect — the same math as CGRenderer.drawGradient.
    private func makeGradientPaint(_ g: Gradient, alpha: Double, localRect: CGRect?) -> RAPaint? {
        var colors: [RAPaint] = []
        var locations: [NSNumber] = []
        for stop in g.colorStops {
            guard let arr = color.parse(stop.color) else { continue }
            let cg = CGColor(
                srgbRed: CGFloat(arr[0] / 255), green: CGFloat(arr[1] / 255),
                blue: CGFloat(arr[2] / 255), alpha: CGFloat(arr[3] * alpha)
            )
            colors.append(RAPaint(cgColor: cg))
            locations.append(NSNumber(value: stop.offset))
        }
        guard colors.count >= 2 else {
            // Degenerate gradients: 1 stop paints solid, 0 stops paints nothing.
            return colors.first
        }

        if let lg = g as? LinearGradient {
            var x = lg.x, y = lg.y, x2 = lg.x2, y2 = lg.y2
            if !lg.global, let r = localRect {
                x = x * Double(r.width) + Double(r.minX)
                x2 = x2 * Double(r.width) + Double(r.minX)
                y = y * Double(r.height) + Double(r.minY)
                y2 = y2 * Double(r.height) + Double(r.minY)
            }
            x = x.isFinite ? x : 0
            x2 = x2.isFinite ? x2 : 1
            y = y.isFinite ? y : 0
            y2 = y2.isFinite ? y2 : 0
            return RAPaint(linear: colors, locations: locations,
                           start: CGPoint(x: x, y: y), end: CGPoint(x: x2, y: y2))
        }
        if let rg = g as? RadialGradient {
            var x = rg.x, y = rg.y, r = rg.r
            if !rg.global, let rect = localRect {
                let w = Double(rect.width), h = Double(rect.height)
                x = x * w + Double(rect.minX)
                y = y * h + Double(rect.minY)
                r = r * Swift.min(w, h)
            }
            x = x.isFinite ? x : 0.5
            y = y.isFinite ? y : 0.5
            r = (r >= 0 && r.isFinite) ? r : 0.5
            return RAPaint(radial: colors, locations: locations,
                           center: CGPoint(x: x, y: y), radius: r)
        }
        return nil
    }

    /// Pattern -> image paint. The engine stretches an image paint over the path's bounds,
    /// so pre-tile the pattern into a `coverRect`-sized bitmap (honoring the pattern's
    /// translate/rotate/scale + repeat mode, like CGRenderer.tilePattern) — the stretched
    /// texture then lands 1:1 on the path.
    /// PORT-NOTE: rebuilt on every refresh (no tile cache); pattern demos only.
    private func makePatternPaint(_ pat: ZRenderKit.Pattern, coverRect: CGRect, alpha: Double) -> RAPaint? {
        guard let img = loadCGImage(pat.image) else { return nil }
        let imgW = CGFloat(img.width), imgH = CGFloat(img.height)
        let sx = CGFloat(pat.scaleX), sy = CGFloat(pat.scaleY)
        guard imgW > 0, imgH > 0, sx != 0, sy != 0,
              coverRect.width.isFinite, coverRect.height.isFinite,
              coverRect.minX.isFinite, coverRect.minY.isFinite,
              coverRect.width > 0, coverRect.height > 0 else { return nil }

        let pxW = Int((coverRect.width * CGFloat(dpr)).rounded(.up))
        let pxH = Int((coverRect.height * CGFloat(dpr)).rounded(.up))
        guard pxW > 0, pxH > 0, pxW * pxH < 32_000_000,
              let ctx = CGContext(
                data: nil, width: pxW, height: pxH, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }

        // Draw in the element-local y-DOWN space of coverRect (flip + translate), exactly the
        // space `tilePattern` tiles in. The resulting bitmap rows then read top-first, which
        // combined with `verticallyFlipped` below yields an upright texture on screen.
        ctx.translateBy(x: 0, y: CGFloat(pxH))
        ctx.scaleBy(x: CGFloat(dpr), y: -CGFloat(dpr))
        ctx.translateBy(x: -coverRect.minX, y: -coverRect.minY)
        ctx.setAlpha(CGFloat(alpha))

        var m = CGAffineTransform(translationX: CGFloat(pat.x), y: CGFloat(pat.y))
        m = m.rotated(by: CGFloat(pat.rotation))
        m = m.scaledBy(x: sx, y: sy)
        ctx.concatenate(m)

        let local = coverRect.applying(m.inverted())
        let tileX = pat.`repeat` == .repeat || pat.`repeat` == .repeatX
        let tileY = pat.`repeat` == .repeat || pat.`repeat` == .repeatY
        let startX = tileX ? (local.minX / imgW).rounded(.down) * imgW : 0
        let startY = tileY ? (local.minY / imgH).rounded(.down) * imgH : 0
        let endX = tileX ? local.maxX : imgW
        let endY = tileY ? local.maxY : imgH
        var py = startY
        while py < endY {
            var px = startX
            while px < endX {
                ctx.saveGState()
                ctx.translateBy(x: px, y: py + imgH)
                ctx.scaleBy(x: 1, y: -1)
                ctx.draw(img, in: CGRect(x: 0, y: 0, width: imgW, height: imgH))
                ctx.restoreGState()
                px += imgW
            }
            py += imgH
        }

        guard let tiled = ctx.makeImage(), let flipped = Self.verticallyFlipped(tiled) else {
            return nil
        }
        return RAPaint(cgImage: flipped)
    }

    /// Vertically mirror an image (see the image-paint orientation note in `addImage`).
    private static func verticallyFlipped(_ img: CGImage) -> CGImage? {
        let w = img.width, h = img.height
        guard w > 0, h > 0, let ctx = CGContext(
            data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()
    }

    private func mapCap(_ cap: CGLineCap) -> RACapStyle {
        switch cap {
        case .round: return .capRound
        case .square: return .capSquare
        default: return .capButt
        }
    }

    private func mapJoin(_ join: CGLineJoin) -> RAJoinStyle {
        switch join {
        case .round: return .joinRound
        default: return .joinMiter   // PORT-NOTE: bevel unsupported by the engine -> miter
        }
    }

    // MARK: - Headless CPU reference render (RasterizerCG)

    /// Benchmark the engine's CPU stage (Context::drawList into an Ra::Buffer — the per-frame
    /// work `writeBuffer` does, minus the GPU encode) over `sceneList`. Returns avg ms/frame.
    public func benchEngine(_ sceneList: RASceneList, frames: Int) -> Double {
        return RARenderHost.benchList(sceneList, scale: CGFloat(dpr),
                                      width: Double(surfaceSize.width),
                                      height: Double(surfaceSize.height),
                                      frames: Int32(frames))
    }

    /// Force a synchronous Metal render pass of the last presented scene (headless testing,
    /// no CoreAnimation commit needed).
    public func displayNow() {
        host.displayNow()
    }

    /// CPU readback of the engine's retained feedback frame — a REAL screenshot of the
    /// Metal pipeline's output (only available while motion blur is enabled, which is what
    /// keeps the feedback texture alive).
    public func renderMetalFrame() -> CGImage? {
        return host.copyFeedbackFrame()
    }

    /// Render the last published scene list through the engine's own CoreGraphics reference
    /// interpreter (`RasterizerCG`) — verifies the display-list translation without a
    /// display/drawable. The GPU path renders the same `RASceneList`.
    /// PORT-NOTE: no feedback loop here — verify motion blur via `renderMetalFrame()`.
    public func renderToImage() -> CGImage? {
        guard let list = lastSceneList else { return nil }
        let w = Double(surfaceSize.width), h = Double(surfaceSize.height)
        let pxW = Int((w * dpr).rounded()), pxH = Int((h * dpr).rounded())
        guard pxW > 0, pxH > 0, let ctx = CGContext(
            data: nil, width: pxW, height: pxH, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        // RasterizerCG expects a layer-style context (scale pre-applied, y-up).
        ctx.scaleBy(x: CGFloat(dpr), y: CGFloat(dpr))
        RARenderHost.renderList(list, scale: CGFloat(dpr), width: w, height: h, into: ctx)
        return ctx.makeImage()
    }
}

// MARK: - PainterBase conformance (the ZRender host-facade seam)

extension RasterizerPainter: LayerHostedPainter {

    public var type: String { return "rasterizer" }

    public func refresh(_ displayList: [Displayable]) {
        let list = buildSceneList(displayList)
        lastSceneList = list
        host.present(list, width: Double(surfaceSize.width), height: Double(surfaceSize.height))
    }

    public func resize(_ width: Double?, _ height: Double?, _ dpr: Double?) {
        if let w = width, let h = height {
            surfaceSize = CGSize(width: w, height: h)
            rootLayer.bounds = CGRect(origin: .zero, size: surfaceSize)
        }
        // dpr is immutable (set at init), matching CALayerPainter.
    }

    public func clear() {
        lastSceneList = nil
        host.present(buildSceneList([]), width: Double(surfaceSize.width),
                     height: Double(surfaceSize.height))
    }

    public func getWidth() -> Double { return Double(surfaceSize.width) }

    public func getHeight() -> Double { return Double(surfaceSize.height) }

    public func getViewportRoot() -> Any? { return rootLayer }

    /// upstream painter.configLayer(zLevel, config) — per-zlevel motion blur, implemented
    /// as the engine feedback pass (see the MOTION BLUR note in the header). `motionBlur ==
    /// false` clears the zlevel's config (a series turning its effect off reverts cleanly),
    /// mirroring CALayerPainter.configLayer.
    public func configLayer(_ zLevel: Double, _ config: Any?) {
        guard let c = config as? LayerConfig else { return }
        if c.motionBlur {
            _layerConfigs[zLevel] = c
        } else {
            _layerConfigs[zLevel] = nil
        }
        // PORT-NOTE: whole-layer feedback — max lastFrameAlpha across configured zlevels.
        let alpha = _layerConfigs.values.map { $0.lastFrameAlpha }.max() ?? 0
        host.setMotionBlurAlpha(alpha)
    }

    public func dispose() {
        lastSceneList = nil
    }
}

#endif
