import ZRenderKit
// Faithful port of zrender test/ssr-measureText.html (zrender#947 / echarts#17326)
//
// Upstream builds SSR Text elements and, for each, strokes a Rect built from the REAL
// `text.getBoundingRect()` to verify measurement: `traverse → rect = el.getBoundingRect();
// zr.add(new Rect({ shape: rect, x: el.x, y: el.y, rotation/scale/origin copied,
// style: { fill:null, stroke: color.random(), lineWidth:1 } }))`.
//
// Now uses the real `getBoundingRect()` (the earlier "Index out of range" crash was fixed at the
// framework level — Transformable.getLocalTransform scratch-matrix realloc). The SSR `renderToString`
// path has no native pane analog (rendered to the real surface); color.random() → fixed strokes.
extension DemoRegistry {
    static let demo_ssr_measureText: Demo = Demo(
        name: "ssr-measureText", category: "Text",
        summary: "measureText: text labels boxed by their real getBoundingRect()"
    ) { zr in
        let lines = ["BEFORE: ABCDEFG1234567", "AFTER: ABCDEFG1234567"]
        let strokes = ["#ee6666", "#5470c6"]   // HTML uses color.random(); fixed for determinism.
        let size = 18.0
        for (i, str) in lines.enumerated() {
            let x = 40.0, y = 55.0 + Double(i) * 70.0
            let t = text(str, x, y, "#000000", size: size)   // html sets no fill → default black
            zr.add(t)
            // Rect({ shape: el.getBoundingRect(), x: el.x, y: el.y }) — the real measured box.
            if let r = t.getBoundingRect() {
                let box = rect(r.x, r.y, r.width, r.height)
                box.x = t.x; box.y = t.y
                box.rotation = t.rotation
                box.scaleX = t.scaleX; box.scaleY = t.scaleY
                box.originX = t.originX; box.originY = t.originY
                zr.add(styled(box, stroke: strokes[i % strokes.count], lineWidth: 1))   // fill:null
            }
        }
    }
}
