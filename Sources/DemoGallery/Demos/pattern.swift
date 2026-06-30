import ZRenderKit
// Migrated from zrender test/pattern.html
extension DemoRegistry {
    static let demo_pattern: Demo = Demo(
        name: "pattern", category: "Paint", summary: "Tiled image Pattern fill — the upstream asset/test.png"
    ) { zr in
        // pattern.html — two Circles `fill: { image: 'asset/test.png' }` (one via path string,
        // one via a loaded Image object; labels 图片路径 / 图片对象). Uses the SAME image as the html:
        // upstreamAsset("test.png") resolves the real file path, which the painter's loadCGImage
        // decodes (+ caches) and `tilePattern` repeats across each clipped circle.
        let asset = upstreamAsset("test.png").path

        // `Pattern(image, repeat)` -> wrapped as ZRColor.pattern, applied via the gradFill helper
        // (which assigns any ZRColor to `style.fill`).
        let pat = Pattern(asset, .repeat)

        let circ1 = circle(180, 100, 80)
        zr.add(gradFill(circ1, .pattern(pat)))
        zr.add(text("图片路径", 180, 92, "#ffffff", size: 22, align: .center))

        // Second circle mirrors the HTML's two-circle layout (image-path vs image-object); both
        // resolve to the same tiled Pattern here.
        let pat2 = Pattern(asset, .repeat)
        let circ2 = circle(500, 100, 80)
        zr.add(gradFill(circ2, .pattern(pat2)))
        zr.add(text("图片对象", 500, 92, "#ffffff", size: 22, align: .center))
    }
}
