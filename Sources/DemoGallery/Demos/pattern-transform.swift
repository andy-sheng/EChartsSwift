import ZRenderKit
// Migrated from zrender test/pattern-transform.html
extension DemoRegistry {
    static let demo_pattern_transform: Demo = Demo(
        name: "pattern-transform", category: "Paint",
        summary: "Image Pattern fill carrying a transform (scaleX + x offset)"
    ) { zr in
        // pattern-transform.html — a Rect filled with an image Pattern that carries a transform:
        //   shape: { x: 0, y: 0, width: 200, height: 200 }
        //   style: { fill: { image: canvas, rotation: Math.PI/6, scaleX: 0.5, x: 100 } }
        // Upstream draws an off-screen <canvas> (loaded from asset/test.png) as the tile. To stay
        // deterministic & self-contained we reuse the same embedded 20×20 PNG tile as the `pattern`
        // demo (ECharts-blue with a white polka dot + amber corner) as a base64 data-URI, decoded by
        // the native painter's loadCGImage. The Pattern's x / scaleX / scaleY fields are honoured by
        // the painter's tile grid (CGRenderer.tilePattern), so scaleX = 0.5 squashes the tiles
        // horizontally and x = 100 shifts the grid anchor. Pattern `rotation` is set to mirror the
        // HTML but is a PORT-TODO in the painter (the tile grid is axis-aligned).
        let tile = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAABQAAAAUCAYAAACNiR0NAAAAd0lEQVR4nGP8dSLiPwMURK3IY6AUMFFsAq0NZAwpOAb3MjUAEzUNI8nA1f2WlHt5NR5DQguPk+bC1QRchEueiYHKgIkuBq4mMgKwqWMiJcCJUcfEQGXARDcDQwl4G5c8I7F5GRQBxIQtEzGG4XMRA7kGEgsGv4EAElwhSajUA98AAAAASUVORK5CYII="

        // fill: { image: ..., rotation: Math.PI / 6, scaleX: 0.5, x: 100 }
        let pat = Pattern(tile, .repeat)
        pat.x = 100
        pat.scaleX = 0.5
        pat.rotation = π / 6

        // The 200×200 source rect, fitted (180×180) and centred within the ~680×200 canvas.
        let r = rect(250, 10, 180, 180)
        zr.add(gradFill(r, .pattern(pat)))
    }
}
