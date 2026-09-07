// ApplePainterSupport — shared Core Graphics display-list drawing and host contract.
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
    func walk(_ el: Element, _ parentClipPaths: [Path]? = nil) {
        if el.ignore { return }
        // Mirror Storage._updateAndAddDisplayable: run the per-element update hooks before descending.
        // This is load-bearing for `ZRText`, whose `update()` (→ `_updateSubTexts`) BUILDS its `TSpan`
        // children; without it a text element has no spans, so the walk below finds no children and the
        // bare `ZRText` (not drawable itself) is dropped — axis/labels rendered blank. Paths/lines carry
        // absolute geometry so they were unaffected, which is why this only surfaced once text landed.
        el.beforeUpdate()
        el.update()
        el.afterUpdate()

        // `renderToImage` bypasses ZRender `Storage`, but inherited clipping is normally resolved by
        // `Storage._updateAndAddDisplayable` into each leaf's `__clipPaths`. Rebuild the same chain here
        // so a clip attached to a Group (for example LineView's cartesian clip rect) reaches all of its
        // drawable descendants. Falling back to `leaf.getClipPath()` in the painter is insufficient:
        // children do not own their parent's clip path.
        var clipPaths = (el.ignoreClip ? nil : parentClipPaths) ?? []
        if !el.ignoreClip {
            var currentClipPath = el.getClipPath()
            var parentClipPath: Element = el
            while let clipPath = currentClipPath {
                clipPath.parent = parentClipPath
                clipPath.updateTransform()
                clipPaths.append(clipPath)
                parentClipPath = clipPath
                currentClipPath = clipPath.getClipPath()
            }
        }
        let resolvedClipPaths: [Path]? = clipPaths.isEmpty ? nil : clipPaths
        // Duck-type the container check exactly like Storage (shared `activeChildrenRef()`): descend
        // into Group, ZRText (→ TSpan children), AND a combine-morphing Path (→ its sub-paths). The
        // previous `el.isGroup` check was narrower than upstream's `(el as GroupLike).childrenRef` — it
        // missed ZRText spans and combine-morph sub-paths, so this Storage-bypassing route (retained
        // `render`, `renderComposite`, `renderToImage`) dropped them.
        if let children = el.activeChildrenRef() {
            for i in 0..<children.count {
                walk(children[i], resolvedClipPaths)
            }
        }
        else if let d = el as? Displayable {
            d.__clipPaths = resolvedClipPaths
            collected.append(d)
        }
        // Decal element (`style.decal`) — Storage._updateAndAddDisplayable adds a Path's synthesized
        // `getDecalElement()` to the display list right after the host (Storage.swift:217-221), so the
        // repeating decal texture paints clipped to the same shape, over the fill. This Storage-bypassing
        // route must mirror that or decals never render via renderToImage/render.
        if let decalEl = (el as? Path)?.getDecalElement(), !decalEl.ignore {
            walk(decalEl, resolvedClipPaths)
        }
        // Attached leader line (`setTextGuideLine`) — Storage._updateAndAddDisplayable adds the host's
        // textGuideLine to the display list right BEFORE its textContent (so the line paints under the
        // label). Like textContent it is NOT part of `activeChildrenRef()`, so walk it explicitly.
        // Without this, pie / (future) labelLine leader lines are silently dropped even though their
        // geometry, stroke and `ignore` are all correct.
        if let guideEl = el.getTextGuideLine(), !guideEl.ignore {
            walk(guideEl, resolvedClipPaths)
        }
        // Attached text content (`setTextContent` + `textConfig`) — its transform was just computed by
        // `el.update()` → `updateInnerText`. zrender's Storage._updateAndAddDisplayable adds the host's
        // `textContent` to the display list right after the host; it is NOT part of `activeChildrenRef()`
        // (the child list), so walk it explicitly. Without this, every label attached via setTextContent
        // (sankey / treemap / tree / sunburst / graph node labels, etc.) is silently dropped.
        if let textEl = el.getTextContent(), !textEl.ignore {
            // Mirror zrender Storage: preserve the attached text's authored z/z2/zlevel. The chart
            // pipeline has already assigned them; copying the host's z2 here erases intentional label
            // lifts and lets later sibling shapes paint over labels at sector boundaries.
            walk(textEl, resolvedClipPaths)
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
/// `Path`, Text (`TSpan`) and `Image` displayables are all painted (see `drawDisplayable`).
public func renderScene(_ root: Element, into renderer: CGRenderer) {
    let list = flattenDisplayList(root)
    drawDisplayListRespectingIncrementalLayers(list, into: renderer) { el, target in
        drawDisplayable(el, into: target)
    }
}

/// zrender splits each zlevel containing ordinary `Displayable.incremental != 0` elements into three
/// physical canvases: normal-below, one transparent incremental canvas, and normal-above. This is
/// visually observable with low-opacity additive strokes: drawing every incremental batch directly
/// onto an opaque chart background makes Core Graphics produce a brighter result. Reconstruct those
/// three layers inside the final bitmap so both live rendering and deterministic snapshots preserve
/// CanvasPainter's composition semantics.
public func drawDisplayListRespectingIncrementalLayers(
    _ list: [Displayable],
    into renderer: CGRenderer,
    drawOne: (Displayable, CGRenderer) -> Void
) {
    func isOrdinaryIncremental(_ element: Displayable) -> Bool {
        element.incremental != 0 && !(element is IncrementalDisplayable)
    }

    func drawIncrementalLayer(_ elements: [Displayable]) {
        guard !elements.isEmpty else { return }
        let width = renderer.ctx.width
        let height = renderer.ctx.height
        guard width > 0, height > 0,
              let layerContext = CGContext(
                data: nil, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return }

        // Match the destination's complete base transform (canvas y-down flip + DPR). Element-local
        // transforms and clips are then applied by drawDisplayable exactly as on the main context.
        layerContext.concatenate(renderer.ctx.ctm)
        let layerRenderer = CGRenderer(layerContext, flipped: renderer.flipped, geometryCache: renderer.geometryCache)
        for element in elements { drawOne(element, layerRenderer) }

        guard let image = layerContext.makeImage() else { return }
        renderer.ctx.saveGState()
        renderer.ctx.concatenate(renderer.ctx.ctm.inverted())
        renderer.ctx.setAlpha(1)
        renderer.ctx.setBlendMode(.normal)
        renderer.ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        renderer.ctx.restoreGState()
    }

    var start = 0
    while start < list.count {
        let zlevel = list[start].zlevel
        var end = start + 1
        while end < list.count, list[end].zlevel == zlevel { end += 1 }
        let level = Array(list[start..<end])

        if let firstIncremental = level.firstIndex(where: isOrdinaryIncremental) {
            for element in level[..<firstIncremental] { drawOne(element, renderer) }
            drawIncrementalLayer(level.filter(isOrdinaryIncremental))
            for element in level[firstIncremental...]
                where !isOrdinaryIncremental(element) {
                drawOne(element, renderer)
            }
        }
        else {
            for element in level { drawOne(element, renderer) }
        }
        start = end
    }
}

/// Dispatch one `Displayable` to its draw helper. Shared by the snapshot route (`renderScene`) and the
/// live refresh loop. An `IncrementalDisplayable` is drawn one-shot here (all its pending displayables),
/// which is correct for a single offscreen frame; the live path uses the retained-bitmap variant
/// (`CALayerPainter.drawIncrementalRetained`) so accumulated dots are not redrawn every frame.
public func drawDisplayable(_ el: Displayable, into r: CGRenderer) {
    if let p = el as? Path {
        drawPath(p, into: r)
    }
    else if let t = el as? TSpan {
        drawTSpan(t, into: r)
    }
    else if let img = el as? ZRImage {
        drawZRImage(img, into: r)
    }
    else if let inc = el as? IncrementalDisplayable {
        inc.eachPendingDisplayable { d in drawDisplayable(d, into: r) }
    }
    // else: unknown Displayable — nothing to paint.
}

private func drawPath(_ p: Path, into r: CGRenderer) {
    if p.invisible { return }
    guard let style = p.pathStyle else { return }
    if style.opacity == 0 { return }

    r.save()
    defer { r.restore() }

    // 1. Clip (applied at the base CTM, with each clip path baked into its own world transform).
    applyClipChain(p, into: r)

    // 2. Element world transform (concatenated onto the base flipped+dpr CTM).
    if let world = p.getComputedTransform() {
        r.transform(AffineTransform(world))
    }

    var paint = PaintStyle.from(style)

    // 2a. strokeNoScale: the stroke keeps its authored width regardless of the element's scale
    //     (zrender canvas: `ctx.lineWidth = lineWidth / el.getLineScale()`). The element's world
    //     transform is already concatenated onto the CTM above, so divide the line width by that
    //     scale to cancel it — otherwise a symbol built as a 2×2 shape scaled by size/2 would stroke
    //     size/2× too thick (an emptyCircle then fills solid instead of reading hollow).
    if style.strokeNoScale == true {
        let lineScale = p.getLineScale()
        if lineScale > 1e-10 {
            paint.lineWidth /= lineScale
        }
    }

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

    // 4b. Composite/blend mode (canvas globalCompositeOperation). Scoped by the save()/restore()
    //     bracketing this element; 'lighter' is the additive blend the incremental demos depend on.
    r.setBlendMode(style.blend)

    // 5a. Large-symbol boost (zrender LargeSymbolDraw.afterBrush): a tiny-symbol large path fills
    //     each datum as its own rect instead of one giant N-sub-path CGPath — see the base Path's
    //     `largeSymbolBoostRects()` doc. Filling one 10⁶-circle path via `CGContext.fillPath` is
    //     super-linear (a 5× point count measured ~32× slower). Opaque compound rectangles use
    //     bounded batches; scatter retains one fill per point to preserve alpha accumulation.
    //     The rects are element-local, so the world transform applied above (step 2) carries them into
    //     surface space exactly as the normal geometry. Fill only (upstream boost issues no stroke).
    if let boost = p.largeSymbolBoostRects() {
        r.fillBoostRects(boost, paint, compound: p.largeRectsAreCompound
            && makeShadow(style) == nil && (style.blend == nil || style.blend == "source-over"))
        return
    }

    // 5. Geometry: replay the Path's PathProxy into the renderer's CGPath rebuilder.
    // strokePercent: zrender rebuilds the path to its leading fraction (canvas/graphic.ts:225,
    // `path.rebuildPath(ctx, strokePart ? strokePercent : 1)`); fill and stroke both follow the
    // trimmed geometry ("Not support separate fill and stroke"). Mirror that here.
    let pathProxy = p.getCachedPathProxy(false)
    let strokePercent = style.strokePercent ?? 1
    r.preparePath(pathProxy, percent: strokePercent < 1 ? strokePercent : 1)

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

    applyClipChain(t, into: r)
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
        // PORT-NOTE (deferred): image not yet decoded. A remote-URL source needs the async
        // `platform.loadImage` → `__image` path (image.ts `createOrUpdateImage`), still unported.
        return
    }

    r.save()
    defer { r.restore() }

    applyClipChain(img, into: r)
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
/// inline `.image(CGImage)` source, then a decode of a `.url` string (file / data URI) via the
/// `platform.loadImage` seam (CONVENTIONS §9). PORT-NOTE (deferred): remote-URL async loading +
/// `onload` dispatch onto `__image` is the still-unported image.ts follow-up.
private func resolveCGImage(_ img: ZRImage) -> CGImage? {
    if let cg = asCGImage(img.__image) { return cg }
    if case .some(.image(let like)) = img.imageStyle.image, let cg = asCGImage(like) {
        return cg
    }
    if case .some(.url(let s)) = img.imageStyle.image {
        // Route through the platform `loadImage` seam. NativePainter installs the native backing
        // (`installNativePlatformAPI`), whose `loadImage` synchronously decodes the string source
        // via `loadCGImage` and returns the `CGImage` as the opaque `ImageLike` handle. Fall back to
        // the direct `loadCGImage` decode when the seam is still the nil-returning stub, so the public
        // `renderScene` snapshot path does not depend on a `CALayerPainter` having been constructed
        // first (its `init` is what installs the native backing).
        return asCGImage(platformApi.loadImage(s, {}, {})) ?? loadCGImage(s)
    }
    return nil
}

/// `Any?` → `CGImage?`. `ImageLike` is the opaque `Any` seam (CONVENTIONS §9); a plain
/// `as? CGImage` on `Any` mis-fires for CoreFoundation types, so dispatch on the CFTypeID.
public func asCGImage(_ value: Any?) -> CGImage? {
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
/// Apply the element's full inherited clip chain — the parent Group clips intersected with the
/// element's own clip — as built by `Storage._updateAndAddDisplayable` into `el.__clipPaths`
/// (Storage.swift:118-165). Upstream's canvas brush reads `el.__clipPaths` directly; the older code
/// here applied only `el.getClipPath()` (the element's OWN clip), so `Group.setClipPath()` never
/// reached the group's children and nested intersection (e.g. clipping.html's circle ∩ rect) could
/// not render. Each clip bakes its own world transform, so all are applied at the base CTM (before
/// the element's own transform); `setClipPath` intersects with the current region, so applying the
/// whole chain yields the nested intersection. Falls back to `getClipPath()` for the (unused)
/// renderScene path where Storage has not populated the chain.
private func applyClipChain(_ el: Displayable, into r: CGRenderer) {
    if let chain = el.__clipPaths, !chain.isEmpty {
        for clip in chain {
            applyClip(clip, into: r)
        }
    }
    else if let clip = el.getClipPath() {
        applyClip(clip, into: r)
    }
}

private func applyClip(_ clip: Path, into r: CGRenderer) {
    let pp = clip.getCachedPathProxy(false)
    var cgPath = r.geometryCache.path(for: pp)
    if let world = clip.getComputedTransform() {
        var t = AffineTransform(world).cg
        if let baked = cgPath.copy(using: &t) {
            cgPath = baked
        }
    }
    r.setClipPath(cgPath)
}

public func makeShadow(_ s: PathStyleProps) -> ShadowStyle? {
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

public func defaultDPR() -> Double {
    #if canImport(UIKit)
    return Double(UIScreen.main.scale)
    #elseif canImport(AppKit)
    return Double(NSScreen.main?.backingScaleFactor ?? 2)
    #else
    return 1
    #endif
}

// MARK: - Layer-hosted painter seam

/// A `PainterBase` whose output surface is a `CALayer` that a host view (`ZRenderView`) can
/// attach and size. `CALayerPainter` (CoreGraphics bitmap) and `RasterizerPainter`
/// (Metal, the independent RasterizerPainter package) both conform, which lets the host swap the
/// rasterization backend without touching the input/animation plumbing.
public protocol LayerHostedPainter: PainterBase {
    var rootLayer: CALayer { get }
}


#endif
