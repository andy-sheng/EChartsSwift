import ZRenderKit
// Migrated from zrender test/dragOrigin.html
extension DemoRegistry {
    static let demo_dragOrigin: Demo = Demo(
        name: "dragOrigin", category: "Interaction",
        summary: "Draggable images rotated about a transform origin (origin [50,50])"
    ) { zr in
        // dragOrigin.html builds two `zrender.Image`s, each `draggable: true`, `rotation: 2`,
        // `origin: [50, 50]`, drawn 100×100 — so each rotates ~114.6° about the CENTRE of its own
        // 100×100 box. The first sits at the canvas origin; the second lives inside a Group at
        // position [100, 100]. Uses the SAME image as the html (upstream/zrender/test/asset/test.png,
        // decoded once and shared via the `.image(...)` source seam). Element x/y offsets are added
        // (deterministically) so both rotated boxes fit the default canvas; the `draggable` flag is
        // preserved via Element.draggable (interactivity via the GUI Handler — the static frame shows
        // the rotated pose).
        let source: ImageSource = decodedUpstreamAsset("test.png").map { .image($0) }
            ?? .url(upstreamAsset("test.png").path)

        // mirror `new zrender.Image({ draggable, rotation: 2, origin: [50,50], style: { image, w, h } })`
        func dragImage() -> ZRImage {
            var ist = ImageStyleProps()
            ist.image = source
            ist.width = 100
            ist.height = 100
            let img = ZRImage()
            img.useStyle(ist)
            img.draggable = .true            // public Element.draggable (the demo's whole point)
            img.rotation = 2                 // radians, anticlockwise
            img.originX = 50; img.originY = 50   // origin: [50, 50] — the box centre it spins about
            return img
        }

        // image 1 — added straight to the host. Upstream leaves it at (0,0); we translate it so its
        // box centres at (160, 100), keeping the rotated square on-canvas.
        let image = dragImage()
        image.x = 110; image.y = 50
        zr.add(image)

        // image 2 — nested in a Group (upstream `group.position == [100, 100]`); we position the
        // Group so image2's box centres at (500, 100). The element transform composes with the
        // Group's, exactly as in the HTML.
        let group = Group()
        group.x = 450; group.y = 50
        let image2 = dragImage()
        group.add(image2)
        zr.add(group)
    }
}
