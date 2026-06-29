import ZRenderKit
// Migrated from zrender test/image.html
extension DemoRegistry {
    static let demo_image: Demo = Demo(
        name: "image", category: "Paint", summary: "Grid of ZRImage tiles (20x20 PNG placed by element position)"
    ) { zr in
        // image.html — a 200×200 nested loop of `new zrender.Image({ position: [i*20, j*20],
        //   scale: [1,1], style: { x: 0, y: 0, image: 'asset/test.png', width: 20, height: 20 },
        //   draggable: true })`. Each Image's ELEMENT position (i*20, j*20) is the transform;
        //   style.x/y (=0) is the local origin and width/height (=20) the dest size — exactly how
        //   drawZRImage blits (CALayerPainter). `draggable: true` is mirrored via Element.draggable;
        //   the no-op scale [1,1] is an acceptable omission.
        //
        // The upstream `asset/test.png` file path can't be resolved headlessly, so — to stay
        // deterministic & self-contained — we embed the same tiny 20×20 PNG tile used by pattern.swift
        // (ECharts-blue with a white polka dot + amber corner) as a base64 data-URI. The native
        // painter's `loadCGImage` decodes base64 data-URIs, so these are REAL Image elements (no
        // placeholder Rect needed). The 200×200 grid is scaled down to a 34×10 grid that fills the
        // 680×200 canvas edge-to-edge, mirroring the HTML's gap-free tiling.
        let tile = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAABQAAAAUCAYAAACNiR0NAAAAd0lEQVR4nGP8dSLiPwMURK3IY6AUMFFsAq0NZAwpOAb3MjUAEzUNI8nA1f2WlHt5NR5DQguPk+bC1QRchEueiYHKgIkuBq4mMgKwqWMiJcCJUcfEQGXARDcDQwl4G5c8I7F5GRQBxIQtEzGG4XMRA7kGEgsGv4EAElwhSajUA98AAAAASUVORK5CYII="

        let tileSize = 20.0
        let cols = 34   // 34 * 20 = 680
        let rows = 10   // 10 * 20 = 200
        for i in 0..<cols {
            for j in 0..<rows {
                var s = ImageStyleProps()
                s.image = .url(tile)
                s.x = 0; s.y = 0            // local origin (HTML style.x/y)
                s.width = tileSize; s.height = tileSize
                let img = ZRImage()
                img.useStyle(s)
                img.x = Double(i) * tileSize   // element position (HTML position[0])
                img.y = Double(j) * tileSize   // element position (HTML position[1])
                img.draggable = .true          // HTML sets `draggable: true` on every Image
                zr.add(img)
            }
        }
    }
}
