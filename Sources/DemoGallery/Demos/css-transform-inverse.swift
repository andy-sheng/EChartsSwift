import ZRenderKit
// Migrated from zrender test/css-transform-inverse.html
extension DemoRegistry {
    static let demo_css_transform_inverse: Demo = Demo(
        name: "css-transform-inverse", category: "Transform",
        summary: "A rect under a 2D transform (scale·rotate) + its origin marker"
    ) { zr in
        // The HTML maps pointer coords through (the inverse of) a chain of CSS transforms on
        // nested boxes — e.g. try2's `translate(...) scale(-0.8, 0.5) rotate(-25deg)`. Here we
        // show the static result: a source rect and the same rect carried by that transform.
        let bw = 150.0, bh = 100.0

        // Source: the untransformed reference rect (dashed ghost outline) + label.
        let srcX = 70.0, srcY = 50.0
        zr.add(styled(rect(srcX, srcY, bw, bh), stroke: "#999", lineWidth: 1, dash: [5, 4]))
        zr.add(text("source", srcX + 6, srcY + 6, "#999", size: 13))

        // The same rect, drawn centered on a Group origin so scale/rotate pivot there, then the
        // group carries the CSS-like 2D transform `scale(-0.8, 0.5) rotate(-25deg)` (the negative
        // x-scale mirrors it — matching the HTML's "transform 2d with negative value" case).
        let originX = 470.0, originY = 110.0
        let g = Group()
        g.add(styled(rect(-bw / 2, -bh / 2, bw, bh), fill: "#008000"))
        g.x = originX; g.y = originY
        g.scaleX = -0.8; g.scaleY = 0.5
        g.rotation = -25.0 * π / 180.0
        zr.add(g)

        // Readable caption (outside the group so it is not mirrored by the negative scale).
        zr.add(text("scale(-0.8, 0.5) · rotate(-25°)", 360, 175, "#008000", size: 13))

        // Transform origin marker (the HTML's orange 6x6 pointer-marker, centered on the origin).
        zr.add(styled(rect(originX - 3, originY - 3, 6, 6), fill: "#ffa500"))
    }
}
