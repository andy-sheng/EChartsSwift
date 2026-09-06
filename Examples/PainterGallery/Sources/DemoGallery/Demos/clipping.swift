import ZRenderKit
// Faithful port of zrender test/clipping.html  (the html's #main div is 1000x600)
//
// Upstream nests two Groups — g1.add(g2); zr.add(g1) — and clips them:
//   g2.setClipPath(circle)  // circle shape {cx:0,cy:0,r:0}, position [200,200], r animates 0->300
//   g1.setClipPath(rect)    // rect  shape {x:-250,y:-20,w:500,h:300}, position [200,150]
// A grid of cells is added to g2, so the grid shows only where it lands inside BOTH clips
// (circle ∩ rect). The circle's radius animates 0->300 over 1000ms, wiping the mosaic into view.
//
// This now renders FAITHFULLY: Storage builds each cell's inherited __clipPaths chain
// (parent g1's rect ∩ parent g2's circle) and the NativePainter applies the whole chain
// (CALayerPainter.applyClipChain), so a Group's clip really does clip its children.
//
// DEVIATIONS (the only allowed ones): upstream tiles a 50x50 grid of draggable test.png Images.
// With no bundled image asset we substitute styled Rect cells (a palette mosaic, the same stand-in
// the `pattern` demo uses), and bound the grid to the region the two clips can actually reveal
// (cells beyond circle ∩ rect are never visible) instead of the full 50x50. The draggable flag has
// no gallery analog and is dropped.
extension DemoRegistry {
    static let demo_clipping: Demo = Demo(
        name: "clipping", category: "Paint",
        summary: "A grid of test.png images revealed through a growing circle clip, itself clipped by a rect (circle ∩ rect)",
        width: 1000, height: 600
    ) { zr in
        // g1.add(g2); zr.add(g1) — neither group has a position of its own (clips carry the offsets).
        let g1 = Group()
        let g2 = Group()
        g1.add(g2)
        zr.add(g1)

        // g2.setClipPath(circle) — shape {cx:0,cy:0,r:0}, position [200,200]; r animates 0->300.
        let clipCircle = circle(0, 0, 0)
        clipCircle.x = 200; clipCircle.y = 200
        g2.setClipPath(clipCircle)

        // g1.setClipPath(rect) — shape {x:-250,y:-20,w:500,h:300}, position [200,150].
        let clipRect = rect(-250, -20, 500, 300)
        clipRect.x = 200; clipRect.y = 150
        g1.setClipPath(clipRect)

        // Grid of Image cells added to g2 at [i*cell, j*cell] with style {x:0,y:0,width:50,height:50,
        // image:'asset/test.png'} — exactly the html. The cells set NO clip of their own; the painter
        // applies the inherited __clipPaths chain (g1's rect ∩ g2's circle), so they show only inside
        // circle ∩ rect. Same image as the html: test.png, decoded ONCE and shared across cells.
        //
        // DEVIATIONS: grid bounded to the clip-visible band (circle ∩ rect lives within world
        // x∈[-50,500], y∈[130,430]) instead of the html's 50x50; `draggable` is dropped.
        let cell = 50.0, cols = 11, rows = 10
        let source: ImageSource = decodedUpstreamAsset("test.png").map { .image($0) }
            ?? .url(upstreamAsset("test.png").path)
        for i in 0..<cols {
            for j in 0..<rows {
                var s = ImageStyleProps()
                s.image = source
                s.x = 0; s.y = 0
                s.width = cell; s.height = cell
                let img = ZRImage()
                img.useStyle(s)
                img.x = Double(i) * cell   // element position (HTML position[0])
                img.y = Double(j) * cell   // element position (HTML position[1])
                g2.add(img)
            }
        }

        // circle.animateShape().when(1000, { r: 300 }).start() — wipe the image grid into view.
        clipCircle.animate("shape").when(1000, ["r": 300.0]).start()
    }
}
