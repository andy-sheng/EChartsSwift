import ZRenderKit
// Migrated from zrender test/image.html
extension DemoRegistry {
    static let demo_image: Demo = Demo(
        name: "image", category: "Paint",
        summary: "Grid of ZRImage tiles — the upstream asset/test.png placed by element position",
        width: 680, height: 200
    ) { zr in
        // image.html — a 200×200 nested loop of `new zrender.Image({ position: [i*20, j*20],
        //   scale: [1,1], style: { x: 0, y: 0, image: 'asset/test.png', width: 20, height: 20 },
        //   draggable: true })`. Each Image's ELEMENT position (i*20, j*20) is the transform;
        //   style.x/y (=0) is the local origin and width/height (=20) the dest size — exactly how
        //   drawZRImage blits (CALayerPainter). `draggable: true` is mirrored via Element.draggable;
        //   the no-op scale [1,1] is an acceptable omission.
        //
        // Uses the SAME image as the html: upstream/zrender/test/asset/test.png (resolved via
        // upstreamAsset, the #filePath trick the gallery's web pane uses). DECODED ONCE into a shared
        // CGImage passed via the `.image(...)` source seam, so all 340 tiles reuse one decode instead
        // of re-reading the 180×180 PNG per element. (Upstream passes the path string and the browser
        // caches by URL; sharing the decoded handle is the equivalent.) Falls back to the path string
        // (painter's loadCGImage decodes + caches it) if the asset can't be decoded here.
        let source: ImageSource = decodedUpstreamAsset("test.png").map { .image($0) }
            ?? .url(upstreamAsset("test.png").path)

        let tileSize = 20.0
        let cols = 34   // 34 * 20 = 680
        let rows = 10   // 10 * 20 = 200
        for i in 0..<cols {
            for j in 0..<rows {
                var s = ImageStyleProps()
                s.image = source             // shared decoded test.png (HTML style.image)
                s.x = 0; s.y = 0             // local origin (HTML style.x/y)
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
