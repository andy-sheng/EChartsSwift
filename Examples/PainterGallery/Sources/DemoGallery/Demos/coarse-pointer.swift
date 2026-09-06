import ZRenderKit
// Migrated from zrender test/coarse-pointer.html
extension DemoRegistry {
    static let demo_coarse_pointer: Demo = Demo(
        name: "coarse-pointer", category: "Interaction",
        summary: "useCoarsePointer enlarges the hit area so nearby touches still register; ignoreCoarsePointer shapes opt out",
        width: 600, height: 800
    ) { zr in
        // coarse-pointer.html calls zrender.init(el, { useCoarsePointer }) and builds three hit
        // targets (a Rect, a Polygon, and an `ignoreCoarsePointer` Rect) plus silent green/red
        // marker circles. With useCoarsePointer on, a touch *near* a shape (a green marker) still
        // registers — Handler.findHover re-tests on a ring of radius ~pointerSize/2 — and the shape's
        // mouseover handler lightens its fill; a touch by a red marker is too far and does not. rect2
        // sets `ignoreCoarsePointer`, so its hit area is never enlarged.
        //
        // Two upstream-call gaps are inherent to the gallery, not this demo: the init option can't be
        // toggled here (Demo.build receives an already-constructed ZRender), and hover only fires on
        // live pointer events a static frame can't supply. The construction calls below still mirror
        // the html 1:1 — the .on(mouseover/mouseout) handlers and the ignoreCoarsePointer flag are
        // issued exactly as upstream, so the scene's drawn elements + events match.

        // Mirrors the html's `this.attr('style', { fill })` recolor. Path has no `fill` setStyle key,
        // so rebuild PathStyleProps + useStyle (the same approach event.swift uses). Using the
        // handler's thisCtx (defaults to the element) avoids retaining the shape in its own listener.
        func setFill(_ ctx: AnyObject?, _ color: String) {
            guard let p = ctx as? Path else { return }
            var st = PathStyleProps(); st.fill = .string(color); p.useStyle(st)
        }

        // 1) Rect — base fill #007; mouseover lightens to #06f, mouseout restores #007.
        let r = styled(rect(170, 110, 50, 50), fill: "#007")
        r.on("mouseover") { ctx, _ in setFill(ctx, "#06f"); return nil }
        r.on("mouseout")  { ctx, _ in setFill(ctx, "#007"); return nil }
        zr.add(r)

        // Instructional marker circles (silent), each with its text block attached as a textContent
        // child positioned via textConfig.position (top/bottom) — the real attach path
        // (Element.updateInnerText).
        func marker(_ cx: Double, _ cy: Double, _ fill: String, _ label: String, _ position: String) {
            let m = circle(cx, cy, 5); m.silent = true
            var ts = TextStyleProps(); ts.text = label; ts.fontSize = .number(12)
            let lbl = ZRText(); lbl.useStyle(ts)
            m.setTextContent(lbl)
            var tc = ElementTextConfig(); tc.position = position
            m.setTextConfig(tc)
            zr.add(styled(m, fill: fill))
        }
        marker(180, 95, "green",
               "1. Touch around the green circles.\n2. Expect the blue shape to be a lighter blue.", "top")
        marker(260, 180, "red",
               "3. Touch around the red circles.\n4. Expect the blue shape not to change.", "bottom")

        // 2) Polygon — exact upstream points; same #007 -> #06f mouseover toggle.
        var ps = PolygonShape()
        ps.points = [[100, 250], [170, 340], [300, 220], [200, 400], [100, 300]]
            .map { VectorArray($0[0], $0[1]) }
        let pg = ZRenderKit.Polygon(); pg.setShape(ps)
        styled(pg, fill: "#007")
        pg.on("mouseover") { ctx, _ in setFill(ctx, "#06f"); return nil }
        pg.on("mouseout")  { ctx, _ in setFill(ctx, "#007"); return nil }
        zr.add(pg)

        let rd1 = circle(160, 270, 5); rd1.silent = true
        zr.add(styled(rd1, fill: "red"))
        let g1 = circle(180, 310, 5); g1.silent = true
        zr.add(styled(g1, fill: "green"))

        // 3) Rect2 with ignoreCoarsePointer — base fill #700; mouseover -> #f00, mouseout -> #700.
        // ignoreCoarsePointer means useCoarsePointer never enlarges its hit area, so even the green
        // markers next to it won't register: the upstream opt-out.
        let r2 = styled(rect(170, 450, 50, 50), fill: "#700")
        r2.ignoreCoarsePointer = true
        r2.on("mouseover") { ctx, _ in setFill(ctx, "#f00"); return nil }
        r2.on("mouseout")  { ctx, _ in setFill(ctx, "#700"); return nil }
        // textContent (ignoreCoarsePointer too), textConfig.position 'bottom'.
        var r2ts = TextStyleProps()
        r2ts.text = "This is a shape with `ignoreCoarsePointer`.\nIt will NOT be affected by `useCoarsePointer`."
        r2ts.fontSize = .number(12)
        let r2label = ZRText(); r2label.useStyle(r2ts); r2label.ignoreCoarsePointer = true
        r2.setTextContent(r2label)
        var r2tc = ElementTextConfig(); r2tc.position = "bottom"
        r2.setTextConfig(r2tc)
        zr.add(r2)

        // rect2's silent markers: two green, two red (upstream order preserved).
        let m1 = circle(200, 470, 5); m1.silent = true; zr.add(styled(m1, fill: "green"))
        let m2 = circle(200, 520, 5); m2.silent = true; zr.add(styled(m2, fill: "green"))
        let m3 = circle(235, 470, 5); m3.silent = true; zr.add(styled(m3, fill: "red"))
        let m4 = circle(200, 540, 5); m4.silent = true; zr.add(styled(m4, fill: "red"))
    }
}
