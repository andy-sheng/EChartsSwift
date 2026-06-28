// NativePainter — fresh native renderer (Core Graphics / Core Animation).
// This is NOT a translation of zrender's CanvasPainter. It is a hand-written backend
// that satisfies the renderer seam (`Renderer`) exported by NativePainter/Renderer.swift.
//
// CGRenderer drives the ~8 paint ops over a single `CGContext`. The path geometry is
// accumulated by its `CGPathRebuilder` (a shape replays its `PathProxy` into it); the
// renderer then fills/strokes that path with a `PaintStyle` flattened from `PathStyleProps`.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
import CoreText
#if canImport(ImageIO)
import ImageIO
#endif
import ZRenderKit

public final class CGRenderer: Renderer {

    public let ctx: CGContext

    /// `true` when the context CTM has been flipped to y-down (the canvas convention). Used to
    /// correct the shadow offset, whose sign is taken in device space (see `shadow`).
    public let flipped: Bool

    private let _pathRebuilder = CGPathRebuilder()

    public var pathRebuilder: PathRebuilder { _pathRebuilder }

    /// Concrete accessor (the protocol getter is type-erased).
    public var cgPathRebuilder: CGPathRebuilder { _pathRebuilder }

    public init(_ ctx: CGContext, flipped: Bool) {
        self.ctx = ctx
        self.flipped = flipped
    }

    /// Reset the accumulated path before replaying a shape's commands.
    public func beginPath() {
        _pathRebuilder.beginPath()
    }

    // MARK: - 1 / 2. Fill & stroke

    public func fillPath(_ style: PaintStyle) {
        // Gradient fill: clip to the path and draw the gradient (mirrors canvas `ctx.fillStyle =
        // gradient`). objectBoundingBox vs userSpaceOnUse coords resolved in `gradientStartEnd`.
        if let g = style.fillGradient {
            fillGradientClipped(g, rule: style.fillRule, alpha: style.fillAlpha, rect: style.boundingRect)
            return
        }
        // Pattern fill: tiled image clipped to the path (best-effort).
        if let pat = style.fillPattern, let img = resolvePatternImage(pat) {
            fillPatternClipped(img, pattern: pat, rule: style.fillRule)
            return
        }
        guard let fill = style.fill else { return }   // no fill / fill == 'none'
        ctx.addPath(_pathRebuilder.path)
        ctx.setFillColor(fill)
        // fillPath(using:) consumes the current path.
        ctx.fillPath(using: style.fillRule)
    }

    public func strokePath(_ style: PaintStyle) {
        // Gradient / pattern stroke: replace the path with its stroked outline, then fill that
        // outline with the gradient/pattern (Core Graphics has no "stroke with gradient").
        if style.strokeGradient != nil || style.strokePattern != nil {
            strokeWithPaint(style)
            return
        }
        guard let stroke = style.stroke else { return }
        ctx.addPath(_pathRebuilder.path)
        ctx.setStrokeColor(stroke)
        ctx.setLineWidth(CGFloat(style.lineWidth))
        ctx.setLineCap(style.lineCap)
        ctx.setLineJoin(style.lineJoin)
        ctx.setMiterLimit(CGFloat(style.miterLimit))
        if let dash = style.lineDash, !dash.isEmpty {
            ctx.setLineDash(phase: CGFloat(style.lineDashOffset), lengths: dash.map { CGFloat($0) })
        }
        else {
            ctx.setLineDash(phase: 0, lengths: [])
        }
        // strokePath() consumes the current path.
        ctx.strokePath()
    }

    // MARK: - Gradient & pattern paint (resolution mirrors zrender/src/canvas/helper.ts)

    /// Clip to the accumulated path and draw `g` as a fill. `rect` is the element-local bounding
    /// rect for `objectBoundingBox` (`!global`) resolution.
    private func fillGradientClipped(_ g: Gradient, rule: CGPathFillRule, alpha: Double, rect: CGRect?) {
        guard let grad = makeCGGradient(g, alpha: alpha) else { return }
        ctx.saveGState()
        ctx.addPath(_pathRebuilder.path)
        if rule == .evenOdd { ctx.clip(using: .evenOdd) } else { ctx.clip() }
        drawGradient(g, grad, rect: rect)
        ctx.restoreGState()
    }

    private func strokeWithPaint(_ style: PaintStyle) {
        ctx.saveGState()
        ctx.addPath(_pathRebuilder.path)
        ctx.setLineWidth(CGFloat(style.lineWidth))
        ctx.setLineCap(style.lineCap)
        ctx.setLineJoin(style.lineJoin)
        ctx.setMiterLimit(CGFloat(style.miterLimit))
        if let dash = style.lineDash, !dash.isEmpty {
            ctx.setLineDash(phase: CGFloat(style.lineDashOffset), lengths: dash.map { CGFloat($0) })
        }
        // Replace the current path with its stroked outline, then clip to it and paint.
        ctx.replacePathWithStrokedPath()
        ctx.clip()
        if let g = style.strokeGradient, let grad = makeCGGradient(g, alpha: style.strokeAlpha) {
            drawGradient(g, grad, rect: style.boundingRect)
        }
        else if let pat = style.strokePattern, let img = resolvePatternImage(pat) {
            tilePattern(img, pattern: pat)
        }
        ctx.restoreGState()
    }

    /// Build a `CGGradient` from a `Gradient`'s `colorStops`, multiplying each stop alpha by
    /// `alpha` (the fill/stroke opacity). Uses `Tool/color.parse` for stop color parsing.
    private func makeCGGradient(_ g: Gradient, alpha: Double) -> CGGradient? {
        var colors: [CGColor] = []
        var locations: [CGFloat] = []
        for stop in g.colorStops {
            guard let arr = color.parse(stop.color) else { continue }
            colors.append(CGColor(
                srgbRed: CGFloat(arr[0] / 255),
                green: CGFloat(arr[1] / 255),
                blue: CGFloat(arr[2] / 255),
                alpha: CGFloat(arr[3] * alpha)
            ))
            locations.append(CGFloat(stop.offset))
        }
        guard !colors.isEmpty else { return nil }
        return CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: colors as CFArray,
            locations: locations
        )
    }

    /// Draw `grad` into the current (clipped) region, positioned per the gradient geometry.
    /// `.drawsBeforeStartLocation`/`.drawsAfterEndLocation` extend the end-stop colors to fill the
    /// whole clip (canvas gradients are not "padded" the same way, but this is the closest match
    /// to `fillStyle = gradient` over the path's bounds).
    private func drawGradient(_ g: Gradient, _ grad: CGGradient, rect: CGRect?) {
        let opts: CGGradientDrawingOptions = [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        if let lg = g as? LinearGradient {
            // createLinearGradient (canvas/helper.ts)
            var x = lg.x, y = lg.y, x2 = lg.x2, y2 = lg.y2
            if !lg.global, let r = rect {
                x = x * Double(r.width) + Double(r.minX)
                x2 = x2 * Double(r.width) + Double(r.minX)
                y = y * Double(r.height) + Double(r.minY)
                y2 = y2 * Double(r.height) + Double(r.minY)
            }
            x = isSafeNum(x) ? x : 0
            x2 = isSafeNum(x2) ? x2 : 1
            y = isSafeNum(y) ? y : 0
            y2 = isSafeNum(y2) ? y2 : 0
            ctx.drawLinearGradient(
                grad,
                start: CGPoint(x: x, y: y),
                end: CGPoint(x: x2, y: y2),
                options: opts
            )
        }
        else if let rg = g as? RadialGradient {
            // createRadialGradient (canvas/helper.ts)
            var x = rg.x, y = rg.y, r = rg.r
            if !rg.global, let rect = rect {
                let w = Double(rect.width), h = Double(rect.height)
                let mn = Swift.min(w, h)
                x = x * w + Double(rect.minX)
                y = y * h + Double(rect.minY)
                r = r * mn
            }
            x = isSafeNum(x) ? x : 0.5
            y = isSafeNum(y) ? y : 0.5
            r = (r >= 0 && isSafeNum(r)) ? r : 0.5
            ctx.drawRadialGradient(
                grad,
                startCenter: CGPoint(x: x, y: y), startRadius: 0,
                endCenter: CGPoint(x: x, y: y), endRadius: CGFloat(r),
                options: opts
            )
        }
    }

    private func fillPatternClipped(_ img: CGImage, pattern: Pattern, rule: CGPathFillRule) {
        ctx.saveGState()
        ctx.addPath(_pathRebuilder.path)
        if rule == .evenOdd { ctx.clip(using: .evenOdd) } else { ctx.clip() }
        tilePattern(img, pattern: pattern)
        ctx.restoreGState()
    }

    /// Tile `img` over the current clip region. PORT-TODO: only the `repeat` mode + x/y offset and
    /// uniform scale are honored; rotation and `repeat-x`/`repeat-y`/`no-repeat` are best-effort
    /// (always tiled in both axes). zrender's `createCanvasPattern` rotation/scale matrix is the
    /// exotic case deferred here.
    private func tilePattern(_ img: CGImage, pattern: Pattern) {
        // Callers (`fillPatternClipped` / `strokeWithPaint`) bracket this in save/clip/restore.
        let bb = ctx.boundingBoxOfClipPath
        let tileW = CGFloat(img.width) * CGFloat(pattern.scaleX)
        let tileH = CGFloat(img.height) * CGFloat(pattern.scaleY)
        guard tileW > 0, tileH > 0, bb.width > 0, bb.height > 0 else { return }
        // Anchor the tile grid at (pattern.x, pattern.y), backing up to cover the clip's top-left.
        var startX = CGFloat(pattern.x)
        while startX > bb.minX { startX -= tileW }
        var startY = CGFloat(pattern.y)
        while startY > bb.minY { startY -= tileH }
        var py = startY
        while py < bb.maxY {
            var px = startX
            while px < bb.maxX {
                // Draw upright (CGContext.draw paints bottom-up; the surrounding CTM is y-down).
                ctx.saveGState()
                ctx.translateBy(x: px, y: py + tileH)
                ctx.scaleBy(x: 1, y: -1)
                ctx.draw(img, in: CGRect(x: 0, y: 0, width: tileW, height: tileH))
                ctx.restoreGState()
                px += tileW
            }
            py += tileH
        }
    }

    /// Resolve a `Pattern`'s image (a `string` URL / file path / data-URI) to a `CGImage`.
    /// PORT-TODO: upstream `image: ImageLike | string` — the decoded `ImageLike` (`__image`) arm and
    /// SVG patterns are the deferred seam; here only the `string` arm is decoded via ImageIO.
    private func resolvePatternImage(_ pattern: Pattern) -> CGImage? {
        return loadCGImage(pattern.image)
    }

    // MARK: - 3. Image

    public func drawImage(_ image: CGImage, dx: Double, dy: Double, dw: Double, dh: Double) {
        // The destination rect is in the current (already y-down) user space. CGContext.draw
        // would otherwise paint images bottom-up; flip locally so the image is upright.
        ctx.saveGState()
        ctx.translateBy(x: CGFloat(dx), y: CGFloat(dy + dh))
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: dw, height: dh))
        ctx.restoreGState()
    }

    /// Draw a source subrect (`sx, sy, sw, sh`, in image pixel space) of `image` into the dest rect.
    /// Mirrors canvas `drawImage(img, sx, sy, sw, sh, dx, dy, dw, dh)`.
    public func drawImage(
        _ image: CGImage,
        sx: Double, sy: Double, sw: Double, sh: Double,
        dx: Double, dy: Double, dw: Double, dh: Double
    ) {
        let crop = CGRect(x: sx, y: sy, width: sw, height: sh)
        let src = image.cropping(to: crop) ?? image
        drawImage(src, dx: dx, dy: dy, dw: dw, dh: dh)
    }

    // MARK: - 4. Text

    public func drawText(_ text: String, x: Double, y: Double, style: TextStyle) {
        // A single positioned run (a TSpan) drawn via Core Text. Layout (line breaking, per-line
        // x/y, rich-text tiling) is already pre-baked upstream (Contain/text + ZRText) into
        // positioned TSpans; here we draw ONE line at its anchor (x, y) honoring textAlign /
        // textBaseline (mirrors canvas `ctx.fillText/strokeText` + `textAlign`/`textBaseline`).
        if text.isEmpty { return }

        let font = style.makeCTFont()
        let attr = NSAttributedString(string: text, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font
        ])
        let line = CTLineCreateWithAttributedString(attr)

        var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
        let width = CTLineGetTypographicBounds(line, &ascent, &descent, &leading)

        // Horizontal anchor (text-anchor: start/middle/end ≡ left/center/right).
        let dx: CGFloat
        switch style.textAlign {
        case "right", "end": dx = -CGFloat(width)
        case "center": dx = -CGFloat(width) / 2
        default: dx = 0   // left / start
        }

        // Vertical baseline. The context is y-down (canvas convention), so a "top" anchor places
        // the baseline `ascent` BELOW y (larger y), etc.
        let by: CGFloat
        switch style.textBaseline {
        case "top", "hanging": by = ascent
        case "middle": by = (ascent - descent) / 2
        case "bottom", "ideographic": by = -descent
        default: by = 0   // alphabetic
        }

        let px = CGFloat(x) + dx
        let py = CGFloat(y) + by

        // Glyphs are authored y-up; flip the text matrix so they render upright in the y-down CTM.
        ctx.saveGState()
        ctx.textMatrix = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: 0)

        let drawFill = {
            if let fill = style.fill {
                self.ctx.setTextDrawingMode(.fill)
                self.ctx.setFillColor(fill)
                self.ctx.textPosition = CGPoint(x: px, y: py)
                CTLineDraw(line, self.ctx)
            }
        }
        let drawStroke = {
            if let stroke = style.stroke, style.lineWidth > 0 {
                self.ctx.setTextDrawingMode(.stroke)
                self.ctx.setStrokeColor(stroke)
                self.ctx.setLineWidth(CGFloat(style.lineWidth))
                self.ctx.textPosition = CGPoint(x: px, y: py)
                CTLineDraw(line, self.ctx)
            }
        }

        if style.strokeFirst {
            drawStroke(); drawFill()
        }
        else {
            drawFill(); drawStroke()
        }
        ctx.restoreGState()
    }

    // MARK: - 5. Clip

    /// Intersect the current clip region with `path`. Passing the renderer's own
    /// `pathRebuilder` clips to the accumulated path. The clip is applied at the CURRENT CTM,
    /// so callers that want a clip in a specific space must set the CTM first (or pre-transform
    /// the path — see `CALayerPainter`).
    ///
    /// PORT-TODO: a `nil` argument cannot un-clip in Core Graphics without a `restoreGState`;
    ///   the painter brackets each element in save/restore, so clip removal is handled there.
    public func setClip(_ path: PathRebuilder?) {
        guard let path = path as? CGPathRebuilder else { return }
        ctx.addPath(path.path)
        ctx.clip()
    }

    /// Clip to an explicit CGPath at the current CTM (convenience used by the painter).
    public func setClipPath(_ cgPath: CGPath, rule: CGPathFillRule = .winding) {
        ctx.addPath(cgPath)
        if rule == .evenOdd {
            ctx.clip(using: .evenOdd)
        }
        else {
            ctx.clip()
        }
    }

    // MARK: - 6. Transform

    /// Concatenate `m` onto the current CTM. zrender treats the matrix as the element's world
    /// transform; the painter brackets each element in save/restore so concatenating onto the
    /// base (flipped + dpr) CTM yields the absolute transform.
    public func transform(_ m: AffineTransform) {
        ctx.concatenate(m.cg)
    }

    // MARK: - 7. Opacity

    public func opacity(_ alpha: Double) {
        ctx.setAlpha(CGFloat(alpha))
    }

    // MARK: - 8. Shadow

    public func shadow(_ shadow: ShadowStyle?) {
        guard let shadow = shadow else {
            // Clear shadow.
            ctx.setShadow(offset: .zero, blur: 0, color: nil)
            return
        }
        // PORT-TODO: the shadow offset is taken in device space, so under a y-down (flipped)
        //   CTM a positive canvas `shadowOffsetY` (downward) must be negated to stay downward
        //   on screen. The blur is not CTM-scaled (canvas `shadowBlur` is in device px — an
        //   acceptable match for dpr-scaled rendering; revisit for non-uniform CTM scale).
        let oy = self.flipped ? -shadow.offsetY : shadow.offsetY
        ctx.setShadow(
            offset: CGSize(width: CGFloat(shadow.offsetX), height: CGFloat(oy)),
            blur: CGFloat(shadow.blur),
            color: shadow.color
        )
    }

    // MARK: - GState bracketing (used by the painter per element)

    public func save() { ctx.saveGState() }
    public func restore() { ctx.restoreGState() }
}

// MARK: - Style flattening (PathStyleProps -> PaintStyle)

public extension PaintStyle {

    /// Flatten zrender's `PathStyleProps` into a concrete Core Graphics paint descriptor.
    ///
    /// Resolves the `ZRColor` fill/stroke union (solid `string` colors only — gradients &
    /// patterns are PORT-TODO and resolve to `nil` paint), bakes `fillOpacity`/`strokeOpacity`
    /// and the global `opacity` into the color alpha, and maps line cap/join/dash enums.
    static func from(_ style: PathStyleProps) -> PaintStyle {
        var out = PaintStyle()

        let opacity = style.opacity ?? 1
        let fillOpacity = style.fillOpacity ?? 1
        let strokeOpacity = style.strokeOpacity ?? 1

        out.fill = resolveColor(style.fill, multiplyAlpha: fillOpacity)
        out.stroke = resolveColor(style.stroke, multiplyAlpha: strokeOpacity)

        // Gradient / pattern paint (the non-`string` arms of the `ZRColor` union). `fill`/`stroke`
        // above are `nil` for these; the gradient/pattern object is carried for clipped drawing.
        out.fillAlpha = fillOpacity
        out.strokeAlpha = strokeOpacity
        (out.fillGradient, out.fillPattern) = resolvePaintObject(style.fill)
        (out.strokeGradient, out.strokePattern) = resolvePaintObject(style.stroke)

        out.lineWidth = style.lineWidth ?? 1
        out.lineDashOffset = style.lineDashOffset ?? 0
        out.lineCap = mapLineCap(style.lineCap)
        out.lineJoin = mapLineJoin(style.lineJoin)
        out.miterLimit = style.miterLimit ?? 10
        out.opacity = opacity
        out.strokeFirst = style.strokeFirst ?? false

        // lineDash: only the concrete `number[]` form is honored here; 'solid'/'dashed'/'dotted'
        // keyword resolution is PORT-TODO (it depends on lineWidth-relative presets in zrender).
        if case let .some(.values(values)) = style.lineDash, !values.isEmpty {
            out.lineDash = values
        }

        return out
    }
}

/// Resolve a `ZRColor` to a `CGColor`. Solid string colors only this phase; gradients &
/// patterns return `nil` (skipped). The string `'none'` (no paint) also returns `nil`.
func resolveColor(_ c: ZRColor?, multiplyAlpha: Double) -> CGColor? {
    guard let c = c else { return nil }
    switch c {
    case .string(let s):
        if s == "none" { return nil }
        guard let arr = color.parse(s) else { return nil }
        // color.parse → [r, g, b, a] with r/g/b in 0..255 and a in 0..1.
        return CGColor(
            srgbRed: CGFloat(arr[0] / 255),
            green: CGFloat(arr[1] / 255),
            blue: CGFloat(arr[2] / 255),
            alpha: CGFloat(arr[3] * multiplyAlpha)
        )
    case .linearGradient, .radialGradient, .pattern:
        // Gradient / pattern paint is carried as an object (see `resolvePaintObject`) and drawn
        // clipped to the path; it produces no solid CGColor.
        return nil
    }
}

/// Extract the gradient / pattern object from a `ZRColor` union (the non-`string` arms). Returns
/// `(gradient, pattern)` with at most one non-nil.
func resolvePaintObject(_ c: ZRColor?) -> (Gradient?, Pattern?) {
    guard let c = c else { return (nil, nil) }
    switch c {
    case .string:
        return (nil, nil)
    case .linearGradient(let g):
        return (g, nil)
    case .radialGradient(let g):
        return (g, nil)
    case .pattern(let p):
        return (nil, p)
    }
}

/// `isFinite` (canvas/helper.ts `isSafeNum`): rejects NaN / ±Infinity.
func isSafeNum(_ x: Double) -> Bool {
    return x.isFinite
}

/// Decode a `string` image source (file path or `data:` URI) to a `CGImage` via ImageIO.
/// PORT-TODO: this is the `string` arm of zrender's `ImageLike | string`; remote URL loading
/// (`platform.loadImage`) and the cached `ImageLike` handle are the deferred renderer seam.
func loadCGImage(_ src: String) -> CGImage? {
    #if canImport(ImageIO)
    var data: Data?
    if src.hasPrefix("data:") {
        // data:[<mime>][;base64],<payload>
        if let comma = src.firstIndex(of: ","), src.contains(";base64") {
            data = Data(base64Encoded: String(src[src.index(after: comma)...]))
        }
        // PORT-TODO: non-base64 (URL-encoded) data URIs are not decoded.
    }
    else if let url = URL(string: src), url.isFileURL {
        data = try? Data(contentsOf: url)
    }
    else {
        data = try? Data(contentsOf: URL(fileURLWithPath: src))
    }
    guard let data = data,
          let source = CGImageSourceCreateWithData(data as CFData, nil),
          let img = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        return nil
    }
    return img
    #else
    // PORT-TODO: ImageIO unavailable — pattern/image string decode unsupported on this platform.
    return nil
    #endif
}

// MARK: - Text style flattening (TSpanStyleProps -> TextStyle)

public extension TextStyle {

    /// Flatten a `TSpanStyleProps` into a Core Text paint descriptor. Resolves fill / stroke
    /// (solid colors only — gradient/pattern text is PORT-TODO) and the font fields.
    static func from(_ s: TSpanStyleProps) -> TextStyle {
        var out = TextStyle()
        out.font = s.font
        out.fontSize = s.fontSize
        out.fontFamily = s.fontFamily
        if let fw = s.fontWeight { out.bold = fontWeightIsBold(fw) }
        if let fst = s.fontStyle { out.italic = (fst == .italic || fst == .oblique) }

        let fillOpacity = s.fillOpacity ?? 1
        let strokeOpacity = s.strokeOpacity ?? 1
        out.fill = resolveColor(s.fill, multiplyAlpha: fillOpacity)
        out.stroke = resolveColor(s.stroke, multiplyAlpha: strokeOpacity)
        // PORT-TODO: gradient/pattern text fill (s.fill == .linearGradient/.radialGradient/.pattern)
        //   is not painted — resolveColor returns nil for those arms (canvas supports it, deferred).
        out.lineWidth = s.lineWidth ?? 1
        out.textAlign = s.textAlign
        out.textBaseline = s.textBaseline
        out.strokeFirst = s.strokeFirst ?? false
        return out
    }

    /// Build a `CTFont` from the resolved fields, preferring the discrete `fontSize`/`fontFamily`
    /// over the CSS `font` shorthand (which is parsed as a fallback by `parseCSSFont`).
    func makeCTFont() -> CTFont {
        var size = fontSize ?? 0
        var family = fontFamily
        var bold = self.bold
        var italic = self.italic

        if (size == 0 || family == nil), let f = font {
            let parsed = parseCSSFont(f)
            if size == 0 { size = parsed.size }
            if family == nil { family = parsed.family }
            bold = bold || parsed.bold
            italic = italic || parsed.italic
        }
        if size == 0 { size = DEFAULT_FONT_SIZE }
        let resolvedFamily = family ?? DEFAULT_FONT_FAMILY

        var base = makeBaseFont(resolvedFamily, size: CGFloat(size))
        // Apply bold / italic symbolic traits where the family doesn't already encode them.
        var traits: CTFontSymbolicTraits = []
        if bold { traits.insert(.traitBold) }
        if italic { traits.insert(.traitItalic) }
        if !traits.isEmpty,
           let styled = CTFontCreateCopyWithSymbolicTraits(base, CGFloat(size), nil, traits, traits) {
            base = styled
        }
        return base
    }
}

/// Map a generic CSS family (sans-serif/serif/monospace) to a concrete font, else create by name;
/// falls back to the system font.
func makeBaseFont(_ family: String, size: CGFloat) -> CTFont {
    let lower = family.lowercased()
    // Generic families → platform system / standard faces.
    if lower.contains("sans-serif") || lower.isEmpty {
        return CTFontCreateUIFontForLanguage(.system, size, nil)
            ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)
    }
    if lower.contains("monospace") || lower.contains("mono") {
        return CTFontCreateWithName("Menlo" as CFString, size, nil)
    }
    if lower.contains("serif") {
        return CTFontCreateWithName("Times New Roman" as CFString, size, nil)
    }
    // Named family (strip quotes / take the first comma-separated candidate).
    let first = family.split(separator: ",").first.map(String.init) ?? family
    let name = first.trimmingCharacters(in: CharacterSet(charactersIn: " '\""))
    return CTFontCreateWithName(name as CFString, size, nil)
}

/// Parse a CSS font shorthand ("[style] [variant] [weight] <size>px [/lh] <family>") into the
/// subset Core Text needs. PORT-TODO: a narrow parser — it scans for the `…px` size token, bold/
/// italic keywords before it, and treats the remainder as the family (no line-height, %, em, etc.).
func parseCSSFont(_ font: String) -> (size: Double, family: String?, bold: Bool, italic: Bool) {
    let tokens = font.split(separator: " ").map(String.init)
    var size: Double = 0
    var bold = false
    var italic = false
    var sizeIndex = -1
    for (i, tok) in tokens.enumerated() {
        let t = tok.lowercased()
        if t.hasSuffix("px") {
            // `12px` or `12px/14` (line-height) — take the numeric prefix.
            let num = t.dropLast(2).split(separator: "/").first.map(String.init) ?? ""
            if let v = Double(num) { size = v; sizeIndex = i }
        }
        else if sizeIndex < 0 {
            if t == "bold" || t == "bolder" { bold = true }
            else if t == "italic" || t == "oblique" { italic = true }
            else if let w = Double(t), w >= 600 { bold = true }
        }
    }
    var family: String?
    if sizeIndex >= 0 && sizeIndex + 1 < tokens.count {
        family = tokens[(sizeIndex + 1)...].joined(separator: " ")
    }
    return (size, family, bold, italic)
}

/// `FontWeight` → bold predicate (bold / bolder, or a numeric weight ≥ 600).
func fontWeightIsBold(_ w: FontWeight) -> Bool {
    switch w {
    case .bold, .bolder: return true
    case .normal, .lighter: return false
    case .number(let n): return n >= 600
    }
}

func mapLineCap(_ cap: String?) -> CGLineCap {
    switch cap {
    case "round": return .round
    case "square": return .square
    default: return .butt   // canvas default
    }
}

func mapLineJoin(_ join: String?) -> CGLineJoin {
    switch join {
    case "round": return .round
    case "bevel": return .bevel
    default: return .miter  // canvas default
    }
}

#endif
