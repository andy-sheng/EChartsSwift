import ZRenderKit
// Migrated from zrender test/pattern-transform.html
extension DemoRegistry {
    static let demo_pattern_transform: Demo = Demo(
        name: "pattern-transform", category: "Paint",
        summary: "Image Pattern fill carrying a transform (rotate π/6 + scaleX 0.5 + x offset)",
        width: 800, height: 400
    ) { zr in
        // pattern-transform.html — a Rect filled with an image Pattern that carries a transform:
        //   shape: { x: 0, y: 0, width: 200, height: 200 }
        //   style: { fill: { image: canvas, rotation: Math.PI/6, scaleX: 0.5, x: 100 } }
        // Upstream draws an off-screen <canvas> (loaded from asset/test.png) as the tile. We use the
        // SAME image: upstreamAsset("test.png") (decoded + cached by the painter's loadCGImage). The
        // painter (CGRenderer.tilePattern) honors the full pattern matrix — translate(x) · rotate(π/6)
        // · scale(0.5,1) — so the tiles are squashed horizontally, shifted by x, AND rotated.
        //
        // DEVIATION: upstream also calls zr.setBackgroundColor({image, repeat:'no-repeat'}); the
        // painter has no image-background path yet, so that single call is unported (the rect itself
        // is faithful).

        // fill: { image: ..., rotation: Math.PI / 6, scaleX: 0.5, x: 100 }
        let pat = Pattern(.url(upstreamAsset("test.png").path), .repeat)
        pat.x = 100
        pat.scaleX = 0.5
        pat.rotation = π / 6

        // rect shape { x:0, y:0, width:200, height:200 } — exactly the html.
        let r = rect(0, 0, 200, 200)
        zr.add(gradFill(r, .pattern(pat)))
    }
}
