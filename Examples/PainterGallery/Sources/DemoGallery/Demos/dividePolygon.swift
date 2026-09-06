import ZRenderKit
// Migrated from zrender test/dividePolygon.html
extension DemoRegistry {
    static let demo_dividePolygon: Demo = Demo(
        name: "dividePolygon", category: "Path tools",
        summary: "split() an Isogon into 40 polygons + a Circle into 40 sector cells"
    ) { zr in
        // dividePolygon.html — zrender.morph.defaultDividePath(shape, 40) is the Swift port's
        // Tool/dividePath.split(_:_:) (upstream re-exports `split` as `defaultDividePath`).
        // Each divided sub-path inherits the source style via copyPathProps (fill:none, stroke:#000),
        // so the result is the shape decomposed into 40 stroked cells — visualizing path → polygons.

        // Isogon (20-gon) → 40 pieces. type "isogon" hits split's default polygon-division branch.
        var iso = IsogonShape(); iso.x = 120; iso.y = 120; iso.r = 100; iso.n = 20
        let ig = Isogon(); ig.setShape(iso)
        styled(ig, stroke: "#000", lineWidth: 1)        // fill defaults to "none"
        for p in ZRenderKit.split(ig, 40) { zr.add(p) }

        // Circle → 40 pieces. type "circle" hits split's sector-division branch (r0=0, 0..2π).
        let c = circle(340, 120, 100)
        styled(c, stroke: "#000", lineWidth: 1)
        for p in ZRenderKit.split(c, 40) { zr.add(p) }
    }
}
