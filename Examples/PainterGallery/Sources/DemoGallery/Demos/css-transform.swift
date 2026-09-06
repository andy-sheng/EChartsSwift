import ZRenderKit
// Migrated from zrender test/css-transform.html
extension DemoRegistry {
    static let demo_css_transform: Demo = Demo(
        name: "css-transform", category: "Transform",
        summary: "Green boxes under 2D transforms (translate/scale/rotate), incl. negative scale + nesting"
    ) { zr in
        // The HTML applies CSS `transform` to green ".try-box" divs. Here each box is a Group
        // (green rect + centered yellow label, both centred at the group origin), so the whole
        // box transforms as a unit via the element's x/y/rotation/scaleX/scaleY.
        // NOTE: zrender `rotation` is screen-anticlockwise (opposite to CSS `rotate`), so CSS
        // degrees are negated when converted to radians.
        let green = "#008000"
        let yellow = "#ffe000"
        let deg = π / 180

        // A green box (centred on its own origin) with a centred yellow caption.
        func tryBox(_ label: String) -> Group {
            let g = Group()
            g.add(styled(rect(-55, -30, 110, 60), fill: green))
            g.add(text(label, 0, -7, yellow, size: 13, align: .center))
            return g
        }

        // try1 — "normal transform 2d": translate + scale(0.8, 0.5) rotate(35deg)
        let b1 = tryBox("2D xform")
        b1.x = 120; b1.y = 100
        b1.scaleX = 0.8; b1.scaleY = 0.5
        b1.rotation = -35 * deg
        zr.add(b1)

        // try2 — "transform 2d with negative value": scale(-0.8, 0.5) rotate(-25deg)
        let b2 = tryBox("neg scale")
        b2.x = 340; b2.y = 100
        b2.scaleX = -0.8; b2.scaleY = 0.5
        b2.rotation = 25 * deg
        zr.add(b2)

        // try3 — "nested transform 2d": an outer transform wrapping an inner transformed box.
        let outer = Group()
        outer.x = 560; outer.y = 100
        outer.scaleX = -0.8; outer.scaleY = 0.5
        outer.rotation = 25 * deg
        let inner = tryBox("nested")
        inner.scaleX = 1.2; inner.scaleY = 1.6
        inner.rotation = -65 * deg
        outer.add(inner)
        zr.add(outer)
    }
}
