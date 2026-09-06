import ZRenderKit
// Migrated from zrender test/pattern.html
extension DemoRegistry {
    static let demo_pattern: Demo = Demo(
        name: "pattern", category: "Paint", summary: "Tiled image Pattern fill — the upstream asset/test.png"
    ) { zr in
        // pattern.html — two Circles `fill: { image: 'asset/test.png' }` (one via path string,
        // one via a loaded Image object; labels 图片路径 / 图片对象). Uses the SAME image as the html:
        // upstreamAsset("test.png") resolves the real file path (painter's loadCGImage decodes +
        // caches it) for the path arm, and decodedUpstreamAsset gives the decoded handle for the
        // image-object arm; `tilePattern` repeats either across each clipped circle.
        let asset = upstreamAsset("test.png").path

        // `Pattern(image, repeat)` -> wrapped as ZRColor.pattern, applied via the gradFill helper
        // (which assigns any ZRColor to `style.fill`).
        let pat = Pattern(.url(asset), .repeat)

        let circ1 = circle(180, 100, 80)
        zr.add(gradFill(circ1, .pattern(pat)))
        zr.add(text("图片路径", 180, 92, "#ffffff", size: 22, align: .center))

        // Second circle mirrors the HTML's `const img = new Image(); img.src = 'asset/test.png'` +
        // `fill: { image: img }` — the IMAGE-OBJECT arm of upstream's `ImageLike | string`: the asset
        // is decoded here into a CGImage handle and handed to Pattern as `.image(...)`, so the
        // painter's resolvePatternImage takes the `.image` branch instead of loading the path.
        // DEVIATION: upstream builds this circle (and its label) INSIDE `img.onload`, so a failed
        // load renders nothing at all; here the circle is always added and the source falls back to
        // the path string (same file, painter-side decode) so the demo still shows something.
        let source: ImageSource = decodedUpstreamAsset("test.png").map { .image($0) } ?? .url(asset)
        let pat2 = Pattern(source, .repeat)
        let circ2 = circle(500, 100, 80)
        zr.add(gradFill(circ2, .pattern(pat2)))
        zr.add(text("图片对象", 500, 92, "#ffffff", size: 22, align: .center))
    }
}
