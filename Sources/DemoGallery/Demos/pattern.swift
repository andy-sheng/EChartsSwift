import ZRenderKit
// Migrated from zrender test/pattern.html
extension DemoRegistry {
    static let demo_pattern: Demo = Demo(
        name: "pattern", category: "Paint", summary: "Tiled image Pattern fill (base64 data-URI tile)"
    ) { zr in
        // pattern.html — `fill: { image: 'asset/test.png' }`: a tiled image Pattern fill.
        // The upstream asset is a file path; to stay deterministic & self-contained we embed a
        // tiny 20×20 PNG tile (ECharts-blue with a white polka dot + amber corner) as a base64
        // data-URI. The native painter's `loadCGImage` decodes base64 data-URIs (CGRenderer.swift)
        // and `tilePattern` repeats it across the clipped path, so the Pattern fill renders.
        let tile = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAABQAAAAUCAYAAACNiR0NAAAAd0lEQVR4nGP8dSLiPwMURK3IY6AUMFFsAq0NZAwpOAb3MjUAEzUNI8nA1f2WlHt5NR5DQguPk+bC1QRchEueiYHKgIkuBq4mMgKwqWMiJcCJUcfEQGXARDcDQwl4G5c8I7F5GRQBxIQtEzGG4XMRA7kGEgsGv4EAElwhSajUA98AAAAASUVORK5CYII="

        // `Pattern(image, repeat)` -> wrapped as ZRColor.pattern, applied via the gradFill helper
        // (which assigns any ZRColor to `style.fill`).
        let pat = Pattern(tile, .repeat)

        let circ1 = circle(180, 100, 80)
        zr.add(gradFill(circ1, .pattern(pat)))
        zr.add(text("图片路径", 180, 92, "#ffffff", size: 22, align: .center))

        // Second circle mirrors the HTML's two-circle layout (image-path vs image-object); both
        // resolve to the same tiled Pattern here.
        let pat2 = Pattern(tile, .repeat)
        let circ2 = circle(500, 100, 80)
        zr.add(gradFill(circ2, .pattern(pat2)))
        zr.add(text("图片对象", 500, 92, "#ffffff", size: 22, align: .center))
    }
}
